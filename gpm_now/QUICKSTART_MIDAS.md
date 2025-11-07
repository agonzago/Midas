# Quick Start: Using Refactored MIDAS in gpm_now

## Prerequisites

Ensure you have the required R packages installed:

```r
install.packages(c("midasr", "forecast", "yaml"))
```

## Step 1: Update Configuration

Add the following to your `config/options.yaml`:

```yaml
# MIDAS Model Selection Parameters
midas_max_y_lag: 4              # Test quarterly lags from 0-4
midas_max_x_lag: 6              # Test monthly lags from 0-6  
midas_month_of_quarter: 2       # For current indicators: 2=1st month, 1=2nd month, 0=3rd month

# Forecast Combination
midas_combination_scheme: "inv_bic"  # Options: "inv_bic", "bic_weights", "equal"

# Lagged Indicators (published 2-3 months after quarter end)
lagged_indicators:
  - "IMP"                 # Imports
  - "IP"                  # Industrial Production
  - "UNEMP"               # Unemployment
  - "PETRO_EXP"           # Petroleum Exports
  - "PETRO_PROD"          # Petroleum Production
  - "RETAIL_SALES"        # Retail Sales
  - "TRADE_BAL"           # Trade Balance
  - "AUTO_SALES_US"       # Auto Sales (US)
  - "CAR_IMP_US"          # Car Imports (US)
  - "TRUCK_IMP_US"        # Truck Imports (US)
  - "EXP"                 # Exports

# Current Indicators (available in first month of quarter)
current_indicators:
  - "CAP_UTILI_US"        # Capacity Utilization (US)
  - "BUS_CLIM_MFG"        # Business Climate Manufacturing
  - "BUS_CLIM_NONMFG"     # Business Climate Non-Manufacturing
  - "CONSUMER_CONF"       # Consumer Confidence
  - "PRODUCER_CONF"       # Producer Confidence
  - "AUTO_PROD"           # Auto Production
  - "AUTO_EXPORT"         # Auto Exports
  - "AUTO_SALES"          # Auto Sales
  - "TRUCK_SALES"         # Truck Sales
  - "PMI_MANU"            # PMI Manufacturing
  - "CONS_SENTI_US"       # Consumer Sentiment (US)
  - "CONS_CONF_US"        # Consumer Confidence (US)
  - "PMI_COMP_US"         # PMI Composite (US)
  - "RETAIL_SALES_US"     # Retail Sales (US)
  - "HOUSING_STARTS_US"   # Housing Starts (US)
  - "IP_US"               # Industrial Production (US)
```

**Note:** Adjust the indicator lists to match the variable names in your data.

## Step 2: Ensure Data Availability

The MIDAS code expects indicators to be available in the vintage snapshot. Make sure:

1. Your `data/monthly/` directory contains files with the indicators listed
2. The vintage builder includes these indicators
3. Variable names match between config and data

## Step 3: Run the Nowcast

### Option A: Use the Main Runner

```bash
cd /home/andres/work/Midas/gpm_now
Rscript main.R
```

The MIDAS models will be fitted automatically as part of the weekly nowcast workflow.

### Option B: Test with Examples First

```bash
# Run the example script to verify everything works
Rscript example_midas_usage.R
```

This will show you:
- How model selection works
- How forecasts are generated
- How BIC weights are calculated
- The expected output format

## Step 4: Interpret the Output

When you run the nowcast, you'll see output like:

```
Processing 11 lagged indicators...
  IMP : forecast = 2.34 , BIC = 45.2 , lags = Y: 2 X: 3 
  IP : forecast = 2.51 , BIC = 43.8 , lags = Y: 1 X: 4 
  ...

Processing 16 current indicators...
  BUS_CLIM_MFG : forecast = 2.42 , BIC = 41.5 , lags = Y: 1 X: 2 
  CONSUMER_CONF : forecast = 2.38 , BIC = 42.1 , lags = Y: 2 X: 3 
  ...

--- BIC-Based Weights (Top 10) ---
  BUS_CLIM_MFG             : weight = 0.085, forecast =   2.42
  IP_US                    : weight = 0.078, forecast =   2.39
  CONSUMER_CONF            : weight = 0.072, forecast =   2.38
  ...

Weighted MIDAS Nowcast: 2.41
```

This shows:
- **Individual forecasts** from each indicator
- **Selected lags** (Y = quarterly, X = monthly)
- **BIC values** (lower is better)
- **Weights** (higher = more influence)
- **Combined nowcast** (weighted average)

## Step 5: Combine with Other Methods

The MIDAS forecasts are automatically combined with other methods (TPRF, DFM) in the runner. To control the combination:

```yaml
# In config/options.yaml
combination_scheme: "inv_bic"  # Use BIC weights for final combination
```

Or to just use MIDAS:

```r
# In R
midas_nowcast <- midas_results  # From fit_or_update_midas_set()
combined <- combine_forecasts(midas_nowcast, scheme = "inv_bic")
print(combined$point)
```

## Troubleshooting

### Error: "Package 'midasr' required"
```r
install.packages("midasr")
```

### Error: "No quarterly target data in vintage"
Check that your vintage snapshot has a `y_q` component with GDP data.

### Error: "Insufficient data for indicator: XXX"
The indicator needs at least 12 observations. Check:
1. Is the indicator name correct in the config?
2. Does the data file contain this indicator?
3. Is the data properly loaded in the vintage?

### Warning: "No BIC values available"
If using `"inv_bic"` or `"bic_weights"` combination scheme, ensure models are fitted successfully. Check earlier warning messages for model fitting failures.

### No models fitted
Common causes:
1. Indicator names in config don't match data
2. Insufficient data for model estimation
3. midasr package not installed

Check the log file in `output/logs/` for detailed error messages.

## Advanced Usage

### Use Rolling Window

```yaml
window:
  type: "rolling"
  length_quarters: 40  # Use last 40 quarters for estimation
```

### Change Selection Criteria

```yaml
midas_max_y_lag: 2      # Test fewer lags (faster)
midas_max_x_lag: 9      # Test more lags (slower, potentially better fit)
```

### Compare Weighting Schemes

Run nowcasts with different schemes and compare:

```r
# Equal weights
result_equal <- combine_forecasts(midas_forecasts, scheme = "equal")

# Inverse BIC (simple)
result_inv_bic <- combine_forecasts(midas_forecasts, scheme = "inv_bic")

# Delta-BIC (sophisticated)
result_bic <- combine_forecasts(midas_forecasts, scheme = "bic_weights")

# Compare
cat("Equal:", result_equal$point, "\n")
cat("Inv BIC:", result_inv_bic$point, "\n")
cat("BIC weights:", result_bic$point, "\n")
```

## Key Differences from Old Mexico Code

| Feature | Old Code | New Code |
|---------|----------|----------|
| Model equations | `eval(parse())` | Direct midasr calls |
| Date handling | Hard-coded | From vintage/config |
| Indicator lists | In script | In config file |
| Error handling | Minimal | Comprehensive |
| Output | Print statements | Structured list + logging |

## Support

For questions or issues:
1. Check `MIDAS_REFACTORING.md` for detailed documentation
2. Review `example_midas_usage.R` for working examples
3. Look at `config/midas_config_example.yaml` for configuration options

## Next Steps After Setup

1. **Validate**: Compare nowcasts with previous system (if available)
2. **Backtest**: Run pseudo-real-time evaluation (see model selection code)
3. **Tune**: Adjust `max_y_lag`, `max_x_lag` based on performance
4. **Monitor**: Track which indicators get highest weights over time
5. **Document**: Record indicator publication schedules for proper categorization
