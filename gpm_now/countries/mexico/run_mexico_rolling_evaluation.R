# run_mexico_rolling_evaluation.R
# Rolling Out-of-Sample Evaluation for Mexico
#
# This script evaluates MIDAS and TPRF models using rolling windows
# with model combination and structural break adjustment

library(midasr)
library(zoo)
library(yaml)

# Set working directory to Mexico country folder
# Works from command line or RStudio
if (interactive() && requireNamespace("rstudioapi", quietly = TRUE) && rstudioapi::isAvailable()) {
  setwd(dirname(rstudioapi::getSourceEditorContext()$path))
} else {
  # Get script path when sourced
  script_path <- getSrcDirectory(function() {})
  if (script_path != "") {
    setwd(script_path)
  } else {
    # Fallback: assume we're already in the right directory
    cat("Note: Could not detect script location. Using current directory.\n")
    cat("Current directory:", getwd(), "\n")
  }
}

# Source all common core functions
common_path <- "../../common"
source(file.path(common_path, "utils.R"))
source(file.path(common_path, "transforms.R"))
source(file.path(common_path, "lagmap.R"))
source(file.path(common_path, "midas_models.R"))
source(file.path(common_path, "tprf_models.R"))
source(file.path(common_path, "dfm_models.R"))
source(file.path(common_path, "selection.R"))
source(file.path(common_path, "combine.R"))
source(file.path(common_path, "structural_breaks.R"))

cat("\n========================================\n")
cat("   Mexico Rolling Evaluation\n")
cat("========================================\n\n")

# Load Mexico quarterly and monthly data
# Note: Adjust paths based on your data location
mex_Q <- read.csv("../../../Data/mex_Q.csv", row.names = 1)
mex_M <- read.csv("../../../Data/mex_M.csv", row.names = 1)

# Convert to time series
y <- ts(mex_Q$DA_GDP, start = c(1993, 1), frequency = 4)
x <- ts(mex_M$DA_EAI, start = c(1993, 1), frequency = 12)

# Ensure alignment: 3 monthly obs per quarterly obs
n_q <- length(y)
n_m_expected <- n_q * 3
if (length(x) > n_m_expected) {
  x <- window(x, end = time(x)[n_m_expected])
}

cat(sprintf("Target variable (y): %d quarters\n", length(y)))
cat(sprintf("Main predictor (x): %d months\n", length(x)))
cat(sprintf("Sample: %s to %s\n\n", 
            format(as.Date(time(y)[1]), "%Y-Q%q"),
            format(as.Date(tail(time(y), 1)), "%Y-Q%q")))

# TPRF panel indicators (optional)
tprf_panel <- cbind(
  mex_M$DA_EAI,
  mex_M$DA_GVFI,
  mex_M$DA_PMI_M,
  mex_M$DA_PMI_NM,
  mex_M$DA_RETSALES,
  mex_M$DA_RETGRO,
  mex_M$DA_RETSUP
)
tprf_panel <- ts(tprf_panel, start = c(1993, 1), frequency = 12)
if (nrow(tprf_panel) > n_m_expected) {
  tprf_panel <- window(tprf_panel, end = time(tprf_panel)[n_m_expected])
}

# Rolling evaluation setup
initial_window <- 60  # 15 years
h <- 1  # 1-quarter ahead forecast

# Model specifications
model_specs <- list(
  # MIDAS models (various lag structures)
  list(name = "MIDAS_AR1_lag3_m2", type = "midas", ar_q = 1, lag_y = 3, lag_x = 2),
  list(name = "MIDAS_AR2_lag4_m2", type = "midas", ar_q = 2, lag_y = 4, lag_x = 2),
  list(name = "MIDAS_AR1_lag4_m3", type = "midas", ar_q = 1, lag_y = 4, lag_x = 3),
  
  # MIDAS models with structural break adjustment
  list(name = "MIDAS_AR2_lag4_m2_ADJ", type = "midas", ar_q = 2, lag_y = 4, lag_x = 2,
       intercept_adjustment = "recent_errors", adjustment_window = 4),
  list(name = "MIDAS_AR1_lag3_m2_ADJ", type = "midas", ar_q = 1, lag_y = 3, lag_x = 2,
       intercept_adjustment = "recent_errors", adjustment_window = 4),
  
  # TPRF models
  list(name = "TPRF_3F_AR1", type = "tprf", n_factors = 3, ar_q = 1),
  list(name = "TPRF_2F_AR2", type = "tprf", n_factors = 2, ar_q = 2)
)

# Storage for results
results <- data.frame(
  date = character(),
  actual = numeric(),
  stringsAsFactors = FALSE
)

# Add columns for each model
for (spec in model_specs) {
  results[[spec$name]] <- numeric(0)
}

# Add columns for MIDAS combinations
results$midas_equal <- numeric(0)
results$midas_inv_bic <- numeric(0)
results$midas_inv_rmse <- numeric(0)

# Rolling window loop
n_windows <- length(y) - initial_window
cat(sprintf("Running %d rolling windows...\n\n", n_windows))

