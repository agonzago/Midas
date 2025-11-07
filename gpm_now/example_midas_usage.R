#!/usr/bin/env Rscript
# example_midas_usage.R
# Example of using the refactored MIDAS implementation

# This script demonstrates:
# 1. BIC-based model selection for individual indicators
# 2. Fitting MIDAS models with selected specifications
# 3. Generating forecasts
# 4. BIC-weighted forecast combination

library(midasr)

# Source the refactored MIDAS functions
source("R/midas_models.R")
source("R/combine.R")

# ============================================================================
# EXAMPLE 1: Single indicator with BIC selection
# ============================================================================

cat("=== EXAMPLE 1: Single Indicator MIDAS ===\n\n")

# Simulate some data (in practice, load from vintage)
set.seed(123)
n_quarters <- 60
n_months <- n_quarters * 3

# Quarterly GDP growth
y_q <- ts(cumsum(rnorm(n_quarters, mean = 0.5, sd = 1)), frequency = 4)

# Monthly indicator (e.g., PMI)
x_m <- ts(cumsum(rnorm(n_months, mean = 0.2, sd = 0.5)), frequency = 12)

# Select best specification using BIC
cat("Selecting best MIDAS specification...\n")
spec <- select_midas_spec_bic(
  y_q = y_q,
  x_m = x_m,
  max_y_lag = 4,
  max_x_lag = 6,
  month_of_quarter = 2  # First month of quarter
)

cat("Selected specification:\n")
cat("  - Y lags:", spec$y_lag, "\n")
cat("  - X lags:", spec$x_lag, "\n")
cat("  - BIC:", round(spec$bic, 2), "\n\n")

# Fit model with selected specification
cat("Fitting MIDAS model...\n")
model <- fit_midas_unrestricted(
  y_q = y_q,
  x_m = x_m,
  y_lag = spec$y_lag,
  x_lag = spec$x_lag,
  month_of_quarter = 2
)

cat("Model fitted successfully\n")
cat("  - Number of observations:", model$n_obs, "\n")
cat("  - Number of coefficients:", length(model$coefficients), "\n\n")

# Generate forecast
cat("Generating forecast...\n")
y_new <- if (spec$y_lag > 0) tail(y_q, spec$y_lag) else NULL
x_new <- tail(x_m, 3)  # Last 3 months (one quarter) - following old code pattern

forecast <- predict_midas_unrestricted(model, y_new, x_new)

cat("Forecast:\n")
cat("  - Point:", round(forecast$point, 2), "\n")
cat("  - Std Error:", round(forecast$se, 2), "\n\n")

# ============================================================================
# EXAMPLE 2: Multiple indicators with BIC weighting
# ============================================================================

cat("\n=== EXAMPLE 2: Multiple Indicators with BIC Weighting ===\n\n")

# Simulate 5 different monthly indicators
n_indicators <- 5
indicators <- list()
for (i in 1:n_indicators) {
  indicators[[paste0("IND_", i)]] <- ts(
    cumsum(rnorm(n_months, mean = 0.3, sd = 0.6)),
    frequency = 12
  )
}

# Fit MIDAS for each indicator and collect forecasts
all_forecasts <- list()
all_bics <- c()

cat("Fitting MIDAS models for", n_indicators, "indicators...\n\n")

for (ind_name in names(indicators)) {
  cat("Processing", ind_name, "...\n")
  
  # Select specification
  spec <- select_midas_spec_bic(
    y_q = y_q,
    x_m = indicators[[ind_name]],
    max_y_lag = 4,
    max_x_lag = 6,
    month_of_quarter = 2
  )
  
  # Fit model
  model <- fit_midas_unrestricted(
    y_q = y_q,
    x_m = indicators[[ind_name]],
    y_lag = spec$y_lag,
    x_lag = spec$x_lag,
    month_of_quarter = 2
  )
  
  # Forecast
  y_new <- if (spec$y_lag > 0) tail(y_q, spec$y_lag) else NULL
  x_new <- tail(indicators[[ind_name]], 3)  # Last 3 months
  
  forecast <- predict_midas_unrestricted(model, y_new, x_new)
  
  # Store results
  forecast$bic <- spec$bic
  all_forecasts[[ind_name]] <- forecast
  all_bics <- c(all_bics, spec$bic)
  names(all_bics)[length(all_bics)] <- ind_name
  
  cat("  Forecast:", round(forecast$point, 2), 
      ", BIC:", round(spec$bic, 2), "\n")
}

