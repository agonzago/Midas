#!/usr/bin/env Rscript
# example_run.R
# Example script demonstrating the GPM Now weekly nowcasting system

# Set working directory to gpm_now folder
# setwd("path/to/gpm_now")

cat("=== GPM Now Weekly Nowcasting System ===\n")
cat("Example demonstration\n\n")

# Load the main runner
cat("Loading runner module...\n")
source("R/runner.R")

# Example 1: Run for current date
cat("\n--- Example 1: Current Date Nowcast ---\n")
tryCatch({
  result <- run_weekly_nowcast(as_of_date = Sys.Date())
  
  cat("\nResults:\n")
  cat(sprintf("  As-of date: %s\n", result$as_of_date))
  cat(sprintf("  Current quarter: %s\n", result$current_quarter))
  cat(sprintf("  Combined nowcast: %.2f%%\n", result$combined_forecast$point))
  cat(sprintf("  95%% interval: [%.2f, %.2f]\n", 
              result$combined_forecast$lo, 
              result$combined_forecast$hi))
  cat(sprintf("  Number of models: %d\n", result$combined_forecast$n_models))
  
  if (!is.null(result$combined_forecast$weights)) {
    cat("\n  Model weights:\n")
    weights <- result$combined_forecast$weights
    for (name in names(weights)) {
      cat(sprintf("    %s: %.3f\n", name, weights[[name]]))
    }
  }
  
  cat("\n  Models updated:\n")
  for (model in result$models_updated) {
    cat(sprintf("    - %s\n", model))
  }
  
  if (!is.null(result$news) && nrow(result$news) > 0) {
    cat("\n  News vs. last week:\n")
    print(result$news)
  }
  
}, error = function(e) {
  cat("Error running nowcast:\n")
  cat(paste("  ", e$message, "\n"))
})

# Example 2: Run for specific date
cat("\n\n--- Example 2: Specific Date Nowcast ---\n")
specific_date <- as.Date("2023-12-15")
cat(sprintf("Running nowcast for: %s\n", specific_date))

tryCatch({
  result2 <- run_weekly_nowcast(as_of_date = specific_date)
  
  cat(sprintf("\nCombined nowcast: %.2f%%\n", result2$combined_forecast$point))
  
}, error = function(e) {
  cat("Error running nowcast:\n")
  cat(paste("  ", e$message, "\n"))
})

# Example 3: Access individual model forecasts
cat("\n\n--- Example 3: Individual Model Forecasts ---\n")

tryCatch({
  result <- run_weekly_nowcast(as_of_date = Sys.Date())
  
  cat("\nIndividual forecasts:\n")
  
  for (model_name in names(result$individual_forecasts)) {
    fcst <- result$individual_forecasts[[model_name]]
    
    if (!is.null(fcst$point) && !is.na(fcst$point)) {
      cat(sprintf("  %s:\n", model_name))
      cat(sprintf("    Point: %.2f%%\n", fcst$point))
      if (!is.null(fcst$se)) {
        cat(sprintf("    SE: %.2f\n", fcst$se))
      }
    }
  }
  
}, error = function(e) {
  cat("Error:\n")
  cat(paste("  ", e$message, "\n"))
})

cat("\n\n=== Example Complete ===\n")
cat("Check output/weekly_reports/ for detailed results\n")
cat("Check output/logs/ for execution logs\n")
cat("Check data/vintages/ for data snapshots\n")
