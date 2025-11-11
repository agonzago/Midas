# Example: MIDAS Model Combination
# This script demonstrates how to use the new MIDAS combination features

# Load required libraries
library(midasr)

# Source the runner
setwd("gpm_now")
source("R/runner.R")

# =============================================================================
# Example 1: Run with default settings
# =============================================================================

cat("\n=== Example 1: Default MIDAS Combination ===\n")

# Run nowcast (MIDAS combination happens automatically)
result <- run_weekly_nowcast(
  as_of_date = Sys.Date(),
  config_path = "config",
  data_path = "data",
  output_path = "output"
)

# Access MIDAS combinations
if (!is.null(result$midas_combinations)) {
  cat("\n--- MIDAS Combination Results ---\n")
  
  # Simple average
  if ("equal" %in% names(result$midas_combinations)) {
    cat("\nSimple Average:\n")
    cat("  Point forecast:", result$midas_combinations$equal$point, "\n")
    cat("  95% CI: [", result$midas_combinations$equal$lo, ",", 
        result$midas_combinations$equal$hi, "]\n")
  }
  
  # BIC-weighted
  if ("inv_bic" %in% names(result$midas_combinations)) {
    cat("\nBIC-weighted:\n")
    cat("  Point forecast:", result$midas_combinations$inv_bic$point, "\n")
    cat("  95% CI: [", result$midas_combinations$inv_bic$lo, ",", 
        result$midas_combinations$inv_bic$hi, "]\n")
    cat("  Top 3 models by weight:\n")
    top_weights <- sort(result$midas_combinations$inv_bic$weights, decreasing = TRUE)[1:3]
    for (i in seq_along(top_weights)) {
      cat("    ", names(top_weights)[i], ":", round(top_weights[i], 3), "\n")
    }
  }
  
  # RMSE-weighted
  if ("inv_rmse" %in% names(result$midas_combinations)) {
    cat("\nRMSE-weighted:\n")
    cat("  Point forecast:", result$midas_combinations$inv_rmse$point, "\n")
    cat("  95% CI: [", result$midas_combinations$inv_rmse$lo, ",", 
        result$midas_combinations$inv_rmse$hi, "]\n")
  }
  
  # Metadata
  if ("metadata" %in% names(result$midas_combinations)) {
    meta <- result$midas_combinations$metadata
    cat("\nCombination Metadata:\n")
    cat("  Original models:", meta$n_models_original, "\n")
    cat("  After trimming:", meta$n_models_trimmed, "\n")
    cat("  Trim percentile:", meta$trim_percentile, "\n")
    if (length(meta$trimmed_models) > 0) {
      cat("  Trimmed models:", paste(meta$trimmed_models, collapse = ", "), "\n")
    }
  }
}

# =============================================================================
# Example 2: Custom configuration
# =============================================================================

cat("\n\n=== Example 2: Custom Trim Percentile ===\n")

# Create custom config programmatically
custom_cfg <- yaml::read_yaml("config/options.yaml")
custom_cfg$midas_trim_percentile <- 0.30  # Trim worst 30%
custom_cfg$midas_combination_schemes <- c("equal", "inv_rmse")  # Only 2 schemes

# Save temporarily
temp_config <- tempfile(fileext = ".yaml")
yaml::write_yaml(custom_cfg, temp_config)

# Note: For production use, modify config/options.yaml directly

cat("Custom configuration:\n")
cat("  Trim percentile: 30%\n")
cat("  Schemes: equal, inv_rmse\n")

# =============================================================================
# Example 3: Comparing combinations
# =============================================================================

cat("\n\n=== Example 3: Comparing Combination Schemes ===\n")

if (!is.null(result$midas_combinations)) {
  schemes <- c("equal", "inv_bic", "inv_rmse")
  
  cat("\nForecast comparison:\n")
  cat(sprintf("%-15s %10s %10s %10s\n", "Scheme", "Forecast", "Lower", "Upper"))
  cat(strrep("-", 50), "\n")
  
  for (scheme in schemes) {
    if (scheme %in% names(result$midas_combinations)) {
      combo <- result$midas_combinations[[scheme]]
      cat(sprintf("%-15s %10.3f %10.3f %10.3f\n", 
                  scheme, combo$point, combo$lo, combo$hi))
    }
  }
  
  # Calculate spread
  forecasts <- sapply(schemes, function(s) {
    if (s %in% names(result$midas_combinations)) {
      result$midas_combinations[[s]]$point
    } else {
      NA
    }
  })
  forecasts <- forecasts[!is.na(forecasts)]
  
  if (length(forecasts) > 1) {
    cat("\nForecast spread:", round(max(forecasts) - min(forecasts), 3), "\n")
    cat("Average forecast:", round(mean(forecasts), 3), "\n")
  }
}

# =============================================================================
# Example 4: Accessing output files
# =============================================================================

cat("\n\n=== Example 4: Output Files ===\n")

# List output files
output_dir <- "output/weekly_reports"
if (dir.exists(output_dir)) {
  files <- list.files(output_dir, pattern = as.character(Sys.Date()), full.names = TRUE)
  
  if (length(files) > 0) {
    cat("Output files created:\n")
    for (f in files) {
      cat("  ", basename(f), "\n")
    }
    
    # Read JSON if available
    json_file <- files[grepl("\\.json$", files)]
    if (length(json_file) > 0) {
      cat("\nJSON structure preview:\n")
      json_data <- jsonlite::read_json(json_file[1])
      if (!is.null(json_data$midas_combinations)) {
        cat("  Available combinations:", paste(names(json_data$midas_combinations), collapse = ", "), "\n")
      }
    }
    
    # Read CSV if available
    csv_file <- files[grepl("\\.csv$", files)]
    if (length(csv_file) > 0) {
      cat("\nCSV columns:\n")
      csv_data <- read.csv(csv_file[1])
      midas_cols <- grep("^midas_", names(csv_data), value = TRUE)
      if (length(midas_cols) > 0) {
        cat("  MIDAS combination columns:", paste(midas_cols, collapse = ", "), "\n")
      }
    }
  }
}

# =============================================================================
# Example 5: Manual combination call
# =============================================================================

cat("\n\n=== Example 5: Manual Combination (Advanced) ===\n")

# This shows how to call the combination function directly
# Useful for custom workflows or testing

if (exists("midas_indiv") && length(midas_indiv) > 0) {
  cat("Calling combine_midas_forecasts() directly...\n")
  
  # Manual call with custom parameters
  manual_combo <- combine_midas_forecasts(
    midas_indiv,
    trim_percentile = 0.20,  # More aggressive trimming
    schemes = c("equal", "inv_bic", "inv_rmse")
  )
  
  cat("\nManual combination completed!\n")
  cat("Number of combinations:", length(manual_combo) - 1, "\n")  # -1 for metadata
}

cat("\n=== Examples Complete ===\n")
cat("\nFor more information, see:\n")
cat("  - gpm_now/MIDAS_COMBINATION_GUIDE.md\n")
cat("  - MIDAS_COMBINATION_SUMMARY.md\n")
