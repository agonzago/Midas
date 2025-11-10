# tprf_models.R
# Three-Pass Regression Filter (3PF/TPRF) models

#' Build TPRF factors from monthly panel
#' Three-Pass Regression Filter (Kelly and Pruitt, 2015)
#' Extracts latent factors from panel with missing data
#' @param X_m_panel Wide matrix of monthly indicators (T x N)
#' @param k Number of factors to extract (NULL for auto-selection)
#' @param as_of_date Date for the factor extraction
#' @param window_cfg Window configuration
#' @return List with factors and metadata
build_tprf_factors <- function(X_m_panel, k, as_of_date, window_cfg) {
  
  if (!is.matrix(X_m_panel)) {
    X_m_panel <- as.matrix(X_m_panel)
  }
  
  # IMPORTANT: Do NOT apply rolling window here!
  # The calling code (run_rolling_evaluation.R) already handles window selection
  # by passing the correct subset of X_panel_full.
  # Applying rolling window here would truncate the ragged edge months.
  # Original rolling window logic commented out:
  # if (!is.null(window_cfg) && window_cfg$type == "rolling") {
  #   ...
  # }
  # Just use X_m_panel as provided
  
  T <- nrow(X_m_panel)  # Time periods
  N <- ncol(X_m_panel)  # Number of series
  
  # Remove columns with too many NAs (>30% threshold - stricter for reliable factors)
  na_prop <- colMeans(is.na(X_m_panel))
  valid_cols <- na_prop < 0.3
  
  if (sum(valid_cols) < 2) {
    # If too strict, relax to 50%
    cat("  Warning: Too few series with <30% missing. Relaxing to <50% missing.\n")
    valid_cols <- na_prop < 0.5
  }
  
  if (sum(valid_cols) < 2) {
    # If still too few, use all available
    cat("  Warning: Too few series with <50% missing. Using all available series.\n")
    valid_cols <- rep(TRUE, N)
  }
  
  X_m_panel <- X_m_panel[, valid_cols, drop = FALSE]
  N <- ncol(X_m_panel)
  
  cat("  Using", N, "series with average", round(mean(na_prop[valid_cols])*100, 1), "% missing data\n")
  
  # Auto-select number of factors if k is NULL
  if (is.null(k)) {
    # Rule of thumb: 1 factor per 3-4 series, max 2 factors
    k <- min(2, max(1, floor(N / 3)))
    cat("  Auto-selected", k, "factor(s) based on", N, "available series\n")
  } else {
    # Adjust number of factors based on available series
    # Rule of thumb: need at least 3-4 series per factor
    k_max <- max(1, floor(N / 3))
    if (k > k_max) {
      cat("  Warning: Too few series (", N, ") for", k, "factors. Reducing to", k_max, "factor(s)\n")
      k <- k_max
    }
  }
  
  if (N < 2) {
    stop("Need at least 2 series to extract factors. Only ", N, " available.")
  }
  
  # Standardize each series (handle NAs)
  X_std <- matrix(NA, nrow = T, ncol = N)
  for (i in 1:N) {
    x <- X_m_panel[, i]
    valid_idx <- !is.na(x)
    if (sum(valid_idx) > 0) {
      x_mean <- mean(x[valid_idx])
      x_sd <- sd(x[valid_idx])
      if (x_sd > 0) {
        X_std[, i] <- (x - x_mean) / x_sd
      } else {
        X_std[, i] <- x - x_mean
      }
    }
  }
  
  tryCatch({
    # Three-Pass Regression Filter
    # Pass 1: Time-series regressions to get loadings
    # Pass 2: Cross-sectional regressions to get factors
    # Pass 3: Time-series regressions to refine loadings
    
    cat("  Extracting", k, "factors using Three-Pass Regression Filter...\n")
    
    # Initialize with PCA on complete cases
    complete_rows <- complete.cases(X_std)
    if (sum(complete_rows) < 10) {
      # Not enough complete data, use mean imputation
      for (j in 1:N) {
        col_mean <- mean(X_std[, j], na.rm = TRUE)
        X_std[is.na(X_std[, j]), j] <- col_mean
      }
      complete_rows <- rep(TRUE, T)
    }
    
    X_complete <- X_std[complete_rows, , drop = FALSE]
    if (nrow(X_complete) > k && ncol(X_complete) > k) {
      pca_init <- prcomp(X_complete, center = FALSE, scale. = FALSE, rank. = k)
      factors_init <- matrix(0, nrow = T, ncol = k)
      factors_init[complete_rows, ] <- pca_init$x[, 1:k, drop = FALSE]
    } else {
      # Fallback to random initialization
      factors_init <- matrix(rnorm(T * k), nrow = T, ncol = k)
    }
    
    # Iterative refinement (EM-like algorithm)
    max_iter <- 10
    tol <- 1e-4
    factors <- factors_init
    loadings <- matrix(0, nrow = N, ncol = k)
    
    for (iter in 1:max_iter) {
      factors_old <- factors
      
      # Pass 1: Estimate loadings via time-series regression
      # For each series i: X_i,t = lambda_i' * F_t + e_i,t
      for (i in 1:N) {
        x_i <- X_std[, i]
        valid_t <- !is.na(x_i)
        
        if (sum(valid_t) > k) {
          # Regression: x_i ~ F
          F_valid <- factors[valid_t, , drop = FALSE]
          x_valid <- x_i[valid_t]
          
          # OLS: lambda_i = (F'F)^{-1} F'x
          FtF <- crossprod(F_valid)
          if (det(FtF) > 1e-10) {
            loadings[i, ] <- solve(FtF, crossprod(F_valid, x_valid))
          }
        }
      }
      
      # Pass 2: Estimate factors via cross-sectional regression
      # For each time t: X_{i,t} = lambda_i' * F_t + e_{i,t}
      # Solve for F_t given lambda
      for (t in 1:T) {
        x_t <- X_std[t, ]
        valid_i <- !is.na(x_t)
        
        if (sum(valid_i) > k) {
          # Regression: x_t ~ Lambda
          Lambda_valid <- loadings[valid_i, , drop = FALSE]
          x_valid <- x_t[valid_i]
          
          # OLS: F_t = (Lambda'Lambda)^{-1} Lambda'x
          LtL <- crossprod(Lambda_valid)
          if (det(LtL) > 1e-10) {
            factors[t, ] <- solve(LtL, crossprod(Lambda_valid, x_valid))
          }
        }
      }
      
      # Check convergence
      factor_change <- sqrt(mean((factors - factors_old)^2))
      if (factor_change < tol) {
        cat("  Converged after", iter, "iterations\n")
        break
      }
    }
    
    # Pass 3: Final refinement of loadings
    for (i in 1:N) {
      x_i <- X_std[, i]
      valid_t <- !is.na(x_i)
      
      if (sum(valid_t) > k) {
        F_valid <- factors[valid_t, , drop = FALSE]
        x_valid <- x_i[valid_t]
        FtF <- crossprod(F_valid)
        if (det(FtF) > 1e-10) {
          loadings[i, ] <- solve(FtF, crossprod(F_valid, x_valid))
        }
      }
    }
    
    # Calculate variance explained (properly accounting for missing values)
    X_fitted <- factors %*% t(loadings)
    
    # Only compare at non-missing observations
    valid_mask <- !is.na(X_std)
    total_var <- sum(X_std[valid_mask]^2)
    residual_var <- sum((X_std[valid_mask] - X_fitted[valid_mask])^2)
    r_squared <- 1 - (residual_var / total_var)
    
    # Convert factors to time series
    factors_ts <- ts(factors, frequency = 12)
    
    cat("  R-squared:", round(r_squared, 3), "\n")
    
    result <- list(
      factors_m = factors_ts,
      loadings = loadings,
      k = k,
      r_squared = r_squared,
      variance_explained = colMeans(factors^2) / sum(colMeans(factors^2)),
      meta = list(
        as_of_date = as_of_date,
        n_series = N,
        n_obs = T,
        method = "three_pass_filter"
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
#' @param factors_m Monthly factors (matrix or ts object)
#' @param y_lag AR lag order
#' @param x_lag Factor lag order  
#' @param month_of_quarter Month within quarter (0, 1, or 2)
#' @param window_cfg Window configuration
#' @return Fitted TPRF-MIDAS model
fit_tprf_midas <- function(y_q, factors_m, y_lag = 2, x_lag = 4, month_of_quarter = 2, window_cfg = NULL) {
  source("R/midas_models.R")
  
  # Use first factor as the main predictor
  # Can be extended to use multiple factors
  if (is.matrix(factors_m) || is.data.frame(factors_m)) {
    if (ncol(factors_m) > 0) {
      factor1 <- factors_m[, 1]
    } else {
      warning("No factors available for TPRF-MIDAS")
      return(NULL)
    }
  } else {
    factor1 <- factors_m
  }
  
  # Convert to ts if not already
  if (!inherits(factor1, "ts")) {
    factor1 <- ts(factor1, frequency = 12)
  }
  
  # Fit MIDAS using the factor as monthly indicator
  model <- fit_midas_unrestricted(
    y_q = y_q,
    x_m = factor1,
    y_lag = y_lag,
    x_lag = x_lag,
    month_of_quarter = month_of_quarter,
    window_cfg = window_cfg
  )
  
  if (!is.null(model)) {
    model$model_type <- "tprf_midas"
    model$n_factors <- if (is.matrix(factors_m)) ncol(factors_m) else 1
  }
  
  return(model)
}

#' Predict with TPRF-MIDAS model
#' @param model Fitted TPRF-MIDAS model
#' @param y_new Recent Y values for AR terms
#' @param factor_new Recent factor values for forecast
#' @return List with forecast, SE, and metadata
predict_tprf_midas <- function(model, y_new, factor_new) {
  source("R/midas_models.R")
  
  if (is.null(model)) {
    return(list(
      point = NA,
      se = NA,
      meta = list(error = "Model is NULL")
    ))
  }
  
  # Use the fixed MIDAS prediction function
  forecast <- predict_midas_unrestricted(model, y_new, factor_new)
  
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
