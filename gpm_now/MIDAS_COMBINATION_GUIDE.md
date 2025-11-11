# MIDAS Model Combination Guide

## Overview

The GPM-Now system now includes advanced model combination capabilities specifically designed for MIDAS (Mixed Data Sampling) forecasts. This feature allows you to combine multiple MIDAS model forecasts using different weighting schemes after trimming the worst-performing models.

## Key Features

### 1. **Automatic RMSE Calculation**
- Each MIDAS model now automatically calculates in-sample RMSE during fitting
- RMSE is stored alongside BIC for use in model trimming and weighting
- Both metrics are reported in logs and output files

### 2. **Model Trimming**
- Removes worst-performing MIDAS models before combination
- Configurable trim percentile (default: 0.25 = remove worst 25%)
- Can trim based on BIC, RMSE, or both metrics
- Prevents poor models from degrading combined forecasts

### 3. **Multiple Combination Schemes**
Three combination schemes are implemented for MIDAS forecasts:

#### **Equal Weighting (Simple Average)**
- Each model receives equal weight: w_i = 1/N
- Robust baseline approach
- No assumptions about model quality

#### **Inverse BIC Weights**
- Models with lower BIC receive higher weights: w_i ∝ 1/BIC_i
- BIC penalizes complexity and rewards fit
- Favors parsimonious models

#### **Inverse RMSE Weights**
- Models with lower in-sample RMSE receive higher weights: w_i ∝ 1/RMSE_i
- Based on historical prediction accuracy
- Rewards models with better historical fit

### 4. **Comprehensive Reporting**
- All three combination schemes are computed and reported
- Individual model weights are displayed
- Results included in both JSON and CSV outputs
- Combination metadata tracked (trimmed models, percentiles, etc.)

## Configuration

Add the following to your `config/options.yaml`:

```yaml
# MIDAS-specific combination settings
midas_combination_schemes: ["equal", "inv_bic", "inv_rmse"]
midas_trim_percentile: 0.25  # Remove worst 25% of models
```

### Configuration Options

- **`midas_combination_schemes`**: Vector of combination schemes to apply
  - Options: `"equal"`, `"inv_bic"`, `"inv_rmse"`
  - Default: `["equal", "inv_bic", "inv_rmse"]`
  
- **`midas_trim_percentile`**: Fraction of worst models to remove
  - Range: 0.0 to 0.5 (0 = no trimming, 0.5 = remove worst 50%)
  - Default: 0.25
  - Example: 0.25 means if you have 20 MIDAS models, the 5 worst will be trimmed

## Usage

The MIDAS combination runs automatically as part of the weekly nowcast:

```r
# Source the runner
source("gpm_now/R/runner.R")

# Run nowcast (MIDAS combination happens automatically)
result <- run_weekly_nowcast(
  as_of_date = Sys.Date(),
  config_path = "gpm_now/config",
  data_path = "gpm_now/data",
  output_path = "gpm_now/output"
)

# Access MIDAS combinations
midas_combos <- result$midas_combinations

# View equal-weighted combination
midas_combos$equal$point
midas_combos$equal$weights

# View BIC-weighted combination
midas_combos$inv_bic$point
midas_combos$inv_bic$weights

# View RMSE-weighted combination
midas_combos$inv_rmse$point
midas_combos$inv_rmse$weights

# Check metadata
midas_combos$metadata$n_models_original
midas_combos$metadata$n_models_trimmed
midas_combos$metadata$trimmed_models
```

## Output Files

### JSON Output (`summary_YYYY-MM-DD.json`)

```json
{
  "as_of_date": "2025-01-15",
  "combined_nowcast": 2.45,
  "midas_combinations": {
    "equal": {
      "point": 2.38,
      "lo": 1.95,
      "hi": 2.81,
      "weights": {
        "indicator1": 0.067,
        "indicator2": 0.067,
        ...
      }
    },
    "inv_bic": {
      "point": 2.42,
      "lo": 2.01,
      "hi": 2.83,
      "weights": {
        "indicator1": 0.089,
        "indicator2": 0.053,
        ...
      }
    },
    "inv_rmse": {
      "point": 2.40,
      "lo": 1.98,
      "hi": 2.82,
      "weights": {
        "indicator1": 0.085,
        "indicator2": 0.062,
        ...
      }
    },
    "metadata": {
      "n_models_original": 20,
      "n_models_trimmed": 15,
      "trim_percentile": 0.25
    }
  },
  "individual_forecasts": [...]
}
```

