# Combine U-MIDAS nowcasts across indicators using BIC and RMSE weights
# Also compute distribution statistics (median, percentiles, trimmed mean/range)

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

args <- commandArgs(trailingOnly = TRUE)
param <- list(
  nowcasts_file   = ifelse(length(args) >= 1, args[[1]], file.path("..", "midas_model_selection", "data", "nowcasts", "umidas_nowcasts_by_vintage.csv")),
  selection_file  = ifelse(length(args) >= 2, args[[2]], file.path("..", "midas_model_selection", "data", "selection", "umidas_selection_summary.csv")),
  out_dir         = ifelse(length(args) >= 3, args[[3]], file.path("..", "midas_model_selection", "data", "combination")),
  trim_prop       = ifelse(length(args) >= 4, as.numeric(args[[4]]), 0.10),
  drop_worst_prop = ifelse(length(args) >= 5, as.numeric(args[[5]]), 0.15),
  drop_metric     = ifelse(length(args) >= 6, args[[6]], "rmse") # one of: rmse, bic
)

if (!dir.exists(param$out_dir)) dir.create(param$out_dir, recursive = TRUE, showWarnings = FALSE)

# Load data
if (!file.exists(param$nowcasts_file)) stop("Nowcasts file not found: ", param$nowcasts_file)
if (!file.exists(param$selection_file)) stop("Selection file not found: ", param$selection_file)

now_dt <- fread(param$nowcasts_file)
sel_dt <- fread(param$selection_file)

# Normalize column names across possible legacy versions
# Legacy selection may have selected_k + bic_sum; new version has selected_p_gdp, selected_K_ind, bic_avg
if (!"bic_avg" %in% names(sel_dt)) {
  if ("bic_sum" %in% names(sel_dt) && "n_forecasts" %in% names(sel_dt)) {
    sel_dt[, bic_avg := bic_sum / pmax(n_forecasts, 1)]
  } else {
    # As a fallback, use scaled bic_sum
    if ("bic_sum" %in% names(sel_dt)) sel_dt[, bic_avg := bic_sum]
  }
}

# Ensure types
now_dt[, test_date := as.Date(test_date)]

# Join weights into nowcasts
weights_dt <- sel_dt[, .(variable, bic_avg, rmse)]
now_dt <- merge(now_dt, weights_dt, by = "variable", all.x = TRUE)

# Helper to compute weights
compute_weights <- function(x, scheme = c("bic", "rmse", "equal")) {
  scheme <- match.arg(scheme)
  w <- rep(NA_real_, length(x))
  if (scheme == "bic") {
    # Use exp(-0.5 * (BIC - min BIC)) stabilization
    if (all(is.na(x))) return(rep(NA_real_, length(x)))
    d <- x - min(x, na.rm = TRUE)
    w <- exp(-0.5 * d)
  } else if (scheme == "rmse") {
    # Precision weights ~ 1/rmse^2
    w <- 1 / (x^2)
  } else if (scheme == "equal") {
    w <- rep(1.0, length(x))
  }
  if (all(!is.finite(w)) || sum(w[is.finite(w)]) <= 0) return(rep(NA_real_, length(x)))
  w / sum(w, na.rm = TRUE)
}

# Aggregation by quarter + test_date
setorder(now_dt, quarter, test_date)
by_keys <- c("quarter", "test_date")

