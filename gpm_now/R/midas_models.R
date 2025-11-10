# midas_models.R
# U-MIDAS unrestricted models for direct quarterly GDP forecasting
# Refactored with BIC-based model selection and proper ragged-edge handling

#' Select best U-MIDAS specification using BIC
#' @param y_q Quarterly target variable (ts object or vector)
#' @param x_m Monthly indicator (ts object or vector)
#' @param max_y_lag Maximum lags of quarterly target to consider
#' @param max_x_lag Maximum lags of monthly indicator (in months) to consider
#' @param month_of_quarter Ragged edge timing: 0=end of quarter, 1=2nd month, 2=1st month
#' @return List with selected lags and BIC value
select_midas_spec_bic <- function(y_q, x_m, max_y_lag = 4, max_x_lag = 6, month_of_quarter = 0) {
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Package 'midasr' required. Install with: install.packages('midasr')")
  }
  
  min_bic <- Inf
  best_y_lag <- 0
  best_x_lag <- 0
  
  # First, test models without lagged Y (AR terms)
  tryCatch({
    fit_temp <- midasr::midas_u(y_q ~ midasr::mls(x_m, month_of_quarter:(month_of_quarter + max_x_lag), 3))
    xmat <- model.matrix(fit_temp)
    ymat <- fit_temp$model$y
    
    # Test different X lag lengths
    for (xj in 1:(max_x_lag + 1)) {
      temp_lm <- lm(ymat ~ xmat[, 2:(1 + xj)])
      temp_bic <- BIC(temp_lm)
      
      if (temp_bic < min_bic) {
        min_bic <- temp_bic
        best_x_lag <- xj - 1
        best_y_lag <- 0
      }
    }
  }, error = function(e) {
    warning("Failed to fit models without Y lags: ", e$message)
  })
  
  # Now test models with lagged Y (AR terms)
  tryCatch({
    fit_temp <- midasr::midas_u(y_q ~ midasr::mls(y_q, 1:max_y_lag, 1) + 
                                  midasr::mls(x_m, month_of_quarter:(month_of_quarter + max_x_lag), 3))
    xmat <- model.matrix(fit_temp)
    ymat <- fit_temp$model$y
    
    # Test all combinations of Y and X lags
    for (jy in 1:max_y_lag) {
      for (xj in 1:(max_x_lag + 1)) {
        # Select columns: intercept + Y lags + X lags
        y_cols <- 1:(jy + 1)  # Intercept + Y lags
        x_cols <- (max_y_lag + 2):(max_y_lag + 1 + xj)  # X lags
        
        temp_lm <- lm(ymat ~ xmat[, y_cols] + xmat[, x_cols])
        temp_bic <- BIC(temp_lm)
        
        if (temp_bic < min_bic) {
          min_bic <- temp_bic
          best_x_lag <- xj - 1
          best_y_lag <- jy
        }
      }
    }
  }, error = function(e) {
    warning("Failed to fit models with Y lags: ", e$message)
  })
  
  return(list(
    y_lag = best_y_lag,
    x_lag = best_x_lag,
    bic = min_bic
  ))
}