### CSV Output (`summary_YYYY-MM-DD.csv`)

| date | combined_point | combined_lo | combined_hi | midas_equal | midas_equal_lo | midas_equal_hi | midas_inv_bic | midas_inv_bic_lo | midas_inv_bic_hi | midas_inv_rmse | midas_inv_rmse_lo | midas_inv_rmse_hi |
|------|----------------|-------------|-------------|-------------|----------------|----------------|---------------|------------------|------------------|----------------|-------------------|-------------------|
| 2025-01-15 | 2.45 | 2.05 | 2.85 | 2.38 | 1.95 | 2.81 | 2.42 | 2.01 | 2.83 | 2.40 | 1.98 | 2.82 |

## Console Output Example

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
     industrial_prod : 0.067
     retail_sales : 0.067
     employment : 0.067

Combining with scheme: inv_bic
  Combined forecast: 2.420
  95% interval: [ 2.013 , 2.827 ]
  Top 5 weights:
     IGAE : 0.089
     exports : 0.078
     retail_sales : 0.071
     employment : 0.065
     industrial_prod : 0.062

Combining with scheme: inv_rmse
  Combined forecast: 2.398
  95% interval: [ 1.982 , 2.814 ]
  Top 5 weights:
     exports : 0.085
     IGAE : 0.082
     retail_sales : 0.076
     employment : 0.068
     industrial_prod : 0.063
```

## Technical Details

### Trimming Algorithm

1. Extract BIC and RMSE for all MIDAS models
2. Calculate percentile thresholds for both metrics
3. Keep models that pass both thresholds (intersection)
4. Minimum of 3 models retained even if below threshold

### Weight Calculation

**Equal Weights:**
```
w_i = 1/N
```

**Inverse BIC:**
```
w_i = (1/BIC_i) / Σ(1/BIC_j)
```

**Inverse RMSE:**
```
w_i = (1/RMSE_i) / Σ(1/RMSE_j)
```

### Combined Forecast

```
ŷ_combined = Σ(w_i × ŷ_i)
```

### Prediction Intervals

The combined prediction interval accounts for:
- Within-model uncertainty (individual standard errors)
- Between-model uncertainty (forecast dispersion)

```
Var(ŷ_combined) = Σ(w_i² × SE_i²) + Σ(w_i × (ŷ_i - ŷ_combined)²)
```

## Best Practices

1. **Start with Default Settings**: Use trim_percentile = 0.25 initially
2. **Compare Schemes**: Review all three combination schemes in your reports
3. **Monitor Trimmed Models**: Check which models are being trimmed regularly
4. **Adjust Trim Percentile**: If too many/few models are trimmed, adjust the percentile
5. **Historical Validation**: Use out-of-sample testing to validate combination performance

## Troubleshooting

### Issue: All models are being trimmed
**Solution**: Reduce `midas_trim_percentile` or check model specifications

### Issue: RMSE/BIC not available
**Solution**: Ensure models are fitting properly and metrics are being calculated

### Issue: Weights are very unequal
**Solution**: This is expected - it means some models perform much better. Consider if you want more equal weighting.

### Issue: Combination fails with error
**Solution**: Check that at least 3 MIDAS models are available after trimming

## References

- Timmermann, A. (2006). "Forecast Combinations." *Handbook of Economic Forecasting*, 1, 135-196.
- Ghysels, E., Santa-Clara, P., & Valkanov, R. (2004). "The MIDAS Touch: Mixed Data Sampling Regression Models."
- Schwarz, G. (1978). "Estimating the Dimension of a Model." *The Annals of Statistics*, 6(2), 461-464.

## Related Files

- **Implementation**: `gpm_now/R/combine.R` (combination functions)
- **MIDAS Models**: `gpm_now/R/midas_models.R` (RMSE calculation)
- **Runner**: `gpm_now/R/runner.R` (integration)
- **Output**: `gpm_now/R/io.R` (reporting)
- **Configuration**: `gpm_now/config/options.yaml` (settings)
