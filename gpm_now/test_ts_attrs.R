library(midasr)

# Create simple test data
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

cat("Original y_q:\n")
cat("  Class:", class(y_q), "\n")
cat("  Length:", length(y_q), "\n")
cat("  Start:", start(y_q), "\n")
cat("  Frequency:", frequency(y_q), "\n")

cat("\nOriginal x_m:\n")
cat("  Class:", class(x_m), "\n")
cat("  Length:", length(x_m), "\n")
cat("  Start:", start(x_m), "\n")
cat("  Frequency:", frequency(x_m), "\n")

# Extend with ts()
y_ext <- c(y_q, NA)
x_ext <- c(x_m, rep(NA, 3))

cat("\nAfter c() - y_ext:\n")
cat("  Class:", class(y_ext), "\n")
cat("  Is ts?:", inherits(y_ext, "ts"), "\n")

cat("\nAfter c() - x_ext:\n")
cat("  Class:", class(x_ext), "\n")
cat("  Is ts?:", inherits(x_ext, "ts"), "\n")

# Reconstruct ts
y_ext_ts <- ts(y_ext, start = start(y_q), frequency = frequency(y_q))
x_ext_ts <- ts(x_ext, start = start(x_m), frequency = frequency(x_m))

cat("\nAfter ts() - y_ext_ts:\n")
cat("  Class:", class(y_ext_ts), "\n")
cat("  Length:", length(y_ext_ts), "\n")
cat("  Start:", start(y_ext_ts), "\n")
cat("  End:", end(y_ext_ts), "\n")

cat("\nAfter ts() - x_ext_ts:\n")
cat("  Class:", class(x_ext_ts), "\n")
cat("  Length:", length(x_ext_ts), "\n")
cat("  Start:", start(x_ext_ts), "\n")
cat("  End:", end(x_ext_ts), "\n")

# Fit model
cat("\nFitting model...\n")
model <- midas_u(y_q ~ mls(y_q, 1:2, 1) + mls(x_m, 2:6, 3))

# Try forecast with ts objects
cat("\nForecasting with ts objects...\n")
newdata_ts <- list(y_q = y_ext_ts, x_m = x_ext_ts)

tryCatch({
  fc <- forecast::forecast(model, newdata = newdata_ts, method = "static")
  cat("SUCCESS! Forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})