#' Select best U-MIDAS specification for lagged indicators (published with delay)
#' @param y_q Quarterly target variable
#' @param x_m Monthly indicator
#' @param max_y_lag Maximum lags of quarterly target to consider
#' @param max_x_lag Maximum lags of monthly indicator to consider
#' @return List with selected lags and BIC value
select_midas_spec_bic_lagged <- function(y_q, x_m, max_y_lag = 4, max_x_lag = 6) {
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Package 'midasr' required. Install with: install.packages('midasr')")
  }
  
  min_bic <- Inf
  best_y_lag <- 0
  best_x_lag <- 0
  
  # For lagged indicators, use lag(mls(...), 1) to shift the entire monthly series by 1 quarter
  
  # First, test models without lagged Y
  tryCatch({
    fit_temp <- midasr::midas_u(y_q ~ lag(midasr::mls(x_m, 0:max_x_lag, 3), 1))
    xmat <- model.matrix(fit_temp)
    ymat <- fit_temp$model$y
    
    for (xj in 1:(max_x_lag + 1)) {
      temp_lm <- lm(ymat ~ xmat[, 2:(1 + xj)])
      temp_bic <- BIC(temp_lm)
      
      if (temp_bic < min_bic) {
        min_bic <- temp_bic
        best_x_lag <- xj - 1
        best_y_lag <- 0
      }
    }
  }, error = function(e) {
    warning("Failed to fit lagged models without Y lags: ", e$message)
  })
  
  # Now test models with lagged Y
  tryCatch({
    fit_temp <- midasr::midas_u(y_q ~ midasr::mls(y_q, 1:max_y_lag, 1) + 
                                  lag(midasr::mls(x_m, 0:max_x_lag, 3), 1))
    xmat <- model.matrix(fit_temp)
    ymat <- fit_temp$model$y
    
    for (jy in 1:max_y_lag) {
      for (xj in 1:(max_x_lag + 1)) {
        y_cols <- 1:(jy + 1)
        x_cols <- (max_y_lag + 2):(max_y_lag + 1 + xj)
        
        temp_lm <- lm(ymat ~ xmat[, y_cols] + xmat[, x_cols])
        temp_bic <- BIC(temp_lm)
        
        if (temp_bic < min_bic) {
          min_bic <- temp_bic
          best_x_lag <- xj - 1
          best_y_lag <- jy
        }
      }
    }
  }, error = function(e) {
    warning("Failed to fit lagged models with Y lags: ", e$message)
  })
  
  return(list(
    y_lag = best_y_lag,
    x_lag = best_x_lag,
    bic = min_bic
  ))
}

#' Fit unrestricted MIDAS model with selected specification
#' @param y_q Quarterly target variable
#' @param x_m Monthly indicator
#' @param y_lag Number of quarterly lags
#' @param x_lag Number of monthly lags
#' @param month_of_quarter Ragged edge timing (NULL for lagged indicators)
#' @param window_cfg Window configuration
#' @return Fitted MIDAS model object
fit_midas_unrestricted <- function(y_q, x_m, y_lag, x_lag, month_of_quarter = NULL, window_cfg = NULL) {
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Package 'midasr' required. Install with: install.packages('midasr')")
  }
  
  # Apply rolling window if specified
  if (!is.null(window_cfg) && !is.null(window_cfg$type) && window_cfg$type == "rolling") {
    n_q <- length(y_q)
    window_length <- window_cfg$length_quarters
    
    if (n_q > window_length) {
      start_idx <- n_q - window_length + 1
      y_q <- y_q[start_idx:n_q]
      
      # Adjust x_m accordingly (3 months per quarter)
      n_m <- length(x_m)
      start_idx_m <- max(1, n_m - window_length * 3 + 1)
      x_m <- x_m[start_idx_m:n_m]
    }
  }
  
  # Fit the model based on specification
  tryCatch({
    if (is.null(month_of_quarter)) {
      # Lagged indicator (published with delay)
      # Use lag() to shift the entire series by 1 quarter (3 months)
      # This means we use data from t-3, t-4, ..., t-3-x_lag months back
      if (y_lag == 0) {
        # Create formula with actual values, not variables
        # NOTE: Don't use midasr:: prefix in formula - it causes forecast() to fail
        fml <- as.formula(sprintf("y_q ~ lag(mls(x_m, 0:%d, 3), 1)", x_lag))
        fit <- midasr::midas_u(fml)
      } else {
        # Create formula with actual values
        fml <- as.formula(sprintf("y_q ~ mls(y_q, 1:%d, 1) + lag(mls(x_m, 0:%d, 3), 1)", 
                                  y_lag, x_lag))
        fit <- midasr::midas_u(fml)
      }
    } else {
      # Current indicator (available within quarter)
      # month_of_quarter specifies the ragged edge:
      # - 0: end of quarter (all 3 months available)
      # - 1: 2nd month of quarter available
      # - 2: 1st month of quarter available
      # The lag specification should reference past data, not future
      # Use x_lag + 1 lags starting from month_of_quarter months back
      # This ensures we're using historical data plus available current quarter data
      
      # Adjust lag range to ensure we don't reference non-existent data
      # The lags should go backwards from month_of_quarter
      # For month_of_quarter=2 (1st month available), use lags 2:(2+x_lag)
      # This means: current month (lag 2), then 3, 4, 5, ... (going back in time)
      
      if (y_lag == 0) {
        # Create formula with actual values
        # NOTE: Don't use midasr:: prefix - causes forecast() to fail with "condition has length > 1"
        fml <- as.formula(sprintf("y_q ~ mls(x_m, %d:%d, 3)", 
                                  month_of_quarter, month_of_quarter + x_lag))
        fit <- midasr::midas_u(fml)
      } else {
        # Create formula with actual values
        fml <- as.formula(sprintf("y_q ~ mls(y_q, 1:%d, 1) + mls(x_m, %d:%d, 3)", 
                                  y_lag, month_of_quarter, month_of_quarter + x_lag))
        fit <- midasr::midas_u(fml)
      }
    }
    
    # Extract model information and store original data for forecasting
    model <- list(
      fit = fit,
      coefficients = coef(fit),
      fitted_values = fitted(fit),
      residuals = residuals(fit),
      y_lag = y_lag,
      x_lag = x_lag,
      month_of_quarter = month_of_quarter,
      n_obs = length(fit$model$y),
      window_cfg = window_cfg,
      # Store original data for extending in forecast
      y_data = y_q,
      x_data = x_m
    )
    
    class(model) <- c("midas_unrestricted", "midas_model")
    
    return(model)
    
  }, error = function(e) {
    warning("MIDAS model fitting failed: ", e$message)
    return(NULL)
  })
}

