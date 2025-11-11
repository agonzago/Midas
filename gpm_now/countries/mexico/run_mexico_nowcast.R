# run_mexico_nowcast.R
# Mexico Weekly Nowcast Runner
# 
# This script runs the weekly nowcast for Mexico, using:
# - Common core functions from gpm_now/common/
# - Mexico-specific configurations and data
# - MIDAS models with combination and structural break handling
# - TPRF (Three-Pass Regression Filter) models

library(midasr)
library(zoo)
library(yaml)
library(jsonlite)

# Set working directory to Mexico country folder
# Works from command line or RStudio
if (interactive() && requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  setwd(dirname(rstudioapi::getSourceEditorContext()$path))
} else {
  # Get script path when sourced
  script_path <- getSrcDirectory(function() {})
  if (script_path != "") {
    setwd(script_path)
  } else {
    # Fallback: assume we're already in the right directory
    cat("Note: Could not detect script location. Using current directory.\n")
    cat("Current directory:", getwd(), "\n")
  }
}

# Source all common core functions
common_path <- "../../common"
source(file.path(common_path, "utils.R"))
source(file.path(common_path, "transforms.R"))
source(file.path(common_path, "lagmap.R"))
source(file.path(common_path, "midas_models.R"))
source(file.path(common_path, "tprf_models.R"))
source(file.path(common_path, "dfm_models.R"))
source(file.path(common_path, "selection.R"))
source(file.path(common_path, "combine.R"))
source(file.path(common_path, "structural_breaks.R"))
source(file.path(common_path, "news.R"))

# Source Mexico-specific runner and I/O functions
source("R/io.R")
source("R/runner.R")

# Run the nowcast
cat("\n========================================\n")
cat("   Mexico Weekly Nowcast\n")
cat("========================================\n\n")

result <- run_weekly_nowcast(
  as_of_date = Sys.Date(),
  config_path = "config",
  data_path = "data",
  output_path = "output"
)

# Print summary
if (!is.null(result)) {
  cat("\n========================================\n")
  cat("   Nowcast Complete\n")
  cat("========================================\n")
  cat(sprintf("Target Quarter: %s\n", result$metadata$target_quarter))
  cat(sprintf("As-of Date: %s\n", result$metadata$as_of_date))
  cat(sprintf("\nForecasts:\n"))
  
  if (!is.null(result$forecasts$midas)) {
    cat(sprintf("  MIDAS Models: %d fitted\n", length(result$forecasts$midas)))
    if (!is.null(result$forecasts$midas_combination)) {
      cat(sprintf("  MIDAS Combinations:\n"))
      cat(sprintf("    - Equal weights: %.2f%%\n", result$forecasts$midas_combination$equal))
      cat(sprintf("    - Inverse BIC: %.2f%%\n", result$forecasts$midas_combination$inv_bic))
      cat(sprintf("    - Inverse RMSE: %.2f%%\n", result$forecasts$midas_combination$inv_rmse))
    }
  }
  
  if (!is.null(result$forecasts$tprf)) {
    cat(sprintf("  TPRF Models: %d fitted\n", length(result$forecasts$tprf)))
  }
  
  cat(sprintf("\nOutputs saved to: %s\n", result$metadata$output_path))
  cat("========================================\n\n")
} else {
  cat("\nNowcast failed. Check logs for details.\n\n")
}
