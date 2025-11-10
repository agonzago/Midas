library(midasr)

# Create simple test data
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

# Define lags
y_lag <- 2
x_lag <- 4
month_of_quarter <- 2

cat("Fitting model with variables in formula...\n")
model1 <- midas_u(y_q ~ mls(y_q, 1:y_lag, 1) + mls(x_m, month_of_quarter:(month_of_quarter + x_lag), 3))

cat("\nModel formula:\n")
print(formula(model1))

cat("\nFormula terms:\n")
print(attr(terms(model1), "term.labels"))

cat("\nModel names:\n")
print(names(model1$model))

cat("\n\nFitting model with literal numbers...\n")
model2 <- midas_u(y_q ~ mls(y_q, 1:2, 1) + mls(x_m, 2:6, 3))

cat("\nModel2 formula:\n")
print(formula(model2))

cat("\nModel2 terms:\n")
print(attr(terms(model2), "term.labels"))

cat("\nTrying forecast with model1...\n")
y_ext1 <- c(y_q, NA)
x_ext1 <- c(x_m, rep(NA, 3))
newdata1 <- list(y_q = y_ext1, x_m = x_ext1)

tryCatch({
  fc1 <- forecast::forecast(model1, newdata = newdata1, method = "static")
  cat("SUCCESS! Forecast:", tail(fc1$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

cat("\nTrying forecast with model2...\n")
y_ext2 <- c(y_q, NA)
x_ext2 <- c(x_m, rep(NA, 3))
newdata2 <- list(y_q = y_ext2, x_m = x_ext2)

tryCatch({
  fc2 <- forecast::forecast(model2, newdata = newdata2, method = "static")
  cat("SUCCESS! Forecast:", tail(fc2$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})
