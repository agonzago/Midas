# U-MIDAS model selection using pseudo-real-time vintages (gpm_now)
# - Input monthly/quarterly from retriever/brazil/output/transformed_data
# - Fit direct U-MIDAS per indicator with BIC lag selection using midasr
# - Includes GDP AR lags (minimum 1) + monthly indicator lags adjusted for horizon
# - Save selected lags and RMSE, plus all nowcasts by Friday

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(stringr)
  library(parallel)
})

# Check for midasr - install if needed
if (!requireNamespace("midasr", quietly = TRUE)) {
  cat("midasr not found. Attempting to install from CRAN...\n")
  install.packages("midasr", repos = "https://cloud.r-project.org")
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Failed to install midasr. Please install manually: install.packages('midasr')")
  }
}
suppressPackageStartupMessages(library(midasr))

args <- commandArgs(trailingOnly = TRUE)
param <- list(
  monthly_file   = ifelse(length(args) >= 1, args[[1]], file.path("..", "retriever", "brazil", "output", "transformed_data", "monthly.csv")),
  quarterly_file = ifelse(length(args) >= 2, args[[2]], file.path("..", "retriever", "brazil", "output", "transformed_data", "quarterly.csv")),
  vintages_dir   = ifelse(length(args) >= 3, args[[3]], file.path(".", "..", "midas_model_selection", "data", "vintages")),
  out_sel_dir    = ifelse(length(args) >= 4, args[[4]], file.path(".", "..", "midas_model_selection", "data", "selection")),
  out_now_dir    = ifelse(length(args) >= 5, args[[5]], file.path(".", "..", "midas_model_selection", "data", "nowcasts")),
  gdp_lags_grid  = if (length(args) >= 6) as.integer(strsplit(args[[6]], ",")[[1]]) else 1:4,
  k_grid         = if (length(args) >= 7) as.integer(strsplit(args[[7]], ",")[[1]]) else 3:9,
  transform_tags = if (length(args) >= 8) strsplit(args[[8]], ",")[[1]] else c("DA_", "DA3m_"),
  target_col     = ifelse(length(args) >= 9, args[[9]], "DA_GDP"),
  n_cores        = if (length(args) >= 10) as.integer(args[[10]]) else max(1L, parallel::detectCores() - 1L)
)

for (d in c(param$out_sel_dir, param$out_now_dir)) if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

monthly <- fread(param$monthly_file)
monthly[, date := as.Date(date)]
quarterly <- fread(param$quarterly_file)
quarterly[, date := as.Date(date)]

# Use target column
stopifnot(param$target_col %in% names(quarterly))
setnames(quarterly, param$target_col, "value")

qstr <- function(d) paste0(year(d), "Q", quarter(d))
quarterly[, quarter := qstr(date)]

# Find start year/quarter for ts objects
qmin <- quarterly[!is.na(value)][order(date)][1, ]
start_year <- year(qmin$date)
start_qtr <- quarter(qmin$date)

# Load vintages
vintage_files <- list.files(param$vintages_dir, pattern = "^pseudo_vintages_.*\\.rds$", full.names = TRUE)
if (length(vintage_files) == 0) stop("No vintage files found.")

q_extract <- function(fn) sub("pseudo_vintages_(.*)\\.rds", "\\1", basename(fn))
q_order <- function(q) { y <- as.integer(substr(q,1,4)); r <- as.integer(substr(q,6,6)); y*4 + r }
q_list <- q_extract(vintage_files)
q_list <- q_list[order(q_order(q_list))]

vmap <- setNames(lapply(vintage_files[order(q_order(q_extract(vintage_files)))], readRDS), q_list)
for (q in names(vmap)) {
  vi <- vmap[[q]]
  vmap[[q]] <- list(fridays = as.Date(names(vi)), data = vi)
}

all_vars <- setdiff(names(monthly), "date")
sel_vars <- unique(unlist(lapply(param$transform_tags, function(tag) all_vars[str_detect(all_vars, fixed(tag))])))
if (length(sel_vars) == 0) {
  warning("No variables matched transform tags; falling back to DA_ and DA3m_ prefixes.")
  sel_vars <- all_vars[str_detect(all_vars, "^(DA_|DA3m_)")]
}

cat("Running U-MIDAS selection for", length(sel_vars), "indicators on", param$n_cores, "cores.\n")
cat("GDP AR lags grid:", paste(param$gdp_lags_grid, collapse=","), "\n")
cat("Indicator lags grid (K):", paste(param$k_grid, collapse=","), "\n\n")

