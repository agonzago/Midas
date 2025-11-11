# structural_breaks.R
# Functions for handling structural breaks in MIDAS models

#' Detect structural break using CUSUM or Chow test
#' @param y Time series
#' @param break_candidates Vector of candidate break dates (indices)
#' @return List with break_point and test statistics
detect_structural_break <- function(y, break_candidates = NULL) {
  if (!requireNamespace("strucchange", quietly = TRUE)) {
    warning("Package 'strucchange' not available. Using simple variance-based detection.")
    return(detect_break_simple(y))
  }
  
  tryCatch({
    # Use BIC to detect breakpoint
    bp_test <- strucchange::breakpoints(y ~ 1, breaks = 1)
    
    if (!is.na(bp_test$breakpoints[1])) {
      break_point <- bp_test$breakpoints[1]
      return(list(
        break_point = break_point,
        break_date = time(y)[break_point],
        method = "BIC"
      ))
    } else {
      return(NULL)
    }
  }, error = function(e) {
    warning("Structural break detection failed: ", e$message)
    return(NULL)
  })
}

#' Simple break detection based on rolling mean shift
#' @param y Time series
#' @return List with break point
detect_break_simple <- function(y, window = 8) {
  n <- length(y)
  if (n < 2 * window) {
    return(NULL)
  }
  
  # Calculate rolling means
  mean_shifts <- numeric(n - 2 * window)
  
  for (i in (window + 1):(n - window)) {
    before_mean <- mean(y[(i - window):(i - 1)], na.rm = TRUE)
    after_mean <- mean(y[i:(i + window - 1)], na.rm = TRUE)
    mean_shifts[i - window] <- abs(after_mean - before_mean)
  }
  
  # Find largest shift
  max_shift_idx <- which.max(mean_shifts) + window
  
  return(list(
    break_point = max_shift_idx,
    break_date = if (inherits(y, "ts")) time(y)[max_shift_idx] else max_shift_idx,
    method = "rolling_mean",
    shift_magnitude = max(mean_shifts)
  ))
}

#' Calculate intercept adjustment for structural break
#' @param y Actual values
#' @param y_fitted Fitted values
#' @param break_point Index of structural break
#' @param window Window for estimating adjustment (quarters)
#' @return Adjustment value
calculate_intercept_adjustment <- function(y, y_fitted, break_point, window = 4) {
  n <- length(y)
  
  if (break_point >= n) {
    return(0)
  }
  
  # Calculate mean residual in window after break
  start_idx <- break_point
  end_idx <- min(break_point + window - 1, n)
  
  if (end_idx <= start_idx) {
    return(0)
  }
  
  # Mean forecast error after break
  post_break_errors <- y[start_idx:end_idx] - y_fitted[start_idx:end_idx]
  adjustment <- mean(post_break_errors, na.rm = TRUE)
  
  return(adjustment)
}

#' Apply intercept adjustment to MIDAS forecast
#' @param model MIDAS model object
#' @param break_info Break information (from detect_structural_break)
#' @param current_period Current forecast period
#' @param adjustment_window Window for calculating adjustment
#' @return Adjustment value to add to forecast
get_intercept_adjustment <- function(model, break_info, current_period, 
                                     adjustment_window = 4) {
  if (is.null(break_info) || is.null(model$fitted_values)) {
    return(0)
  }
  
  break_point <- break_info$break_point
  
  # Only apply adjustment if we're forecasting after the break
  if (current_period <= break_point) {
    return(0)
  }
  
  # Check if we have enough post-break data to estimate adjustment
  n_fitted <- length(model$fitted_values)
  
  if (break_point >= n_fitted) {
    return(0)
  }
  
  # Use data immediately after break to estimate level shift
  y_actual <- model$fit$model$y
  y_fitted <- model$fitted_values
  
  adjustment <- calculate_intercept_adjustment(
    y_actual, 
    y_fitted, 
    break_point, 
    adjustment_window
  )
  
  return(adjustment)
}

#' Fit MIDAS with structural break (regime-specific models)
#' @param y_q Quarterly target
#' @param x_m Monthly indicator
#' @param break_point Break point index
#' @param y_lag Y lags
#' @param x_lag X lags
#' @param month_of_quarter Month of quarter parameter
#' @return List with pre-break and post-break models
fit_midas_with_break <- function(y_q, x_m, break_point, y_lag, x_lag, 
                                  month_of_quarter = NULL) {
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Package 'midasr' required")
  }
  
  # Split data at break
  y_pre <- window(y_q, end = time(y_q)[break_point - 1])
  x_pre <- window(x_m, end = time(x_m)[(break_point - 1) * 3])
  
  y_post <- window(y_q, start = time(y_q)[break_point])
  x_post <- window(x_m, start = time(x_m)[(break_point - 1) * 3 + 1])
  
  # Fit pre-break model
  model_pre <- tryCatch({
    fit_midas_unrestricted(y_pre, x_pre, y_lag, x_lag, month_of_quarter)
  }, error = function(e) NULL)
  
  # Fit post-break model
  model_post <- tryCatch({
    fit_midas_unrestricted(y_post, x_post, y_lag, x_lag, month_of_quarter)
  }, error = function(e) NULL)
  
  return(list(
    model_pre = model_pre,
    model_post = model_post,
    break_point = break_point,
    use_post = !is.null(model_post)
  ))
}

