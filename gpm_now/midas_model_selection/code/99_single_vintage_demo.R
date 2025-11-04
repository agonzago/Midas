# Single-vintage U-MIDAS demo using midasr
# - Reads a single quarter's vintage RDS
# - Picks one Friday (index or "last") to get last_month and horizon for one indicator
# - Builds quarterly/monthly ts aligned for midasr
# - Grid-searches p_gdp and K_ind by BIC and prints the selected spec
# - Attempts a one-step forecast for the test quarter

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(stringr)
})

if (!requireNamespace("midasr", quietly = TRUE)) {
  stop("Package 'midasr' is required. Please install with install.packages('midasr')")
}
library(midasr)

args <- commandArgs(trailingOnly = TRUE)
param <- list(
  monthly_file   = ifelse(length(args) >= 1, args[[1]], file.path("..","..","retriever","brazil","output","transformed_data","monthly.csv")),
  quarterly_file = ifelse(length(args) >= 2, args[[2]], file.path("..","..","retriever","brazil","output","transformed_data","quarterly.csv")),
  vintages_dir   = ifelse(length(args) >= 3, args[[3]], file.path("..","midas_model_selection","data","vintages")),
  quarter_str    = ifelse(length(args) >= 4, args[[4]], "2024Q4"),
  friday_index   = ifelse(length(args) >= 5, args[[5]], "last"),
  variable       = ifelse(length(args) >= 6, args[[6]], "DA_RETAIL_SALES_US"),
  target_col     = ifelse(length(args) >= 7, args[[7]], "DA_GDP"),
  p_grid         = if (length(args) >= 8) as.integer(strsplit(args[[8]], ",")[[1]]) else 1:3,
  k_grid         = if (length(args) >= 9) as.integer(strsplit(args[[9]], ",")[[1]]) else 3:6
)

qstr <- function(d) paste0(year(d), "Q", quarter(d))
q_from_str <- function(qs) {
  y <- as.integer(substr(qs,1,4)); q <- as.integer(substr(qs,6,6)); as.Date(sprintf("%04d-%02d-01", y, (q-1)*3+1))
}

monthly <- fread(param$monthly_file)
monthly[, date := as.Date(date)]
quarterly <- fread(param$quarterly_file)
quarterly[, date := as.Date(date)]
stopifnot(param$target_col %in% names(quarterly))
setnames(quarterly, param$target_col, "y")
quarterly[, quarter := qstr(date)]

vfile <- file.path(param$vintages_dir, sprintf("pseudo_vintages_%s.rds", param$quarter_str))
if (!file.exists(vfile)) stop("Vintage file not found: ", vfile)
vt <- readRDS(vfile)
fridays <- as.Date(names(vt))
if (identical(param$friday_index, "last")) idx <- length(fridays) else idx <- as.integer(param$friday_index)
if (is.na(idx) || idx < 1 || idx > length(fridays)) stop("Invalid friday_index: ", param$friday_index)
friday <- sort(fridays)[idx]
avail <- vt[[as.character(friday)]]$availability
if (!(param$variable %in% avail$variable)) stop("Variable not in availability: ", param$variable)
row <- avail[variable == param$variable][1]
last_month <- as.Date(row$last_month)
h <- as.integer(row$horizon_months)
cat(sprintf("Selected %s: last_month=%s, horizon(h)=%d\n", param$variable, last_month, h))

# Training quarters: all strictly before the selected quarter
q_t_date <- q_from_str(param$quarter_str)
train_quarters <- quarterly[date < q_t_date & !is.na(y)][order(date)]
if (nrow(train_quarters) < 8) stop("Too few training quarters (<8). Choose a later quarter.")

y_train <- train_quarters$y
q_dates <- train_quarters$date

# Build LF ts starting at the first training quarter
lf_start <- q_dates[1]
y_ts <- ts(y_train, start = c(year(lf_start), quarter(lf_start)), frequency = 4)

# Build HF ts for the indicator: include pre-sample months so that lags h:(h+K-1) exist
maxK <- max(param$k_grid)
max_k <- h + maxK - 1
q_start_mon <- floor_date(lf_start, unit = "quarter")
hf_start <- q_start_mon %m-% months(max_k)
ind_series <- monthly[date >= hf_start & date <= last_month, .(date, z = get(param$variable))]
if (nrow(ind_series) == 0) stop("No monthly data for ", param$variable)
# Ensure no all-NA region
if (all(is.na(ind_series$z))) stop("Monthly series all NA in window for ", param$variable)

