# Quick test of midasr U-MIDAS with GDP AR lags + monthly indicator lags

# Install if needed
if (!requireNamespace("midasr", quietly = TRUE)) {
  cat("Installing midasr...\n")
  install.packages("midasr", repos = "https://cloud.r-project.org")
}

suppressPackageStartupMessages(library(midasr))

# Simulated data
set.seed(42)
n_quarters <- 20
gdp_q <- cumsum(rnorm(n_quarters, mean = 0.5, sd = 1))
indicator_m <- cumsum(rnorm(n_quarters * 3, mean = 0.2, sd = 0.5))

# Convert to ts
gdp_ts <- ts(gdp_q, start = c(2020, 1), frequency = 4)
indicator_ts <- ts(indicator_m, start = c(2020, 1), frequency = 12)

cat("GDP (quarterly):", head(gdp_q), "...\n")
cat("Indicator (monthly):", head(indicator_m, 9), "...\n\n")

# Test 1: U-MIDAS with GDP AR(1) + monthly indicator lags 3-5 (simulating h=3)
cat("=== Test 1: U-MIDAS with GDP AR(1) + Indicator lags 3-5 ===\n")
tryCatch({
  # Using first 15 quarters for training
  gdp_train <- window(gdp_ts, end = c(2023, 3))
  ind_train <- window(indicator_ts, end = c(2023, 9))  # Through Sep 2023
  
  # Formula: y ~ mls(y, 1, 1) + mls(x, 3:5, 3)
  # - GDP lag 1 (1 quarter back)
  # - Indicator lags 3-5 (3-5 months back relative to quarter end)
  fit1 <- midas_r(gdp_train ~ mls(gdp_train, 1, 1) + mls(ind_train, 3:5, 3), start = NULL)
  
  cat("Model fitted successfully!\n")
  cat("Coefficients:\n")
  print(coef(fit1))
  cat("\nBIC:", BIC(fit1), "\n")
  
  # Forecast next quarter (2023Q4)
  pred <- predict(fit1)
  cat("Last fitted value:", tail(pred, 1), "\n")
  cat("Actual 2023Q4:", gdp_q[16], "\n\n")
  
}, error = function(e) {
  cat("Error in Test 1:", conditionMessage(e), "\n\n")
})

# Test 2: Just indicator lags (no GDP AR)
cat("=== Test 2: U-MIDAS with Indicator lags 3-8 only ===\n")
tryCatch({
  gdp_train <- window(gdp_ts, end = c(2023, 3))
  ind_train <- window(indicator_ts, end = c(2023, 9))
  
  fit2 <- midas_r(gdp_train ~ mls(ind_train, 3:8, 3), start = NULL)
  
  cat("Model fitted successfully!\n")
  cat("BIC:", BIC(fit2), "\n\n")
  
}, error = function(e) {
  cat("Error in Test 2:", conditionMessage(e), "\n\n")
})

# Test 3: GDP AR(2) + Indicator lags 3-6
cat("=== Test 3: U-MIDAS with GDP AR(2) + Indicator lags 3-6 ===\n")
tryCatch({
  gdp_train <- window(gdp_ts, end = c(2023, 3))
  ind_train <- window(indicator_ts, end = c(2023, 9))
  
  fit3 <- midas_r(gdp_train ~ mls(gdp_train, 1:2, 1) + mls(ind_train, 3:6, 3), start = NULL)
  
  cat("Model fitted successfully!\n")
  cat("Coefficients:\n")
  print(coef(fit3))
  cat("\nBIC:", BIC(fit3), "\n\n")
  
}, error = function(e) {
  cat("Error in Test 3:", conditionMessage(e), "\n\n")
})

cat("All tests complete.\n")
