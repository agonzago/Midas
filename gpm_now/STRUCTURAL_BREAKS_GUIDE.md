# Structural Break Handling in MIDAS Models

## Problem Identified

Looking at the rolling evaluation plots (especially post-2021), MIDAS models show systematic under-prediction of GDP growth. This is a classic **structural break** problem where:

1. Pre-2021: Lower/different GDP growth patterns
2. Post-2021: Higher growth rates (post-COVID recovery)
3. MIDAS models trained on pre-2021 data "remember" the old regime

## Solutions Implemented

### 1. **Intercept Adjustment (Mean Correction)**

**Method**: Estimate the mean forecast error over recent quarters and add this as an adjustment to the forecast.

**Variants**:
- `recent_errors`: Use mean of last N forecast errors
- `post_break_mean`: Detect break point, use mean error after break

**How it works**:
```
Adjusted Forecast = Base MIDAS Forecast + Mean(Recent Errors)
```

**New Model Specifications**:
- `MIDAS_AR2_lag4_m2_ADJ`: AR(2) model with intercept adjustment (4-quarter window)
- `MIDAS_AR1_lag3_m2_ADJ`: AR(1) model with intercept adjustment (4-quarter window)

### 2. **Rolling Windows** (Already Implemented)

The `MIDAS_AR2_lag4_m2_roll40` specification uses a 40-quarter rolling window, which naturally adapts to structural changes by "forgetting" old data.

## Implementation Details

### Files Modified
1. **`gpm_now/R/structural_breaks.R`** (NEW)
   - `detect_structural_break()` - Detects breaks using BIC or rolling means
   - `calculate_intercept_adjustment()` - Calculates mean adjustment
   - `estimate_rolling_adjustment()` - Estimates adjustment in rolling windows
   - `adaptive_intercept_correction()` - Exponentially weighted adjustments

2. **`gpm_now/run_rolling_evaluation.R`**
   - Added intercept_adjustment parameter to specs
   - Applies adjustment after generating base forecast
   - Two new model variants with _ADJ suffix

### Configuration Parameters

Each model spec can now have:
```r
list(
  type = "midas",
  y_lag = 2, 
  x_lag = 4, 
  month_of_quarter = 2,
  window_type = "expanding",
  intercept_adjustment = "recent_errors",  # "none", "recent_errors", "post_break_mean"
  adjustment_window = 4                     # Number of quarters for adjustment
)
```

## Usage

### Run Rolling Evaluation with Adjusted Models
```bash
cd gpm_now
Rscript run_rolling_evaluation.R
```

This will now include:
- Original MIDAS models (no adjustment)
- Adjusted MIDAS models (with _ADJ suffix)
- Performance comparison

### Expected Results

Models with intercept adjustment should show:
- **Better post-2021 performance**: Reduced systematic bias
- **Lower RMSE**: Especially in periods after structural breaks
- **Adaptive forecasts**: Automatically adjusts to new regime

### Interpretation

Look for in the output:
1. **RMSE comparison**: Adjusted models should beat non-adjusted
2. **Mean Error (ME)**: Should be closer to zero for adjusted models
3. **Post-2021 errors**: Visual inspection should show better tracking

## Alternative Approaches (Not Yet Implemented)

### 1. Shorter Rolling Windows
```r
"MIDAS_AR2_lag4_m2_roll20" = list(
  type = "midas",
  y_lag = 2, x_lag = 4, month_of_quarter = 2,
  window_type = "rolling", 
  window_length = 20  # 5 years instead of 10
)
```

### 2. Structural Break Detection with Regime Switching
- Automatically detect breaks using `strucchange` package
- Fit separate models before/after break
- Switch between models based on regime

### 3. Time-Varying Parameter Models
- Allow MIDAS coefficients to change over time
- Use Kalman filter or TVP-VAR approaches

### 4. Dummy Variables for Known Breaks
```r
# Add COVID dummy to MIDAS formula
y_q ~ mls(y_q, 1:2, 1) + mls(x_m, 2:6, 3) + covid_dummy
```

## Monitoring and Validation

### Check Adjustment Magnitudes
```r
# After running evaluation, check adjustments
adj_models <- grep("_ADJ$", names(results_all), value = TRUE)
for (model_name in adj_models) {
  # Adjustments are stored in the forecast generation loop
  # Could be extracted and plotted
}
```

### Visual Inspection
The plots will show:
- Adjusted models should track actuals better post-2021
- Reduced systematic deviation
- More stable forecast errors

## Best Practices

1. **Start Conservative**: Use 4-quarter adjustment window
2. **Compare Multiple Approaches**: Run both adjusted and non-adjusted
3. **Monitor Stability**: Check if adjustment magnitude is reasonable
4. **Document Breaks**: Note when major structural changes occur
5. **Regular Re-evaluation**: Structural break handling may need updates

## References

- Clements, M. P., & Hendry, D. F. (1998). *Forecasting Economic Time Series*. Cambridge University Press.
- Stock, J. H., & Watson, M. W. (1996). "Evidence on Structural Instability in Macroeconomic Time Series Relations." *Journal of Business & Economic Statistics*.
- Hansen, B. E. (2001). "The New Econometrics of Structural Change: Dating Breaks in U.S. Labor Productivity." *Journal of Economic Perspectives*.

## Expected Improvements

Based on your plots showing ~5-7% improvement from combination:
- **Intercept adjustment**: Could provide additional 10-20% RMSE reduction post-2021
- **Combined with model combination**: Best of both worlds
- **Total potential**: 15-25% improvement over baseline expanding window models

Run the evaluation to see actual performance!
