# Mexico MIDAS Rolling Window Out-of-Sample Evaluation
# Tests the fixed MIDAS implementation with pseudo-real-time forecasts
# Includes TPRF-MIDAS comparison and MIDAS combination

library(midasr)
source("R/midas_models.R")
source("R/tprf_models.R")
source("R/combine.R")
source("R/structural_breaks.R")

cat("=== MIDAS Rolling Window Evaluation ===\n\n")

# Load data
mex_Q <- read.csv("../Data/mex_Q.csv")
mex_M <- read.csv("../Data/mex_M.csv")

# Extract and clean data
y_data <- na.omit(mex_Q$DA_GDP)
x_data <- na.omit(mex_M$DA_EAI)

# Get dates
y_dates <- as.Date(mex_Q$X)[!is.na(mex_Q$DA_GDP)]
x_dates <- as.Date(mex_M$X)[!is.na(mex_M$DA_EAI)]

# Align data (ensure X has 3 * length(Y) observations)
n_quarters <- length(y_data)
n_months_needed <- n_quarters * 3

if (length(x_data) < n_months_needed) {
  n_quarters <- floor(length(x_data) / 3)
  y_data <- head(y_data, n_quarters)
  y_dates <- head(y_dates, n_quarters)
}
x_data_aligned <- head(x_data, n_quarters * 3)

# Create time series
y_start_year <- as.numeric(format(y_dates[1], "%Y"))
y_start_quarter <- ceiling(as.numeric(format(y_dates[1], "%m")) / 3)
x_start_year <- y_start_year
x_start_month <- (y_start_quarter - 1) * 3 + 1

y_q_full <- ts(y_data, start = c(y_start_year, y_start_quarter), frequency = 4)
x_m_full <- ts(x_data_aligned, start = c(x_start_year, x_start_month), frequency = 12)

cat("Full dataset:\n")
cat("  Y (GDP):", length(y_q_full), "quarters from", 
    paste(start(y_q_full), collapse="-"), "to", paste(end(y_q_full), collapse="-"), "\n")
cat("  X (EAI):", length(x_m_full), "months\n\n")

# Build panel for TPRF
cat("Building indicator panel for TPRF...\n")
indicator_cols <- c("DA_EAI", "DA_GVFI", "DA_PMI_M", "DA_PMI_NM", 
                    "DA_RETSALES", "DA_RETGRO", "DA_RETSUP")
available_cols <- indicator_cols[indicator_cols %in% names(mex_M)]
cat("  Available indicators:", length(available_cols), "-", paste(available_cols, collapse=", "), "\n")

X_panel_full <- NULL
use_tprf <- length(available_cols) >= 2

if (use_tprf) {
  X_panel_full <- matrix(NA, nrow = length(x_m_full), ncol = length(available_cols))
  colnames(X_panel_full) <- available_cols
  
  for (i in seq_along(available_cols)) {
    col_data <- mex_M[[available_cols[i]]]
    X_panel_full[, i] <- head(col_data, length(x_m_full))
  }
  cat("  Panel dimensions:", nrow(X_panel_full), "x", ncol(X_panel_full), "\n\n")
} else {
  cat("  Not enough indicators for TPRF (need >= 2)\n\n")
}

# Rolling window parameters
initial_window <- 60  # Start with 60 quarters (15 years)
min_window <- 40      # Minimum window: 40 quarters (10 years)

# Model specifications to test
specs <- list(
  "MIDAS_AR2_lag4_m2" = list(
    type = "midas",
    y_lag = 2, x_lag = 4, month_of_quarter = 2, 
    window_type = "expanding",
    intercept_adjustment = "none"
  ),
  "MIDAS_AR2_lag4_m2_roll40" = list(
    type = "midas",
    y_lag = 2, x_lag = 4, month_of_quarter = 2, 
    window_type = "rolling", window_length = 40,
    intercept_adjustment = "none"
  ),
  "MIDAS_AR1_lag3_m2" = list(
    type = "midas",
    y_lag = 1, x_lag = 3, month_of_quarter = 2, 
    window_type = "expanding",
    intercept_adjustment = "none"
  ),
  "MIDAS_AR2_lag4_m2_ADJ" = list(
    type = "midas",
    y_lag = 2, x_lag = 4, month_of_quarter = 2, 
    window_type = "expanding",
    intercept_adjustment = "recent_errors",
    adjustment_window = 4
  ),
  "MIDAS_AR1_lag3_m2_ADJ" = list(
    type = "midas",
    y_lag = 1, x_lag = 3, month_of_quarter = 2, 
    window_type = "expanding",
    intercept_adjustment = "recent_errors",
    adjustment_window = 4
  ),
  "TPRF_AR2_lag4_m2" = list(
    type = "tprf",
    k_factors = NULL,  # Auto-adjust based on available data
    y_lag = 2, x_lag = 4, month_of_quarter = 2,
    window_type = "expanding"
  ),
  "TPRF_AR2_lag4_m2_roll40" = list(
    type = "tprf",
    k_factors = NULL,  # Auto-adjust based on available data
    y_lag = 2, x_lag = 4, month_of_quarter = 2,
    window_type = "rolling", window_length = 40
  )
)

# Remove TPRF specs if not enough indicators
if (!use_tprf) {
  specs <- specs[!sapply(specs, function(s) s$type == "tprf")]
}

cat("Model specifications:\n")
for (spec_name in names(specs)) {
  spec <- specs[[spec_name]]
  if (spec$type == "tprf") {
    cat(sprintf("  %s: TPRF with %d factors, y_lag=%d, x_lag=%d, moq=%s, %s window\n",
                spec_name, spec$k_factors, spec$y_lag, spec$x_lag, 
                spec$month_of_quarter, spec$window_type))
  } else {
    cat(sprintf("  %s: y_lag=%d, x_lag=%d, moq=%s, %s window\n",
                spec_name, spec$y_lag, spec$x_lag, spec$month_of_quarter, spec$window_type))
  }
}
cat("\n")

# Check if we have enough data
n_total <- length(y_q_full)
if (n_total < initial_window + 4) {
  cat("Error: Not enough data for rolling evaluation\n")
  cat("  Need:", initial_window + 4, "quarters\n")
  cat("  Have:", n_total, "quarters\n")
  quit(save = "no")
}

