# Executive Summary Report for U-MIDAS Nowcasting
# Produces print-friendly tables showing:
# 1. Latest nowcast per combination scheme (all schemes sorted by historical RMSE)
# 2. Top contributing indicators by weight
# 3. Month-by-month evolution within current quarter
# 4. Model performance comparison

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

args <- commandArgs(trailingOnly = TRUE)
param <- list(
  combined_file  = ifelse(length(args) >= 1, args[[1]], file.path("..", "midas_model_selection", "data", "combination", "umidas_combined_nowcasts.csv")),
  nowcasts_file  = ifelse(length(args) >= 2, args[[2]], file.path("..", "midas_model_selection", "data", "nowcasts", "umidas_nowcasts_by_vintage.csv")),
  selection_file = ifelse(length(args) >= 3, args[[3]], file.path("..", "midas_model_selection", "data", "selection", "umidas_selection_summary.csv")),
  out_dir        = ifelse(length(args) >= 4, args[[4]], file.path("..", "midas_model_selection", "data", "combination")),
  top_n          = ifelse(length(args) >= 5, as.integer(args[[5]]), 10)
)

if (!dir.exists(param$out_dir)) dir.create(param$out_dir, recursive = TRUE, showWarnings = FALSE)

# Load data
if (!file.exists(param$combined_file)) stop("Combined file not found: ", param$combined_file)
if (!file.exists(param$nowcasts_file)) stop("Nowcasts file not found: ", param$nowcasts_file)
if (!file.exists(param$selection_file)) stop("Selection file not found: ", param$selection_file)

comb_dt <- fread(param$combined_file)
comb_dt[, test_date := as.Date(test_date)]

now_dt <- fread(param$nowcasts_file)
now_dt[, test_date := as.Date(test_date)]

sel_dt <- fread(param$selection_file)

# Ensure bic_avg exists
if (!"bic_avg" %in% names(sel_dt)) {
  if ("bic_sum" %in% names(sel_dt) && "n_forecasts" %in% names(sel_dt)) {
    sel_dt[, bic_avg := bic_sum / pmax(n_forecasts, 1)]
  } else if ("bic_sum" %in% names(sel_dt)) {
    sel_dt[, bic_avg := bic_sum]
  }
}

# Helper: compute weights
compute_weights <- function(x, scheme = c("bic", "rmse", "equal")) {
  scheme <- match.arg(scheme)
  w <- rep(NA_real_, length(x))
  if (scheme == "bic") {
    if (all(is.na(x))) return(rep(NA_real_, length(x)))
    d <- x - min(x, na.rm = TRUE)
    w <- exp(-0.5 * d)
  } else if (scheme == "rmse") {
    w <- 1 / (x^2)
  } else if (scheme == "equal") {
    w <- rep(1.0, length(x))
  }
  if (all(!is.finite(w)) || sum(w[is.finite(w)]) <= 0) return(rep(NA_real_, length(x)))
  w / sum(w, na.rm = TRUE)
}

cat("\n")
cat("═══════════════════════════════════════════════════════════════════════════\n")
cat("                    U-MIDAS NOWCASTING EXECUTIVE SUMMARY                   \n")
cat("═══════════════════════════════════════════════════════════════════════════\n")
cat("\n")

# ============================================================================
# 1. LATEST NOWCAST PER COMBINATION SCHEME
# ============================================================================

latest <- comb_dt[, .SD[which.max(as.Date(test_date))], by = quarter]
latest_q <- latest[which.max(as.Date(test_date)), quarter]
latest_row <- latest[quarter == latest_q]

cat("LATEST QUARTER:", latest_q, "\n")
cat("Latest vintage date:", as.character(latest_row$test_date), "\n")
cat("Number of indicators:", latest_row$n_models, "\n\n")

# Compute historical RMSE for each combination scheme
comb_schemes <- c("comb_bic", "comb_rmse", "comb_equal", "comb_trimmed")
scheme_names <- c("BIC-weighted", "RMSE-weighted", "Equal-weighted", "Trimmed Mean")

