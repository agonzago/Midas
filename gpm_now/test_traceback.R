library(midasr)
source("R/midas_models.R")

# Create simple test data
set.seed(123)
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

# Generate new data for forecast
y_new <- rnorm(1, mean = 2, sd = 0.5)
x_new <- rnorm(3, mean = 100, sd = 10)

# Fit model
cat("Fitting model...\n")
model <- fit_midas_unrestricted(
  y_q = y_q,
  x_m = x_m,
  y_lag = 2,
  x_lag = 4,
  month_of_quarter = 2
)

cat("Calling predict with traceback...\n")
result <- tryCatch({
  predict_midas_unrestricted(model, y_new, x_new)
}, error = function(e) {
  cat("ERROR DETAILS:\n")
  cat("Message:", e$message, "\n")
  cat("Call:", deparse(e$call), "\n")
  cat("\nFull traceback:\n")
  traceback()
  return(NA)
})

cat("Result:", result, "\n")
