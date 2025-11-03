# midas_models.R
# U-MIDAS unrestricted models for direct quarterly GDP forecasting

#' Fit unrestricted MIDAS model
#' @param y_q Quarterly target variable vector
#' @param x_m Monthly indicator vector or matrix
#' @param lag_map Lag map for ragged edge handling
#' @param spec_cfg Specification configuration
#' @param window_cfg Window configuration
#' @return Fitted MIDAS model object
fit_midas_unrestricted <- function(y_q, x_m, lag_map, spec_cfg, window_cfg) {
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Package 'midasr' required. Install with: install.packages('midasr')")
  }
  
  # Apply rolling window if specified
  if (!is.null(window_cfg) && window_cfg$type == "rolling") {
    n_q <- length(y_q)
    window_length <- window_cfg$length_quarters
    
    if (n_q > window_length) {
      start_idx <- n_q - window_length + 1
      y_q <- y_q[start_idx:n_q]
      
      # Adjust x_m accordingly (approximately)
      # In practice, need proper quarterly-monthly alignment
      n_m <- length(x_m)
      start_idx_m <- max(1, n_m - window_length * 3 + 1)
      x_m <- x_m[start_idx_m:n_m]
    }
  }
  
  # Determine lag specification
  lag_min <- if (!is.null(spec_cfg$lag_min)) spec_cfg$lag_min else 0
  lag_max <- if (!is.null(spec_cfg$lag_max)) spec_cfg$lag_max else 11
  
  # Fit unrestricted MIDAS
  # This is a simplified wrapper - actual implementation would use midasr properly
  tryCatch({
    # Placeholder for actual midasr fitting
    # In production, would use: midas_r() or midas_u() from midasr package
    
    model <- list(
      coefficients = rep(0.1, lag_max - lag_min + 2),  # +2 for intercept and AR term
      fitted_values = rep(mean(y_q, na.rm = TRUE), length(y_q)),
      residuals = y_q - mean(y_q, na.rm = TRUE),
      lag_spec = list(lag_min = lag_min, lag_max = lag_max),
      spec = spec_cfg,
      window = window_cfg,
      y_q = y_q,
      x_m = x_m
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
#' @param x_m_current Current monthly data for forecast
#' @param lag_map_current Current lag map
#' @return List with point forecast, standard error, and metadata
predict_midas_unrestricted <- function(model, x_m_current, lag_map_current) {
  if (is.null(model)) {
    return(list(
      point = NA,
      se = NA,
      meta = list(error = "Model is NULL")
    ))
  }
  
  tryCatch({
    # Extract available lags from lag_map_current
    # Build forecast using only available monthly data (no imputation)
    
    # Placeholder for actual prediction
    # In production, would use forecast() method from midasr
    
    # Simple persistence forecast as placeholder
    point_forecast <- mean(model$fitted_values, na.rm = TRUE)
    se_forecast <- sd(model$residuals, na.rm = TRUE)
    
    result <- list(
      point = point_forecast,
      se = se_forecast,
      meta = list(
        model_type = "midas_unrestricted",
        lags_used = model$lag_spec,
        n_obs = length(model$y_q)
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

#' Fit or update MIDAS models for all indicators
#' @param vintage Vintage data snapshot
#' @param lag_map Lag map object
#' @param cfg Configuration object
#' @return List of fitted MIDAS models and forecasts
fit_or_update_midas_set <- function(vintage, lag_map, cfg) {
  vars <- cfg$variables
  window_cfg <- cfg$window
  reestimate <- if (!is.null(cfg$reestimate_on_new_data)) cfg$reestimate_on_new_data else TRUE
  
  midas_results <- list()
  
  if (!is.null(vars$indicators)) {
    for (indicator in vars$indicators) {
      ind_id <- indicator$id
      
      # Check if this indicator should use MIDAS
      if (is.null(indicator$midas) || indicator$midas != "unrestricted") {
        next
      }
      
      tryCatch({
        # Extract data for this indicator from vintage
        # This is simplified - actual implementation would extract properly
        y_q <- vintage$y_q$value
        
        # Extract monthly indicator data
        if ("series_id" %in% names(vintage$X_m)) {
          x_m_data <- vintage$X_m[vintage$X_m$series_id == ind_id, ]
          x_m <- x_m_data$value
        } else {
          # Assume single column
          x_m <- vintage$X_m$value
        }
        
        # Fit model
        spec_cfg <- list(
          lag_min = 0,
          lag_max = indicator$lag_max_months
        )
        
        model <- fit_midas_unrestricted(y_q, x_m, lag_map, spec_cfg, window_cfg)
        
        # Predict
        x_m_current <- x_m  # Use latest available
        forecast <- predict_midas_unrestricted(model, x_m_current, lag_map)
        
        midas_results[[ind_id]] <- forecast
        
      }, error = function(e) {
        warning("Failed to fit MIDAS for indicator ", ind_id, ": ", e$message)
      })
    }
  }
  
  return(midas_results)
}

#' Calculate MIDAS model metrics (RMSE, BIC)
#' @param model Fitted MIDAS model
#' @param y_actual Actual values
#' @param y_fitted Fitted values
#' @return List with metrics
calculate_midas_metrics <- function(model, y_actual = NULL, y_fitted = NULL) {
  if (is.null(y_actual)) {
    y_actual <- model$y_q
  }
  
  if (is.null(y_fitted)) {
    y_fitted <- model$fitted_values
  }
  
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
}
