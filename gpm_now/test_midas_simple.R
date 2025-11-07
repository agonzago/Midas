#!/usr/bin/env Rscript
# Simple test to understand midasr forecast behavior

library(midasr)

# Create simple test data
set.seed(123)
n_q <- 60
n_m <- n_q * 3

y_q <- ts(cumsum(rnorm(n_q, 0.5, 1)), frequency = 4)
x_m <- ts(cumsum(rnorm(n_m, 0.2, 0.5)), frequency = 12)

cat("=== Test 1: Model without Y lags ===\n")
fit1 <- midas_u(y_q ~ mls(x_m, 2:4, 3))
cat("Model fitted\n")
cat("Coefficients:", length(coef(fit1)), "\n")

# Try to forecast - USE ORIGINAL VARIABLE NAMES
cat("\nAttempting forecast without Y lags...\n")
x_new <- tail(x_m, 3)
cat("x_new:", x_new, "\n")

tryCatch({
  fc1 <- forecast(fit1, newdata = list(x_m = x_new), method = "static")
  cat("Forecast successful:", fc1$mean, "\n")
}, error = function(e) {
  cat("ERROR:", e$message, "\n")
})

cat("\n=== Test 2: Model with Y lags ===\n")
fit2 <- midas_u(y_q ~ mls(y_q, 1:2, 1) + mls(x_m, 2:4, 3))
cat("Model fitted\n")
cat("Coefficients:", length(coef(fit2)), "\n")

# Try to forecast - USE ORIGINAL VARIABLE NAMES
cat("\nAttempting forecast with Y lags...\n")
y_new <- tail(y_q, 2)
x_new <- tail(x_m, 3)
cat("y_new:", y_new, "\n")
cat("x_new:", x_new, "\n")

tryCatch({
  fc2 <- forecast(fit2, newdata = list(y_q = y_new, x_m = x_new), method = "static")
  cat("Forecast successful:", fc2$mean, "\n")
}, error = function(e) {
  cat("ERROR:", e$message, "\n")
})

cat("\n=== Test 3: Try with c() wrapping (like old code) ===\n")
tryCatch({
  fc3 <- forecast(fit2, newdata = list(y_q = c(tail(y_q, 1)), x_m = c(x_new)), method = "static")
  cat("Forecast successful:", fc3$mean, "\n")
}, error = function(e) {
  cat("ERROR:", e$message, "\n")
})

cat("\n=== Test 4: Check what newdata structure is expected ===\n")
cat("Model formula:", deparse(formula(fit2)), "\n")
cat("Model terms:", names(fit2$model), "\n")
