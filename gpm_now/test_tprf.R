# Test Three-Pass Regression Filter (TPRF) with MIDAS
# Uses panel of monthly indicators to extract factors, then forecasts with MIDAS

library(midasr)
source("R/midas_models.R")
source("R/tprf_models.R")

cat("=== TPRF-MIDAS Test ===\n\n")

# Load data
mex_Q <- read.csv("../Data/mex_Q.csv")
mex_M <- read.csv("../Data/mex_M.csv")

# Extract GDP
y_data <- na.omit(mex_Q$DA_GDP)
y_dates <- as.Date(mex_Q$X)[!is.na(mex_Q$DA_GDP)]
y_start_year <- as.numeric(format(y_dates[1], "%Y"))
y_start_quarter <- ceiling(as.numeric(format(y_dates[1], "%m")) / 3)
y_q <- ts(y_data, start = c(y_start_year, y_start_quarter), frequency = 4)

# Build panel of monthly indicators
# Select multiple indicators for factor extraction
indicator_cols <- c("DA_EAI", "DA_GVFI", "DA_PMI_M", "DA_PMI_NM", 
                    "DA_RETSALES", "DA_RETGRO", "DA_RETSUP")

# Check which columns exist and have data
available_cols <- indicator_cols[indicator_cols %in% names(mex_M)]
cat("Available indicators:", length(available_cols), "\n")
cat(" ", paste(available_cols, collapse=", "), "\n\n")

if (length(available_cols) < 2) {
  cat("ERROR: Need at least 2 indicators for factor extraction\n")
  cat("Using DA_EAI only - falling back to standard MIDAS\n")
  quit(save = "no")
}

# Create panel matrix (time x variables)
n_quarters <- length(y_q)
n_months <- n_quarters * 3

X_panel <- matrix(NA, nrow = n_months, ncol = length(available_cols))
colnames(X_panel) <- available_cols

for (i in seq_along(available_cols)) {
  col_data <- mex_M[[available_cols[i]]]
  # Take first n_months observations (aligned with Y)
  if (length(col_data) >= n_months) {
    X_panel[, i] <- head(col_data, n_months)
  }
}

cat("Panel dimensions:", nrow(X_panel), "x", ncol(X_panel), "\n")
cat("Missing data:\n")
na_counts <- colSums(is.na(X_panel))
print(na_counts)
cat("\n")

# Extract factors using Three-Pass Regression Filter
cat("Extracting factors using TPRF...\n")
k_factors <- 2  # Extract 2 factors

tprf_result <- build_tprf_factors(
  X_m_panel = X_panel,
  k = k_factors,
  as_of_date = Sys.Date(),
  window_cfg = NULL  # Use all available data
)

if (!is.null(tprf_result) && !any(is.na(tprf_result$factors_m))) {
  cat("\n✓ Factor extraction successful\n")
  cat("  Number of factors:", tprf_result$k, "\n")
  cat("  R-squared:", round(tprf_result$r_squared, 3), "\n")
  cat("  Variance explained by each factor:\n")
  print(round(tprf_result$variance_explained, 3))
  cat("\n")
  
  # Convert factors to ts
  factors_m <- ts(tprf_result$factors_m, 
                  start = c(y_start_year, (y_start_quarter-1)*3 + 1),
                  frequency = 12)
  
  cat("Factors time series:\n")
  cat("  Length:", length(factors_m[,1]), "months\n")
  cat("  Start:", paste(start(factors_m), collapse="-"), "\n")
  cat("  End:", paste(end(factors_m), collapse="-"), "\n")
  cat("  Last 6 values of Factor 1:", tail(factors_m[,1], 6), "\n\n")
  
  # Fit TPRF-MIDAS model
  cat("Fitting TPRF-MIDAS model...\n")
  model <- fit_tprf_midas(
    y_q = y_q,
    factors_m = factors_m,
    y_lag = 2,
    x_lag = 4,
    month_of_quarter = 2,
    window_cfg = NULL
  )
  
  if (!is.null(model)) {
    cat("✓ Model fitted successfully!\n")
    cat("  Model type:", model$model_type, "\n")
    cat("  Coefficients:", length(coef(model$fit)), "\n")
    cat("  RMSE:", round(sqrt(mean(model$residuals^2, na.rm=TRUE)), 3), "\n")
    cat("  Using", model$n_factors, "factor(s)\n\n")
    
    # Make forecast
    cat("Generating nowcast...\n")
    y_new <- tail(y_q, 2)  # Last 2 quarters for AR
    factor_new <- tail(factors_m[,1], 1)  # Last month of factor
    
    forecast <- predict_tprf_midas(model, y_new, factor_new)
    
    if (!is.na(forecast$point)) {
      cat("\n=== TPRF-MIDAS NOWCAST ===\n")
      cat("Point forecast:", round(forecast$point, 3), "%\n")
      cat("Standard error:", round(forecast$se, 3), "\n")
      cat("95% CI: [", 
          round(forecast$point - 1.96*forecast$se, 3), ",",
          round(forecast$point + 1.96*forecast$se, 3), "]\n")
      
      cat("\nComparison:\n")
      cat("  Last observed GDP growth:", round(tail(y_q, 1), 3), "%\n")
      cat("  TPRF-MIDAS nowcast:", round(forecast$point, 3), "%\n")
      
      cat("\n✓ TPRF-MIDAS nowcasting completed successfully!\n")
      
      # Compare with standard MIDAS (using first indicator only)
      cat("\n--- Comparison: Standard MIDAS vs TPRF-MIDAS ---\n")
      x_m_single <- ts(X_panel[, 1], 
                       start = c(y_start_year, (y_start_quarter-1)*3 + 1),
                       frequency = 12)
      
      model_standard <- fit_midas_unrestricted(
        y_q = y_q,
        x_m = x_m_single,
        y_lag = 2,
        x_lag = 4,
        month_of_quarter = 2
      )
      
      if (!is.null(model_standard)) {
        x_new <- tail(x_m_single, 1)
        fc_standard <- predict_midas_unrestricted(model_standard, y_new, x_new)
        
        cat("Standard MIDAS (", available_cols[1], "):\n", sep="")
        cat("  Forecast:", round(fc_standard$point, 3), "%\n")
        cat("  RMSE:", round(sqrt(mean(model_standard$residuals^2, na.rm=TRUE)), 3), "\n")
        
        cat("\nTPRF-MIDAS (", k_factors, " factors from ", length(available_cols), " indicators):\n", sep="")
        cat("  Forecast:", round(forecast$point, 3), "%\n")
        cat("  RMSE:", round(sqrt(mean(model$residuals^2, na.rm=TRUE)), 3), "\n")
        
        improvement <- sqrt(mean(model_standard$residuals^2, na.rm=TRUE)) - 
                      sqrt(mean(model$residuals^2, na.rm=TRUE))
        cat("\nRMSE improvement:", round(improvement, 3), 
            "(", round(improvement/sqrt(mean(model_standard$residuals^2, na.rm=TRUE))*100, 1), "%)\n")
      }
      
    } else {
      cat("✗ Forecast generation failed\n")
    }
    
  } else {
    cat("✗ Model fitting failed\n")
  }
  
} else {
  cat("✗ Factor extraction failed\n")
}