agg <- now_dt[!is.na(y_hat), {
  # Drop worst performers (by param$drop_metric) before combining
  dt <- .SD
  n_before <- nrow(dt)
  metric_vec <- if (tolower(param$drop_metric) == "bic") dt$bic_avg else dt$rmse
  valid <- is.finite(metric_vec)
  if (sum(valid) > 0 && is.finite(param$drop_worst_prop) && param$drop_worst_prop > 0) {
    ord <- order(metric_vec[valid], decreasing = FALSE)
    n_keep <- max(1L, ceiling((1 - param$drop_worst_prop) * sum(valid)))
    keep_mask <- rep(FALSE, nrow(dt))
    idx_valid <- which(valid)
    keep_mask[idx_valid[ord[seq_len(n_keep)]]] <- TRUE
    dt <- dt[keep_mask]
  }

  # weights vectors on filtered dt
  wb <- compute_weights(dt$bic_avg, "bic")
  wr <- compute_weights(dt$rmse, "rmse")
  we <- compute_weights(rep(1, nrow(dt)), "equal")

  # combined nowcasts
  comb_bic  <- if (length(wb) == 0 || all(is.na(wb))) NA_real_ else sum(wb * dt$y_hat, na.rm = TRUE)
  comb_rmse <- if (length(wr) == 0 || all(is.na(wr))) NA_real_ else sum(wr * dt$y_hat, na.rm = TRUE)
  comb_equal <- if (length(we) == 0 || all(is.na(we))) NA_real_ else sum(we * dt$y_hat, na.rm = TRUE)

  # distribution stats
  yh <- dt$y_hat
  n <- sum(!is.na(yh))
  p10 <- as.numeric(quantile(yh, probs = 0.10, na.rm = TRUE, type = 7))
  p25 <- as.numeric(quantile(yh, probs = 0.25, na.rm = TRUE, type = 7))
  med <- as.numeric(quantile(yh, probs = 0.50, na.rm = TRUE, type = 7))
  p75 <- as.numeric(quantile(yh, probs = 0.75, na.rm = TRUE, type = 7))
  p90 <- as.numeric(quantile(yh, probs = 0.90, na.rm = TRUE, type = 7))
  mu  <- mean(yh, na.rm = TRUE)
  sdv <- sd(yh, na.rm = TRUE)
  mn  <- suppressWarnings(min(yh, na.rm = TRUE))
  mx  <- suppressWarnings(max(yh, na.rm = TRUE))

  trm <- mean(yh, trim = param$trim_prop, na.rm = TRUE)
  trim_low <- as.numeric(quantile(yh, probs = param$trim_prop, na.rm = TRUE, type = 7))
  trim_high <- as.numeric(quantile(yh, probs = 1 - param$trim_prop, na.rm = TRUE, type = 7))
  trim_range <- trim_high - trim_low

  # y_true should be same across variables for a given quarter; pick first non-NA
  y_true_val <- suppressWarnings(dt$y_true[which(!is.na(dt$y_true))[1]])

  .(n_models_before = n_before,
    n_models = n,
    drop_metric = tolower(param$drop_metric),
    drop_prop = param$drop_worst_prop,
    comb_bic = comb_bic,
    comb_rmse = comb_rmse,
    comb_equal = comb_equal,
    p10 = p10, p25 = p25, median = med, p75 = p75, p90 = p90,
    mean = mu, sd = sdv, min = mn, max = mx,
    trimmed_mean = trm, trimmed_low = trim_low, trimmed_high = trim_high, trimmed_range = trim_range,
    y_true = y_true_val)
}, by = by_keys]

# Save
out_file <- file.path(param$out_dir, "umidas_combined_nowcasts.csv")
fwrite(agg, out_file)
cat("Saved:", out_file, "\n")

# Also save a latest-per-quarter snapshot (latest Friday)
latest <- agg[, .SD[which.max(as.Date(test_date))], by = quarter]
out_latest <- file.path(param$out_dir, "umidas_combined_nowcasts_latest.csv")
fwrite(latest, out_latest)
cat("Saved:", out_latest, "\n")

# Membership table: which indicators were included/dropped at each vintage, with weights
membership <- now_dt[!is.na(y_hat), {
  dt <- .SD
  metric_vec <- if (tolower(param$drop_metric) == "bic") dt$bic_avg else dt$rmse
  valid <- is.finite(metric_vec)
  keep_mask <- rep(FALSE, nrow(dt))
  if (sum(valid) > 0 && is.finite(param$drop_worst_prop) && param$drop_worst_prop > 0) {
    ord <- order(metric_vec[valid], decreasing = FALSE)
    n_keep <- max(1L, ceiling((1 - param$drop_worst_prop) * sum(valid)))
    idx_valid <- which(valid)
    keep_mask[idx_valid[ord[seq_len(n_keep)]]] <- TRUE
  } else if (sum(valid) > 0) {
    keep_mask[valid] <- TRUE
  }

  # Compute weights on kept models
  dt_f <- dt[keep_mask]
  wb <- compute_weights(dt_f$bic_avg, "bic")
  wr <- compute_weights(dt_f$rmse, "rmse")
  weight_bic <- rep(NA_real_, nrow(dt))
  weight_rmse <- rep(NA_real_, nrow(dt))
  if (nrow(dt_f) > 0) {
    weight_bic[keep_mask] <- wb
    weight_rmse[keep_mask] <- wr
  }

  data.table(variable = dt$variable,
             metric_value = metric_vec,
             included = keep_mask,
             weight_bic = weight_bic,
             weight_rmse = weight_rmse,
             y_hat = dt$y_hat)
}, by = by_keys]

out_membership <- file.path(param$out_dir, "umidas_combination_membership.csv")
fwrite(membership, out_membership)
cat("Saved:", out_membership, "\n")

# Enhance selection summary with exclusion rates
excl <- membership[, .(n_vintages = .N,
                       n_excluded = sum(!included, na.rm = TRUE),
                       exclusion_rate = mean(!included, na.rm = TRUE)),
                   by = .(variable)]
sel_enh <- merge(sel_dt, excl, by = "variable", all.x = TRUE)
out_sel_enh <- file.path(param$out_dir, "umidas_selection_with_exclusion.csv")
fwrite(sel_enh, out_sel_enh)
cat("Saved:", out_sel_enh, "\n")
