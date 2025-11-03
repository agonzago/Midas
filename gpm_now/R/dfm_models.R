# dfm_models.R
# Dynamic Factor Model with state-space support

#' Fit DFM on monthly panel
#' @param X_m_panel Wide matrix of monthly indicators
#' @param k_candidates Vector of candidate factor counts
#' @param options DFM options from config
#' @return List with best model, factors, and selection info
fit_dfm_monthly <- function(X_m_panel, k_candidates, options) {
  # Dynamic Factor Model fitting
  # This is a placeholder - would use dfms or nowcastDFM package
  
  if (!is.matrix(X_m_panel)) {
    X_m_panel <- as.matrix(X_m_panel)
  }
  
  # Standardize data
  X_std <- scale(X_m_panel, center = TRUE, scale = TRUE)
  
  best_k <- NULL
  best_ic <- Inf
  best_factors <- NULL
  
  for (k in k_candidates) {
    tryCatch({
      # Use PCA as a simple proxy for DFM
      # In production, use actual DFM methods (dfms package, state-space models)
      pca_result <- prcomp(X_std, center = FALSE, scale. = FALSE)
      
      # Extract k factors
      factors <- pca_result$x[, 1:min(k, ncol(pca_result$x)), drop = FALSE]
      
      # Calculate information criterion (simplified BIC)
      n <- nrow(X_std)
      p <- ncol(X_std)
      
      # Reconstruction error
      loadings <- pca_result$rotation[, 1:min(k, ncol(pca_result$x)), drop = FALSE]
      X_recon <- factors %*% t(loadings)
      sse <- sum((X_std - X_recon)^2, na.rm = TRUE)
      
      # BIC-like criterion
      n_params <- k * (p + n)
      ic <- log(sse / (n * p)) + n_params * log(n * p) / (n * p)
      
      if (ic < best_ic) {
        best_ic <- ic
        best_k <- k
        best_factors <- factors
      }
      
    }, error = function(e) {
      warning("DFM fitting failed for k=", k, ": ", e$message)
    })
  }
  
  if (is.null(best_k)) {
    warning("DFM fitting failed for all k candidates")
    return(NULL)
  }
  
  result <- list(
    best_model = list(
      k = best_k,
      factors = best_factors,
      ic = best_ic
    ),
    factors_m = best_factors,
    k_selected = best_k,
    info = list(
      candidates_tested = k_candidates,
      selection_criterion = "BIC",
      best_ic = best_ic
    )
  )
  
  class(result) <- c("dfm_fit", "list")
  
  return(result)
}

#' Predict DFM factors for new data
#' @param dfm_fit Fitted DFM object
#' @param X_m_current Current monthly panel data
#' @return Matrix of predicted factors
predict_dfm_factors <- function(dfm_fit, X_m_current) {
  if (is.null(dfm_fit) || is.null(dfm_fit$best_model)) {
    warning("Invalid DFM fit object")
    return(NULL)
  }
  
  # For new data, project onto factor space
  # This is simplified - actual DFM would use Kalman filtering
  
  # Return existing factors (in real-time would extend via filtering)
  return(dfm_fit$factors_m)
}

#' Fit DFM-MIDAS (factors as MIDAS regressors)
#' @param y_q Quarterly target
#' @param factors_m Monthly DFM factors
#' @param lag_map Lag map
#' @param window_cfg Window configuration
#' @return Fitted model
fit_dfm_midas <- function(y_q, factors_m, lag_map, window_cfg) {
  source("R/midas_models.R")
  
  if (is.null(factors_m) || ncol(factors_m) == 0) {
    warning("No DFM factors available")
    return(NULL)
  }
  
  # Use first factor for MIDAS regression
  factor1 <- factors_m[, 1]
  
  spec_cfg <- list(
    lag_min = 0,
    lag_max = 11
  )
  
  model <- fit_midas_unrestricted(y_q, factor1, lag_map, spec_cfg, window_cfg)
  
  if (!is.null(model)) {
    model$model_type <- "dfm_midas"
    model$n_factors <- ncol(factors_m)
  }
  
  return(model)
}

#' Predict with DFM-MIDAS
#' @param model Fitted DFM-MIDAS model
#' @param factors_m_current Current factors
#' @param lag_map_current Current lag map
#' @return Forecast list
predict_dfm_midas <- function(model, factors_m_current, lag_map_current) {
  source("R/midas_models.R")
  
  if (is.null(model)) {
    return(list(
      point = NA,
      se = NA,
      meta = list(error = "Model is NULL")
    ))
  }
  
  # Current factor
  if (is.matrix(factors_m_current) && ncol(factors_m_current) > 0) {
    factor_current <- factors_m_current[, 1]
  } else {
    factor_current <- factors_m_current
  }
  
  forecast <- predict_midas_unrestricted(model, factor_current, lag_map_current)
  
  if (!is.null(forecast$meta)) {
    forecast$meta$model_type <- "dfm_midas"
  }
  
  return(forecast)
}