z_ts <- ts(ind_series$z, start = c(year(ind_series$date[1]), month(ind_series$date[1])), frequency = 12)

# Sanity print lengths
cat(sprintf("LF length=%d, HF length=%d, expected min HF >= %d\n",
            length(y_ts), length(z_ts), length(y_ts)*3 + (h + min(param$k_grid) - 1)))

# Model selection
results <- list()
best <- NULL
best_bic <- Inf
for (p in param$p_grid) {
  for (K in param$k_grid) {
    ind_lags <- h:(h+K-1)
    if (min(ind_lags) < 0) next
    fmla <- if (p > 0) {
      as.formula(sprintf("y_ts ~ mls(y_ts, %d:%d, 1) + mls(z_ts, %d:%d, 3)", 1, p, min(ind_lags), max(ind_lags)))
    } else {
      as.formula(sprintf("y_ts ~ mls(z_ts, %d:%d, 3)", min(ind_lags), max(ind_lags)))
    }
    environment(fmla) <- environment()
    fit <- tryCatch(midasr::midas_r(fmla, start = NULL), error = function(e) e)
    if (inherits(fit, "error")) {
      cat(sprintf("  p=%d K=%d -> FAILED: %s\n", p, K, conditionMessage(fit)))
      next
    }
    bic_val <- tryCatch(BIC(fit), error = function(e) NA_real_)
    nobs <- length(fitted(fit))
    cat(sprintf("  p=%d K=%d -> BIC=%.3f (nobs=%d)\n", p, K, bic_val, nobs))
    results[[paste(p,K,sep=":")]] <- list(p=p, K=K, bic=bic_val, fit=fit)
    if (!is.na(bic_val) && bic_val < best_bic) {
      best_bic <- bic_val; best <- results[[paste(p,K,sep=":")]]
    }
  }
}

if (is.null(best)) stop("No successful midasr fits. Try another indicator or Friday.")
cat(sprintf("\nSelected: p=%d, K=%d with BIC=%.3f\n", best$p, best$K, best$bic))

# One-step-ahead forecast for q_t
# We'll compute regressors for q_t using monthly z at last_month and horizon h
q_t_last_month <- q_start_mon %m+% months(2) # last month of q_t
if (q_t_last_month != floor_date(q_t_date, unit = "quarter") %m+% months(2)) {
  q_t_last_month <- floor_date(q_t_date, unit = "quarter") %m+% months(2)
}
lag_months <- q_t_last_month %m-% months(h + 0:(best$K-1))
z_fc <- monthly[date %in% lag_months, .(date, z = get(param$variable))]
# order as lag_months
z_fc <- z_fc[match(lag_months, z_fc$date)]
if (nrow(z_fc) != best$K || any(is.na(z_fc$z))) {
  cat("Not enough monthly values for forecast at requested horizon.\n")
} else {
  # Build a newdata list with the same y_ts (for AR lags) and an extended z_ts containing z_fc window aligned to hf_start
  # midasr predict requires a list with series used in the formula
  new_z_ts <- ts(c(as.numeric(z_ts), rep(NA_real_, 12)), start = start(z_ts), frequency = 12)
  # We won't rely on predict's automatic OOS; instead, compute the linear prediction manually from coefficients
  cf <- coef(best$fit)
  # Separate intercept, AR coefs, and indicator coefs by name heuristics
  intercept <- unname(cf["(Intercept)"])
  ar_idx <- grepl("mls\(y_ts", names(cf), fixed = TRUE)
  x_idx <- grepl("mls\(z_ts", names(cf), fixed = TRUE)
  ar_coefs <- cf[ar_idx]
  x_coefs <- cf[x_idx]
  # Prepare AR lags: last p quarters of y
  y_lags <- rev(tail(y_train, length(ar_coefs)))
  # Prepare x lags in the same order as coefficients
  x_lags <- as.numeric(z_fc$z)[seq_len(length(x_coefs))]
  y_hat <- intercept + sum(ar_coefs * y_lags) + sum(x_coefs * x_lags)
  cat(sprintf("Forecast for %s (using %s on %s, h=%d): %.4f\n", param$quarter_str, param$variable, as.character(friday), h, y_hat))
}
