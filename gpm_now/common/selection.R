# selection.R
# Model selection and persistence logic

#' Select best model based on metrics
#' @param metrics_df Data frame with model metrics (rmse, bic, etc.)
#' @param primary Primary selection criterion
#' @param secondary Secondary selection criterion
#' @return Selected model specification ID
select_model <- function(metrics_df, primary = "rmse", secondary = "bic") {
  if (is.null(metrics_df) || nrow(metrics_df) == 0) {
    warning("No metrics available for model selection")
    return(NULL)
  }
  
  # Check if primary criterion column exists
  if (!primary %in% names(metrics_df)) {
    warning("Primary criterion '", primary, "' not found in metrics")
    return(NULL)
  }
  
  # Sort by primary criterion
  metrics_df <- metrics_df[order(metrics_df[[primary]]), ]
  
  # If there's a tie (or multiple models within tolerance), use secondary
  if (!is.null(secondary) && secondary %in% names(metrics_df)) {
    # Get models within 5% of best primary metric
    best_primary <- metrics_df[[primary]][1]
    tolerance <- 0.05 * best_primary
    
    candidates <- metrics_df[metrics_df[[primary]] <= (best_primary + tolerance), ]
    
    if (nrow(candidates) > 1) {
      # Use secondary criterion
      candidates <- candidates[order(candidates[[secondary]]), ]
      selected <- candidates[1, ]
    } else {
      selected <- metrics_df[1, ]
    }
  } else {
    selected <- metrics_df[1, ]
  }
  
  # Return spec_id or model identifier
  if ("spec_id" %in% names(selected)) {
    return(selected$spec_id)
  } else if ("model_id" %in% names(selected)) {
    return(selected$model_id)
  } else {
    return(rownames(selected)[1])
  }
}

#' Create model registry for tracking specs
#' @param registry_path Path to registry file
#' @return Registry data frame or new empty registry
load_model_registry <- function(registry_path = "output/models/registry.csv") {
  if (file.exists(registry_path)) {
    registry <- read.csv(registry_path, stringsAsFactors = FALSE)
    return(registry)
  } else {
    # Create new registry
    registry <- data.frame(
      model_id = character(),
      indicator_id = character(),
      method = character(),
      spec_hash = character(),
      selected_date = as.Date(character()),
      rmse = numeric(),
      bic = numeric(),
      frozen = logical(),
      stringsAsFactors = FALSE
    )
    return(registry)
  }
}

#' Save model registry
#' @param registry Registry data frame
#' @param registry_path Path to save registry
save_model_registry <- function(registry, registry_path = "output/models/registry.csv") {
  dir.create(dirname(registry_path), showWarnings = FALSE, recursive = TRUE)
  write.csv(registry, file = registry_path, row.names = FALSE)
}

#' Add or update model in registry
#' @param registry Registry data frame
#' @param model_id Model identifier
#' @param indicator_id Indicator ID
#' @param method Method name
#' @param spec Model specification
#' @param metrics Model metrics
#' @param frozen Whether model is frozen
#' @return Updated registry
update_registry <- function(registry, model_id, indicator_id, method, spec, metrics, frozen = TRUE) {
  # Compute spec hash for auditing
  spec_hash <- digest::digest(spec, algo = "md5")
  
  # Check if model already exists
  existing_idx <- which(registry$model_id == model_id)
  
  new_entry <- data.frame(
    model_id = model_id,
    indicator_id = indicator_id,
    method = method,
    spec_hash = spec_hash,
    selected_date = as.character(Sys.Date()),
    rmse = if (!is.null(metrics$rmse)) metrics$rmse else NA,
    bic = if (!is.null(metrics$bic)) metrics$bic else NA,
    frozen = frozen,
    stringsAsFactors = FALSE
  )
  
  if (length(existing_idx) > 0) {
    # Update existing entry
    registry[existing_idx, ] <- new_entry
  } else {
    # Add new entry
    registry <- rbind(registry, new_entry)
  }
  
  return(registry)
}

#' Check if model should be re-estimated
#' @param registry Registry data frame
#' @param model_id Model ID
#' @param reselection_trigger Condition to trigger reselection
#' @return Logical indicating if re-estimation is needed
should_reestimate <- function(registry, model_id, reselection_trigger = NULL) {
  if (nrow(registry) == 0) {
    return(TRUE)
  }
  
  model_entry <- registry[registry$model_id == model_id, ]
  
  if (nrow(model_entry) == 0) {
    return(TRUE)
  }
  
  # Check if frozen
  if (model_entry$frozen[1]) {
    # Check reselection trigger
    if (!is.null(reselection_trigger)) {
      # Could be based on time elapsed, performance degradation, etc.
      return(reselection_trigger)
    }
    return(FALSE)
  }
  
  return(TRUE)
}

#' Perform rolling window evaluation for model selection
#' @param y_q Quarterly target
#' @param x_m Monthly indicator
#' @param specs List of model specifications to evaluate
#' @param window_length Window length in quarters
#' @param horizon Forecast horizon
#' @return Data frame with evaluation metrics
rolling_evaluation <- function(y_q, x_m, specs, window_length = 40, horizon = 1) {
  n_q <- length(y_q)
  
  if (n_q < window_length + horizon) {
    warning("Insufficient data for rolling evaluation")
    return(NULL)
  }
  
  results <- list()
  
  for (spec_id in names(specs)) {
    spec <- specs[[spec_id]]
    forecasts <- c()
    actuals <- c()
    
    # Rolling window
    for (t in (window_length + 1):(n_q - horizon + 1)) {
      # Training window
      train_y <- y_q[(t - window_length):(t - 1)]
      
      # Simplified: assume x_m aligned
      # In practice, need proper monthly-quarterly alignment
      train_x <- x_m[1:(length(train_y) * 3)]
      
      # Fit model (simplified)
      # In practice, use actual fitting functions
      model_mean <- mean(train_y, na.rm = TRUE)
      
      # Forecast
      forecast <- model_mean
      actual <- y_q[t + horizon - 1]
      
      forecasts <- c(forecasts, forecast)
      actuals <- c(actuals, actual)
    }
    
    # Calculate metrics
    errors <- actuals - forecasts
    rmse <- sqrt(mean(errors^2, na.rm = TRUE))
    mae <- mean(abs(errors), na.rm = TRUE)
    
    results[[spec_id]] <- data.frame(
      spec_id = spec_id,
      rmse = rmse,
      mae = mae,
      n_forecasts = length(forecasts),
      stringsAsFactors = FALSE
    )
  }
  
  # Combine results
  results_df <- do.call(rbind, results)
  rownames(results_df) <- NULL
  
  return(results_df)
}

#' Freeze model specification
#' @param registry Registry data frame
#' @param model_id Model ID to freeze
#' @return Updated registry
freeze_model <- function(registry, model_id) {
  idx <- which(registry$model_id == model_id)
  if (length(idx) > 0) {
    registry$frozen[idx] <- TRUE
  }
  return(registry)
}

#' Unfreeze model specification (trigger reselection)
#' @param registry Registry data frame
#' @param model_id Model ID to unfreeze
#' @return Updated registry
unfreeze_model <- function(registry, model_id) {
  idx <- which(registry$model_id == model_id)
  if (length(idx) > 0) {
    registry$frozen[idx] <- FALSE
  }
  return(registry)
}
