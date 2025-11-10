# Test script to verify MIDAS fixes
# This script tests the key fixes made to resolve NaN forecasts

suppressPackageStartupMessages({
  library(midasr)
  library(data.table)
})

source("R/midas_models.R")

cat("=== Testing MIDAS Fixes ===\n\n")

# Test 1: Variable name extraction from model
cat("Test 1: Verify variable name extraction in predict function\n")
test_variable_names <- function() {
  # Create simple test data
  set.seed(123)
  y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
  x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)
  
  # Use our fit function which stores the data
  model <- tryCatch({
    fit_midas_unrestricted(y_q, x_m, y_lag = 2, x_lag = 3, month_of_quarter = 2)
  }, error = function(e) {
    cat("  ERROR fitting model:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(model)) {
    cat("  FAILED: Could not fit test model\n")
    return(FALSE)
  }
  
  # Test prediction with new data
  x_new <- c(100, 105, NA)  # Only 2 months available
  
  result <- tryCatch({
    predict_midas_unrestricted(model, y_new = NULL, x_new = x_new)
  }, error = function(e) {
    cat("  ERROR in prediction:", e$message, "\n")
    return(NULL)
  })
  
  if (is.null(result)) {
    cat("  FAILED: Prediction returned NULL\n")
    return(FALSE)
  }
  
  if (is.na(result$point)) {
    cat("  FAILED: Prediction returned NA\n")
    cat("  Error details:", result$meta$error, "\n")
    return(FALSE)
  }
  
  cat("  PASSED: Prediction =", round(result$point, 3), "\n")
  return(TRUE)
}

test1_result <- test_variable_names()

# Test 2: Data extraction with ragged edge
cat("\nTest 2: Verify ragged-edge data extraction\n")
test_ragged_edge <- function() {
  # Create mock vintage data
  vintage <- list(
    X_m = data.frame(
      date = seq(as.Date("2020-01-01"), by = "month", length.out = 36),
      series_id = rep("indicator1", 36),
      value = rnorm(36, mean = 100, sd = 10)
    )
  )
  
  # Test extraction without lag_map (should use simple tail logic)
  x_new <- extract_forecast_data(vintage, "indicator1", is_lagged = FALSE)
  
  if (is.null(x_new)) {
    cat("  FAILED: extract_forecast_data returned NULL\n")
    return(FALSE)
  }
  
  if (length(x_new) != 3) {
    cat("  FAILED: Expected 3 values, got", length(x_new), "\n")
    return(FALSE)
  }
  
  cat("  PASSED: Extracted", length(x_new), "values:", 
      paste(round(x_new, 2), collapse = ", "), "\n")
  
  # Test with lagged indicator
  x_lagged <- extract_forecast_data(vintage, "indicator1", is_lagged = TRUE)
  
  if (length(x_lagged) != 3) {
    cat("  FAILED: Expected 3 values for lagged, got", length(x_lagged), "\n")
    return(FALSE)
  }
  
  cat("  PASSED: Lagged extraction also returns 3 values\n")
  return(TRUE)
}

test2_result <- test_ragged_edge()

# Test 3: Lag specification doesn't create errors
cat("\nTest 3: Verify lag specification in model fitting\n")
test_lag_specification <- function() {
  set.seed(456)
  y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
  x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)
  
  # Test with month_of_quarter = 2 (first month available)
  model <- fit_midas_unrestricted(
    y_q = y_q,
    x_m = x_m,
    y_lag = 2,
    x_lag = 4,
    month_of_quarter = 2
  )
  
  if (is.null(model)) {
    cat("  FAILED: fit_midas_unrestricted returned NULL\n")
    return(FALSE)
  }
  
  cat("  PASSED: Model fitted successfully\n")
  cat("  Model has", length(model$coefficients), "coefficients\n")
  cat("  RMSE =", round(sqrt(mean(model$residuals^2)), 3), "\n")
  
  return(TRUE)
}

test3_result <- test_lag_specification()

# Summary
cat("\n=== Test Summary ===\n")
cat("Test 1 (Variable names):", ifelse(test1_result, "PASSED", "FAILED"), "\n")
cat("Test 2 (Ragged edge):", ifelse(test2_result, "PASSED", "FAILED"), "\n")
cat("Test 3 (Lag specification):", ifelse(test3_result, "PASSED", "FAILED"), "\n")

all_passed <- test1_result && test2_result && test3_result
cat("\nOverall:", ifelse(all_passed, "ALL TESTS PASSED", "SOME TESTS FAILED"), "\n")

if (!all_passed) {
  cat("\nPlease review the failures above and check the implementation.\n")
  quit(status = 1)
}

cat("\n=== All tests passed! The fixes appear to be working correctly. ===\n")