perf_summary <- data.table()
for (i in seq_along(comb_schemes)) {
  scheme_col <- comb_schemes[i]
  scheme_name <- scheme_names[i]
  
  if (scheme_col %in% names(comb_dt)) {
    # Calculate historical RMSE where y_true is available
    hist_data <- comb_dt[!is.na(y_true) & !is.na(get(scheme_col))]
    if (nrow(hist_data) > 0) {
      rmse_val <- sqrt(mean((hist_data[[scheme_col]] - hist_data$y_true)^2, na.rm = TRUE))
      mae_val <- mean(abs(hist_data[[scheme_col]] - hist_data$y_true), na.rm = TRUE)
      n_obs <- nrow(hist_data)
    } else {
      rmse_val <- NA_real_
      mae_val <- NA_real_
      n_obs <- 0L
    }
    
    perf_summary <- rbind(perf_summary, data.table(
      scheme = scheme_name,
      latest_nowcast = latest_row[[scheme_col]],
      historical_rmse = rmse_val,
      historical_mae = mae_val,
      n_obs = n_obs
    ))
  }
}

# Sort by historical RMSE (best first)
setorder(perf_summary, historical_rmse)

cat("─────────────────────────────────────────────────────────────────────────\n")
cat("ALL COMBINATION SCHEMES (sorted by historical RMSE)\n")
cat("─────────────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-20s %12s %12s %12s %8s\n", "Scheme", "Latest", "Hist RMSE", "Hist MAE", "N"))
cat("─────────────────────────────────────────────────────────────────────────\n")
for (i in seq_len(nrow(perf_summary))) {
  row <- perf_summary[i]
  cat(sprintf("%-20s %12.4f %12.4f %12.4f %8d\n",
              row$scheme,
              row$latest_nowcast,
              row$historical_rmse,
              row$historical_mae,
              row$n_obs))
}
cat("─────────────────────────────────────────────────────────────────────────\n")
cat("\n")

# Show actual if available
if (!is.na(latest_row$y_true)) {
  cat("ACTUAL VALUE:", sprintf("%.4f", latest_row$y_true), "\n\n")
} else {
  cat("ACTUAL VALUE: Not yet available\n\n")
}

# ============================================================================
# 2. TOP CONTRIBUTORS (by BIC and RMSE weights)
# ============================================================================

cat("─────────────────────────────────────────────────────────────────────────\n")
cat("TOP", param$top_n, "CONTRIBUTORS BY WEIGHT\n")
cat("─────────────────────────────────────────────────────────────────────────\n\n")

# Get latest nowcasts for all indicators
latest_now <- now_dt[quarter == latest_q & test_date == latest_row$test_date]
latest_now <- merge(latest_now, sel_dt[, .(variable, bic_avg, rmse, selected_p_gdp, selected_K_ind)], 
                    by = "variable", all.x = TRUE)

if (nrow(latest_now) > 0) {
  # BIC weights
  latest_now[, weight_bic := compute_weights(bic_avg, "bic"), by = .(quarter, test_date)]
  latest_now[, weight_rmse := compute_weights(rmse, "rmse"), by = .(quarter, test_date)]
  
  # Top by BIC weight
  top_bic <- latest_now[order(-weight_bic)][1:min(param$top_n, .N)]
  cat("By BIC Weight:\n")
  cat(sprintf("%-35s %10s %10s %10s %8s %8s\n", "Indicator", "Forecast", "Weight", "BIC", "p_GDP", "K_ind"))
  cat(strrep("─", 95), "\n")
  for (i in seq_len(nrow(top_bic))) {
    row <- top_bic[i]
    cat(sprintf("%-35s %10.4f %10.4f %10.2f %8d %8d\n",
                substr(row$variable, 1, 35),
                row$y_hat,
                row$weight_bic,
                row$bic_avg,
                row$selected_p_gdp,
                row$selected_K_ind))
  }
  cat("\n")
  
  # Top by RMSE weight
  top_rmse <- latest_now[order(-weight_rmse)][1:min(param$top_n, .N)]
  cat("By RMSE Weight:\n")
  cat(sprintf("%-35s %10s %10s %10s %8s %8s\n", "Indicator", "Forecast", "Weight", "RMSE", "p_GDP", "K_ind"))
  cat(strrep("─", 95), "\n")
  for (i in seq_len(nrow(top_rmse))) {
    row <- top_rmse[i]
    cat(sprintf("%-35s %10.4f %10.4f %10.4f %8d %8d\n",
                substr(row$variable, 1, 35),
                row$y_hat,
                row$weight_rmse,
                row$rmse,
                row$selected_p_gdp,
                row$selected_K_ind))
  }
  cat("\n")
} else {
  cat("No indicator-level nowcasts available for latest vintage.\n\n")
}

# ============================================================================
# 3. MONTH-BY-MONTH EVOLUTION IN CURRENT QUARTER
# ============================================================================