# Helper: get horizon and last month for a variable at a given quarter/friday index
get_vintage_info <- function(var, q, idx) {
  vi <- vmap[[q]]
  frs <- sort(vi$fridays)
  if (length(frs) == 0 || idx > length(frs)) return(list(last_month = as.Date(NA), horizon = NA_integer_))
  vinfo <- vi$data[[as.character(frs[idx])]]$availability
  hit <- which(vinfo$variable == var)
  if (length(hit) == 0) return(list(last_month = as.Date(NA), horizon = NA_integer_))
  list(last_month = vinfo$last_month[hit[1]], horizon = vinfo$horizon_months[hit[1]])
}

# Helpers for OLS fallback when midasr alignment fails
quarter_last_month_start <- function(qdate) {
  # Returns the first day of the last month in the quarter of qdate
  lubridate::floor_date(qdate, unit = "quarter") %m+% months(2)
}

build_midas_design <- function(train_q_dates, z_dt, h, K) {
  # z_dt must have columns: date (Date) and value (numeric)
  offsets <- h + seq.int(0L, K - 1L)
  X_list <- vector("list", length(train_q_dates))
  keep <- rep(TRUE, length(train_q_dates))
  for (i in seq_along(train_q_dates)) {
    qd <- train_q_dates[i]
    lm_start <- quarter_last_month_start(qd)
    mdates <- lm_start %m-% months(offsets)
    vals_dt <- z_dt[date %in% mdates]
    # preserve the order of mdates
    if (nrow(vals_dt) < length(mdates)) {
      keep[i] <- FALSE
      X_list[[i]] <- rep(NA_real_, K)
      next
    }
    ord <- match(mdates, vals_dt$date)
    vals <- vals_dt$value[ord]
    if (any(is.na(vals))) {
      keep[i] <- FALSE
      X_list[[i]] <- rep(NA_real_, K)
    } else {
      X_list[[i]] <- as.numeric(vals)
    }
  }
  X <- do.call(rbind, X_list)
  list(X = X, keep = keep)
}

fit_umidas_ols <- function(train_y, train_q_dates, z_dt, p_gdp, K_ind, h_ind, test_q_date, last_month) {
  # z_dt: data.table with columns date (Date), value (numeric) for the indicator
  # Ensure we only use monthly data up to last_month for this vintage
  z_sub <- z_dt[date <= last_month]
  if (nrow(z_sub) == 0) return(NULL)
  des <- build_midas_design(train_q_dates, z_sub, h_ind, K_ind)
  keep <- des$keep
  X <- des$X
  # Build AR lags
  if (p_gdp > 0) {
    Y_lag <- embed(train_y, p_gdp + 1)
    # Align with X rows
    # Determine indices corresponding to the last nrow(Y_lag) quarters
    idx_offset <- length(train_y) - nrow(Y_lag)
    X_eff <- X[(idx_offset + 1):nrow(X), , drop = FALSE]
    keep_eff <- keep[(idx_offset + 1):length(keep)]
    # Drop rows with missing X or flagged keep FALSE
    rows <- which(keep_eff & rowSums(is.na(X_eff)) == 0)
    if (length(rows) < (p_gdp + K_ind + 2)) return(NULL)
    y_reg <- Y_lag[rows, 1]
    y_lags <- Y_lag[rows, -1, drop = FALSE]
    X_reg <- X_eff[rows, , drop = FALSE]
    df <- data.frame(y = y_reg, y_lags, X_reg)
    names(df) <- c("y", paste0("y_lag", 1:p_gdp), paste0("x_", 0:(K_ind - 1)))
    fit <- tryCatch(lm(y ~ ., data = df), error = function(e) NULL)
  } else {
    # No AR terms
    rows <- which(keep & rowSums(is.na(X)) == 0)
    if (length(rows) < (K_ind + 2)) return(NULL)
    y_reg <- train_y[rows]
    X_reg <- X[rows, , drop = FALSE]
    df <- data.frame(y = y_reg, X_reg)
    names(df) <- c("y", paste0("x_", 0:(K_ind - 1)))
    fit <- tryCatch(lm(y ~ ., data = df), error = function(e) NULL)
  }
  if (is.null(fit)) return(NULL)
  bic_val <- tryCatch(BIC(fit), error = function(e) NA_real_)
  # One-step-ahead forecast for test quarter
  # Build AR lags for forecast
  if (p_gdp > 0) {
    y_lags_fc <- tail(train_y, p_gdp)
  }
  # Build indicator K values for test quarter at horizon h
  lm_start_test <- quarter_last_month_start(test_q_date)
  mdates_fc <- lm_start_test %m-% months(h_ind + seq.int(0L, K_ind - 1L))
  z_fc_dt <- z_sub[date %in% mdates_fc]
  if (nrow(z_fc_dt) < length(mdates_fc)) return(list(model = fit, bic = bic_val, forecast = NA_real_, coef = coef(fit)))
  z_fc <- z_fc_dt$value[match(mdates_fc, z_fc_dt$date)]
  if (any(is.na(z_fc))) return(list(model = fit, bic = bic_val, forecast = NA_real_, coef = coef(fit)))
  new_df <- as.list(setNames(as.numeric(z_fc), paste0("x_", 0:(K_ind - 1))))
  if (p_gdp > 0) for (i in 1:p_gdp) new_df[[paste0("y_lag", i)]] <- y_lags_fc[i]
  new_df <- as.data.frame(new_df)
  y_hat <- tryCatch(as.numeric(predict(fit, newdata = new_df)), error = function(e) NA_real_)
  list(model = fit, bic = bic_val, forecast = y_hat, coef = coef(fit))
}

