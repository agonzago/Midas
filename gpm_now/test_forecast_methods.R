library(midasr)

# Create simple test data
set.seed(123)
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

cat("Fitting model...\n")
model <- midas_u(y_q ~ mls(y_q, 1:2, 1) + mls(x_m, 2:6, 3))

# Extend data
y_ext <- c(y_q, NA)
x_ext <- c(x_m, rep(NA, 3))

# Make ts
y_ext_ts <- ts(y_ext, start = start(y_q), frequency = frequency(y_q))
x_ext_ts <- ts(x_ext, start = start(x_m), frequency = frequency(x_m))

newdata <- list(y_q = y_ext_ts, x_m = x_ext_ts)

cat("\n\nTesting forecast with different options...\n")

# Option 1: method="static"
cat("\n1. method='static':\n")
tryCatch({
  fc <- forecast::forecast(model, newdata = newdata, method = "static")
  cat("   SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("   FAILED:", e$message, "\n")
})

# Option 2: method="dynamic"
cat("\n2. method='dynamic':\n")
tryCatch({
  fc <- forecast::forecast(model, newdata = newdata, method = "dynamic")
  cat("   SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("   FAILED:", e$message, "\n")
})

# Option 3: No method specified
cat("\n3. No method:\n")
tryCatch({
  fc <- forecast::forecast(model, newdata = newdata)
  cat("   SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("   FAILED:", e$message, "\n")
})

# Option 4: midasr::forecast.midas_r instead of forecast::forecast
cat("\n4. Using midasr::forecast.midas_r:\n")
tryCatch({
  fc <- midasr::forecast.midas_r(model, newdata = newdata, method = "static")
  cat("   SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("   FAILED:", e$message, "\n")
})
