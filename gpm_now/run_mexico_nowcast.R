# Mexico MIDAS Nowcasting Script
# Uses the fixed MIDAS implementation to forecast GDP growth

library(midasr)
source("R/midas_models.R")

cat("=== Mexico MIDAS Nowcasting ===\n\n")

# Load data
mex_Q <- read.csv("../Data/mex_Q.csv")
mex_M <- read.csv("../Data/mex_M.csv")

# Extract GDP (quarterly target variable)
y_data <- mex_Q$DA_GDP
y_dates <- as.Date(mex_Q$X)

# Extract monthly indicator (EAI - Economic Activity Index)
x_data <- mex_M$DA_EAI
x_dates <- as.Date(mex_M$X)

# Remove NAs
y_data <- na.omit(y_data)
x_data <- na.omit(x_data)

# Align the data: ensure X covers at least the same period as Y
# Y starts at 1993-Q2 (April 1993), ends at 2023-Q4 (Dec 2023)
# X starts at 1993-02 (Feb 1993), ends at 2023-12 (Dec 2023)

# For quarterly data starting 1993-Q2: we need 123 quarters
# For monthly data: we need 123*3 = 369 months minimum
# But X only needs to start from Jan 1993 to cover Q2 onwards

# Find alignment point
y_start_date <- y_dates[!is.na(mex_Q$DA_GDP)][1]
y_start_year <- as.numeric(format(y_start_date, "%Y"))
y_start_month <- as.numeric(format(y_start_date, "%m"))
y_start_quarter <- ceiling(y_start_month / 3)

x_start_date <- x_dates[!is.na(mex_M$DA_EAI)][1]
x_start_year <- as.numeric(format(x_start_date, "%Y"))
x_start_month <- as.numeric(format(x_start_date, "%m"))

cat("Data alignment:\n")
cat("  Y (GDP) starts:", format(y_start_date, "%Y-%m"), "- Quarter", y_start_quarter, "\n")
cat("  X (EAI) starts:", format(x_start_date, "%Y-%m"), "\n")

# Calculate how many months of X we need
# If Y starts at Q2 (month 4-6), we need X from at least month 1
# Total months needed: align X to start of Y's first quarter, then add Y length * 3

# Find the start of the first quarter containing Y
q_start_month <- (y_start_quarter - 1) * 3 + 1

# We need X data from the start of Y's first quarter
months_before_y <- y_start_month - q_start_month
x_needed_start <- which(format(x_dates, "%Y-%m") == format(y_start_date, "%Y-%m"))[1] - months_before_y

# Take X data aligned with Y quarters
n_quarters <- length(y_data)
n_months_needed <- n_quarters * 3

# Adjust X to align properly
if (x_start_month <= q_start_month && x_start_year == y_start_year) {
  # X starts early enough
  x_offset <- (q_start_month - x_start_month)
  x_aligned <- x_data[(x_offset + 1):(x_offset + n_months_needed)]
} else {
  # X starts too late, take from beginning
  x_aligned <- head(x_data, n_months_needed)
}

# Ensure we have the right length
if (length(x_aligned) < n_months_needed) {
  cat("\nWarning: Not enough monthly data. Truncating quarterly data.\n")
  n_quarters_max <- floor(length(x_aligned) / 3)
  y_data <- head(y_data, n_quarters_max)
  x_aligned <- head(x_aligned, n_quarters_max * 3)
}

# Create time series objects
y_q <- ts(y_data, start = c(y_start_year, y_start_quarter), frequency = 4)
x_m <- ts(x_aligned, start = c(y_start_year, q_start_month), frequency = 12)

cat("\nTime series created:\n")
cat("  Y (GDP):", length(y_q), "quarters from", 
    paste(start(y_q), collapse="-"), "to", paste(end(y_q), collapse="-"), "\n")
cat("  X (EAI):", length(x_m), "months from",
    paste(start(x_m), collapse="-"), "to", paste(end(x_m), collapse="-"), "\n")
cat("  Last 4 Y values:", tail(y_q, 4), "\n")
cat("  Last 6 X values:", tail(x_m, 6), "\n\n")

# Fit MIDAS model
cat("Fitting MIDAS model...\n")
model <- fit_midas_unrestricted(
  y_q = y_q,
  x_m = x_m,
  y_lag = 2,
  x_lag = 4,
  month_of_quarter = 2  # Current quarter, 1st month available
)

if (!is.null(model)) {
  cat("✓ Model fitted successfully!\n\n")
  
  # Model statistics
  cat("Model Statistics:\n")
  cat("  Number of coefficients:", length(coef(model$fit)), "\n")
  cat("  Observations used:", model$n_obs, "\n")
  cat("  RMSE:", round(sqrt(mean(model$residuals^2, na.rm=TRUE)), 3), "\n")
  cat("  Y lag:", model$y_lag, "\n")
  cat("  X lag:", model$x_lag, "\n")
  cat("  Month of quarter:", model$month_of_quarter, "\n\n")
  
  # Show coefficients
  cat("Coefficients:\n")
  print(round(coef(model$fit), 4))
  cat("\n")
  
  # Make a forecast
  cat("Making nowcast...\n")
  y_new <- tail(y_q, 2)  # Last 2 quarters for AR terms
  x_new <- tail(x_m, 1)  # Only 1 month available (ragged edge)
  
  forecast <- predict_midas_unrestricted(model, y_new, x_new)
  
  if (!is.na(forecast$point)) {
    cat("\n=== NOWCAST RESULTS ===\n")
    cat("Point forecast:", round(forecast$point, 3), "%\n")
    cat("Standard error:", round(forecast$se, 3), "\n")
    cat("68% Confidence interval: [", 
        round(forecast$point - forecast$se, 3), ",", 
        round(forecast$point + forecast$se, 3), "]\n")
    cat("95% Confidence interval: [",
        round(forecast$point - 1.96*forecast$se, 3), ",",
        round(forecast$point + 1.96*forecast$se, 3), "]\n")
    
    cat("\nComparison:\n")
    cat("  Last observed GDP growth:", round(tail(y_q, 1), 3), "%\n")
    cat("  Nowcast for next quarter:", round(forecast$point, 3), "%\n")
    cat("  Change:", round(forecast$point - tail(y_q, 1), 3), "pp\n")
    
    cat("\n✓ Nowcast completed successfully!\n")
  } else {
    cat("✗ Forecast generation failed\n")
  }
  
} else {
  cat("✗ Model fitting failed\n")
  cat("\nTroubleshooting:\n")
  cat("  - Check that Y and X are properly aligned\n")
  cat("  - Ensure X has exactly 3*length(Y) observations\n")
  cat("  - Y length:", length(y_q), "quarters\n")
  cat("  - X length:", length(x_m), "months (need", 3*length(y_q), ")\n")
}