# Run rolling window evaluation
cat("Starting rolling window evaluation...\n")
cat("  Initial window:", initial_window, "quarters\n")
cat("  Number of forecasts:", n_total - initial_window, "\n\n")

results_all <- list()

for (spec_name in names(specs)) {
  spec <- specs[[spec_name]]
  cat("Evaluating:", spec_name, "\n")
  
  forecasts <- numeric(n_total - initial_window)
  actuals <- numeric(n_total - initial_window)
  dates <- character(n_total - initial_window)
  forecast_dates <- numeric(n_total - initial_window)
  
  for (h in 1:(n_total - initial_window)) {
    forecast_period <- initial_window + h
    
    # Determine training window
    if (spec$window_type == "rolling" && !is.null(spec$window_length)) {
      # Rolling window: use last window_length quarters
      train_end <- forecast_period - 1
      train_start <- max(1, train_end - spec$window_length + 1)
      window_cfg <- list(type = "rolling", length_quarters = spec$window_length)
    } else {
      # Expanding window: use all data up to forecast period
      train_start <- 1
      train_end <- forecast_period - 1
      window_cfg <- NULL
    }
    
    # Extract training data - simpler indexing
    y_train <- y_q_full[train_start:train_end]
    x_train <- x_m_full[(train_start*3 - 2):(train_end*3)]
    
    # Convert back to ts objects with proper attributes
    y_train <- ts(y_train, start = start(y_q_full), frequency = 4)
    x_train <- ts(x_train, start = start(x_m_full), frequency = 12)
    
    # Extract training panel for TPRF if needed
    # IMPORTANT: For ragged edge, include data up to the number of available months
    factor_future_values <- NULL
    if (spec$type == "tprf" && use_tprf) {
      # month_of_quarter uses 0=end of quarter, 1=second month, 2=first month
      # Translate to how many months of the forecast quarter are observed
      available_months <- max(1, min(3, 3 - spec$month_of_quarter))
      last_month_available <- (forecast_period - 1) * 3 + available_months
      X_panel_train <- X_panel_full[(train_start*3 - 2):last_month_available, , drop = FALSE]
    }
    
    # Fit model based on type
    if (spec$type == "tprf" && use_tprf) {
      # TPRF-MIDAS: Extract factors from training sample only
      model_info <- tryCatch({
        # Diagnostic for first forecast
        if (h == 1) {
          cat("  TPRF Diagnostics (first forecast):\n")
          cat("    Training panel dims:", nrow(X_panel_train), "x", ncol(X_panel_train), "\n")
          cat("    Y training length:", length(y_train), "quarters\n")
          cat("    Expected X length:", length(y_train) * 3, "months\n")
        }
        
        # Extract factors using ONLY the training data
        tprf_res <- build_tprf_factors(
          X_m_panel = X_panel_train,
          k = spec$k_factors,
          as_of_date = NULL,
          window_cfg = window_cfg
        )
        
        if (!is.null(tprf_res) && !any(is.na(tprf_res$factors_m))) {
          # Separate completed-quarter factors (for fitting) and ragged months (for forecasting)
          train_start_year <- as.numeric(start(y_train)[1])
          train_start_quarter <- as.numeric(start(y_train)[2])
          train_start_month <- (train_start_quarter - 1) * 3 + 1

          factor_matrix <- as.matrix(tprf_res$factors_m)
          total_factor_months <- nrow(factor_matrix)
          train_months_needed <- length(y_train) * 3
          
          if (total_factor_months < train_months_needed) {
            stop(sprintf("Factor matrix shorter (%d) than training months (%d)", 
                         total_factor_months, train_months_needed))
          }
          
          completed_matrix <- factor_matrix[seq_len(train_months_needed), , drop = FALSE]
          ragged_matrix <- NULL
          if (total_factor_months > train_months_needed) {
            ragged_matrix <- factor_matrix[(train_months_needed + 1):total_factor_months, , drop = FALSE]
          }
          
          # Create ts object aligned with training window
          factors_train <- ts(completed_matrix, 
                              start = c(train_start_year, train_start_month), 
                              frequency = 12)
          
          if (h == 1) {
            cat("    Factor dimensions: ", total_factor_months, "rows\n")
            cat("    Training quarters:", length(y_train), "\n")
            ragged_count <- if (!is.null(ragged_matrix)) nrow(ragged_matrix) else 0
            cat("    Ragged edge months:", ragged_count, "(expected", available_months, ")\n")
          }

          if (h == 1) {
            cat("    Factors extracted: R^2 =", round(tprf_res$r_squared, 3), "\n")
            cat("    Factor ts: length =", length(factors_train[,1]), 
                ", start =", paste(start(factors_train), collapse="-"), "\n")
          }
          
          # Fit MIDAS on factors and RETURN the model
          tprf_model <- fit_tprf_midas(
            y_q = y_train,
            factors_m = factors_train,
            y_lag = spec$y_lag,
            x_lag = spec$x_lag,
            month_of_quarter = spec$month_of_quarter,
            window_cfg = window_cfg
          )
          
          future_factors <- if (!is.null(ragged_matrix)) {
            head(as.numeric(ragged_matrix[, 1]), available_months)
          } else {
            numeric(0)
          }
          
          list(model = tprf_model, future = future_factors)
        } else {
          if (h == 1) cat("    TPRF factor extraction returned NULL or NA\n")
          list(model = NULL, future = NULL)
        }
      }, error = function(e) {
        if (h == 1) {
          cat("  First TPRF model error:", e$message, "\n")
        }
        list(model = NULL, future = NULL)
      })
      
      model <- model_info$model
      factor_future_values <- model_info$future
    } else {
      # Standard MIDAS
      model <- tryCatch({
        fit_midas_unrestricted(
          y_q = y_train,
          x_m = x_train,
          y_lag = spec$y_lag,
          x_lag = spec$x_lag,
          month_of_quarter = spec$month_of_quarter,
          window_cfg = window_cfg
        )
      }, error = function(e) {
        if (h == 1) {
          cat("  First model error:", e$message, "\n")
          cat("    y_train length:", length(y_train), "\n")
          cat("    x_train length:", length(x_train), "\n")
        }
        NULL
      })
    }
    if (!is.null(model)) {
      # Prepare forecast data
      y_new <- if (spec$y_lag > 0) tail(y_train, spec$y_lag) else NULL
      
      # Generate forecast based on model type
      if (spec$type == "tprf" && use_tprf) {
        # For TPRF: use factor values from available months of forecast quarter
        if (!is.null(factor_future_values) && length(factor_future_values) > 0) {
          factor_new <- factor_future_values
          fc <- tryCatch({
            predict_tprf_midas(model, y_new, factor_new)
          }, error = function(e) {
            list(point = NA)
          })
        } else {
          fc <- list(point = NA)
        }
      } else {
        # For standard MIDAS: use last X value
        x_new <- tail(x_train, 1)
        fc <- tryCatch({
          predict_midas_unrestricted(model, y_new, x_new)
        }, error = function(e) {
          list(point = NA)
        })
        
        # Apply intercept adjustment if specified
        if (!is.null(spec$intercept_adjustment) && spec$intercept_adjustment != "none") {
          adjustment_method <- spec$intercept_adjustment
          adjustment_window <- if (!is.null(spec$adjustment_window)) spec$adjustment_window else 4
          
          # Calculate adjustment based on recent errors
          adjustment <- estimate_rolling_adjustment(
            y_train, 
            model$fitted_values, 
            method = adjustment_method,
            window = adjustment_window
          )
          
          # Apply adjustment to forecast
          if (!is.na(fc$point) && !is.na(adjustment)) {
            fc$point <- fc$point + adjustment
            fc$adjustment <- adjustment
          }
        }
      }
      
      forecasts[h] <- fc$point
    } else {
      forecasts[h] <- NA
    }
    
    # Actual value
    actuals[h] <- y_q_full[forecast_period]
    dates[h] <- format(y_dates[forecast_period], "%Y-%m")
    forecast_dates[h] <- as.numeric(time(y_q_full)[forecast_period])
    
    if (h %% 10 == 0) {
      cat("  Completed", h, "/", n_total - initial_window, "forecasts\n")
    }
  }
  
  # Calculate metrics
  valid_idx <- !is.na(forecasts) & !is.na(actuals)
  errors <- actuals[valid_idx] - forecasts[valid_idx]
  
  if (length(errors) > 0) {
    rmse <- sqrt(mean(errors^2))
    mae <- mean(abs(errors))
    me <- mean(errors)
    
    results_all[[spec_name]] <- data.frame(
      spec = spec_name,
      n_forecasts = sum(valid_idx),
      rmse = rmse,
      mae = mae,
      me = me,
      stringsAsFactors = FALSE
    )
    
    # Store detailed results for plotting
    results_all[[spec_name]]$forecasts <- list(forecasts)
    results_all[[spec_name]]$actuals <- list(actuals)
    results_all[[spec_name]]$dates <- list(dates)
    results_all[[spec_name]]$forecast_dates <- list(forecast_dates)
    results_all[[spec_name]]$errors <- list(errors)
    
    cat(sprintf("  RMSE: %.3f, MAE: %.3f, ME: %.3f, Valid: %d/%d\n",
                rmse, mae, me, sum(valid_idx), length(forecasts)))
  } else {
    cat("  No valid forecasts\n")
  }
  
  cat("\n")
}

