# Common Functions - GPM Now Core Library

This folder contains the **country-agnostic** core functions used by all country implementations in the GPM Now nowcasting framework.

## 📁 Files Overview

### Model Implementations

#### `midas_models.R`
MIDAS (Mixed Data Sampling) model estimation and forecasting.

**Key Functions:**
- `fit_or_update_midas_set()` - Fit MIDAS model with specified lag structure
- `forecast_midas()` - Generate out-of-sample forecast
- `calculate_midas_metrics()` - Compute BIC, AIC, RMSE

**Example:**
```r
result <- fit_or_update_midas_set(
  y = quarterly_gdp,
  x = monthly_indicator,
  ar_q = 2,           # AR(2) for quarterly variable
  lag_y = 4,          # 4 quarterly lags
  lag_x = 2,          # 2 lag periods for monthly (6 months)
  poly_degree = "beta", # Beta polynomial for monthly lags
  h = 1               # 1-quarter ahead forecast
)
```

#### `tprf_models.R`
Three-Pass Regression Filter for factor-based nowcasting.

**Key Functions:**
- `fit_tprf_model()` - Estimate TPRF with panel of monthly indicators
- `extract_factors()` - Extract common factors from panel
- `forecast_tprf()` - Generate factor-based forecast

**Example:**
```r
result <- fit_tprf_model(
  y = quarterly_gdp,
  X_panel = monthly_panel,  # Matrix of monthly indicators
  n_factors = 3,            # Extract 3 factors
  ar_q = 1,                 # AR(1) specification
  h = 1                     # 1-quarter ahead
)
```

#### `dfm_models.R`
Dynamic Factor Models using state-space framework.

**Key Functions:**
- `fit_dfm()` - Estimate DFM via EM algorithm
- `forecast_dfm()` - Factor-based forecast
- `smooth_factors()` - Kalman smoothing for factors

### Model Combination

#### `combine.R`
Model combination and trimming for improved forecasts.

**Key Functions:**
- `combine_midas_forecasts()` - Combine multiple MIDAS forecasts
- `trim_midas_models()` - Remove worst performing models
- `calculate_weights()` - Compute combination weights

**Weighting Schemes:**
- `"equal"` - Equal weights (simple average)
- `"inv_bic"` - Inverse BIC weights (better fit gets higher weight)
- `"inv_rmse"` - Inverse RMSE weights (more accurate gets higher weight)

**Example:**
```r
combined <- combine_midas_forecasts(
  forecasts = list(
    model1 = 2.5,
    model2 = 2.3,
    model3 = 2.8
  ),
  model_info = list(
    model1 = list(bic = 150, rmse = 1.2),
    model2 = list(bic = 145, rmse = 1.1),
    model3 = list(bic = 155, rmse = 1.3)
  ),
  schemes = c("equal", "inv_bic", "inv_rmse"),
  trim_percentile = 0.25  # Remove worst 25%
)
# Returns: list(equal = 2.53, inv_bic = 2.48, inv_rmse = 2.45)
```

### Structural Break Handling

#### `structural_breaks.R`
Detection and adjustment for structural breaks in time series.

**Key Functions:**
- `detect_structural_break()` - Identify break points
- `calculate_intercept_adjustment()` - Compute level adjustment
- `estimate_rolling_adjustment()` - Rolling window adjustment

**Adjustment Methods:**
- `"recent_errors"` - Use mean of recent forecast errors
- `"rolling_mean"` - Rolling mean of actual vs predicted
- `"structural_test"` - Based on statistical break tests

**Example:**
```r
# Calculate adjustment based on recent 4-quarter forecast errors
adjustment <- calculate_intercept_adjustment(
  y_train = actual_gdp,
  y_fitted = fitted_values,
  method = "recent_errors",
  window_size = 4
)

# Apply to new forecast
adjusted_forecast <- forecast + adjustment
```

### Data Transformations

#### `transforms.R`
Time series transformations and data preparation.

**Key Functions:**
- `apply_transformation()` - Apply specified transformation
- `difference_series()` - First or seasonal differencing
- `growth_rate()` - Calculate growth rates (MoM, YoY)

**Available Transformations:**
- `"level"` - No transformation
- `"log"` - Natural logarithm
- `"diff"` - First difference
- `"log_diff"` - Log difference (approx growth rate)
- `"pct_mom"` - Month-over-month percent change
- `"pct_yoy"` - Year-over-year percent change
- `"pct_qoq"` - Quarter-over-quarter percent change

**Example:**
```r
# Convert level to YoY growth
gdp_growth <- apply_transformation(
  x = gdp_level,
  transform = "pct_yoy",
  freq = "quarterly"
)
```

### Utilities

#### `utils.R`
General utility functions for logging, validation, and data handling.

**Key Functions:**
- `log_message()` - Write to log file
- `validate_time_series()` - Check TS properties
- `align_frequencies()` - Align quarterly/monthly data
- `create_lag_matrix()` - Build lag structure

#### `lagmap.R`
Lag structure mapping for MIDAS models.

**Key Functions:**
- `create_midas_lagmap()` - Generate MIDAS lag structure
- `align_midas_data()` - Align quarterly/monthly for MIDAS

#### `selection.R`
Model selection and information criteria.

