library(midasr)

# Create data
set.seed(123)
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

# Test 1: Using as.formula with sprintf
cat("==== Test 1: Using as.formula(sprintf(...)) ====\n")
fml1 <- as.formula(sprintf("y_q ~ midasr::mls(y_q, 1:%d, 1) + midasr::mls(x_m, %d:%d, 3)", 2, 2, 5))
cat("Formula:", deparse(fml1), "\n")
model1 <- midasr::midas_u(fml1)

y_ext <- c(y_q, NA)
x_ext <- c(x_m, rep(NA, 3))
newdata <- list(y_q = y_ext, x_m = x_ext)

cat("\nForecasting:\n")
tryCatch({
  fc <- forecast::forecast(model1, newdata = newdata, method = "static")
  cat("SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

# Test 2: Literal formula
cat("\n==== Test 2: Using literal formula ====\n")
model2 <- midasr::midas_u(y_q ~ midasr::mls(y_q, 1:2, 1) + midasr::mls(x_m, 2:5, 3))

cat("\nForecasting:\n")
tryCatch({
  fc <- forecast::forecast(model2, newdata = newdata, method = "static")
  cat("SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

# Test 3: Using as.formula without sprintf
cat("\n==== Test 3: Using as.formula without sprintf ====\n")
fml3 <- as.formula("y_q ~ midasr::mls(y_q, 1:2, 1) + midasr::mls(x_m, 2:5, 3)")
cat("Formula:", deparse(fml3), "\n")
model3 <- midasr::midas_u(fml3)

cat("\nForecasting:\n")
tryCatch({
  fc <- forecast::forecast(model3, newdata = newdata, method = "static")
  cat("SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})