cat("─────────────────────────────────────────────────────────────────────────\n")
cat("EVOLUTION WITHIN", latest_q, "(by month of quarter)\n")
cat("─────────────────────────────────────────────────────────────────────────\n\n")

curr_q_data <- comb_dt[quarter == latest_q]

if ("month_of_quarter" %in% names(curr_q_data)) {
  # Aggregate by month
  month_agg <- curr_q_data[, {
    # Get latest Friday in each month
    .SD[which.max(test_date)]
  }, by = month_of_quarter]
  
  setorder(month_agg, month_of_quarter)
  
  cat(sprintf("%-8s %-12s %12s %12s %12s %12s %10s\n", 
              "Month", "Date", "BIC-wtd", "RMSE-wtd", "Equal-wtd", "Trimmed", "N Models"))
  cat(strrep("─", 90), "\n")
  
  for (i in seq_len(nrow(month_agg))) {
    row <- month_agg[i]
    cat(sprintf("%-8d %-12s %12.4f %12.4f %12.4f %12.4f %10d\n",
                row$month_of_quarter,
                as.character(row$test_date),
                if ("comb_bic" %in% names(row)) row$comb_bic else NA,
                if ("comb_rmse" %in% names(row)) row$comb_rmse else NA,
                if ("comb_equal" %in% names(row)) row$comb_equal else NA,
                if ("comb_trimmed" %in% names(row)) row$comb_trimmed else NA,
                row$n_models))
  }
  cat("\n")
} else {
  # Show all Fridays
  setorder(curr_q_data, test_date)
  cat(sprintf("%-12s %12s %12s %12s %12s %10s\n", 
              "Date", "BIC-wtd", "RMSE-wtd", "Equal-wtd", "Trimmed", "N Models"))
  cat(strrep("─", 80), "\n")
  
  for (i in seq_len(nrow(curr_q_data))) {
    row <- curr_q_data[i]
    cat(sprintf("%-12s %12.4f %12.4f %12.4f %12.4f %10d\n",
                as.character(row$test_date),
                if ("comb_bic" %in% names(row)) row$comb_bic else NA,
                if ("comb_rmse" %in% names(row)) row$comb_rmse else NA,
                if ("comb_equal" %in% names(row)) row$comb_equal else NA,
                if ("comb_trimmed" %in% names(row)) row$comb_trimmed else NA,
                row$n_models))
  }
  cat("\n")
}

# ============================================================================
# 4. HISTORICAL PERFORMANCE BY QUARTER
# ============================================================================

cat("─────────────────────────────────────────────────────────────────────────\n")
cat("HISTORICAL PERFORMANCE BY QUARTER (latest vintage per quarter)\n")
cat("─────────────────────────────────────────────────────────────────────────\n\n")

hist_perf <- latest[!is.na(y_true) & !is.na(comb_bic)]
setorder(hist_perf, quarter)

if (nrow(hist_perf) > 0) {
  cat(sprintf("%-8s %-12s %10s %12s %12s %12s %12s\n", 
              "Quarter", "Date", "Actual", "BIC-wtd", "RMSE-wtd", "Equal-wtd", "Trimmed"))
  cat(strrep("─", 90), "\n")
  
  for (i in seq_len(nrow(hist_perf))) {
    row <- hist_perf[i]
    cat(sprintf("%-8s %-12s %10.4f %12.4f %12.4f %12.4f %12.4f\n",
                row$quarter,
                as.character(row$test_date),
                row$y_true,
                if ("comb_bic" %in% names(row)) row$comb_bic else NA,
                if ("comb_rmse" %in% names(row)) row$comb_rmse else NA,
                if ("comb_equal" %in% names(row)) row$comb_equal else NA,
                if ("comb_trimmed" %in% names(row)) row$comb_trimmed else NA))
  }
  cat("\n")
  
  # Show errors
  cat("Errors (Forecast - Actual):\n")
  cat(sprintf("%-8s %12s %12s %12s %12s\n", 
              "Quarter", "BIC-wtd", "RMSE-wtd", "Equal-wtd", "Trimmed"))
  cat(strrep("─", 60), "\n")
  
  for (i in seq_len(nrow(hist_perf))) {
    row <- hist_perf[i]
    cat(sprintf("%-8s %12.4f %12.4f %12.4f %12.4f\n",
                row$quarter,
                if ("comb_bic" %in% names(row)) row$comb_bic - row$y_true else NA,
                if ("comb_rmse" %in% names(row)) row$comb_rmse - row$y_true else NA,
                if ("comb_equal" %in% names(row)) row$comb_equal - row$y_true else NA,
                if ("comb_trimmed" %in% names(row)) row$comb_trimmed - row$y_true else NA))
  }
  cat("\n")
} else {
  cat("No historical data with actuals available yet.\n\n")
}

