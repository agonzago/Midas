# U-MIDAS model selection using pseudo-real-time vintages
# - Uses vintages built by 01_build_pseudo_vintages.R
# - For each indicator (filtered by transformation tags), selects a single lag length K by BIC
# - Direct forecasting (no bridging) with monthly lags as regressors (unrestricted weights)
# - Computes nowcasts per Friday and RMSE vs actual GDP

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(stringr)
})

args <- commandArgs(trailingOnly = TRUE)
param <- list(
  monthly_file   = ifelse(length(args) >= 1, args[[1]], file.path("..", "..", "gpm_now", "data", "monthly", "monthly_data.csv")),
  quarterly_file = ifelse(length(args) >= 2, args[[2]], file.path("..", "..", "gpm_now", "data", "quarterly", "quarterly_data.csv")),
  vintages_dir   = ifelse(length(args) >= 3, args[[3]], file.path("..", "data", "vintages")),
  out_sel_dir    = ifelse(length(args) >= 4, args[[4]], file.path("..", "data", "selection")),
  out_now_dir    = ifelse(length(args) >= 5, args[[5]], file.path("..", "data", "nowcasts")),
  k_grid         = ifelse(length(args) >= 6, as.integer(strsplit(args[[6]], ",")[[1]]), 1:12),
  transform_tags = ifelse(length(args) >= 7, strsplit(args[[7]], ",")[[1]], c("DA", "DA3m", "log_dm", "dm", "3m"))
)

if (!dir.exists(param$out_sel_dir)) dir.create(param$out_sel_dir, recursive = TRUE, showWarnings = FALSE)
if (!dir.exists(param$out_now_dir)) dir.create(param$out_now_dir, recursive = TRUE, showWarnings = FALSE)

monthly <- fread(param$monthly_file)
monthly[, date := as.Date(date)]
quarterly <- fread(param$quarterly_file)
quarterly[, date := as.Date(date)]

# Helper: get quarter string like 2024Q1 from a Date at quarter end
qstr <- function(d) paste0(year(d), "Q", quarter(d))

# Load vintages
vintage_files <- list.files(param$vintages_dir, pattern = "^pseudo_vintages_.*\\.rds$", full.names = TRUE)
if (length(vintage_files) == 0) stop("No vintage files found. Run 01_build_pseudo_vintages.R first.")

vintages_all <- lapply(vintage_files, readRDS)
# Flatten: list of quarters, each is a named list keyed by test_date char
quarters_available <- names(vintages_all)

# Index quarterly actuals by quarter string
quarterly[, quarter := qstr(date)]
setkey(quarterly, quarter)

# Filter indicators by transform tags
all_vars <- setdiff(names(monthly), "date")
sel_vars <- unique(unlist(lapply(param$transform_tags, function(tag) {
  all_vars[str_detect(all_vars, fixed(tag))]
})))
if (length(sel_vars) == 0) {
  warning("No variables matched transform tags; falling back to all variables.")
  sel_vars <- all_vars
}

# Extract all quarters present in vintages and sort chronologically
q_extract <- function(fn) sub("pseudo_vintages_(.*)\\.rds", "\\1", basename(fn))
q_list <- q_extract(vintage_files)

# Quarter sort helper
q_order <- function(q) {
  y <- as.integer(substr(q,1,4)); r <- as.integer(substr(q,6,6)); y*4 + r
}
q_list <- q_list[order(q_order(q_list))]

# Prepare a map: quarter -> fridays character vector and availability tables per variable
decode_vintage <- function(vq) {
  frds <- as.Date(names(vq))
  frds <- frds[order(frds)]
  list(fridays = frds, data = vq)
}

vmap <- setNames(lapply(vintages_all, decode_vintage), q_list)

# Helper: get last available month for var at quarter q and friday index idx (1-based)
last_month_at <- function(var, q, idx) {
  vi <- vmap[[q]]
  frs <- vi$fridays
  if (length(frs) == 0) return(as.Date(NA))
  i <- min(idx, length(frs))
  vinfo <- vi$data[[as.character(frs[i])]]$availability
  idx <- which(vinfo$variable == var)
  if (length(idx) == 0) return(as.Date(NA))
  row <- vinfo[idx, ]
  if (nrow(row) == 0) return(as.Date(NA))
  row$last_month[1]
}

# Build feature vector of length K with last K monthly lags ending at lm_date (inclusive)
feat_vec <- function(var, lm_date, K) {
  if (is.na(lm_date)) return(rep(NA_real_, K))
  # Pull monthly series
  x <- data.table(date = monthly$date, val = monthly[[var]])
  setorder(x, date)
  x <- x[date <= lm_date]
  if (nrow(x) == 0) return(rep(NA_real_, K))
  vals <- tail(x$val, K)
  if (length(vals) < K) vals <- c(rep(NA_real_, K - length(vals)), vals)
  as.numeric(rev(vals)) # most recent first
}

