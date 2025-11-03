# combine.R
# Forecast combination and interval construction

#' Combine forecasts from multiple models
#' @param indiv_list List of individual forecast objects
#' @param scheme Combination scheme ("equal", "inv_mse_shrink", "bic_weights")
#' @param history Historical forecast performance (for weighting)
#' @return List with combined point, intervals, and weights
combine_forecasts <- function(indiv_list, scheme = "equal", history = NULL) {
  # Extract point forecasts and standard errors
  points <- sapply(indiv_list, function(x) {
    if (!is.null(x$point)) x$point else NA
  })
  
  ses <- sapply(indiv_list, function(x) {
    if (!is.null(x$se)) x$se else NA
  })
  
  # Remove NA forecasts
  valid_idx <- !is.na(points)
  
  if (sum(valid_idx) == 0) {
    warning("No valid forecasts to combine")
    return(list(
      point = NA,
      lo = NA,
      hi = NA,
      weights = NA
    ))
  }
  
  points <- points[valid_idx]
  ses <- ses[valid_idx]
  model_names <- names(indiv_list)[valid_idx]
  
  # Calculate weights based on scheme
  weights <- calculate_weights(scheme, points, ses, model_names, history)
  
  # Combined point forecast
  combined_point <- sum(weights * points)
  
  # Combined variance (accounting for within and between model uncertainty)
  within_var <- sum(weights^2 * ses^2)
  between_var <- sum(weights * (points - combined_point)^2)
  combined_var <- within_var + between_var
  combined_se <- sqrt(combined_var)
  
  # Construct intervals (95% confidence)
  z_score <- 1.96
  lo <- combined_point - z_score * combined_se
  hi <- combined_point + z_score * combined_se
  
  result <- list(
    point = combined_point,
    lo = lo,
    hi = hi,
    se = combined_se,
    weights = setNames(weights, model_names),
    n_models = length(points)
  )
  
  return(result)
}

#' Calculate combination weights
#' @param scheme Weighting scheme
#' @param points Vector of point forecasts
#' @param ses Vector of standard errors
#' @param model_names Vector of model names
#' @param history Historical performance data
#' @return Vector of weights
calculate_weights <- function(scheme, points, ses, model_names, history) {
  n_models <- length(points)
  
  if (scheme == "equal") {
    # Equal weights
    weights <- rep(1 / n_models, n_models)
    
  } else if (scheme == "inv_mse_shrink") {
    # Inverse MSE with shrinkage toward equal weights
    
    if (!is.null(history) && "mse" %in% names(history)) {
      # Use historical MSE
      mse_vals <- sapply(model_names, function(name) {
        if (name %in% names(history$mse)) {
          history$mse[[name]]
        } else {
          mean(history$mse, na.rm = TRUE)  # Use average if not found
        }
      })
    } else {
      # Use current SE as proxy for MSE
      mse_vals <- ses^2
    }
    
    # Avoid division by zero
    mse_vals[mse_vals < 1e-10] <- 1e-10
    
    # Inverse MSE weights
    inv_mse <- 1 / mse_vals
    weights_inv <- inv_mse / sum(inv_mse)
    
    # Equal weights
    weights_eq <- rep(1 / n_models, n_models)
    
    # Shrinkage (default lambda = 0.2)
    lambda <- 0.2
    weights <- (1 - lambda) * weights_inv + lambda * weights_eq
    
  } else if (scheme == "bic_weights") {
    # BIC-based weights
    
    if (!is.null(history) && "bic" %in% names(history)) {
      bic_vals <- sapply(model_names, function(name) {
        if (name %in% names(history$bic)) {
          history$bic[[name]]
        } else {
          0  # Neutral if not found
        }
      })
      
      # Convert BIC to weights (lower BIC is better)
      # Use exp(-0.5 * delta_BIC)
      min_bic <- min(bic_vals)
      delta_bic <- bic_vals - min_bic
      weights <- exp(-0.5 * delta_bic)
      weights <- weights / sum(weights)
      
    } else {
      # Fall back to equal weights
      weights <- rep(1 / n_models, n_models)
    }
    
  } else {
    # Unknown scheme, use equal weights
    warning("Unknown combination scheme: ", scheme, ". Using equal weights.")
    weights <- rep(1 / n_models, n_models)
  }
  
  # Ensure weights sum to 1
  weights <- weights / sum(weights)
  
  return(weights)
}

#' Extract historical performance for weighting
#' @param forecast_archive Archive of past forecasts and outcomes
#' @param lookback_periods Number of past periods to use
#' @return List with performance metrics by model
extract_historical_performance <- function(forecast_archive, lookback_periods = 20) {
  if (is.null(forecast_archive) || length(forecast_archive) == 0) {
    return(NULL)
  }
  
  # This is a placeholder for extracting historical MSE and BIC
  # In practice, would calculate from past forecast errors
  
  performance <- list(
    mse = list(),
    bic = list()
  )
  
  # For each model, calculate MSE from past forecasts
  # Simplified implementation
  
  return(performance)
}

#' Calculate prediction intervals accounting for model uncertainty
#' @param combined_point Combined point forecast
#' @param individual_forecasts List of individual forecasts
#' @param coverage Desired coverage level (default 0.95)
#' @return List with lower and upper bounds
calculate_prediction_intervals <- function(combined_point, individual_forecasts, coverage = 0.95) {
  # Extract point forecasts
  points <- sapply(individual_forecasts, function(x) {
    if (!is.null(x$point)) x$point else NA
  })
  
  # Extract standard errors
  ses <- sapply(individual_forecasts, function(x) {
    if (!is.null(x$se)) x$se else NA
  })
  
  # Remove NAs
  valid_idx <- !is.na(points) & !is.na(ses)
  points <- points[valid_idx]
  ses <- ses[valid_idx]
  
  if (length(points) == 0) {
    return(list(lo = NA, hi = NA))
  }
  
  # Model uncertainty (dispersion across forecasts)
  model_sd <- sd(points)
  
  # Average within-model uncertainty
  avg_se <- mean(ses)
  
  # Total uncertainty
  total_se <- sqrt(avg_se^2 + model_sd^2)
  
  # Quantile for coverage
  z_score <- qnorm(0.5 + coverage / 2)
  
  lo <- combined_point - z_score * total_se
  hi <- combined_point + z_score * total_se
  
  return(list(lo = lo, hi = hi, se = total_se))
}

#' Trim extreme forecasts (optional robustness step)
#' @param indiv_list List of individual forecasts
#' @param trim_quantile Quantile threshold for trimming
#' @return Trimmed list of forecasts
trim_extreme_forecasts <- function(indiv_list, trim_quantile = 0.1) {
  points <- sapply(indiv_list, function(x) {
    if (!is.null(x$point)) x$point else NA
  })
  
  valid_idx <- !is.na(points)
  points_valid <- points[valid_idx]
  
  if (length(points_valid) < 3) {
    return(indiv_list)  # Don't trim if too few forecasts
  }
  
  # Calculate quantiles
  lo_thresh <- quantile(points_valid, trim_quantile)
  hi_thresh <- quantile(points_valid, 1 - trim_quantile)
  
  # Keep only forecasts within bounds
  keep_idx <- valid_idx & (points >= lo_thresh) & (points <= hi_thresh)
  
  trimmed_list <- indiv_list[keep_idx]
  
  if (length(trimmed_list) == 0) {
    warning("All forecasts were trimmed. Returning original list.")
    return(indiv_list)
  }
  
  return(trimmed_list)
}
