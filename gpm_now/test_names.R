library(midasr)

# Create data
set.seed(123)
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

# Test 1: Create formula inside function
cat("==== Test 1: Formula created inside function ====\n")
fit_fn <- function(yy, xx, y_lag, x_lag, moq) {
  fml <- as.formula(sprintf("yy ~ midasr::mls(yy, 1:%d, 1) + midasr::mls(xx, %d:%d, 3)",
                            y_lag, moq, moq + x_lag))
  cat("Formula:", deparse(fml), "\n")
  fit <- midasr::midas_u(fml)
  return(fit)
}

model1 <- fit_fn(y_q, x_m, 2, 3, 2)

# Try forecast
y_ext <- c(y_q, NA)
x_ext <- c(x_m, rep(NA, 3))
newdata1 <- list(yy = y_ext, xx = x_ext)

cat("\nForecasting with model1:\n")
tryCatch({
  fc <- forecast::forecast(model1, newdata = newdata1, method = "static")
  cat("SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

# Test 2: Create formula outside function but with same names
cat("\n==== Test 2: Formula created outside function ====\n")
y_lag <- 2
x_lag <- 3
moq <- 2
fml2 <- as.formula(sprintf("y_q ~ midasr::mls(y_q, 1:%d, 1) + midasr::mls(x_m, %d:%d, 3)",
                           y_lag, moq, moq + x_lag))
model2 <- midasr::midas_u(fml2)

y_ext2 <- c(y_q, NA)
x_ext2 <- c(x_m, rep(NA, 3))
newdata2 <- list(y_q = y_ext2, x_m = x_ext2)

cat("\nForecasting with model2:\n")
tryCatch({
  fc <- forecast::forecast(model2, newdata = newdata2, method = "static")
  cat("SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})
