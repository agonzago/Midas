# tprf_models.R
# Three-Pass Regression Filter (3PF/TPRF) models

#' Build TPRF factors from monthly panel
#' @param X_m_panel Wide matrix of monthly indicators
#' @param k Number of factors
#' @param as_of_date Date for the factor extraction
#' @param window_cfg Window configuration
#' @return List with factors and metadata
build_tprf_factors <- function(X_m_panel, k, as_of_date, window_cfg) {
  # Three-Pass Regression Filter
  # This is a simplified placeholder implementation
  
  if (!is.matrix(X_m_panel)) {
    X_m_panel <- as.matrix(X_m_panel)
  }
  
  # Apply rolling window if specified
  if (!is.null(window_cfg) && window_cfg$type == "rolling") {
    n_rows <- nrow(X_m_panel)
    window_length_months <- window_cfg$length_quarters * 3
    
    if (n_rows > window_length_months) {
      start_idx <- n_rows - window_length_months + 1
      X_m_panel <- X_m_panel[start_idx:n_rows, , drop = FALSE]
    }
  }
  
  # Remove columns with too many NAs
  na_prop <- colMeans(is.na(X_m_panel))
  valid_cols <- na_prop < 0.5
  X_m_panel <- X_m_panel[, valid_cols, drop = FALSE]
  
  # Standardize
  X_std <- scale(X_m_panel, center = TRUE, scale = TRUE)
  
  # Simple PCA as a proxy for 3PF
  # In production, implement actual three-pass filter
  tryCatch({
    pca_result <- prcomp(X_std, center = FALSE, scale. = FALSE)
    
    # Extract k factors
    factors <- pca_result$x[, 1:min(k, ncol(pca_result$x)), drop = FALSE]
    
    result <- list(
      factors_m = factors,
      loadings = pca_result$rotation[, 1:min(k, ncol(pca_result$x)), drop = FALSE],
      k = k,
      variance_explained = summary(pca_result)$importance[2, 1:min(k, ncol(pca_result$x))],
      meta = list(
        as_of_date = as_of_date,
        n_series = ncol(X_m_panel),
        n_obs = nrow(X_m_panel)
      )
    )
    
    return(result)
    
  }, error = function(e) {
    warning("TPRF factor extraction failed: ", e$message)
    return(list(
      factors_m = matrix(NA, nrow = nrow(X_m_panel), ncol = k),
      k = k,
      meta = list(error = e$message)
    ))
  })
}

#' Fit TPRF-MIDAS model (MIDAS on factors)
#' @param y_q Quarterly target variable
#' @param factors_m Monthly factors
#' @param lag_map Lag map for ragged edge
#' @param window_cfg Window configuration
#' @return Fitted TPRF-MIDAS model
fit_tprf_midas <- function(y_q, factors_m, lag_map, window_cfg) {
  source("R/midas_models.R")
  
  # Fit MIDAS using factors as regressors
  # Use first factor for simplicity (can extend to multiple factors)
  
  if (ncol(factors_m) > 0) {
    factor1 <- factors_m[, 1]
  } else {
    warning("No factors available for TPRF-MIDAS")
    return(NULL)
  }
  
  spec_cfg <- list(
    lag_min = 0,
    lag_max = 11
  )
  
  model <- fit_midas_unrestricted(y_q, factor1, lag_map, spec_cfg, window_cfg)
  
  if (!is.null(model)) {
    model$model_type <- "tprf_midas"
    model$n_factors <- ncol(factors_m)
  }
  
  return(model)
}

#' Predict with TPRF-MIDAS model
#' @param model Fitted TPRF-MIDAS model
#' @param factors_m_current Current monthly factors
#' @param lag_map_current Current lag map
#' @return List with forecast, SE, and metadata
predict_tprf_midas <- function(model, factors_m_current, lag_map_current) {
  source("R/midas_models.R")
  
  if (is.null(model)) {
    return(list(
      point = NA,
      se = NA,
      meta = list(error = "Model is NULL")
    ))
  }
  
  # Use current factors for prediction
  if (is.matrix(factors_m_current) && ncol(factors_m_current) > 0) {
    factor_current <- factors_m_current[, 1]
  } else {
    factor_current <- factors_m_current
  }
  
  forecast <- predict_midas_unrestricted(model, factor_current, lag_map_current)
  
  if (!is.null(forecast$meta)) {
    forecast$meta$model_type <- "tprf_midas"
  }
  
  return(forecast)
}

#' Update TPRF if needed based on schedule
#' @param vintage Vintage data snapshot
#' @param lag_map Lag map
#' @param cfg Configuration
#' @return TPRF forecast or NULL
maybe_update_tprf <- function(vintage, lag_map, cfg) {
  # Check if TPRF should be updated
  # Simplified: always update for now
  
  vars <- cfg$variables
  
  # Get indicators marked for TPRF
  tprf_indicators <- c()
  if (!is.null(vars$indicators)) {
    for (ind in vars$indicators) {
      if (!is.null(ind$in_tprf) && ind$in_tprf) {
        tprf_indicators <- c(tprf_indicators, ind$id)
      }
    }
  }
  
  if (length(tprf_indicators) == 0) {
    warning("No indicators marked for TPRF")
    return(NULL)
  }
  
  # Build panel matrix
  # Simplified: assume vintage$X_m has all data
  # In practice, filter by tprf_indicators
  
  X_m_panel <- as.matrix(vintage$X_m[, setdiff(names(vintage$X_m), c("date", "series_id")), drop = FALSE])
  
  if (ncol(X_m_panel) == 0 || nrow(X_m_panel) == 0) {
    warning("Empty panel for TPRF")
    return(NULL)
  }
  
  # Extract factors
  k_factors <- if (!is.null(cfg$dfm$factors_k_candidates)) cfg$dfm$factors_k_candidates[1] else 3
  
  tprf_result <- build_tprf_factors(
    X_m_panel, 
    k = k_factors, 
    as_of_date = vintage$as_of_date,
    window_cfg = cfg$window
  )
  
  # Fit TPRF-MIDAS
  y_q <- vintage$y_q$value
  factors_m <- tprf_result$factors_m
  
  model <- fit_tprf_midas(y_q, factors_m, lag_map, cfg$window)
  
  # Predict
  forecast <- predict_tprf_midas(model, factors_m, lag_map)
  
  return(forecast)
}