# Fit U-MIDAS using midasr
# Returns: list(coef, bic, forecast) or NULL on error
fit_umidas_midasr <- function(gdp_ts, indicator_ts, p_gdp, K_ind, h_ind) {
  # p_gdp: number of GDP AR lags (quarterly)
  # K_ind: number of indicator lags (monthly)
  # h_ind: horizon offset (how many months back the first available lag is)
  
  # Build formula: y ~ mls(y, p_gdp, 1) + mls(x, h:(h+K-1), 3)
  # Lag specification: h:(h+K-1) means we use K lags starting from h months back
  
  tryCatch({
    # Create lag range for indicator
    ind_lags <- h_ind:(h_ind + K_ind - 1)
    
    # Build formula dynamically
    if (p_gdp > 0) {
      fmla <- as.formula(sprintf("gdp_ts ~ mls(gdp_ts, %d:%d, 1) + mls(indicator_ts, %d:%d, 3)",
                                 1, p_gdp, min(ind_lags), max(ind_lags)))
    } else {
      fmla <- as.formula(sprintf("gdp_ts ~ mls(indicator_ts, %d:%d, 3)",
                                 min(ind_lags), max(ind_lags)))
    }
    # Critical: bind formula to the current environment so midasr sees local variables
    environment(fmla) <- environment()
    
    # Fit U-MIDAS (unrestricted) using midas_r from midasr
  fit <- midasr::midas_r(fmla, start = NULL)
    
    # Extract BIC
    bic_val <- BIC(fit)
    
    # Forecast (out-of-sample for the next quarter)
    fcst <- tryCatch({
      pred <- predict(fit, newdata = NULL)
      tail(pred, 1)
    }, error = function(e) NA_real_)
    
    list(model = fit, bic = bic_val, forecast = fcst, coef = coef(fit))
  }, error = function(e) {
    cat("fit error:", conditionMessage(e), "\n")
    NULL
  })
}