# Calculate BIC-based weights
cat("\nCalculating BIC-based weights...\n")
weights <- 1 / all_bics
weights <- weights / sum(weights)

cat("\nWeights:\n")
for (ind_name in names(weights)) {
  cat("  ", ind_name, ":", round(weights[ind_name], 3), "\n")
}

# Combined forecast
combined_point <- sum(weights * sapply(all_forecasts, function(x) x$point))
cat("\nCombined forecast (BIC-weighted):", round(combined_point, 2), "\n")

# Compare with equal weights
equal_weights <- rep(1/n_indicators, n_indicators)
equal_combined <- sum(equal_weights * sapply(all_forecasts, function(x) x$point))
cat("Combined forecast (equal weights):", round(equal_combined, 2), "\n")

# ============================================================================
# EXAMPLE 3: Lagged indicator (published with delay)
# ============================================================================

cat("\n\n=== EXAMPLE 3: Lagged Indicator (Published with Delay) ===\n\n")

# Simulate a lagged indicator (e.g., imports, industrial production)
x_m_lagged <- ts(cumsum(rnorm(n_months, mean = 0.4, sd = 0.7)), frequency = 12)

cat("Selecting specification for lagged indicator...\n")
spec_lagged <- select_midas_spec_bic_lagged(
  y_q = y_q,
  x_m = x_m_lagged,
  max_y_lag = 4,
  max_x_lag = 6
)

cat("Selected specification:\n")
cat("  - Y lags:", spec_lagged$y_lag, "\n")
cat("  - X lags:", spec_lagged$x_lag, "\n")
cat("  - BIC:", round(spec_lagged$bic, 2), "\n\n")

# Fit model (note: month_of_quarter = NULL for lagged structure)
model_lagged <- fit_midas_unrestricted(
  y_q = y_q,
  x_m = x_m_lagged,
  y_lag = spec_lagged$y_lag,
  x_lag = spec_lagged$x_lag,
  month_of_quarter = NULL  # NULL triggers lagged specification
)

# Forecast (for lagged indicators, use last complete quarter of data)
y_new <- if (spec_lagged$y_lag > 0) tail(y_q, spec_lagged$y_lag) else NULL
x_new <- tail(x_m_lagged, 3)  # Last 3 months (1 quarter)

forecast_lagged <- predict_midas_unrestricted(model_lagged, y_new, x_new)

cat("Forecast from lagged indicator:\n")
cat("  - Point:", round(forecast_lagged$point, 2), "\n")
cat("  - Std Error:", round(forecast_lagged$se, 2), "\n\n")

# ============================================================================
# EXAMPLE 4: Using the main wrapper function
# ============================================================================

cat("\n=== EXAMPLE 4: Using fit_or_update_midas_set() ===\n\n")

# Create a mock vintage and configuration
vintage <- list(
  y_q = list(value = y_q),
  X_m = data.frame(
    series_id = rep(names(indicators), each = n_months),
    value = unlist(indicators),
    stringsAsFactors = FALSE
  )
)

cfg <- list(
  midas_max_y_lag = 4,
  midas_max_x_lag = 6,
  midas_month_of_quarter = 2,
  lagged_indicators = c(),  # Empty for this example
  current_indicators = names(indicators),
  window = NULL
)

# Run the main function
cat("Running fit_or_update_midas_set()...\n\n")
midas_results <- fit_or_update_midas_set(vintage, lag_map = NULL, cfg)

cat("\n=== Results Summary ===\n")
cat("Number of models fitted:", length(midas_results), "\n")

if (length(midas_results) > 0) {
  # Extract weighted nowcast
  weights <- sapply(midas_results, function(x) x$weight)
  points <- sapply(midas_results, function(x) x$point)
  weighted_nowcast <- sum(weights * points)
  
  cat("Weighted MIDAS Nowcast:", round(weighted_nowcast, 2), "\n\n")
  
  cat("Individual contributions:\n")
  for (ind_name in names(midas_results)) {
    cat(sprintf("  %-10s: %.2f (weight: %.3f)\n",
                ind_name,
                midas_results[[ind_name]]$point,
                midas_results[[ind_name]]$weight))
  }
}

cat("\n=== Examples Complete ===\n")