#' Adaptive intercept correction using recent forecast errors
#' @param recent_errors Vector of recent forecast errors
#' @param decay Decay factor (0 to 1, higher = more weight on recent)
#' @return Adjustment value
adaptive_intercept_correction <- function(recent_errors, decay = 0.7) {
  if (length(recent_errors) == 0) {
    return(0)
  }
  
  # Remove NAs
  recent_errors <- recent_errors[!is.na(recent_errors)]
  
  if (length(recent_errors) == 0) {
    return(0)
  }
  
  # Exponentially weighted mean of recent errors
  n <- length(recent_errors)
  weights <- decay^(0:(n-1))
  weights <- rev(weights) / sum(weights)  # Most recent gets highest weight
  
  adjustment <- sum(weights * recent_errors)
  
  return(adjustment)
}

#' Add intercept adjustment option to MIDAS prediction
#' @param model MIDAS model
#' @param y_new New Y data
#' @param x_new New X data
#' @param adjustment Intercept adjustment value
#' @return Forecast with adjustment
predict_midas_with_adjustment <- function(model, y_new = NULL, x_new = NULL, 
                                          adjustment = 0) {
  # Get base forecast
  forecast <- predict_midas_unrestricted(model, y_new, x_new)
  
  # Apply adjustment
  if (!is.na(forecast$point) && !is.na(adjustment)) {
    forecast$point <- forecast$point + adjustment
    
    # Store adjustment in metadata
    if (is.null(forecast$meta)) {
      forecast$meta <- list()
    }
    forecast$meta$intercept_adjustment <- adjustment
    forecast$meta$unadjusted_point <- forecast$point - adjustment
  }
  
  return(forecast)
}

#' Detect and handle structural breaks in rolling evaluation
#' @param y_train Training target data
#' @param y_fitted Fitted values
#' @param method Method for adjustment ("recent_errors", "post_break_mean", "none")
#' @param window Window for adjustment estimation
#' @return Adjustment value
estimate_rolling_adjustment <- function(y_train, y_fitted, 
                                       method = "recent_errors", 
                                       window = 4) {
  if (method == "none") {
    return(0)
  }
  
  # Ensure both vectors are numeric and handle length mismatch
  y_train <- as.numeric(y_train)
  y_fitted <- as.numeric(y_fitted)
  
  # Match lengths - fitted values are typically shorter due to lags
  n_fitted <- length(y_fitted)
  n_train <- length(y_train)
  
  if (n_fitted != n_train) {
    # Take the last n_fitted values of y_train to match fitted values
    if (n_train > n_fitted) {
      y_train <- tail(y_train, n_fitted)
    } else {
      # Fitted is longer than train (shouldn't happen, but handle it)
      y_fitted <- tail(y_fitted, n_train)
    }
  }
  
  # Calculate residuals
  residuals <- y_train - y_fitted
  
  if (method == "recent_errors") {
    # Use most recent errors
    n <- length(residuals)
    if (n < window) {
      window <- n
    }
    
    if (n == 0) {
      return(0)
    }
    
    recent_errors <- tail(residuals, window)
    adjustment <- mean(recent_errors, na.rm = TRUE)
    
  } else if (method == "post_break_mean") {
    # Try to detect break and use post-break errors
    break_info <- detect_break_simple(y_train)
    
    if (!is.null(break_info) && break_info$break_point < length(y_train)) {
      post_break_errors <- residuals[(break_info$break_point):length(residuals)]
      adjustment <- mean(post_break_errors, na.rm = TRUE)
    } else {
      # Fall back to recent errors
      adjustment <- mean(tail(residuals, window), na.rm = TRUE)
    }
  } else {
    adjustment <- 0
  }
  
  # Handle NAs
  if (is.na(adjustment)) {
    adjustment <- 0
  }
  
  # Safeguard against extreme adjustments
  max_adjustment <- 5  # Maximum 5 percentage points
  adjustment <- max(min(adjustment, max_adjustment), -max_adjustment)
  
  return(adjustment)
}
