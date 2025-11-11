# combine.R
# Forecast combination and interval construction

#' Combine forecasts from multiple models
#' @param indiv_list List of individual forecast objects
#' @param scheme Combination scheme ("equal", "inv_mse_shrink", "bic_weights", "inv_bic", "inv_rmse")
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
  
  # Extract BIC values if available
  bics <- sapply(indiv_list, function(x) {
    if (!is.null(x$bic)) x$bic else NA
  })
  
  # Extract RMSE values if available
  rmses <- sapply(indiv_list, function(x) {
    if (!is.null(x$rmse)) x$rmse else NA
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
  bics <- bics[valid_idx]
  rmses <- rmses[valid_idx]
  model_names <- names(indiv_list)[valid_idx]
  
  # Calculate weights based on scheme
  weights <- calculate_weights(scheme, points, ses, bics, rmses, model_names, history)
  
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
#' @param bics Vector of BIC values
#' @param rmses Vector of RMSE values
#' @param model_names Vector of model names
#' @param history Historical performance data
#' @return Vector of weights
calculate_weights <- function(scheme, points, ses, bics, rmses, model_names, history) {
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
    
  } else if (scheme == "inv_bic") {
    # Simple inverse BIC weights (lower BIC = better model = higher weight)
    # This is the approach from the old Mexico MIDAS code
    
    if (!all(is.na(bics))) {
      # Use BIC values directly from models
      bic_vals <- bics
    } else if (!is.null(history) && "bic" %in% names(history)) {
      # Use historical BIC
      bic_vals <- sapply(model_names, function(name) {
        if (name %in% names(history$bic)) {
          history$bic[[name]]
        } else {
          mean(history$bic, na.rm = TRUE)
        }
      })
    } else {
      # Fall back to equal weights
      warning("No BIC values available for inv_bic scheme. Using equal weights.")
      weights <- rep(1 / n_models, n_models)
      return(weights / sum(weights))
    }
    
    # Avoid division by zero
    bic_vals[bic_vals < 1e-10] <- 1e-10
    
    # Inverse BIC weights (lower BIC gets higher weight)
    weights <- 1 / bic_vals
    weights <- weights / sum(weights)
    
  } else if (scheme == "bic_weights") {
    # BIC-based weights using delta-BIC approach (more sophisticated)
    # This accounts for the relative likelihood of models
    
    if (!all(is.na(bics))) {
      bic_vals <- bics
    } else if (!is.null(history) && "bic" %in% names(history)) {
      bic_vals <- sapply(model_names, function(name) {
        if (name %in% names(history$bic)) {
          history$bic[[name]]
        } else {
          0  # Neutral if not found
        }
      })
    } else {
      # Fall back to equal weights
      weights <- rep(1 / n_models, n_models)
      return(weights / sum(weights))
    }
    
    # Convert BIC to weights (lower BIC is better)
    # Use exp(-0.5 * delta_BIC) based on information theory
    min_bic <- min(bic_vals, na.rm = TRUE)
    delta_bic <- bic_vals - min_bic
    weights <- exp(-0.5 * delta_bic)
    weights <- weights / sum(weights)
    
  } else if (scheme == "inv_rmse") {
    # Simple inverse RMSE weights (lower RMSE = better model = higher weight)
    
    if (!all(is.na(rmses))) {
      # Use RMSE values directly from models
      rmse_vals <- rmses
    } else if (!is.null(history) && "rmse" %in% names(history)) {
      # Use historical RMSE
      rmse_vals <- sapply(model_names, function(name) {
        if (name %in% names(history$rmse)) {
          history$rmse[[name]]
        } else {
          mean(history$rmse, na.rm = TRUE)
        }
      })
    } else {
      # Fall back to equal weights
      warning("No RMSE values available for inv_rmse scheme. Using equal weights.")
      weights <- rep(1 / n_models, n_models)
      return(weights / sum(weights))
    }
    
    # Avoid division by zero
    rmse_vals[rmse_vals < 1e-10] <- 1e-10
    
    # Inverse RMSE weights (lower RMSE gets higher weight)
    weights <- 1 / rmse_vals
    weights <- weights / sum(weights)
    
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

#' Trim worst performing MIDAS models based on metric thresholds
#' @param midas_list List of MIDAS individual forecasts
#' @param trim_percentile Percentile threshold for trimming (e.g., 0.25 = keep top 75%)
#' @param metric Metric to use for trimming ("bic", "rmse", or "both")
#' @return Trimmed list of MIDAS forecasts
trim_midas_models <- function(midas_list, trim_percentile = 0.25, metric = "both") {
  if (length(midas_list) < 4) {
    cat("Too few MIDAS models (", length(midas_list), ") to trim. Keeping all.\n")
    return(midas_list)
  }
  
  # Extract metrics
  bics <- sapply(midas_list, function(x) {
    if (!is.null(x$bic)) x$bic else NA
  })
  
  rmses <- sapply(midas_list, function(x) {
    if (!is.null(x$rmse)) x$rmse else NA
  })
  
  keep_idx <- rep(TRUE, length(midas_list))
  
  if (metric %in% c("bic", "both")) {
    valid_bic <- !is.na(bics)
    if (sum(valid_bic) > 0) {
      bic_threshold <- quantile(bics[valid_bic], 1 - trim_percentile)
      keep_idx <- keep_idx & (!valid_bic | (bics <= bic_threshold))
    }
  }
  
  if (metric %in% c("rmse", "both")) {
    valid_rmse <- !is.na(rmses)
    if (sum(valid_rmse) > 0) {
      rmse_threshold <- quantile(rmses[valid_rmse], 1 - trim_percentile)
      keep_idx <- keep_idx & (!valid_rmse | (rmses <= rmse_threshold))
    }
  }
  
  trimmed_list <- midas_list[keep_idx]
  
  if (length(trimmed_list) == 0) {
    warning("All MIDAS models were trimmed. Returning original list.")
    return(midas_list)
  }
  
  n_removed <- length(midas_list) - length(trimmed_list)
  cat("Trimmed", n_removed, "worst performing MIDAS models. Kept", length(trimmed_list), "models.\n")
  
  return(trimmed_list)
}

#' Combine MIDAS forecasts using multiple schemes
#' @param midas_list List of MIDAS individual forecasts
#' @param trim_percentile Percentile threshold for trimming worst models (e.g., 0.25 = remove worst 25%)
#' @param schemes Vector of combination schemes to apply
#' @return List with combinations for each scheme
combine_midas_forecasts <- function(midas_list, trim_percentile = 0.25, 
                                    schemes = c("equal", "inv_bic", "inv_rmse")) {
  if (length(midas_list) == 0) {
    warning("No MIDAS forecasts to combine")
    return(list())
  }
  
  cat("\n=== MIDAS Model Combination ===\n")
  cat("Total MIDAS models:", length(midas_list), "\n")
  
  # Trim worst performing models
  midas_trimmed <- trim_midas_models(midas_list, trim_percentile = trim_percentile, metric = "both")
  
  # Generate combinations using different schemes
  combinations <- list()
  
  for (scheme in schemes) {
    cat("\nCombining with scheme:", scheme, "\n")
    
    combo <- combine_forecasts(midas_trimmed, scheme = scheme, history = NULL)
    
    if (!is.na(combo$point)) {
      combinations[[scheme]] <- combo
      
      cat("  Combined forecast:", round(combo$point, 3), "\n")
      cat("  95% interval: [", round(combo$lo, 3), ",", round(combo$hi, 3), "]\n")
      
      # Show top 5 weights
      if (!is.null(combo$weights) && !all(is.na(combo$weights))) {
        sorted_weights <- sort(combo$weights, decreasing = TRUE)
        cat("  Top 5 weights:\n")
        for (i in seq_len(min(5, length(sorted_weights)))) {
          cat("    ", names(sorted_weights)[i], ": ", round(sorted_weights[i], 3), "\n")
        }
      }
    } else {
      warning("Combination failed for scheme: ", scheme)
    }
  }
  
  # Add metadata
  combinations$metadata <- list(
    n_models_original = length(midas_list),
    n_models_trimmed = length(midas_trimmed),
    trim_percentile = trim_percentile,
    schemes = schemes,
    trimmed_models = setdiff(names(midas_list), names(midas_trimmed))
  )
  
  return(combinations)
}