# Build training set up to quarter index t-1, using friday index idx for raggedness
build_training <- function(var, t_idx, idx, K, q_seq) {
  X <- list(); y <- c(); qy <- c()
  if (t_idx <= 1) return(list(X = NULL, y = NULL, quarters = NULL))
  for (j in 1:(t_idx-1)) {
    qj <- q_seq[j]
    lmj <- last_month_at(var, qj, idx)
    fv <- feat_vec(var, lmj, K)
  yj <- quarterly[quarterly$quarter == qj, ][["value"]]
  yj <- if (length(yj) == 0) NA_real_ else yj[1]
    if (!is.na(yj) && all(!is.na(fv))) {
      X[[length(X)+1]] <- c(1, fv) # intercept
      y <- c(y, yj)
      qy <- c(qy, qj)
    }
  }
  if (length(X) == 0) return(list(X = NULL, y = NULL, quarters = NULL))
  list(X = do.call(rbind, X), y = y, quarters = qy)
}

# Fit OLS and compute BIC; return coefficients
ols_bic <- function(X, y) {
  qrX <- qr(X)
  coef <- qr.coef(qrX, y)
  yhat <- as.vector(X %*% coef)
  n <- length(y)
  k <- ncol(X)
  sse <- sum((y - yhat)^2)
  sigma2 <- sse / n
  bic <- n * log(sse / n) + k * log(n)
  list(coef = coef, bic = bic, sse = sse, sigma2 = sigma2)
}

# Main selection loop
results <- list()
nowcasts_out <- list()

for (var in sel_vars) {
  cat("Selecting model for", var, "...\n")
  bic_sum <- setNames(rep(0, length(param$k_grid)), param$k_grid)
  valid_k <- setNames(rep(FALSE, length(param$k_grid)), param$k_grid)
  preds_by_k <- vector("list", length(param$k_grid)); names(preds_by_k) <- as.character(param$k_grid)

  # Loop over target quarters
  for (ti in seq_along(q_list)) {
    q_t <- q_list[ti]
    # Skip if no actual y
    y_true <- quarterly[list(q_t), value]
    if (is.na(y_true)) next

    # For each friday within quarter
    frs <- vmap[[q_t]]$fridays
    for (idx in seq_along(frs)) {
      lm_t <- last_month_at(var, q_t, idx)
      if (is.na(lm_t)) next

      # Evaluate each K
      for (K in param$k_grid) {
        tr <- build_training(var, ti, idx, K, q_list)
        if (is.null(tr$X)) next
  # Require more observations than parameters (intercept + K)
  if (nrow(tr$X) <= (ncol(tr$X))) next
  fit <- tryCatch(ols_bic(tr$X, tr$y), error = function(e) NULL)
        if (is.null(fit) || !is.finite(fit$bic)) next
  bic_sum[as.character(K)] <- bic_sum[as.character(K)] + fit$bic
  valid_k[as.character(K)] <- TRUE
        # Predict for current vintage
        x_t <- c(1, feat_vec(var, lm_t, K))
        if (any(is.na(x_t))) next
        y_hat <- sum(x_t * fit$coef)
        ascK <- as.character(K)
        newrow <- data.table(variable = var, quarter = q_t, test_date = frs[idx], K = K, y_true = y_true, y_hat = y_hat)
        if (is.null(preds_by_k[[ascK]])) preds_by_k[[ascK]] <- newrow else preds_by_k[[ascK]] <- rbind(preds_by_k[[ascK]], newrow)
      }
    }
  }

  # Choose K with minimum aggregate BIC
  # Restrict to Ks that had at least one valid fit
  ks_ok <- names(valid_k)[valid_k]
  if (length(ks_ok) == 0) next
  bic_sub <- bic_sum[ks_ok]
  bic_sub <- bic_sub[is.finite(bic_sub)]
  if (length(bic_sub) == 0) next
  K_star <- as.integer(names(which.min(bic_sub)))

  preds <- preds_by_k[[as.character(K_star)]]
  if (is.null(preds) || nrow(preds) == 0) next
  rmse <- sqrt(mean((preds$y_hat - preds$y_true)^2, na.rm = TRUE))

  results[[var]] <- data.table(variable = var, selected_k = K_star, bic_sum = bic_sum[[as.character(K_star)]], rmse = rmse, n_forecasts = nrow(preds))
  nowcasts_out[[var]] <- preds
}

# Save selections
if (length(results) > 0) { 
  sel_dt <- rbindlist(results, fill = TRUE)
  fwrite(sel_dt, file.path(param$out_sel_dir, "umidas_selection_summary.csv"))
  cat("Saved:", file.path(param$out_sel_dir, "umidas_selection_summary.csv"), "\n")
}

# Save per-variable nowcasts
if (length(nowcasts_out) > 0) {
  now_dt <- rbindlist(nowcasts_out, fill = TRUE)
  fwrite(now_dt, file.path(param$out_now_dir, "umidas_nowcasts_by_vintage.csv"))
  cat("Saved:", file.path(param$out_now_dir, "umidas_nowcasts_by_vintage.csv"), "\n")
}

cat("Done.\n")