# Combine and display results
cat("\n=== EVALUATION RESULTS ===\n\n")

if (length(results_all) == 0) {
  cat("ERROR: No valid results - all models failed\n")
  cat("\nCheck warnings:\n")
  print(warnings())
} else {
  results_df <- do.call(rbind, results_all)
  results_df <- results_df[order(results_df$rmse), ]
  rownames(results_df) <- NULL
  
  print(results_df)
  
  cat("\n")
  cat("Best specification (by RMSE):", results_df$spec[1], "\n")
  cat("  RMSE:", round(results_df$rmse[1], 3), "\n")
  cat("  MAE:", round(results_df$mae[1], 3), "\n")
  
  # Identify MIDAS vs TPRF models
  midas_models <- grep("^MIDAS_", results_df$spec, value = TRUE)
  tprf_models <- grep("^TPRF_", results_df$spec, value = TRUE)
  
  if (length(tprf_models) > 0 && length(midas_models) > 0) {
    cat("\n--- MIDAS vs TPRF Comparison ---\n")
    cat("Best MIDAS:", midas_models[which.min(results_df$rmse[results_df$spec %in% midas_models])], "\n")
    cat("  RMSE:", round(min(results_df$rmse[results_df$spec %in% midas_models]), 3), "\n")
    cat("Best TPRF:", tprf_models[which.min(results_df$rmse[results_df$spec %in% tprf_models])], "\n")
    cat("  RMSE:", round(min(results_df$rmse[results_df$spec %in% tprf_models]), 3), "\n")
    
    improvement <- min(results_df$rmse[results_df$spec %in% midas_models]) - 
                   min(results_df$rmse[results_df$spec %in% tprf_models])
    cat("TPRF improvement:", round(improvement, 3), "points\n")
  }
  
  # =============================================================================
  # MIDAS MODEL COMBINATION
  # =============================================================================
  
  if (length(midas_models) >= 2) {
    cat("\n=== MIDAS MODEL COMBINATION ===\n\n")
    
    # For each time period, combine MIDAS forecasts
    n_forecasts <- length(results_all[[midas_models[1]]]$forecasts[[1]])
    
    combo_equal <- numeric(n_forecasts)
    combo_inv_rmse <- numeric(n_forecasts)
    combo_actuals <- results_all[[midas_models[1]]]$actuals[[1]]
    combo_dates <- results_all[[midas_models[1]]]$forecast_dates[[1]]
    
    # Calculate inverse RMSE weights (based on full-sample RMSE)
    midas_rmses <- results_df$rmse[results_df$spec %in% midas_models]
    names(midas_rmses) <- midas_models
    inv_rmse_weights <- 1 / midas_rmses
    inv_rmse_weights <- inv_rmse_weights / sum(inv_rmse_weights)
    
    cat("MIDAS models included:", length(midas_models), "\n")
    cat("Combination weights (inverse RMSE):\n")
    for (i in seq_along(midas_models)) {
      cat(sprintf("  %-30s: %.3f (RMSE=%.3f)\n", 
                  midas_models[i], inv_rmse_weights[i], midas_rmses[i]))
    }
    cat("\n")
    
    # Combine forecasts for each time period
    for (t in 1:n_forecasts) {
      # Extract forecasts from all MIDAS models for this time period
      midas_fcsts_t <- sapply(midas_models, function(m) {
        results_all[[m]]$forecasts[[1]][t]
      })
      
      # Remove NAs
      valid_fcsts <- !is.na(midas_fcsts_t)
      
      if (sum(valid_fcsts) > 0) {
        # Equal weights
        combo_equal[t] <- mean(midas_fcsts_t[valid_fcsts])
        
        # Inverse RMSE weights (renormalize for available models)
        weights_t <- inv_rmse_weights[valid_fcsts]
        weights_t <- weights_t / sum(weights_t)
        combo_inv_rmse[t] <- sum(weights_t * midas_fcsts_t[valid_fcsts])
      } else {
        combo_equal[t] <- NA
        combo_inv_rmse[t] <- NA
      }
    }
    
    # Calculate combination performance
    valid_combo <- !is.na(combo_equal) & !is.na(combo_actuals)
    
    if (sum(valid_combo) > 0) {
      errors_equal <- combo_actuals[valid_combo] - combo_equal[valid_combo]
      errors_inv_rmse <- combo_actuals[valid_combo] - combo_inv_rmse[valid_combo]
      
      rmse_equal <- sqrt(mean(errors_equal^2))
      mae_equal <- mean(abs(errors_equal))
      
      rmse_inv_rmse <- sqrt(mean(errors_inv_rmse^2))
      mae_inv_rmse <- mean(abs(errors_inv_rmse))
      
      cat("Combination Results:\n")
      cat(sprintf("  Equal weights:   RMSE=%.3f, MAE=%.3f\n", rmse_equal, mae_equal))
      cat(sprintf("  Inv-RMSE weights: RMSE=%.3f, MAE=%.3f\n", rmse_inv_rmse, mae_inv_rmse))
      
      # Compare to best individual MIDAS
      best_midas_rmse <- min(results_df$rmse[results_df$spec %in% midas_models])
      cat(sprintf("  Best individual:  RMSE=%.3f\n", best_midas_rmse))
      
      improvement_equal <- best_midas_rmse - rmse_equal
      improvement_inv_rmse <- best_midas_rmse - rmse_inv_rmse
      
      cat("\nImprovement over best individual MIDAS:\n")
      cat(sprintf("  Equal weights:    %.3f points (%.1f%%)\n", 
                  improvement_equal, 100 * improvement_equal / best_midas_rmse))
      cat(sprintf("  Inv-RMSE weights: %.3f points (%.1f%%)\n", 
                  improvement_inv_rmse, 100 * improvement_inv_rmse / best_midas_rmse))
      
      # Store combination results in results_all for plotting
      combo_equal_full <- data.frame(
        spec = "MIDAS_COMBO_EQUAL",
        n_forecasts = sum(valid_combo),
        rmse = rmse_equal,
        mae = mae_equal,
        me = mean(errors_equal),
        stringsAsFactors = FALSE
      )
      combo_equal_full$forecasts <- list(combo_equal)
      combo_equal_full$actuals <- list(combo_actuals)
      combo_equal_full$dates <- list(results_all[[midas_models[1]]]$dates[[1]])
      combo_equal_full$forecast_dates <- list(combo_dates)
      combo_equal_full$errors <- list(errors_equal)
      
      combo_inv_rmse_full <- data.frame(
        spec = "MIDAS_COMBO_INV_RMSE",
        n_forecasts = sum(valid_combo),
        rmse = rmse_inv_rmse,
        mae = mae_inv_rmse,
        me = mean(errors_inv_rmse),
        stringsAsFactors = FALSE
      )
      combo_inv_rmse_full$forecasts <- list(combo_inv_rmse)
      combo_inv_rmse_full$actuals <- list(combo_actuals)
      combo_inv_rmse_full$dates <- list(results_all[[midas_models[1]]]$dates[[1]])
      combo_inv_rmse_full$forecast_dates <- list(combo_dates)
      combo_inv_rmse_full$errors <- list(errors_inv_rmse)
      
      # Store in results_all for plotting
      results_all[["MIDAS_COMBO_EQUAL"]] <- combo_equal_full
      results_all[["MIDAS_COMBO_INV_RMSE"]] <- combo_inv_rmse_full
      
      # Add to results_df (only basic columns, matching structure)
      combo_equal_row <- data.frame(
        spec = "MIDAS_COMBO_EQUAL",
        n_forecasts = sum(valid_combo),
        rmse = rmse_equal,
        mae = mae_equal,
        me = mean(errors_equal),
        stringsAsFactors = FALSE
      )
      
      combo_inv_rmse_row <- data.frame(
        spec = "MIDAS_COMBO_INV_RMSE",
        n_forecasts = sum(valid_combo),
        rmse = rmse_inv_rmse,
        mae = mae_inv_rmse,
        me = mean(errors_inv_rmse),
        stringsAsFactors = FALSE
      )
      
      # Ensure column order matches before rbind
      results_df <- rbind(results_df[, c("spec", "n_forecasts", "rmse", "mae", "me")], 
                          combo_equal_row, 
                          combo_inv_rmse_row)
      results_df <- results_df[order(results_df$rmse), ]
      rownames(results_df) <- NULL
    }
    
    cat("\n")
  } else {
    cat("\n(Skipping MIDAS combination - need at least 2 MIDAS models)\n\n")
  }
  
  cat("✓ Rolling window evaluation completed!\n")
  
  # Create visualizations
  cat("\n=== CREATING VISUALIZATIONS ===\n\n")
  
  # Get best MIDAS and best TPRF models
  best_midas <- midas_models[which.min(results_df$rmse[results_df$spec %in% midas_models])]
  
  fc_midas <- results_all[[best_midas]]$forecasts[[1]]
  act_midas <- results_all[[best_midas]]$actuals[[1]]
  dates_midas <- results_all[[best_midas]]$forecast_dates[[1]]
  valid_midas <- !is.na(fc_midas) & !is.na(act_midas)
  errors_midas <- act_midas[valid_midas] - fc_midas[valid_midas]
  
  # Check if TPRF models exist
  has_tprf <- length(tprf_models) > 0
  if (has_tprf) {
    best_tprf <- tprf_models[which.min(results_df$rmse[results_df$spec %in% tprf_models])]
    fc_tprf <- results_all[[best_tprf]]$forecasts[[1]]
    act_tprf <- results_all[[best_tprf]]$actuals[[1]]
    dates_tprf <- results_all[[best_tprf]]$forecast_dates[[1]]
    valid_tprf <- !is.na(fc_tprf) & !is.na(act_tprf)
    errors_tprf <- act_tprf[valid_tprf] - fc_tprf[valid_tprf]
  }
  
  pdf("rolling_evaluation_plots.pdf", width = 12, height = 8)
  
  # ============================================================================
  # SECTION 1: MIDAS MODEL EVALUATION
  # ============================================================================
  
  # Page 1: MIDAS - Title page with summary
  par(mfrow = c(1, 1), mar = c(2, 2, 3, 2))
  plot.new()
  text(0.5, 0.9, "MIDAS MODEL EVALUATION", cex = 2.5, font = 2)
  text(0.5, 0.75, paste("Best Model:", best_midas), cex = 1.8, font = 1)
  text(0.5, 0.55, sprintf("RMSE: %.3f", results_df$rmse[results_df$spec == best_midas]), cex = 1.5)
  text(0.5, 0.45, sprintf("MAE: %.3f", results_df$mae[results_df$spec == best_midas]), cex = 1.5)
  text(0.5, 0.35, sprintf("Mean Error: %.3f", results_df$me[results_df$spec == best_midas]), cex = 1.5)
  text(0.5, 0.25, sprintf("Number of forecasts: %d", results_df$n_forecasts[results_df$spec == best_midas]), cex = 1.5)
  text(0.5, 0.1, "Method: Single Indicator (Economic Activity Index)", cex = 1.2, col = "darkblue")
  
  # Page 2: MIDAS - Forecast vs Actual
  par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
  plot(dates_midas[valid_midas], act_midas[valid_midas], type = "l", lwd = 3, col = "black",
       xlab = "Time", ylab = "GDP Growth (%)", 
       main = paste("MIDAS: Forecast vs Actual -", best_midas),
       ylim = range(c(act_midas[valid_midas], fc_midas[valid_midas]), na.rm = TRUE),
       cex.main = 1.5, cex.lab = 1.3)
  lines(dates_midas[valid_midas], fc_midas[valid_midas], col = "steelblue", lwd = 2.5, lty = 1)
  legend("topright", legend = c("Actual", "MIDAS Forecast"), 
         col = c("black", "steelblue"), lwd = c(3, 2.5), lty = c(1, 1), cex = 1.2)
  grid(col = "gray80")
  
  # Page 3: MIDAS - Forecast Errors over Time
  par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
  plot(dates_midas[valid_midas], errors_midas, type = "h", lwd = 2, col = "steelblue",
       xlab = "Time", ylab = "Forecast Error (%)",
       main = paste("MIDAS: Forecast Errors -", best_midas),
       cex.main = 1.5, cex.lab = 1.3)
  lines(dates_midas[valid_midas], errors_midas, col = "darkblue", lwd = 1)
  abline(h = 0, col = "black", lwd = 2)
  abline(h = mean(errors_midas), col = "red", lty = 2, lwd = 2)
  abline(h = c(-2*sd(errors_midas), 2*sd(errors_midas)), col = "orange", lty = 3, lwd = 1.5)
  legend("topright", 
         legend = c("Errors", "Mean", "±2 SD"), 
         col = c("steelblue", "red", "orange"), 
         lty = c(1, 2, 3), lwd = c(2, 2, 1.5), cex = 1.2)
  grid(col = "gray80")
  
  # Page 4: MIDAS - Error Distribution
  par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
  hist(errors_midas, breaks = 20, col = "lightblue", border = "white",
       xlab = "Forecast Error (%)", main = paste("MIDAS: Error Distribution -", best_midas),
       freq = FALSE, cex.main = 1.5, cex.lab = 1.3)
  lines(density(errors_midas), col = "darkblue", lwd = 3)
  abline(v = 0, col = "red", lty = 2, lwd = 2)
  abline(v = mean(errors_midas), col = "orange", lty = 2, lwd = 2)
  legend("topright", 
         legend = c("Density", "Zero", "Mean Error"), 
         col = c("darkblue", "red", "orange"), 
         lty = c(1, 2, 2), lwd = c(3, 2, 2), cex = 1.2)
  text(min(errors_midas) + 5, max(density(errors_midas)$y) * 0.9,
       sprintf("Mean: %.3f\nSD: %.3f\nRMSE: %.3f", 
               mean(errors_midas), sd(errors_midas), sqrt(mean(errors_midas^2))),
       adj = 0, cex = 1.2)
  
  # Page 5: MIDAS - Scatter Plot
  par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
  plot(act_midas[valid_midas], fc_midas[valid_midas], pch = 19, col = rgb(0, 0.3, 0.7, 0.6),
       xlab = "Actual GDP Growth (%)", ylab = "Forecast GDP Growth (%)",
       main = paste("MIDAS: Forecast vs Actual Scatter -", best_midas),
       xlim = range(act_midas[valid_midas]), ylim = range(act_midas[valid_midas]),
       cex = 1.5, cex.main = 1.5, cex.lab = 1.3)
  abline(0, 1, col = "red", lwd = 2, lty = 2)
  abline(lm(fc_midas[valid_midas] ~ act_midas[valid_midas]), col = "blue", lwd = 2, lty = 1)
  
  corr_midas <- cor(act_midas[valid_midas], fc_midas[valid_midas])
  text(min(act_midas[valid_midas]) + 5, max(act_midas[valid_midas]) - 5, 
       sprintf("Correlation: %.3f\nRMSE: %.3f\nR²: %.3f", 
               corr_midas, sqrt(mean(errors_midas^2)), corr_midas^2),
       adj = 0, cex = 1.3)
  legend("bottomright", legend = c("45° line", "Fitted line"), 
         col = c("red", "blue"), lty = c(2, 1), lwd = 2, cex = 1.2)
  grid(col = "gray80")
  grid(col = "gray80")
  
  # ============================================================================
  # SECTION 2: TPRF MODEL EVALUATION (if available)
  # ============================================================================
  
  if (has_tprf) {
    # Page 6: TPRF - Title page with summary
    par(mfrow = c(1, 1), mar = c(2, 2, 3, 2))
    plot.new()
    text(0.5, 0.9, "TPRF-MIDAS MODEL EVALUATION", cex = 2.5, font = 2)
    text(0.5, 0.75, paste("Best Model:", best_tprf), cex = 1.8, font = 1)
    text(0.5, 0.55, sprintf("RMSE: %.3f", results_df$rmse[results_df$spec == best_tprf]), cex = 1.5)
    text(0.5, 0.45, sprintf("MAE: %.3f", results_df$mae[results_df$spec == best_tprf]), cex = 1.5)
    text(0.5, 0.35, sprintf("Mean Error: %.3f", results_df$me[results_df$spec == best_tprf]), cex = 1.5)
    text(0.5, 0.25, sprintf("Number of forecasts: %d", results_df$n_forecasts[results_df$spec == best_tprf]), cex = 1.5)
    text(0.5, 0.1, "Method: Factor-Based (Three-Pass Regression Filter)", cex = 1.2, col = "darkgreen")
    
    # Page 7: TPRF - Forecast vs Actual
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    plot(dates_tprf[valid_tprf], act_tprf[valid_tprf], type = "l", lwd = 3, col = "black",
         xlab = "Time", ylab = "GDP Growth (%)", 
         main = paste("TPRF: Forecast vs Actual -", best_tprf),
         ylim = range(c(act_tprf[valid_tprf], fc_tprf[valid_tprf]), na.rm = TRUE),
         cex.main = 1.5, cex.lab = 1.3)
    lines(dates_tprf[valid_tprf], fc_tprf[valid_tprf], col = "darkgreen", lwd = 2.5, lty = 1)
    legend("topright", legend = c("Actual", "TPRF Forecast"), 
           col = c("black", "darkgreen"), lwd = c(3, 2.5), lty = c(1, 1), cex = 1.2)
    grid(col = "gray80")
    
    # Page 8: TPRF - Forecast Errors over Time
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    plot(dates_tprf[valid_tprf], errors_tprf, type = "h", lwd = 2, col = "darkgreen",
         xlab = "Time", ylab = "Forecast Error (%)",
         main = paste("TPRF: Forecast Errors -", best_tprf),
         cex.main = 1.5, cex.lab = 1.3)
    lines(dates_tprf[valid_tprf], errors_tprf, col = "darkgreen", lwd = 1)
    abline(h = 0, col = "black", lwd = 2)
    abline(h = mean(errors_tprf), col = "red", lty = 2, lwd = 2)
    abline(h = c(-2*sd(errors_tprf), 2*sd(errors_tprf)), col = "orange", lty = 3, lwd = 1.5)
    legend("topright", 
           legend = c("Errors", "Mean", "±2 SD"), 
           col = c("darkgreen", "red", "orange"), 
           lty = c(1, 2, 3), lwd = c(2, 2, 1.5), cex = 1.2)
    grid(col = "gray80")
    
    # Page 9: TPRF - Error Distribution
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    hist(errors_tprf, breaks = 20, col = "lightgreen", border = "white",
         xlab = "Forecast Error (%)", main = paste("TPRF: Error Distribution -", best_tprf),
         freq = FALSE, cex.main = 1.5, cex.lab = 1.3)
    lines(density(errors_tprf), col = "darkgreen", lwd = 3)
    abline(v = 0, col = "red", lty = 2, lwd = 2)
    abline(v = mean(errors_tprf), col = "orange", lty = 2, lwd = 2)
    legend("topright", 
           legend = c("Density", "Zero", "Mean Error"), 
           col = c("darkgreen", "red", "orange"), 
           lty = c(1, 2, 2), lwd = c(3, 2, 2), cex = 1.2)
    text(min(errors_tprf) + 5, max(density(errors_tprf)$y) * 0.9,
         sprintf("Mean: %.3f\nSD: %.3f\nRMSE: %.3f", 
                 mean(errors_tprf), sd(errors_tprf), sqrt(mean(errors_tprf^2))),
         adj = 0, cex = 1.2)
    
    # Page 10: TPRF - Scatter Plot
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    plot(act_tprf[valid_tprf], fc_tprf[valid_tprf], pch = 19, col = rgb(0, 0.5, 0, 0.6),
         xlab = "Actual GDP Growth (%)", ylab = "Forecast GDP Growth (%)",
         main = paste("TPRF: Forecast vs Actual Scatter -", best_tprf),
         xlim = range(act_tprf[valid_tprf]), ylim = range(act_tprf[valid_tprf]),
         cex = 1.5, cex.main = 1.5, cex.lab = 1.3)
    abline(0, 1, col = "red", lwd = 2, lty = 2)
    abline(lm(fc_tprf[valid_tprf] ~ act_tprf[valid_tprf]), col = "darkgreen", lwd = 2, lty = 1)
    
    corr_tprf <- cor(act_tprf[valid_tprf], fc_tprf[valid_tprf])
    text(min(act_tprf[valid_tprf]) + 5, max(act_tprf[valid_tprf]) - 5, 
         sprintf("Correlation: %.3f\nRMSE: %.3f\nR²: %.3f", 
                 corr_tprf, sqrt(mean(errors_tprf^2)), corr_tprf^2),
         adj = 0, cex = 1.3)
    legend("bottomright", legend = c("45° line", "Fitted line"), 
           col = c("red", "darkgreen"), lty = c(2, 1), lwd = 2, cex = 1.2)
    grid(col = "gray80")
    
    # ============================================================================
    # SECTION 3: MIDAS vs TPRF COMPARISON
    # ============================================================================
    
    # Page 11: Comparison - Title page
    par(mfrow = c(1, 1), mar = c(2, 2, 3, 2))
    plot.new()
    text(0.5, 0.9, "MIDAS vs TPRF-MIDAS COMPARISON", cex = 2.5, font = 2)
    
    rmse_midas <- results_df$rmse[results_df$spec == best_midas]
    rmse_tprf <- results_df$rmse[results_df$spec == best_tprf]
    improvement_pct <- (rmse_midas - rmse_tprf) / rmse_midas * 100
    
    text(0.5, 0.7, "MIDAS Model", cex = 1.8, font = 2, col = "steelblue")
    text(0.5, 0.62, paste(best_midas), cex = 1.3)
    text(0.5, 0.55, sprintf("RMSE: %.3f", rmse_midas), cex = 1.5)
    
    text(0.5, 0.43, "TPRF Model", cex = 1.8, font = 2, col = "darkgreen")
    text(0.5, 0.35, paste(best_tprf), cex = 1.3)
    text(0.5, 0.28, sprintf("RMSE: %.3f", rmse_tprf), cex = 1.5)
    
    winner <- ifelse(improvement_pct > 0, "MIDAS", "TPRF")
    winner_col <- ifelse(improvement_pct > 0, "steelblue", "darkgreen")
    text(0.5, 0.12, sprintf("%s performs better by %.1f%%", winner, abs(improvement_pct)), 
         cex = 1.6, font = 2, col = winner_col)
    
    # Page 12: Direct Forecast Comparison
    valid_comp <- valid_midas & valid_tprf
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    plot(dates_midas[valid_comp], act_midas[valid_comp], type = "l", lwd = 3, col = "black",
         xlab = "Time", ylab = "GDP Growth (%)",
         main = "Forecast Comparison: MIDAS vs TPRF",
         ylim = range(c(act_midas[valid_comp], fc_midas[valid_comp], fc_tprf[valid_comp]), na.rm = TRUE),
         cex.main = 1.5, cex.lab = 1.3)
    lines(dates_midas[valid_comp], fc_midas[valid_comp], col = "steelblue", lwd = 2.5, lty = 1)
    lines(dates_tprf[valid_comp], fc_tprf[valid_comp], col = "darkgreen", lwd = 2.5, lty = 2)
    legend("topright", 
           legend = c("Actual", 
                     sprintf("MIDAS (RMSE: %.2f)", rmse_midas),
                     sprintf("TPRF (RMSE: %.2f)", rmse_tprf)),
           col = c("black", "steelblue", "darkgreen"), 
           lwd = c(3, 2.5, 2.5), lty = c(1, 1, 2), cex = 1.2)
    grid(col = "gray80")
    
    # Page 13: Error Comparison Over Time
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    plot(dates_midas[valid_comp], errors_midas[valid_midas][valid_comp], 
         type = "l", lwd = 2.5, col = "steelblue",
         xlab = "Time", ylab = "Forecast Error (%)",
         main = "Forecast Errors: MIDAS vs TPRF",
         ylim = range(c(errors_midas[valid_midas][valid_comp], errors_tprf[valid_tprf][valid_comp]), na.rm = TRUE),
         cex.main = 1.5, cex.lab = 1.3)
    lines(dates_tprf[valid_comp], errors_tprf[valid_tprf][valid_comp], col = "darkgreen", lwd = 2.5, lty = 2)
    abline(h = 0, col = "black", lty = 1, lwd = 2)
    legend("topright", legend = c(best_midas, best_tprf, "Zero"),
           col = c("steelblue", "darkgreen", "black"), 
           lwd = c(2.5, 2.5, 2), lty = c(1, 2, 1), cex = 1.2)
    grid(col = "gray80")
    
    # Page 14: RMSE Comparison Bar Chart
    par(mfrow = c(1, 1), mar = c(7, 5, 4, 2))
    colors <- ifelse(grepl("^TPRF_", results_df$spec), "darkgreen", "steelblue")
    barplot(results_df$rmse, names.arg = results_df$spec, 
            col = colors,
            main = "RMSE Comparison: All Models",
            ylab = "RMSE", las = 2, cex.names = 0.9,
            cex.main = 1.5, cex.lab = 1.3)
    legend("topright", legend = c("MIDAS", "TPRF"), 
           fill = c("steelblue", "darkgreen"), cex = 1.2)
    grid(col = "gray80")
    
    # Page 15: Cumulative Squared Errors
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    cse_midas <- cumsum(errors_midas[valid_midas][valid_comp]^2)
    cse_tprf <- cumsum(errors_tprf[valid_tprf][valid_comp]^2)
    
    plot(dates_midas[valid_comp], cse_midas, type = "l", lwd = 3, col = "steelblue",
         xlab = "Time", ylab = "Cumulative Squared Error",
         main = "Cumulative Forecast Performance",
         ylim = range(c(cse_midas, cse_tprf)),
         cex.main = 1.5, cex.lab = 1.3)
    lines(dates_tprf[valid_comp], cse_tprf, col = "darkgreen", lwd = 3, lty = 2)
    legend("topleft", legend = c(best_midas, best_tprf),
           col = c("steelblue", "darkgreen"), lwd = 3, lty = c(1, 2), cex = 1.2)
    grid(col = "gray80")
    
    text(dates_midas[valid_comp][length(dates_midas[valid_comp])*0.5], 
         max(cse_midas, cse_tprf)*0.85,
         sprintf("Final RMSE:\nMIDAS: %.3f\nTPRF: %.3f\n\n%s better by %.1f%%",
                 sqrt(mean(errors_midas[valid_midas][valid_comp]^2)), 
                 sqrt(mean(errors_tprf[valid_tprf][valid_comp]^2)),
                 winner, abs(improvement_pct)),
         adj = 0, cex = 1.2, font = 2)
  } else {
    # If no TPRF models, add a page showing all MIDAS models
    par(mfrow = c(1, 1), mar = c(7, 5, 4, 2))
    barplot(results_df$rmse, names.arg = results_df$spec, 
            col = "steelblue",
            main = "RMSE Comparison: All MIDAS Models",
            ylab = "RMSE", las = 2, cex.names = 0.9,
            cex.main = 1.5, cex.lab = 1.3)
    grid(col = "gray80")
  }
  
  # ============================================================================
  # SECTION 4: MIDAS COMBINATION RESULTS (if available)
  # ============================================================================
  
  if ("MIDAS_COMBO_EQUAL" %in% names(results_all)) {
    cat("Adding MIDAS combination plots...\n")
    
    fc_combo_equal <- results_all[["MIDAS_COMBO_EQUAL"]]$forecasts[[1]]
    fc_combo_inv_rmse <- results_all[["MIDAS_COMBO_INV_RMSE"]]$forecasts[[1]]
    act_combo <- results_all[["MIDAS_COMBO_EQUAL"]]$actuals[[1]]
    dates_combo <- results_all[["MIDAS_COMBO_EQUAL"]]$forecast_dates[[1]]
    valid_combo_plot <- !is.na(fc_combo_equal) & !is.na(act_combo)
    
    rmse_combo_equal <- results_df$rmse[results_df$spec == "MIDAS_COMBO_EQUAL"]
    rmse_combo_inv_rmse <- results_df$rmse[results_df$spec == "MIDAS_COMBO_INV_RMSE"]
    
    # Page: MIDAS Combination - Title page
    par(mfrow = c(1, 1), mar = c(2, 2, 3, 2))
    plot.new()
    text(0.5, 0.9, "MIDAS MODEL COMBINATION", cex = 2.5, font = 2)
    text(0.5, 0.75, sprintf("Number of models combined: %d", length(midas_models)), cex = 1.5)
    
    text(0.5, 0.6, "Equal Weights", cex = 1.6, font = 2, col = "purple")
    text(0.5, 0.53, sprintf("RMSE: %.3f", rmse_combo_equal), cex = 1.4)
    
    text(0.5, 0.40, "Inverse-RMSE Weights", cex = 1.6, font = 2, col = "darkorange")
    text(0.5, 0.33, sprintf("RMSE: %.3f", rmse_combo_inv_rmse), cex = 1.4)
    
    best_individual_midas <- min(results_df$rmse[results_df$spec %in% midas_models])
    improvement_equal <- (best_individual_midas - rmse_combo_equal) / best_individual_midas * 100
    improvement_inv_rmse <- (best_individual_midas - rmse_combo_inv_rmse) / best_individual_midas * 100
    
    text(0.5, 0.18, sprintf("Best individual MIDAS: RMSE = %.3f", best_individual_midas), cex = 1.3)
    text(0.5, 0.10, sprintf("Improvement: Equal = %.1f%%, Inv-RMSE = %.1f%%", 
                            improvement_equal, improvement_inv_rmse), cex = 1.2, col = "darkblue")
    
    # Page: MIDAS Combination - Forecast vs Actual
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    plot(dates_combo[valid_combo_plot], act_combo[valid_combo_plot], 
         type = "l", lwd = 3, col = "black",
         xlab = "Time", ylab = "GDP Growth (%)",
         main = "MIDAS Combinations: Forecast vs Actual",
         ylim = range(c(act_combo[valid_combo_plot], 
                       fc_combo_equal[valid_combo_plot], 
                       fc_combo_inv_rmse[valid_combo_plot]), na.rm = TRUE),
         cex.main = 1.5, cex.lab = 1.3)
    lines(dates_combo[valid_combo_plot], fc_combo_equal[valid_combo_plot], 
          col = "purple", lwd = 2.5, lty = 1)
    lines(dates_combo[valid_combo_plot], fc_combo_inv_rmse[valid_combo_plot], 
          col = "darkorange", lwd = 2.5, lty = 2)
    lines(dates_combo[valid_combo_plot], fc_midas[valid_combo_plot], 
          col = adjustcolor("steelblue", alpha.f = 0.6), lwd = 1.5, lty = 3)
    legend("topright", 
           legend = c("Actual", 
                     sprintf("Equal (RMSE: %.2f)", rmse_combo_equal),
                     sprintf("Inv-RMSE (RMSE: %.2f)", rmse_combo_inv_rmse),
                     sprintf("Best Individual (RMSE: %.2f)", best_individual_midas)),
           col = c("black", "purple", "darkorange", "steelblue"), 
           lwd = c(3, 2.5, 2.5, 1.5), lty = c(1, 1, 2, 3), cex = 1.1)
    grid(col = "gray80")
    
    # Page: MIDAS Combination - Error Comparison
    errors_combo_equal <- act_combo[valid_combo_plot] - fc_combo_equal[valid_combo_plot]
    errors_combo_inv_rmse <- act_combo[valid_combo_plot] - fc_combo_inv_rmse[valid_combo_plot]
    
    par(mfrow = c(1, 1), mar = c(5, 5, 4, 2))
    plot(dates_combo[valid_combo_plot], errors_combo_equal, 
         type = "l", lwd = 2.5, col = "purple",
         xlab = "Time", ylab = "Forecast Error (%)",
         main = "MIDAS Combinations: Forecast Errors",
         ylim = range(c(errors_combo_equal, errors_combo_inv_rmse)),
         cex.main = 1.5, cex.lab = 1.3)
    lines(dates_combo[valid_combo_plot], errors_combo_inv_rmse, 
          col = "darkorange", lwd = 2.5, lty = 2)
    abline(h = 0, col = "black", lwd = 2)
    legend("topright", 
           legend = c("Equal Weights", "Inv-RMSE Weights"),
           col = c("purple", "darkorange"), lwd = 2.5, lty = c(1, 2), cex = 1.2)
    grid(col = "gray80")
    
    # Page: All Models Comparison (including combinations)
    par(mfrow = c(1, 1), mar = c(9, 5, 4, 2))
    combo_colors <- ifelse(grepl("^TPRF_", results_df$spec), "darkgreen",
                    ifelse(grepl("^MIDAS_COMBO_", results_df$spec), "purple", "steelblue"))
    barplot(results_df$rmse, names.arg = results_df$spec, 
            col = combo_colors,
            main = "RMSE Comparison: All Models + Combinations",
            ylab = "RMSE", las = 2, cex.names = 0.8,
            cex.main = 1.5, cex.lab = 1.3)
    legend("topright", 
           legend = c("MIDAS Individual", "MIDAS Combination", "TPRF"), 
           fill = c("steelblue", "purple", "darkgreen"), cex = 1.1)
    grid(col = "gray80")
  }
  
  dev.off()
  
  cat("✓ Plots saved to: rolling_evaluation_plots.pdf\n\n")
}

# Optionally save results
# Create a clean version without list columns for CSV
results_csv <- results_df[, c("spec", "n_forecasts", "rmse", "mae", "me")]
write.csv(results_csv, "rolling_evaluation_results.csv", row.names = FALSE)
cat("✓ Results saved to: rolling_evaluation_results.csv\n")
