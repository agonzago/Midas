# transforms.R
# Seasonal adjustment and transformation helpers

#' Apply transformation to a time series
#' @param x Numeric vector
#' @param transform Type of transformation
#' @return Transformed vector
apply_transform <- function(x, transform) {
  if (is.null(transform) || transform == "none" || transform == "level") {
    return(x)
  }
  
  result <- switch(transform,
    "log" = log(x),
    "diff" = c(NA, diff(x)),
    "pct_mom" = 100 * (x / lag(x, 1) - 1),
    "pct_mom_sa" = 100 * (x / lag(x, 1) - 1),  # Assumes data is already SA
    "pct_qoq" = 100 * (x / lag(x, 1) - 1),
    "pct_yoy" = 100 * (x / lag(x, 12) - 1),
    "pct_yoy_q" = 100 * (x / lag(x, 4) - 1),
    "log_diff" = c(NA, diff(log(x))),
    x  # default: return as-is
  )
  
  return(result)
}

#' Lag function that works with vectors
#' @param x Numeric vector
#' @param k Number of lags (positive for backward, negative for forward)
#' @return Lagged vector
lag <- function(x, k = 1) {
  if (k == 0) return(x)
  n <- length(x)
  
  if (k > 0) {
    # Backward lag
    c(rep(NA, k), x[1:(n - k)])
  } else {
    # Forward lag
    k <- abs(k)
    c(x[(k + 1):n], rep(NA, k))
  }
}

#' Aggregate monthly data to quarterly (simple average)
#' @param monthly_data Data frame with date and value columns
#' @param method Aggregation method ("mean", "sum", "last")
#' @return Data frame with quarterly aggregated data
aggregate_monthly_to_quarterly <- function(monthly_data, method = "mean") {
  if (!requireNamespace("dplyr", quietly = TRUE)) {
    stop("Package 'dplyr' required. Install with: install.packages('dplyr')")
  }
  if (!requireNamespace("lubridate", quietly = TRUE)) {
    stop("Package 'lubridate' required. Install with: install.packages('lubridate')")
  }
  
  # Add quarter column
  monthly_data$quarter <- paste0(
    lubridate::year(monthly_data$date), 
    "Q", 
    lubridate::quarter(monthly_data$date)
  )
  
  # Aggregate
  if (method == "mean") {
    quarterly_data <- monthly_data %>%
      dplyr::group_by(quarter) %>%
      dplyr::summarise(value = mean(value, na.rm = TRUE), .groups = "drop")
  } else if (method == "sum") {
    quarterly_data <- monthly_data %>%
      dplyr::group_by(quarter) %>%
      dplyr::summarise(value = sum(value, na.rm = TRUE), .groups = "drop")
  } else if (method == "last") {
    quarterly_data <- monthly_data %>%
      dplyr::group_by(quarter) %>%
      dplyr::summarise(value = dplyr::last(value), .groups = "drop")
  } else {
    stop("Unknown aggregation method: ", method)
  }
  
  return(quarterly_data)
}

#' Align monthly data to quarterly frequency
#' @param monthly_vec Monthly vector
#' @param target_quarters Vector of target quarters
#' @param method Alignment method
#' @return Vector aligned to quarterly frequency
align_monthly_to_quarterly <- function(monthly_vec, target_quarters, method = "mean") {
  # Simplified alignment - in practice would need proper date handling
  # This is a placeholder for the actual implementation
  warning("align_monthly_to_quarterly is a placeholder implementation")
  return(rep(NA, length(target_quarters)))
}

#' Create lagged matrix for MIDAS regression
#' @param x Monthly series vector
#' @param lag_min Minimum lag (in months)
#' @param lag_max Maximum lag (in months)
#' @param horizon Forecast horizon
#' @return Matrix with lagged values
create_midas_lag_matrix <- function(x, lag_min = 0, lag_max = 11, horizon = 0) {
  n <- length(x)
  n_lags <- lag_max - lag_min + 1
  
  # Create matrix to hold lags
  lag_mat <- matrix(NA, nrow = n, ncol = n_lags)
  
  for (i in 1:n_lags) {
    lag_val <- lag_min + i - 1 + horizon
    if (lag_val >= 0 && lag_val < n) {
      lag_mat[, i] <- lag(x, lag_val)
    }
  }
  
  colnames(lag_mat) <- paste0("L", lag_min:lag_max)
  return(lag_mat)
}

#' Seasonal adjustment placeholder
#' @param x Time series vector
#' @param frequency Frequency (12 for monthly, 4 for quarterly)
#' @return Seasonally adjusted series
seasonal_adjust <- function(x, frequency = 12) {
  # Placeholder for seasonal adjustment
  # In practice, would use X-13ARIMA-SEATS or similar
  warning("seasonal_adjust is a placeholder. Use proper SA methods in production.")
  
  # Simple moving average deseasonalization
  if (length(x) < frequency * 2) {
    return(x)
  }
  
  # Calculate seasonal factors (simplified)
  n <- length(x)
  seasons <- rep(1:frequency, length.out = n)
  
  # This is a very simplified approach - use proper methods in production
  return(x)
}