#' Predict with unrestricted MIDAS model
#' @param model Fitted MIDAS model object
#' @param y_new New quarterly data for forecast (latest Y values for AR component)
#' @param x_new New monthly data for forecast (should be 3 values for one quarter)
#' @return List with point forecast, standard error, and metadata
predict_midas_unrestricted <- function(model, y_new = NULL, x_new = NULL) {
  if (is.null(model)) {
    return(list(
      point = NA,
      se = NA,
      meta = list(error = "Model is NULL")
    ))
  }
  
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Package 'midasr' required for prediction")
  }
  
  tryCatch({
    # Prepare newdata for forecast
    # midasr::forecast() requires FULL time series extended with forecast period
    # Following the Mexico_Midas.R pattern
    
    # Extract variable names from model
    model_data <- model$fit$model
    y_name <- names(model_data)[1]
    
    # Extract X variable name from formula
    # Skip the first mls() term if it's the Y variable (AR term)
    model_terms <- terms(model$fit)
    term_labels <- attr(model_terms, "term.labels")
    
    x_name <- NULL
    for (term_label in term_labels) {
      if (grepl("mls\\([^,)]+", term_label)) {
        # Match mls(var_name, ... or midasr::mls(var_name, ...
        var_name <- sub(".*mls\\(([^,)]+).*", "\\1", term_label)
        var_name <- gsub("lag\\(|\\)|midasr::", "", var_name)
        var_name <- trimws(var_name)
        
        # Skip if this is the Y variable (AR term)
        if (var_name != y_name) {
          x_name <- var_name
          break
        } else {
        }
      }
    }
    
    if (is.null(x_name)) {
      x_name <- "x_m"
    }
    
    # Get historical data from stored model data
    y_hist <- if (!is.null(model$y_data)) model$y_data else model$fit$model[[y_name]]
    x_hist <- if (!is.null(model$x_data)) model$x_data else NULL
    
    # Check that x_hist exists
    if (is.null(x_hist) || length(x_hist) == 0) {
      warning("No historical X data available in model for forecasting")
      return(list(
        point = NA,
        se = NA,
        meta = list(error = "No historical X data in model")
      ))
    }
    
    # Extend Y by 1 period (quarterly) with NA for forecast
    y_extended <- c(y_hist, NA)
    
    # Extend X by 3 periods (monthly) with new data
    if (!is.null(x_new) && length(x_new) > 0) {
      # Ensure exactly 3 values
      x_len <- length(x_new)
      if (x_len < 3) {
        x_new <- c(x_new, rep(NA, 3 - x_len))
      } else if (x_len > 3) {
        x_new <- tail(x_new, 3)
      }
    } else {
      x_new <- rep(NA, 3)
    }
    
    x_extended <- c(x_hist, x_new)
    
    
    # Preserve ts attributes if present
    y_is_ts <- inherits(y_hist, "ts")
    x_is_ts <- inherits(x_hist, "ts")
    
    if (y_is_ts) {
      y_extended <- ts(y_extended, start = start(y_hist), frequency = frequency(y_hist))
    }
    if (x_is_ts) {
      x_extended <- ts(x_extended, start = start(x_hist), frequency = frequency(x_hist))
    }
    
    # Create newdata list with proper variable names
    newdata <- list()
    newdata[[y_name]] <- y_extended
    newdata[[x_name]] <- x_extended
    
    
    # Generate forecast
    forecast_obj <- forecast::forecast(model$fit, newdata = newdata, method = "static")
    point_forecast <- tail(as.numeric(forecast_obj$mean), 1)
    
    # Calculate standard error from residuals
    se_forecast <- sd(model$residuals, na.rm = TRUE)
    
    result <- list(
      point = point_forecast,
      se = se_forecast,
      meta = list(
        model_type = "midas_unrestricted",
        y_lag = model$y_lag,
        x_lag = model$x_lag,
        month_of_quarter = model$month_of_quarter,
        n_obs = model$n_obs
      )
    )
    
    return(result)
    
  }, error = function(e) {
    warning("MIDAS prediction failed: ", e$message)
    return(list(
      point = NA,
      se = NA,
      meta = list(error = e$message)
    ))
  })
}