**Key Functions:**
- `calculate_bic()` - Bayesian Information Criterion
- `calculate_aic()` - Akaike Information Criterion
- `cross_validation()` - Time series CV

#### `news.R`
Nowcast news decomposition (data vs model news).

**Key Functions:**
- `decompose_news()` - Decompose forecast revision
- `calculate_news_impacts()` - Impact of new data releases

## 🔧 Usage Principles

### 1. Source All Functions Before Use

Country-specific scripts should source all common functions at startup:

```r
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
source(file.path(common_path, "news.R"))
```

### 2. Functions Are Country-Agnostic

All functions in `common/` should work for any country:
- No hard-coded country names
- No specific data paths
- No country-specific assumptions

### 3. Pass Configuration as Parameters

Don't rely on global configuration inside common functions:

```r
# Good: Configuration passed as parameters
result <- fit_midas_model(y, x, ar_q = 2, lag_y = 4)

# Bad: Reading config inside function
# fit_midas_model <- function(y, x) {
#   cfg <- read_yaml("config/options.yaml")  # Don't do this!
# }
```

### 4. Return Structured Results

Functions should return consistent list structures:

```r
result <- fit_or_update_midas_set(...)
# Returns:
# list(
#   forecast = numeric,
#   fitted_values = numeric vector,
#   residuals = numeric vector,
#   bic = numeric,
#   aic = numeric,
#   rmse = numeric,
#   model = midas_r object
# )
```

## 🛠️ Development Guidelines

### Adding New Functions

1. **Keep it general**: Function should work for any country
2. **Document thoroughly**: Use roxygen2-style comments
3. **Test extensively**: Test with multiple countries' data
4. **Handle errors gracefully**: Use `tryCatch()` for robustness

### Example Function Template

```r
#' Fit MIDAS Model
#'
#' @param y Quarterly target variable (ts object)
#' @param x Monthly predictor variable (ts object)
#' @param ar_q Number of AR lags for quarterly variable
#' @param lag_y Number of quarterly lags to include
#' @param lag_x Number of monthly lag periods (each = 3 months)
#' @param poly_degree Polynomial type ("beta", "almon", "none")
#' @param h Forecast horizon (default: 1)
#' @return List with forecast, fitted values, metrics, model object
#' @export
fit_or_update_midas_set <- function(y, x, ar_q, lag_y, lag_x, 
                                    poly_degree = "beta", h = 1) {
  # Validation
  if (!is.ts(y) || !is.ts(x)) {
    stop("Both y and x must be ts objects")
  }
  
  # Implementation
  tryCatch({
    # ... model fitting code ...
    
    return(list(
      forecast = fc,
      fitted_values = fitted,
      residuals = resid,
      bic = bic_value,
      model = model_obj
    ))
  }, error = function(e) {
    stop(sprintf("MIDAS fitting failed: %s", e$message))
  })
}
```

### Modifying Existing Functions

1. **Maintain backward compatibility**: Don't break existing country implementations
2. **Add optional parameters**: Use defaults for new features
3. **Update documentation**: Explain new functionality
4. **Test all countries**: Verify Mexico, Brazil, etc. still work

## 📊 Function Dependencies

```
utils.R
  └── All other files depend on utils.R for logging, validation

transforms.R
  └── Used by data preparation in all models

lagmap.R
  └── Required by midas_models.R

midas_models.R
  ├── Depends on: utils.R, lagmap.R, transforms.R
  └── Used by: combine.R, structural_breaks.R

tprf_models.R
  ├── Depends on: utils.R, transforms.R
  └── Used by: Country-specific runners

combine.R
  ├── Depends on: utils.R
  └── Uses: Output from midas_models.R

structural_breaks.R
  ├── Depends on: utils.R
  └── Modifies: Output from midas_models.R

selection.R
  ├── Depends on: utils.R
  └── Used by: Model selection routines

news.R
  ├── Depends on: utils.R
  └── Used by: Nowcast news analysis
```

## 🔗 Integration with Countries

### Mexico
See `countries/mexico/README.md` for Mexico-specific implementation details.

### Brazil
See `countries/brazil/README.md` for Brazil-specific implementation details.

### Adding New Country
See main `gpm_now/README.md` for step-by-step guide to add new countries.

## 📝 Testing Common Functions

Test functions with synthetic data:

```r
# Generate test data
y <- ts(rnorm(100, mean = 2, sd = 1), start = c(2000, 1), frequency = 4)
x <- ts(rnorm(300, mean = 2, sd = 1), start = c(2000, 1), frequency = 12)

# Test MIDAS
result <- fit_or_update_midas_set(y, x, ar_q = 1, lag_y = 3, lag_x = 2)
print(result$forecast)

# Test combination
forecasts <- list(m1 = 2.5, m2 = 2.3, m3 = 2.8)
model_info <- list(
  m1 = list(bic = 150, rmse = 1.2),
  m2 = list(bic = 145, rmse = 1.1),
  m3 = list(bic = 155, rmse = 1.3)
)
combined <- combine_midas_forecasts(forecasts, model_info, c("equal", "inv_rmse"))
print(combined)
```

---

**Last Updated**: November 2025  
**Purpose**: Shared core library for multi-country nowcasting  
**Maintainer**: GPM Now Development Team
