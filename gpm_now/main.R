#!/usr/bin/env Rscript
# main.R
# Main entry point for the GPM Now weekly nowcasting system
# Usage: Rscript main.R [date]
# Example: Rscript main.R 2024-01-15

args <- commandArgs(trailingOnly = TRUE)

# Parse date argument if provided
if (length(args) > 0) {
  as_of_date <- as.Date(args[1])
  cat(sprintf("Running nowcast for specified date: %s\n", as_of_date))
} else {
  as_of_date <- Sys.Date()
  cat(sprintf("Running nowcast for today: %s\n", as_of_date))
}

# Source the runner
source("R/runner.R")

# Run the weekly nowcast
cat("\nStarting GPM Now weekly nowcasting system...\n")
cat(paste(rep("=", 60), collapse = ""), "\n", sep = "")

result <- run_weekly_nowcast(as_of_date = as_of_date)

cat("\n")
cat(paste(rep("=", 60), collapse = ""), "\n", sep = "")
cat("NOWCAST SUMMARY\n")
cat(paste(rep("=", 60), collapse = ""), "\n", sep = "")
cat(sprintf("As of: %s\n", result$as_of_date))
cat(sprintf("Quarter: %s\n", result$current_quarter))
cat("\n")
cat(sprintf("Combined Nowcast: %.2f%%\n", result$combined_forecast$point))
cat(sprintf("95%% Confidence Interval: [%.2f%%, %.2f%%]\n", 
            result$combined_forecast$lo, result$combined_forecast$hi))
cat(sprintf("Standard Error: %.2f\n", result$combined_forecast$se))
cat("\n")

if (!is.null(result$combined_forecast$weights)) {
  cat("Model Weights:\n")
  weights <- result$combined_forecast$weights
  for (name in names(weights)) {
    cat(sprintf("  %-20s: %.3f\n", name, weights[[name]]))
  }
  cat("\n")
}

cat(sprintf("Models Updated: %d\n", length(result$models_updated)))
for (model in result$models_updated) {
  cat(sprintf("  - %s\n", model))
}
cat("\n")

if (!is.null(result$news) && nrow(result$news) > 0) {
  cat("News vs. Previous Week:\n")
  combined_news <- result$news[result$news$series_id == "COMBINED", ]
  if (nrow(combined_news) > 0) {
    cat(sprintf("  Overall change: %.2f pp (from %.2f to %.2f)\n",
                combined_news$delta_nowcast_pp[1],
                combined_news$prev_value[1],
                combined_news$new_value[1]))
  }
  cat("\n")
}

cat(paste(rep("=", 60), collapse = ""), "\n", sep = "")
cat("\nOutputs saved to:\n")
cat("  - output/weekly_reports/\n")
cat("  - output/logs/\n")
cat("  - data/vintages/\n")
cat("\nDone!\n")