#' Fit DFM with state-space quarterly mapping (for monthly proxy)
#' @param y_q Quarterly GDP target
#' @param y_m_proxy Monthly GDP proxy (e.g., IBC-Br)
#' @param factors_m Monthly DFM factors
#' @param options State-space options
#' @return State-space model object
fit_dfm_state_space <- function(y_q, y_m_proxy, factors_m, options) {
  # State-space model with quarterly state, monthly measurements
  # This would use KFAS or MARSS package
  
  if (is.null(y_m_proxy)) {
    warning("No monthly proxy provided for state-space model")
    return(NULL)
  }
  
  # Placeholder for KFAS implementation
  # State: quarterly GDP growth
  # Measurement 1: quarterly GDP (quarterly freq)
  # Measurement 2: monthly proxy (monthly freq)
  # Measurement 3: monthly factors (monthly freq)
  
  ss_model <- list(
    state_dim = 1,  # One state: quarterly GDP
    y_q = y_q,
    y_m_proxy = y_m_proxy,
    factors_m = factors_m,
    params = list(
      alpha = 1.0,  # Mapping coefficient monthly -> quarterly
      var_state = var(y_q, na.rm = TRUE),
      var_meas_q = var(y_q, na.rm = TRUE) * 0.1,
      var_meas_m = var(y_m_proxy, na.rm = TRUE) * 0.1
    ),
    engine = if (!is.null(options$engine)) options$engine else "KFAS"
  )
  
  class(ss_model) <- c("dfm_state_space", "list")
  
  return(ss_model)
}

#' Predict with DFM state-space model
#' @param ss_model State-space model object
#' @param y_m_proxy_current Current monthly proxy values
#' @param factors_m_current Current monthly factors
#' @return List with quarterly forecast, SE, and state details
predict_dfm_state_space <- function(ss_model, y_m_proxy_current, factors_m_current) {
  if (is.null(ss_model)) {
    return(list(
      point_q = NA,
      se_q = NA,
      state_details = list(error = "Model is NULL")
    ))
  }
  
  # Kalman filtering to get state estimate
  # This is a placeholder - actual implementation would use KFAS
  
  # Simple average of quarterly and monthly proxy as placeholder
  q_mean <- mean(ss_model$y_q, na.rm = TRUE)
  m_mean <- mean(ss_model$y_m_proxy, na.rm = TRUE)
  
  point_forecast <- (q_mean + m_mean) / 2
  se_forecast <- sqrt(ss_model$params$var_state)
  
  result <- list(
    point_q = point_forecast,
    se_q = se_forecast,
    state_details = list(
      filtered_state = point_forecast,
      state_variance = ss_model$params$var_state
    )
  )
  
  return(result)
}

#' Update DFM if needed
#' @param vintage Vintage snapshot
#' @param cfg Configuration
#' @return DFM fit object
maybe_update_dfm <- function(vintage, cfg) {
  vars <- cfg$variables
  
  # Get indicators marked for DFM
  dfm_indicators <- c()
  if (!is.null(vars$indicators)) {
    for (ind in vars$indicators) {
      if (!is.null(ind$in_dfm) && ind$in_dfm) {
        dfm_indicators <- c(dfm_indicators, ind$id)
      }
    }
  }
  
  if (length(dfm_indicators) == 0) {
    warning("No indicators marked for DFM")
    return(NULL)
  }
  
  # Build panel
  X_m_panel <- as.matrix(vintage$X_m[, setdiff(names(vintage$X_m), c("date", "series_id")), drop = FALSE])
  
  if (ncol(X_m_panel) == 0 || nrow(X_m_panel) == 0) {
    warning("Empty panel for DFM")
    return(NULL)
  }
  
  # Fit DFM
  k_candidates <- if (!is.null(cfg$dfm$factors_k_candidates)) {
    cfg$dfm$factors_k_candidates
  } else {
    c(2, 3, 4)
  }
  
  dfm_fit <- fit_dfm_monthly(X_m_panel, k_candidates, cfg$dfm)
  
  return(dfm_fit)
}

#' Predict with DFM state-space model if enabled
#' @param dfm DFM fit object
#' @param vintage Vintage snapshot
#' @param lag_map Lag map
#' @param cfg Configuration
#' @return Forecast or NULL
maybe_predict_dfm_state_space <- function(dfm, vintage, lag_map, cfg) {
  if (is.null(dfm)) {
    return(NULL)
  }
  
  # Check if state-space is enabled and monthly proxy exists
  use_ss <- if (!is.null(cfg$state_space$use_quarterly_state)) {
    cfg$state_space$use_quarterly_state
  } else {
    FALSE
  }
  
  if (!use_ss || is.null(vintage$y_m_proxy)) {
    return(NULL)
  }
  
  # Fit state-space model
  ss_model <- fit_dfm_state_space(
    vintage$y_q$value,
    vintage$y_m_proxy$value,
    dfm$factors_m,
    cfg$state_space
  )
  
  # Predict
  forecast <- predict_dfm_state_space(
    ss_model,
    vintage$y_m_proxy$value,
    dfm$factors_m
  )
  
  # Convert to standard forecast format
  result <- list(
    point = forecast$point_q,
    se = forecast$se_q,
    meta = list(
      model_type = "dfm_state_space",
      state_details = forecast$state_details
    )
  )
  
  return(result)
}
