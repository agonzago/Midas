# Generate Comprehensive Forecast Evaluation Report
# Compares MIDAS vs TPRF-MIDAS with detailed diagnostics

library(midasr)
source("R/midas_models.R")
source("R/tprf_models.R")

# Load results from rolling evaluation
if (!file.exists("rolling_evaluation_results.csv")) {
  stop("Please run 'run_rolling_evaluation.R' first to generate results")
}

results <- read.csv("rolling_evaluation_results.csv")

cat(paste(rep("=", 80), collapse=""), "\n")
cat("MIDAS NOWCASTING EVALUATION REPORT\n")
cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

# Section 1: Executive Summary
cat("1. EXECUTIVE SUMMARY\n")
cat(paste(rep("-", 80), collapse=""), "\n\n")

midas_models <- results[grep("^MIDAS_", results$spec), ]
tprf_models <- results[grep("^TPRF_", results$spec), ]

cat("Models Evaluated:\n")
cat("  - MIDAS (single indicator):", nrow(midas_models), "specifications\n")
cat("  - TPRF-MIDAS (factor-based):", nrow(tprf_models), "specifications\n\n")

best_overall <- results[which.min(results$rmse), ]
cat("Best Overall Model:\n")
cat("  Specification:", best_overall$spec, "\n")
cat("  RMSE:", round(best_overall$rmse, 4), "\n")
cat("  MAE:", round(best_overall$mae, 4), "\n")
cat("  Mean Error:", round(best_overall$me, 4), "\n")
cat("  Number of forecasts:", best_overall$n_forecasts, "\n\n")

# Section 2: MIDAS Models
cat("\n2. MIDAS MODELS (Single Indicator)\n")
cat(paste(rep("-", 80), collapse=""), "\n\n")

cat("Performance Metrics:\n")
print(midas_models[order(midas_models$rmse), ])
cat("\n")

best_midas <- midas_models[which.min(midas_models$rmse), ]
cat("Best MIDAS Specification:", best_midas$spec, "\n")
cat("  RMSE:", round(best_midas$rmse, 4), "\n")
cat("  MAE:", round(best_midas$mae, 4), "\n")
cat("  Mean Error (Bias):", round(best_midas$me, 4), "\n\n")

# Section 3: TPRF-MIDAS Models
if (nrow(tprf_models) > 0) {
  cat("\n3. TPRF-MIDAS MODELS (Factor-Based)\n")
  cat(paste(rep("-", 80), collapse=""), "\n\n")
  
  cat("Three-Pass Regression Filter extracts common factors from panel of indicators\n")
  cat("Then uses factors as regressors in MIDAS framework\n\n")
  
  cat("Performance Metrics:\n")
  print(tprf_models[order(tprf_models$rmse), ])
  cat("\n")
  
  best_tprf <- tprf_models[which.min(tprf_models$rmse), ]
  cat("Best TPRF Specification:", best_tprf$spec, "\n")
  cat("  RMSE:", round(best_tprf$rmse, 4), "\n")
  cat("  MAE:", round(best_tprf$mae, 4), "\n")
  cat("  Mean Error (Bias):", round(best_tprf$me, 4), "\n\n")
}

# Section 4: MIDAS vs TPRF Comparison
if (nrow(tprf_models) > 0 && nrow(midas_models) > 0) {
  cat("\n4. MIDAS VS TPRF-MIDAS COMPARISON\n")
  cat(paste(rep("-", 80), collapse=""), "\n\n")
  
  rmse_improvement <- best_midas$rmse - best_tprf$rmse
  rmse_improvement_pct <- (rmse_improvement / best_midas$rmse) * 100
  
  mae_improvement <- best_midas$mae - best_tprf$mae
  mae_improvement_pct <- (mae_improvement / best_midas$mae) * 100
  
  cat("Root Mean Squared Error (RMSE):\n")
  cat("  Best MIDAS:", sprintf("%8.4f", best_midas$rmse), "\n")
  cat("  Best TPRF: ", sprintf("%8.4f", best_tprf$rmse), "\n")
  cat("  Difference:", sprintf("%8.4f", rmse_improvement), 
      sprintf("(%+.2f%%)", rmse_improvement_pct), "\n\n")
  
  cat("Mean Absolute Error (MAE):\n")
  cat("  Best MIDAS:", sprintf("%8.4f", best_midas$mae), "\n")
  cat("  Best TPRF: ", sprintf("%8.4f", best_tprf$mae), "\n")
  cat("  Difference:", sprintf("%8.4f", mae_improvement), 
      sprintf("(%+.2f%%)", mae_improvement_pct), "\n\n")
  
  cat("Mean Error (Bias):\n")
  cat("  Best MIDAS:", sprintf("%8.4f", best_midas$me), "\n")
  cat("  Best TPRF: ", sprintf("%8.4f", best_tprf$me), "\n")
  cat("  Difference:", sprintf("%8.4f", best_midas$me - best_tprf$me), "\n\n")
  
  # Interpretation
  cat("Interpretation:\n")
  if (abs(rmse_improvement_pct) < 2) {
    cat("  - Performance is similar between MIDAS and TPRF (<2% difference)\n")
  } else if (rmse_improvement_pct > 2) {
    cat("  - TPRF shows improvement of", round(abs(rmse_improvement_pct), 1), "%\n")
    cat("  - Factor extraction successfully captures additional information\n")
  } else {
    cat("  - MIDAS performs better by", round(abs(rmse_improvement_pct), 1), "%\n")
    cat("  - Single indicator may be more robust than factor model\n")
  }
  
  # Statistical test (Diebold-Mariano if we had the forecasts)
  cat("\n")
}

