# Minimal debug test
suppressPackageStartupMessages({
  library(midasr)
  library(forecast)
})

source("R/midas_models.R")

options(error = function() {
  traceback(2)
  quit(status = 1)
})

set.seed(123)
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

cat("Fitting model...\n")
model <- fit_midas_unrestricted(y_q, x_m, y_lag = 2, x_lag = 3, month_of_quarter = 2)

cat("Model fitted successfully\n")
cat("y_data length:", length(model$y_data), "\n")
cat("x_data length:", length(model$x_data), "\n")

x_new <- c(100, 105, NA)
cat("Calling predict...\n")

result <- predict_midas_unrestricted(model, NULL, x_new)

cat("Result:", result$point, "\n")