process_indicator <- function(var) {
  cat("Selecting model for", var, "...\n")
  bic_grid <- expand.grid(p_gdp = param$gdp_lags_grid, K_ind = param$k_grid)
  bic_grid$bic_sum <- 0
  bic_grid$n_valid <- 0
  preds_by_config <- vector("list", nrow(bic_grid))

  for (ti in seq_along(q_list)) {
    q_t <- q_list[ti]
  y_true <- quarterly[quarter == q_t][["value"]]
    if (length(y_true) == 0 || is.na(y_true[1])) next
    y_true <- y_true[1]
    frs <- sort(vmap[[q_t]]$fridays)
    if (length(frs) == 0) next
    for (idx in seq_along(frs)) {
      test_friday <- frs[idx]
      vinfo <- get_vintage_info(var, q_t, idx)
      if (is.na(vinfo$last_month) || is.na(vinfo$horizon)) next
      h_ind <- vinfo$horizon
      if (ti <= 1) next
      train_quarters <- q_list[1:(ti-1)]
      train_gdp <- quarterly[quarter %in% train_quarters][order(date)][["value"]]
      if (any(is.na(train_gdp)) || length(train_gdp) < 2) next
      # Align monthly series start to the first month of the first training quarter
      first_train_q_date <- quarterly[quarter == train_quarters[1], date][1]
      q_start_date <- lubridate::floor_date(first_train_q_date, unit = "quarter")

  # LF series object aligned to the start of the training sample
  N_q <- length(train_gdp)
  first_train_q_date <- quarterly[quarter == train_quarters[1], date][1]
  gdp_ts <- ts(train_gdp, start = c(year(first_train_q_date), quarter(first_train_q_date)), frequency = 4)
      # We'll build HF series per configuration ensuring pre-sample lags are included
      for (cfg_idx in seq_len(nrow(bic_grid))) {
        p_gdp <- bic_grid$p_gdp[cfg_idx]
        K_ind <- bic_grid$K_ind[cfg_idx]
        if (length(train_gdp) <= p_gdp) next
        # Compute exact HF window needed for this configuration
        max_k <- h_ind + K_ind - 1
  needed_hf_len <- N_q * 3 + max_k + 3
        # Start the HF window max_k months BEFORE the first training quarter to have complete lags
  hf_start_date <- q_start_date %m-% months(max_k)
        hf_end_date <- vinfo$last_month
        mon_sub_cfg <- monthly[date >= hf_start_date & date <= hf_end_date][order(date)]
  if (nrow(mon_sub_cfg) < needed_hf_len) next
  # Use exactly the needed number of HF observations (take the first needed_hf_len to align with ts starts)
  indicator_vals_cfg <- mon_sub_cfg[[var]][seq_len(needed_hf_len)]
        indicator_ts <- ts(indicator_vals_cfg, start = c(year(hf_start_date), month(hf_start_date)), frequency = 12)

        fit_result <- fit_umidas_midasr(gdp_ts, indicator_ts, p_gdp, K_ind, h_ind)
        # Fallback: try OLS design if midasr fails
        if (is.null(fit_result)) {
          # Prepare monthly series for this var
          z_dt <- data.table(date = monthly$date, value = monthly[[var]])
          fit_result <- fit_umidas_ols(
            train_y = train_gdp,
            train_q_dates = quarterly[quarter %in% train_quarters][order(date), date],
            z_dt = z_dt,
            p_gdp = p_gdp,
            K_ind = K_ind,
            h_ind = h_ind,
            test_q_date = quarterly[quarter == q_t, date][1],
            last_month = vinfo$last_month
          )
        }
        if (is.null(fit_result)) next
        bic_grid$bic_sum[cfg_idx] <- bic_grid$bic_sum[cfg_idx] + fit_result$bic
        bic_grid$n_valid[cfg_idx] <- bic_grid$n_valid[cfg_idx] + 1
        if (!is.na(fit_result$forecast)) {
          newrow <- data.table(
            variable = var,
            quarter = q_t,
            test_date = test_friday,
            p_gdp = p_gdp,
            K_ind = K_ind,
            horizon = h_ind,
            y_true = y_true,
            y_hat = fit_result$forecast
          )
          if (is.null(preds_by_config[[cfg_idx]])) preds_by_config[[cfg_idx]] <- newrow
          else preds_by_config[[cfg_idx]] <- rbind(preds_by_config[[cfg_idx]], newrow)
        }
      }
    }
  }

  bic_grid <- bic_grid[bic_grid$n_valid > 0, ]
  if (nrow(bic_grid) == 0) {
    cat("No valid fits for", var, "(all configs invalid)\n")
    return(NULL)
  }
  bic_grid$bic_avg <- bic_grid$bic_sum / bic_grid$n_valid
  best_idx <- which.min(bic_grid$bic_avg)
  best_cfg <- bic_grid[best_idx, ]
  full_grid <- expand.grid(p_gdp = param$gdp_lags_grid, K_ind = param$k_grid)
  orig_idx <- which(full_grid$p_gdp == best_cfg$p_gdp & full_grid$K_ind == best_cfg$K_ind)[1]
  preds <- preds_by_config[[orig_idx]]
  if (is.null(preds) || nrow(preds) == 0) {
    cat("No predictions accumulated for", var, "selected config p=", best_cfg$p_gdp, ", K=", best_cfg$K_ind, "\n")
    return(NULL)
  }
  rmse <- sqrt(mean((preds$y_hat - preds$y_true)^2, na.rm = TRUE))
  sel_row <- data.table(
    variable = var,
    selected_p_gdp = best_cfg$p_gdp,
    selected_K_ind = best_cfg$K_ind,
    bic_avg = best_cfg$bic_avg,
    rmse = rmse,
    n_forecasts = nrow(preds)
  )
  list(sel = sel_row, now = preds)
}

out_list <- mclapply(sel_vars, process_indicator, mc.cores = param$n_cores)
sel_list <- lapply(out_list, function(x) if (!is.null(x)) x$sel)
now_list <- lapply(out_list, function(x) if (!is.null(x)) x$now)

sel_list <- Filter(function(x) !is.null(x) && is.data.table(x) && nrow(x) > 0, sel_list)
if (length(sel_list) > 0) {
  sel_dt <- rbindlist(sel_list, fill = TRUE)
  fwrite(sel_dt, file.path(param$out_sel_dir, "umidas_selection_summary.csv"))
  cat("Saved:", file.path(param$out_sel_dir, "umidas_selection_summary.csv"), "\n")
}

now_list <- Filter(function(x) !is.null(x) && is.data.table(x) && nrow(x) > 0, now_list)
if (length(now_list) > 0) {
  now_dt <- rbindlist(now_list, fill = TRUE)
  fwrite(now_dt, file.path(param$out_now_dir, "umidas_nowcasts_by_vintage.csv"))
  cat("Saved:", file.path(param$out_now_dir, "umidas_nowcasts_by_vintage.csv"), "\n")
}

cat("Done.\n")