# Section 5: Model Specifications
cat("\n5. MODEL SPECIFICATIONS DETAILS\n")
cat(paste(rep("-", 80), collapse=""), "\n\n")

cat("MIDAS Models:\n")
cat("  - Use single economic activity indicator (EAI)\n")
cat("  - Mixed-frequency: monthly indicator -> quarterly forecast\n")
cat("  - Incorporates lags of both Y (GDP) and X (indicator)\n")
cat("  - Handles ragged edge (incomplete quarter data)\n\n")

if (nrow(tprf_models) > 0) {
  cat("TPRF-MIDAS Models:\n")
  cat("  - Extract latent factors from panel of indicators\n")
  cat("  - Three-Pass Regression Filter handles missing data\n")
  cat("  - Uses 2 factors capturing common variation\n")
  cat("  - Factors replace single indicator in MIDAS regression\n")
  cat("  - Combines information from multiple indicators efficiently\n\n")
}

cat("Window Types:\n")
cat("  - Expanding: Uses all available historical data\n")
cat("  - Rolling (40Q): Uses fixed window of last 40 quarters\n\n")

# Section 6: Recommendations
cat("\n6. RECOMMENDATIONS\n")
cat(paste(rep("-", 80), collapse=""), "\n\n")

if (best_overall$spec == best_midas$spec) {
  cat("1. RECOMMENDED MODEL: ", best_midas$spec, "\n")
  cat("   - Best overall performance\n")
  cat("   - Simpler specification (single indicator)\n")
  cat("   - More robust and interpretable\n\n")
} else if (nrow(tprf_models) > 0 && best_overall$spec == best_tprf$spec) {
  cat("1. RECOMMENDED MODEL: ", best_tprf$spec, "\n")
  cat("   - Best overall performance\n")
  cat("   - Leverages multiple indicators through factors\n")
  cat("   - More comprehensive information set\n\n")
}

cat("2. Model Selection Considerations:\n")
cat("   - Lower RMSE indicates better forecast accuracy\n")
cat("   - Mean error shows systematic bias (should be close to 0)\n")
cat("   - Compare expanding vs rolling windows for stability\n\n")

cat("3. Next Steps:\n")
cat("   - Review plots in 'rolling_evaluation_plots.pdf'\n")
cat("   - Check for periods with large forecast errors\n")
cat("   - Consider updating indicators if available\n")
cat("   - Re-evaluate after adding new data\n\n")

# Section 7: Technical Notes
cat("\n7. TECHNICAL NOTES\n")
cat(paste(rep("-", 80), collapse=""), "\n\n")

cat("Evaluation Method:\n")
cat("  - Out-of-sample rolling window evaluation\n")
cat("  - Pseudo-real-time: models use only data available at each forecast date\n")
cat("  - Initial training window: 60 quarters\n")
cat("  - Ragged edge: Only 1 month of current quarter available\n\n")

cat("TPRF Implementation:\n")
cat("  - Factors re-extracted at each forecast origin\n")
cat("  - No look-ahead bias\n")
cat("  - Handles unbalanced panel with missing observations\n")
cat("  - Standardized indicators before factor extraction\n\n")

cat(paste(rep("=", 80), collapse=""), "\n")
cat("END OF REPORT\n")
cat(paste(rep("=", 80), collapse=""), "\n")

# Save report
sink("forecast_evaluation_report.txt")
cat(paste(rep("=", 80), collapse=""), "\n")
cat("MIDAS NOWCASTING EVALUATION REPORT\n")
cat("Generated:", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), "\n")
cat(paste(rep("=", 80), collapse=""), "\n\n")

cat("1. EXECUTIVE SUMMARY\n")
cat(paste(rep("-", 80), collapse=""), "\n\n")
cat("Models Evaluated:\n")
cat("  - MIDAS (single indicator):", nrow(midas_models), "specifications\n")
cat("  - TPRF-MIDAS (factor-based):", nrow(tprf_models), "specifications\n\n")
cat("Best Overall Model:\n")
cat("  Specification:", best_overall$spec, "\n")
cat("  RMSE:", round(best_overall$rmse, 4), "\n")
cat("  MAE:", round(best_overall$mae, 4), "\n\n")

cat("2. FULL RESULTS\n")
cat(paste(rep("-", 80), collapse=""), "\n\n")
print(results[order(results$rmse), ])

if (nrow(tprf_models) > 0 && nrow(midas_models) > 0) {
  cat("\n\n3. COMPARISON\n")
  cat(paste(rep("-", 80), collapse=""), "\n\n")
  cat("Best MIDAS:  RMSE =", round(best_midas$rmse, 4), ", MAE =", round(best_midas$mae, 4), "\n")
  cat("Best TPRF:   RMSE =", round(best_tprf$rmse, 4), ", MAE =", round(best_tprf$mae, 4), "\n")
  cat("Improvement:", round((best_midas$rmse - best_tprf$rmse)/best_midas$rmse * 100, 2), "%\n")
}

sink()

cat("\n✓ Report saved to: forecast_evaluation_report.txt\n")
