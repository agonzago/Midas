# Integration test: Full MIDAS workflow with all fixes applied
library(midasr)
source("R/midas_models.R")

cat("=== MIDAS Integration Test ===\n\n")

# Create realistic test data
set.seed(42)
n_quarters <- 50
n_months <- n_quarters * 3

# Quarterly GDP-like series
y_q <- ts(cumsum(rnorm(n_quarters, mean = 0.5, sd = 0.3)) + 100, 
          start = c(2010, 1), frequency = 4)

# Monthly indicator series
x_m <- ts(rnorm(n_months, mean = 50, sd = 5), 
          start = c(2010, 1), frequency = 12)

cat("Data created:\n")
cat("  y_q: ", length(y_q), " quarterly observations\n")
cat("  x_m: ", length(x_m), " monthly observations\n\n")

# Test 1: Fit MIDAS model (lagged indicator)
cat("Test 1: Lagged indicator MIDAS model\n")
model_lagged <- fit_midas_unrestricted(
  y_q = y_q,
  x_m = x_m,
  y_lag = 2,
  x_lag = 4,
  month_of_quarter = NULL  # Lagged indicator
)

if (!is.null(model_lagged)) {
  cat("  ✓ Model fitted successfully\n")
  cat("  Coefficients:", length(coef(model_lagged$fit)), "\n")
  cat("  RMSE:", round(sqrt(mean(model_lagged$residuals^2)), 3), "\n")
  
  # Make forecast
  y_new <- tail(y_q, 2)
  x_new <- tail(x_m, 3)
  forecast_lagged <- predict_midas_unrestricted(model_lagged, y_new, x_new)
  
  if (!is.na(forecast_lagged$point)) {
    cat("  ✓ Forecast successful:", round(forecast_lagged$point, 3), "\n")
  } else {
    cat("  ✗ Forecast failed\n")
  }
} else {
  cat("  ✗ Model fitting failed\n")
}

# Test 2: Fit MIDAS model (current indicator)
cat("\nTest 2: Current indicator MIDAS model\n")
model_current <- fit_midas_unrestricted(
  y_q = y_q,
  x_m = x_m,
  y_lag = 2,
  x_lag = 4,
  month_of_quarter = 2  # Current indicator, 1st month available
)

if (!is.null(model_current)) {
  cat("  ✓ Model fitted successfully\n")
  cat("  Coefficients:", length(coef(model_current$fit)), "\n")
  cat("  RMSE:", round(sqrt(mean(model_current$residuals^2)), 3), "\n")
  
  # Make forecast with ragged edge (only 1 month available)
  y_new <- tail(y_q, 2)
  x_new <- tail(x_m, 1)  # Only first month of quarter
  forecast_current <- predict_midas_unrestricted(model_current, y_new, x_new)
  
  if (!is.na(forecast_current$point)) {
    cat("  ✓ Forecast successful:", round(forecast_current$point, 3), "\n")
  } else {
    cat("  ✗ Forecast failed\n")
  }
} else {
  cat("  ✗ Model fitting failed\n")
}

# Test 3: Different lag specifications
cat("\nTest 3: Varying lag specifications\n")
test_specs <- list(
  list(y_lag = 0, x_lag = 3, moq = 2),
  list(y_lag = 1, x_lag = 2, moq = 1),
  list(y_lag = 3, x_lag = 6, moq = NULL)
)

success_count <- 0
for (i in seq_along(test_specs)) {
  spec <- test_specs[[i]]
  model <- fit_midas_unrestricted(y_q, x_m, spec$y_lag, spec$x_lag, spec$moq)
  
  if (!is.null(model)) {
    y_new <- if (spec$y_lag > 0) tail(y_q, spec$y_lag) else NULL
    x_new <- tail(x_m, 3)
    fc <- predict_midas_unrestricted(model, y_new, x_new)
    
    if (!is.na(fc$point)) {
      success_count <- success_count + 1
      cat(sprintf("  Spec %d (y_lag=%d, x_lag=%d, moq=%s): ✓ Forecast=%.3f\n",
                  i, spec$y_lag, spec$x_lag, 
                  ifelse(is.null(spec$moq), "NULL", spec$moq),
                  fc$point))
    }
  }
}

cat(sprintf("\n  %d/%d specifications successful\n", success_count, length(test_specs)))

# Summary
cat("\n=== Integration Test Summary ===\n")
if (success_count == length(test_specs) && 
    !is.na(forecast_lagged$point) && 
    !is.na(forecast_current$point)) {
  cat("✓ ALL TESTS PASSED\n")
  cat("✓ MIDAS implementation is working correctly\n")
} else {
  cat("✗ SOME TESTS FAILED\n")
}