# ============================================================================
# 5. DISTRIBUTION STATISTICS FOR LATEST NOWCAST
# ============================================================================

cat("─────────────────────────────────────────────────────────────────────────\n")
cat("DISTRIBUTION STATISTICS (Latest Vintage)\n")
cat("─────────────────────────────────────────────────────────────────────────\n\n")

cat(sprintf("%-20s: %10.4f\n", "Minimum", latest_row$min))
cat(sprintf("%-20s: %10.4f\n", "10th percentile", latest_row$p10))
cat(sprintf("%-20s: %10.4f\n", "25th percentile", latest_row$p25))
cat(sprintf("%-20s: %10.4f\n", "Median", latest_row$median))
cat(sprintf("%-20s: %10.4f\n", "Mean", latest_row$mean))
cat(sprintf("%-20s: %10.4f\n", "75th percentile", latest_row$p75))
cat(sprintf("%-20s: %10.4f\n", "90th percentile", latest_row$p90))
cat(sprintf("%-20s: %10.4f\n", "Maximum", latest_row$max))
cat(sprintf("%-20s: %10.4f\n", "Std deviation", latest_row$sd))
cat(sprintf("%-20s: %10.4f\n", "Trimmed mean (10%%)", latest_row$trimmed_mean))
cat(sprintf("%-20s: %10.4f\n", "Trimmed range (10%%)", latest_row$trimmed_range))
cat("\n")

cat("═══════════════════════════════════════════════════════════════════════════\n")
cat("                              END OF REPORT                                 \n")
cat("═══════════════════════════════════════════════════════════════════════════\n")

# Save to file
out_file <- file.path(param$out_dir, paste0("executive_summary_", latest_q, ".txt"))
sink(out_file)

cat("\n")
cat("═══════════════════════════════════════════════════════════════════════════\n")
cat("                    U-MIDAS NOWCASTING EXECUTIVE SUMMARY                   \n")
cat("═══════════════════════════════════════════════════════════════════════════\n")
cat("\nGenerated:", as.character(Sys.time()), "\n\n")
cat("LATEST QUARTER:", latest_q, "\n")
cat("Latest vintage date:", as.character(latest_row$test_date), "\n")
cat("Number of indicators:", latest_row$n_models, "\n\n")

cat("─────────────────────────────────────────────────────────────────────────\n")
cat("ALL COMBINATION SCHEMES (sorted by historical RMSE)\n")
cat("─────────────────────────────────────────────────────────────────────────\n")
cat(sprintf("%-20s %12s %12s %12s %8s\n", "Scheme", "Latest", "Hist RMSE", "Hist MAE", "N"))
cat("─────────────────────────────────────────────────────────────────────────\n")
for (i in seq_len(nrow(perf_summary))) {
  row <- perf_summary[i]
  cat(sprintf("%-20s %12.4f %12.4f %12.4f %8d\n",
              row$scheme,
              row$latest_nowcast,
              row$historical_rmse,
              row$historical_mae,
              row$n_obs))
}
cat("─────────────────────────────────────────────────────────────────────────\n")
cat("\n")

if (!is.na(latest_row$y_true)) {
  cat("ACTUAL VALUE:", sprintf("%.4f", latest_row$y_true), "\n\n")
} else {
  cat("ACTUAL VALUE: Not yet available\n\n")
}

if (nrow(latest_now) > 0) {
  cat("─────────────────────────────────────────────────────────────────────────\n")
  cat("TOP", param$top_n, "CONTRIBUTORS BY BIC WEIGHT\n")
  cat("─────────────────────────────────────────────────────────────────────────\n")
  cat(sprintf("%-35s %10s %10s %10s %8s %8s\n", "Indicator", "Forecast", "Weight", "BIC", "p_GDP", "K_ind"))
  cat(strrep("─", 95), "\n")
  for (i in seq_len(nrow(top_bic))) {
    row <- top_bic[i]
    cat(sprintf("%-35s %10.4f %10.4f %10.2f %8d %8d\n",
                substr(row$variable, 1, 35),
                row$y_hat,
                row$weight_bic,
                row$bic_avg,
                row$selected_p_gdp,
                row$selected_K_ind))
  }
  cat("\n")
}

sink()
cat("\nSaved executive summary to:", out_file, "\n")