for (i in 1:n_windows) {
  train_end <- initial_window + i - 1
  
  y_train <- window(y, end = time(y)[train_end])
  x_train <- window(x, end = time(x)[train_end * 3])
  
  # Reference date for this forecast
  ref_time <- time(y)[train_end]
  target_time <- time(y)[train_end + h]
  actual_value <- y[train_end + h]
  
  # Convert to year-quarter string
  ref_year <- floor(ref_time)
  ref_quarter <- round((ref_time - ref_year) * 4 + 1)
  target_year <- floor(target_time)
  target_quarter <- round((target_time - target_year) * 4 + 1)
  
  if (i %% 10 == 0 || i == 1) {
    cat(sprintf("[%d/%d] Training end: %d-Q%d, Target: %d-Q%d\n", 
                i, n_windows, ref_year, ref_quarter, target_year, target_quarter))
  }
  
  # Store actual value
  row_data <- list(
    date = sprintf("%d-Q%d", target_year, target_quarter),
    actual = actual_value
  )
  
  # Fit MIDAS models
  midas_forecasts <- list()
  midas_info <- list()
  
  for (spec in model_specs) {
    if (spec$type == "midas") {
      tryCatch({
        # Fit MIDAS model
        result <- fit_or_update_midas_set(
          y = y_train,
          x = x_train,
          ar_q = spec$ar_q,
          lag_y = spec$lag_y,
          lag_x = spec$lag_x,
          poly_degree = "beta",
          h = h
        )
        
        # Apply intercept adjustment if specified
        fc <- result$forecast
        if (!is.null(spec$intercept_adjustment)) {
          adj <- calculate_intercept_adjustment(
            y_train = y_train,
            y_fitted = result$fitted_values,
            method = spec$intercept_adjustment,
            window_size = spec$adjustment_window
          )
          fc <- fc + adj
        }
        
        row_data[[spec$name]] <- fc
        
        # Store for combination (only non-adjusted MIDAS)
        if (is.null(spec$intercept_adjustment)) {
          midas_forecasts[[spec$name]] <- fc
          midas_info[[spec$name]] <- list(
            bic = result$bic,
            rmse = result$rmse
          )
        }
        
      }, error = function(e) {
        row_data[[spec$name]] <<- NA
      })
      
    } else if (spec$type == "tprf") {
      # TPRF models
      tryCatch({
        tprf_train <- window(tprf_panel, end = time(tprf_panel)[train_end * 3, ])
        
        result <- fit_tprf_model(
          y = y_train,
          X_panel = tprf_train,
          n_factors = spec$n_factors,
          ar_q = spec$ar_q,
          h = h
        )
        
        row_data[[spec$name]] <- result$forecast
        
      }, error = function(e) {
        row_data[[spec$name]] <<- NA
      })
    }
  }
  
  # MIDAS model combination
  if (length(midas_forecasts) >= 2) {
    tryCatch({
      combo <- combine_midas_forecasts(
        forecasts = midas_forecasts,
        model_info = midas_info,
        schemes = c("equal", "inv_bic", "inv_rmse"),
        trim_percentile = 0.25
      )
      
      row_data$midas_equal <- combo$equal
      row_data$midas_inv_bic <- combo$inv_bic
      row_data$midas_inv_rmse <- combo$inv_rmse
      
    }, error = function(e) {
      row_data$midas_equal <- NA
      row_data$midas_inv_bic <- NA
      row_data$midas_inv_rmse <- NA
    })
  } else {
    row_data$midas_equal <- NA
    row_data$midas_inv_bic <- NA
    row_data$midas_inv_rmse <- NA
  }
  
  # Append to results
  results <- rbind(results, as.data.frame(row_data, stringsAsFactors = FALSE))
}

cat("\n========================================\n")
cat("   Evaluation Complete\n")
cat("========================================\n\n")

# Calculate RMSE for all models
cat("Root Mean Squared Error (RMSE):\n")
cat("--------------------------------\n")

for (model_name in names(results)[-c(1, 2)]) {  # Skip date and actual
  valid_idx <- !is.na(results[[model_name]])
  if (sum(valid_idx) > 0) {
    rmse <- sqrt(mean((results$actual[valid_idx] - results[[model_name]][valid_idx])^2))
    cat(sprintf("%-25s: %.4f\n", model_name, rmse))
  }
}

# Save results
output_file <- "output/rolling_evaluation_results.csv"
dir.create("output", showWarnings = FALSE, recursive = TRUE)
write.csv(results, output_file, row.names = FALSE)
cat(sprintf("\nResults saved to: %s\n", output_file))

# Generate comparison plots
if (require(ggplot2, quietly = TRUE) && require(reshape2, quietly = TRUE)) {
  cat("\nGenerating plots...\n")
  
  # Create plots directory
  dir.create("plots", showWarnings = FALSE, recursive = TRUE)
  
  tryCatch({
    # Plot 1: All MIDAS models vs actual
    # Extract year and quarter from date strings like "2020-Q1"
    results$year <- as.numeric(sub("-Q.*", "", results$date))
    results$quarter <- as.numeric(sub(".*-Q", "", results$date))
    results$date_numeric <- results$year + (results$quarter - 1) / 4
    
    results_long <- reshape2::melt(results[, c("date_numeric", "actual", grep("MIDAS", names(results), value = TRUE))],
                                   id.vars = "date_numeric", variable.name = "model", value.name = "forecast")
    
    p <- ggplot(results_long, aes(x = date_numeric, y = forecast, color = model)) +
      geom_line(aes(linetype = ifelse(model == "actual", "solid", "dashed"))) +
      theme_minimal() +
      labs(title = "Mexico GDP Growth: MIDAS Models vs Actual",
           x = "Year", y = "GDP Growth (%)", color = "Model", linetype = "") +
      theme(legend.position = "bottom")
    
    ggsave("plots/midas_comparison.png", p, width = 12, height = 6)
    
    cat("Plots saved to plots/ directory\n")
  }, error = function(e) {
    cat(sprintf("Plot generation failed: %s\n", e$message))
    cat("Continuing without plots...\n")
  })
} else {
  cat("\nSkipping plots (ggplot2 or reshape2 not available)\n")
}

cat("\n========================================\n\n")
