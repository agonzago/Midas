# MIDAS Model Combination - Implementation Summary

## What Was Implemented

The system now includes **model combination for MIDAS forecasts** integrated into both **weekly nowcasting** and **rolling evaluation** with the following capabilities:

### ✅ Core Features

1. **RMSE Calculation** - All MIDAS models now compute in-sample RMSE automatically
2. **Model Trimming** - Worst-performing models are removed before combination (configurable)
3. **Multiple Combination Schemes**:
   - Simple Average (equal weights)
   - BIC-weighted combination (inverse BIC)
   - RMSE-weighted combination (inverse RMSE)
4. **Enhanced Reporting** - All combinations included in output files

## Files Modified

### `gpm_now/R/midas_models.R`
- Added RMSE calculation in `fit_or_update_midas_set()`
- Store RMSE alongside BIC for each model
- Display RMSE in console logs

### `gpm_now/R/combine.R`
- Added `inv_rmse` weighting scheme to `calculate_weights()`
- Created `trim_midas_models()` function to remove worst performers
- Created `combine_midas_forecasts()` function for MIDAS-specific combination
- Updated function signatures to handle RMSE values

### `gpm_now/R/runner.R`
- Added MIDAS combination step after individual model fitting
- Pass MIDAS combinations to output reporting
- Include combinations in return object

### `gpm_now/R/io.R`
- Updated `write_weekly_summary()` to accept MIDAS combinations
- Add MIDAS combination columns to CSV output
- Include MIDAS combinations in JSON output with full metadata

### `gpm_now/config/options.yaml`
- Added `midas_combination_schemes` configuration
- Added `midas_trim_percentile` configuration (default: 0.25)

## New Configuration Options

```yaml
# Add to config/options.yaml
midas_combination_schemes: ["equal", "inv_bic", "inv_rmse"]
midas_trim_percentile: 0.25  # Remove worst 25% of models
```

## Usage Example

```r
# Run nowcast (MIDAS combination automatic)
result <- run_weekly_nowcast()

# Access combined MIDAS forecasts
result$midas_combinations$equal$point       # Simple average
result$midas_combinations$inv_bic$point     # BIC-weighted
result$midas_combinations$inv_rmse$point    # RMSE-weighted

# Check weights
result$midas_combinations$inv_bic$weights

# Check metadata
result$midas_combinations$metadata$n_models_original
result$midas_combinations$metadata$n_models_trimmed
```

## Output Example

### Console Output
```
=== MIDAS Model Combination ===
Total MIDAS models: 20
Trimmed 5 worst performing MIDAS models. Kept 15 models.

Combining with scheme: equal
  Combined forecast: 2.380
  95% interval: [ 1.952 , 2.808 ]
  Top 5 weights:
     IGAE : 0.067
     exports : 0.067
     ...

Combining with scheme: inv_bic
  Combined forecast: 2.420
  Top 5 weights:
     IGAE : 0.089
     exports : 0.078
     ...
```

### CSV Output
The summary CSV now includes additional columns:
- `midas_equal`, `midas_equal_lo`, `midas_equal_hi`
- `midas_inv_bic`, `midas_inv_bic_lo`, `midas_inv_bic_hi`
- `midas_inv_rmse`, `midas_inv_rmse_lo`, `midas_inv_rmse_hi`

### JSON Output
Full combination details with weights and metadata stored in the JSON file.

## Key Implementation Details

### Trimming Logic
- Trims based on **both** BIC and RMSE by default
- Takes intersection (model must pass both thresholds)
- Configurable percentile (default: 25%)
- Minimum 3 models always retained

### Weighting Schemes
- **Equal**: `w_i = 1/N`
- **Inverse BIC**: `w_i = (1/BIC_i) / Σ(1/BIC_j)`
- **Inverse RMSE**: `w_i = (1/RMSE_i) / Σ(1/RMSE_j)`

### Combined Intervals
Accounts for both within-model and between-model uncertainty:
```
Var(ŷ) = Σ(w_i² × SE_i²) + Σ(w_i × (ŷ_i - ŷ)²)
```

## TPRF Models

**Note**: This implementation is **MIDAS-specific only**. TPRF (Three-Pass Regression Filter) models are **not** included in these combinations. They continue to:
- Generate individual forecasts
- Be included in the overall model combination
- Appear in the individual forecasts section of reports

To combine TPRF models separately, you would need to create a similar `combine_tprf_forecasts()` function.

## Benefits

1. **Robustness**: Trimming removes poor models that could degrade performance
2. **Flexibility**: Multiple schemes allow comparison of different weighting approaches
3. **Transparency**: Full reporting shows which models contribute most
4. **Simplicity**: Automatic - no manual intervention needed
5. **Best Practice**: Follows forecast combination literature (Timmermann, 2006)

## Next Steps (Optional Enhancements)

1. **Out-of-Sample Validation**: Test combination schemes on historical data
2. **Dynamic Trimming**: Adjust trim percentile based on performance
3. **Historical Weighting**: Use past forecast errors instead of in-sample metrics
4. **TPRF Combination**: Extend to other model types if desired
5. **Adaptive Schemes**: Learn optimal weights over time

## Documentation

See `gpm_now/MIDAS_COMBINATION_GUIDE.md` for comprehensive documentation including:
- Detailed configuration options
- Usage examples
- Technical formulas
- Troubleshooting guide
- Best practices

## Testing

To test the implementation:

### 1. Weekly Nowcast
```r
# Update config
# Edit gpm_now/config/options.yaml to include:
#   midas_combination_schemes: ["equal", "inv_bic", "inv_rmse"]
#   midas_trim_percentile: 0.25

# Run nowcast
source("gpm_now/R/runner.R")
result <- run_weekly_nowcast(
  as_of_date = Sys.Date(),
  config_path = "gpm_now/config",
  data_path = "gpm_now/data",
  output_path = "gpm_now/output"
)

# Access combinations
result$midas_combinations$equal$point
result$midas_combinations$inv_bic$point
result$midas_combinations$inv_rmse$point
```

### 2. Rolling Evaluation (Out-of-Sample Testing)
```r
# Run from gpm_now directory
setwd("gpm_now")
Rscript run_rolling_evaluation.R

# This will:
# - Fit individual MIDAS models in rolling windows
# - Generate MIDAS combinations at each time point
# - Compare combination vs individual model performance
# - Create plots showing combination results
# - Save results to rolling_evaluation_results.csv

# Output includes:
# - MIDAS_COMBO_EQUAL row with RMSE/MAE
# - MIDAS_COMBO_INV_RMSE row with RMSE/MAE
# - Dedicated visualization pages in rolling_evaluation_plots.pdf
```

## Integration Status

✅ **Weekly Nowcast** (`run_weekly_nowcast()`)  
   - MIDAS combination runs automatically  
   - Results in JSON/CSV outputs  
   - Console reports weights and forecasts  

✅ **Rolling Evaluation** (`run_rolling_evaluation.R`)  
   - Out-of-sample combination testing  
   - Performance metrics vs individual models  
   - Visualization plots included  
   - Results saved to CSV
  config_path = "gpm_now/config",
  data_path = "gpm_now/data",
  output_path = "gpm_now/output"
)

# 3. Check results
print(result$midas_combinations)

# 4. Review outputs
# Check: gpm_now/output/weekly_reports/summary_YYYY-MM-DD.json
# Check: gpm_now/output/weekly_reports/summary_YYYY-MM-DD.csv
```

---

**Implementation completed successfully!** All MIDAS models now calculate RMSE, worst performers are trimmed, and three combination schemes (simple average, BIC weights, and inverse RMSE) are generated and reported.