#' Calculate MIDAS model metrics (RMSE, BIC)
#' @param model Fitted MIDAS model
#' @return List with metrics
calculate_midas_metrics <- function(model) {
  if (is.null(model) || is.null(model$fit)) {
    return(list(rmse = NA, bic = NA, n = 0, k = 0))
  }
  
  tryCatch({
    y_actual <- model$fit$model$y
    y_fitted <- fitted(model$fit)
    
    # Remove NAs
    valid_idx <- !is.na(y_actual) & !is.na(y_fitted)
    y_actual <- y_actual[valid_idx]
    y_fitted <- y_fitted[valid_idx]
    
    n <- length(y_actual)
    k <- length(model$coefficients)
    
    # RMSE
    rmse <- sqrt(mean((y_actual - y_fitted)^2))
    
    # BIC
    sse <- sum((y_actual - y_fitted)^2)
    bic <- n * log(sse / n) + k * log(n)
    
    metrics <- list(
      rmse = rmse,
      bic = bic,
      n = n,
      k = k
    )
    
    return(metrics)
    
  }, error = function(e) {
    warning("Failed to calculate MIDAS metrics: ", e$message)
    return(list(rmse = NA, bic = NA, n = 0, k = 0))
  })
}

#' Fit or update MIDAS models for all indicators with BIC-based selection and weighting
#' @param vintage Vintage data snapshot
#' @param lag_map Lag map object
#' @param cfg Configuration object
#' @return List with individual forecasts and BIC weights
fit_or_update_midas_set <- function(vintage, lag_map, cfg) {
  # vars <- cfg$variables  # Removed: not currently used
  window_cfg <- cfg$window
  
  # Get quarterly target
  if (is.null(vintage$y_q) || is.null(vintage$y_q$value)) {
    warning("No quarterly target data in vintage")
    return(list())
  }
  
  y_q <- vintage$y_q$value
  
  # Get configuration for MIDAS selection
  max_y_lag <- if (!is.null(cfg$midas_max_y_lag)) cfg$midas_max_y_lag else 4
  max_x_lag <- if (!is.null(cfg$midas_max_x_lag)) cfg$midas_max_x_lag else 6
  month_of_quarter <- if (!is.null(cfg$midas_month_of_quarter)) cfg$midas_month_of_quarter else 2
  
  # Lists to categorize indicators by publication timing
  # These should ideally come from configuration or calendar
  lagged_indicators <- if (!is.null(cfg$lagged_indicators)) cfg$lagged_indicators else c()
  current_indicators <- if (!is.null(cfg$current_indicators)) cfg$current_indicators else c()
  
  # Storage for results
  midas_forecasts <- list()
  midas_bics <- c()
  
  # Process lagged indicators (published with delay - not available in first month of quarter)
  if (length(lagged_indicators) > 0) {
    cat("Processing", length(lagged_indicators), "lagged indicators...\n")
    
    for (ind_id in lagged_indicators) {
      tryCatch({
        # Extract monthly data for this indicator
        x_m <- extract_indicator_data(vintage, ind_id)
        
        if (is.null(x_m) || length(x_m) < 12) {
          warning("Insufficient data for indicator: ", ind_id)
          next
        }
        
        # Select best specification using BIC
        spec <- select_midas_spec_bic_lagged(y_q, x_m, max_y_lag, max_x_lag)
        
        # Fit model with selected specification
        model <- fit_midas_unrestricted(
          y_q = y_q,
          x_m = x_m,
          y_lag = spec$y_lag,
          x_lag = spec$x_lag,
          month_of_quarter = NULL,  # NULL indicates lagged structure
          window_cfg = window_cfg
        )
        
        if (is.null(model)) {
          warning("Failed to fit model for indicator: ", ind_id)
          next
        }
        
        # Prepare newdata for forecast
        # For lagged indicators, use data through last complete quarter
        y_new <- if (spec$y_lag > 0) tail(y_q, spec$y_lag) else NULL
        x_new <- extract_forecast_data(vintage, ind_id, is_lagged = TRUE, lag_map = lag_map)
        
        # Generate forecast
        forecast <- predict_midas_unrestricted(model, y_new, x_new)
        
        if (!is.na(forecast$point)) {
          midas_forecasts[[ind_id]] <- forecast
          midas_bics <- c(midas_bics, spec$bic)
          names(midas_bics)[length(midas_bics)] <- ind_id
          
          cat("  ", ind_id, ": forecast =", round(forecast$point, 2), 
              ", BIC =", round(spec$bic, 1), 
              ", lags = Y:", spec$y_lag, "X:", spec$x_lag, "\n")
        }
        
      }, error = function(e) {
        warning("Error processing lagged indicator ", ind_id, ": ", e$message)
      })
    }
  }
  
  # Process current indicators (available in first month of quarter)
  if (length(current_indicators) > 0) {
    cat("Processing", length(current_indicators), "current indicators...\n")
    
    for (ind_id in current_indicators) {
      tryCatch({
        # Extract monthly data
        x_m <- extract_indicator_data(vintage, ind_id)
        
        if (is.null(x_m) || length(x_m) < 12) {
          warning("Insufficient data for indicator: ", ind_id)
          next
        }
        
        # Select best specification using BIC
        spec <- select_midas_spec_bic(y_q, x_m, max_y_lag, max_x_lag, month_of_quarter)
        
        # Fit model
        model <- fit_midas_unrestricted(
          y_q = y_q,
          x_m = x_m,
          y_lag = spec$y_lag,
          x_lag = spec$x_lag,
          month_of_quarter = month_of_quarter,
          window_cfg = window_cfg
        )
        
        if (is.null(model)) {
          warning("Failed to fit model for indicator: ", ind_id)
          next
        }
        
        # Prepare newdata for forecast
        y_new <- if (spec$y_lag > 0) tail(y_q, spec$y_lag) else NULL
        x_new <- extract_forecast_data(vintage, ind_id, is_lagged = FALSE, lag_map = lag_map)
        
        # Generate forecast
        forecast <- predict_midas_unrestricted(model, y_new, x_new)
        
        if (!is.na(forecast$point)) {
          midas_forecasts[[ind_id]] <- forecast
          midas_bics <- c(midas_bics, spec$bic)
          names(midas_bics)[length(midas_bics)] <- ind_id
          
          cat("  ", ind_id, ": forecast =", round(forecast$point, 2),
              ", BIC =", round(spec$bic, 1),
              ", lags = Y:", spec$y_lag, "X:", spec$x_lag, "\n")
        }
        
      }, error = function(e) {
        warning("Error processing current indicator ", ind_id, ": ", e$message)
      })
    }
  }
  
  # Calculate BIC-based weights
  if (length(midas_bics) > 0) {
    # Inverse BIC weights (lower BIC = higher weight)
    weights <- 1 / midas_bics
    weights <- weights / sum(weights)
    
    # Add weights to each forecast
    for (ind_id in names(midas_forecasts)) {
      midas_forecasts[[ind_id]]$weight <- weights[ind_id]
      midas_forecasts[[ind_id]]$bic <- midas_bics[ind_id]
    }
    
    # Sort by weight (descending)
    sorted_indices <- order(weights, decreasing = TRUE)
    sorted_names <- names(weights)[sorted_indices]
    
    cat("\n--- BIC-Based Weights (Top 10) ---\n")
    for (i in seq_len(min(10, length(sorted_names)))) {
      ind_id <- sorted_names[i]
      cat(sprintf("  %-25s: weight = %.3f, forecast = %6.2f\n", 
                  ind_id, weights[ind_id], midas_forecasts[[ind_id]]$point))
    }
    
    # Calculate weighted average forecast
    weighted_forecast <- sum(weights * sapply(midas_forecasts, function(x) x$point))
    cat(sprintf("\nWeighted MIDAS Nowcast: %.2f\n", weighted_forecast))
  }
  
  return(midas_forecasts)
}

