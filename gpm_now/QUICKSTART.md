# Quick Start Guide - GPM Now

## Prerequisites

1. **R installation** (version 4.0 or higher)
2. **Required R packages**:
   ```r
   install.packages(c(
     "midasr", "dfms", "data.table", "dplyr", "tidyr",
     "lubridate", "zoo", "yaml", "jsonlite", "digest"
   ))
   ```

3. **Optional packages** (for advanced features):
   ```r
   install.packages(c("KFAS", "MARSS"))
   ```

## Installation

No installation needed - this is a self-contained R package/toolbox.

## First Run

### Option 1: Interactive R Session

```r
# Set working directory
setwd("path/to/gpm_now")

# Load and run
source("R/runner.R")
result <- run_weekly_nowcast()

# View results
print(result$combined_forecast)
```

### Option 2: Command Line

```bash
cd gpm_now
Rscript main.R
```

### Option 3: Specific Date

```bash
cd gpm_now
Rscript main.R 2024-01-15
```

## Configuration

### 1. Set up your data

Place your data files in:
- `data/quarterly/quarterly_data.csv` - Quarterly GDP data
- `data/monthly/monthly_data.csv` - Monthly indicators panel
- `data/monthly/ibc_br_m.csv` - Monthly GDP proxy (optional)

**Quarterly data format:**
```csv
date,quarter,value
2023-03-31,2023Q1,1.4
2023-06-30,2023Q2,0.9
```

**Monthly data format (wide):**
```csv
date,ipi_mfg,retail_real,credit_total
2023-10-31,0.1,0.2,0.2
2023-11-30,0.2,0.3,0.3
```

### 2. Configure indicators

Edit `config/variables.yaml`:

```yaml
target:
  id_q: "gdp_q_qoq_sa"
  id_m_proxy: null  # or "ibc_br_m" for Brazil

indicators:
  - id: "ipi_mfg"
    freq: "monthly"
    transform: "pct_mom_sa"
    lag_max_months: 12
    midas: "unrestricted"
    in_tprf: true
    in_dfm: true
```

### 3. Set release calendar

Edit `config/calendar.csv`:

```csv
release_date,series_id,ref_period,source_url,note
2024-02-15,ipi_mfg,2024-01,https://source.com,Monthly IPI
```

### 4. Configure models

Edit `config/options.yaml`:

```yaml
window:
  type: "rolling"
  length_quarters: 60

combination:
  scheme: "inv_mse_shrink"  # or "equal" or "bic_weights"

dfm:
  factors_k_candidates: [2, 3, 4]
```

## Understanding Output

### Weekly Summary Files

Location: `output/weekly_reports/`

**CSV format:** `summary_YYYY-MM-DD.csv`
```csv
date,combined_point,combined_lo,combined_hi
2024-01-15,2.35,1.80,2.90
```

**JSON format:** `summary_YYYY-MM-DD.json`
```json
{
  "as_of_date": "2024-01-15",
  "combined_nowcast": 2.35,
  "combined_interval": [1.80, 2.90],
  "weights": {
    "ipi_mfg": 0.25,
    "tprf": 0.30,
    "dfm_midas": 0.45
  }
}
```

### News Decomposition

Location: `output/weekly_reports/news_YYYY-MM-DD.csv`

Shows changes vs. previous week:
```csv
as_of_date,series_id,delta_nowcast_pp,prev_value,new_value
2024-01-15,COMBINED,0.15,2.20,2.35
```

### Logs

Location: `output/logs/nowcast_YYYY-MM-DD.log`

Detailed execution log for debugging and auditing.

### Vintages

Location: `data/vintages/YYYY-MM-DD.rds`

Immutable snapshots of data as it was known on each date.

## Common Tasks

### Weekly Update Workflow

```r
# 1. Update data files with latest releases
# 2. Update calendar.csv with new release dates
# 3. Run nowcast
source("R/runner.R")
result <- run_weekly_nowcast()

# 4. Review results
print(result$combined_forecast)
print(result$news)

# 5. Check logs for any issues
# See: output/logs/
```

### Add a New Indicator

1. Add data column to `data/monthly/monthly_data.csv`
2. Add indicator specification to `config/variables.yaml`:
   ```yaml
   - id: "new_indicator"
     freq: "monthly"
     transform: "pct_mom_sa"
     lag_max_months: 12
     midas: "unrestricted"
     in_tprf: true
     in_dfm: true
   ```
3. Add release dates to `config/calendar.csv`
4. Rerun nowcast

### Change Combination Scheme

Edit `config/options.yaml`:
```yaml
combination:
  scheme: "equal"  # Simple average
  # or
  scheme: "inv_mse_shrink"  # Performance-weighted
  # or
  scheme: "bic_weights"  # BIC-based
```

### Adjust Rolling Window

Edit `config/options.yaml`:
```yaml
window:
  type: "rolling"
  length_quarters: 40  # Shorter window for more recent patterns
```

## Troubleshooting

### Missing Packages Error

```r
# Install missing package
install.packages("package_name")
```

### No Data Available

- Check data files exist in `data/` directories
- Verify CSV format matches examples
- Check date formats (YYYY-MM-DD for monthly, YYYY-MM-DD for quarterly)

### Empty Nowcast

- Ensure indicators are marked with `in_tprf: true` or `in_dfm: true`
- Check calendar.csv has release dates before current date
- Verify data availability in vintage snapshots

### Model Fitting Errors

- Check for sufficient data (minimum ~40 quarters recommended)
- Ensure no constant series (zero variance)
- Verify transformations are appropriate

## Advanced Usage

### Accessing Individual Models

```r
result <- run_weekly_nowcast()

# U-MIDAS forecasts
result$individual_forecasts$ipi_mfg

# TPRF forecast
result$individual_forecasts$tprf

# DFM forecasts
result$individual_forecasts$dfm_midas
result$individual_forecasts$dfm_ss  # State-space (if enabled)
```

### Manual Model Selection

```r
source("R/selection.R")

# Load model registry
registry <- load_model_registry()

# Freeze a model
registry <- freeze_model(registry, "midas_ipi_mfg")

# Unfreeze to trigger reselection
registry <- unfreeze_model(registry, "midas_ipi_mfg")

# Save registry
save_model_registry(registry)
```

### Custom Weighting

```r
source("R/combine.R")

# Load historical performance
# (implement extract_historical_performance for your use case)

# Combine with custom scheme
combo <- combine_forecasts(
  all_forecasts,
  scheme = "inv_mse_shrink",
  history = historical_perf
)
```

## Next Steps

1. **Implement Production Methods**:
   - Replace PCA with actual Three-Pass Filter
   - Use `midasr` package for proper MIDAS estimation
   - Implement DFM with `dfms` or `nowcastDFM`
   - Add KFAS/MARSS for state-space models

2. **Add Seasonal Adjustment**:
   - Integrate X-13ARIMA-SEATS
   - Pre-process data before loading

3. **Extend Model Selection**:
   - Implement rolling window evaluation
   - Add cross-validation
   - Track out-of-sample performance

4. **Enhance News Decomposition**:
   - Decompose by data release
   - Calculate marginal contributions
   - Track forecast revisions

## Support

For issues or questions:
1. Check logs in `output/logs/`
2. Review configuration files
3. Consult README.md for detailed methodology
4. Check example_run.R for usage examples

## References

See README.md for academic references and methodology details.
