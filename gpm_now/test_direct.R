# Direct test without tryCatch
suppressPackageStartupMessages({
  library(midasr)
  library(forecast)
})

set.seed(123)
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

# Fit
fit <- midas_u(y_q ~ mls(y_q, 1:2, 1) + mls(x_m, 2:5, 3))

model <- list(
  fit = fit,
  y_data = y_q,
  x_data = x_m,
  y_lag = 2,
  x_lag = 3
)

# Extract names
model_data <- model$fit$model
y_name <- names(model_data)[1]
cat("y_name:", y_name, "\n")

model_terms <- terms(model$fit)
term_labels <- attr(model_terms, "term.labels")
cat("term_labels:", term_labels, "\n")

x_name <- NULL
for (term_label in term_labels) {
  if (grepl("mls\\([^,]+,", term_label)) {
    var_name <- sub(".*mls\\(([^,]+),.*", "\\1", term_label)
    var_name <- gsub("lag\\(|\\)", "", var_name)
    var_name <- trimws(var_name)
    cat("Found variable:", var_name, "\n")
    
    # Skip if this is the Y variable (AR term)
    if (var_name != y_name) {
      x_name <- var_name
      break
    }
  }
}
cat("x_name:", x_name, "\n")

# Get data
y_hist <- model$y_data
x_hist <- model$x_data

cat("y_hist length:", length(y_hist), "\n")
cat("x_hist length:", length(x_hist), "\n")

# Extend
y_extended <- c(y_hist, NA)
x_new <- c(100, 105, NA)
x_extended <- c(x_hist, x_new)

cat("y_extended length:", length(y_extended), "\n")
cat("x_extended length:", length(x_extended), "\n")

# Check ts
y_is_ts <- inherits(y_hist, "ts")
x_is_ts <- inherits(x_hist, "ts")

cat("y_is_ts:", y_is_ts, "\n")
cat("x_is_ts:", x_is_ts, "\n")

if (y_is_ts) {
  y_extended <- ts(y_extended, start = start(y_hist), frequency = frequency(y_hist))
}
if (x_is_ts) {
  x_extended <- ts(x_extended, start = start(x_hist), frequency = frequency(x_hist))
}

cat("Creating newdata...\n")
newdata <- list()
newdata[[y_name]] <- y_extended
newdata[[x_name]] <- x_extended

cat("Forecasting...\n")
forecast_obj <- forecast(model$fit, newdata = newdata, method = "static")

cat("Done! Forecast:", tail(forecast_obj$mean, 1), "\n")