#' Extract indicator data from vintage
#' @param vintage Vintage snapshot
#' @param ind_id Indicator ID
#' @return Vector of indicator values
extract_indicator_data <- function(vintage, ind_id) {
  if (is.null(vintage$X_m)) {
    return(NULL)
  }
  
  # Handle different vintage structures
  if ("series_id" %in% names(vintage$X_m)) {
    # Panel format
    ind_data <- vintage$X_m[vintage$X_m$series_id == ind_id, ]
    if (nrow(ind_data) == 0) {
      return(NULL)
    }
    return(ind_data$value)
  } else if (ind_id %in% names(vintage$X_m)) {
    # Wide format
    return(vintage$X_m[[ind_id]])
  } else {
    return(NULL)
  }
}

#' Extract forecast data (most recent observations for prediction)
#' @param vintage Vintage snapshot
#' @param ind_id Indicator ID
#' @param is_lagged Whether this is a lagged indicator
#' @param lag_map Optional lag map for ragged-edge handling
#' @return Vector of recent observations for forecasting (length 3 for one quarter)
extract_forecast_data <- function(vintage, ind_id, is_lagged = FALSE, lag_map = NULL) {
  x_m <- extract_indicator_data(vintage, ind_id)
  
  if (is.null(x_m)) {
    return(rep(NA, 3))  # Return 3 NAs if no data available
  }
  
  # Note: Date information could be used for more sophisticated ragged-edge handling
  # Currently using simpler logic based on lag_map availability flags
  
  if (is_lagged) {
    # For lagged indicators (published with delay), use data from the previous quarter
    # Take the last 3 months of available data
    if (length(x_m) >= 3) {
      return(tail(x_m, 3))
    } else {
      # Pad with NAs at the beginning if insufficient data
      return(c(rep(NA, 3 - length(x_m)), x_m))
    }
  } else {
    # For current indicators (available within the quarter)
    # We need to handle the ragged edge properly:
    # - Some months in the current quarter may be available
    # - Others may not be available yet (should be NA)
    
    # If we have lag_map information, use it to determine which months are available
    if (!is.null(lag_map) && !is.null(lag_map$indicators) && ind_id %in% names(lag_map$indicators)) {
      available_months <- lag_map$indicators[[ind_id]]$available_months
      
      # Build the forecast data based on availability
      # Assuming quarter_months has 3 elements (months 1, 2, 3 of quarter)
      forecast_data <- rep(NA, 3)
      
      for (i in seq_along(available_months)) {
        if (i <= length(available_months) && available_months[[i]]) {
          # This month is available, get the data
          # The last i months of data correspond to the current quarter months
          if (length(x_m) >= i) {
            forecast_data[i] <- x_m[length(x_m) - (length(available_months) - i)]
          }
        }
      }
      
      return(forecast_data)
    } else {
      # No lag_map available, use simple heuristic:
      # Take the last available observations and pad with NAs
      last_obs <- tail(x_m, 3)
      
      if (length(last_obs) < 3) {
        # Pad with NAs at the end (future months not available yet)
        last_obs <- c(last_obs, rep(NA, 3 - length(last_obs)))
      }
      
      return(last_obs)
    }
  }
}
