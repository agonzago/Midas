# GPM Now: Weekly Nowcasting System

A comprehensive R-based weekly nowcasting system implementing U-MIDAS, 3PF (Three-Pass Regression Filter), and DFM (Dynamic Factor Models) for real-time GDP forecasting.

## Overview

GPM Now is designed for weekly GDP nowcasting with support for:
- **Multiple countries**: Brazil (with monthly GDP proxy IBC-Br) and countries with quarterly GDP only
- **Three parallel modeling tracks**:
  1. U-MIDAS (unrestricted MIDAS per indicator)
  2. 3PF/TPRF (Three-Pass Regression Filter with factors)
  3. DFM (Dynamic Factor Models with optional state-space mapping)
- **Direct forecasts**: No bridging or imputation of unreleased months
- **Calendar-aware ragged edge**: Uses only released data
- **Model selection**: RMSE/BIC-based with persistence
- **Forecast combination**: Multiple schemes with uncertainty intervals
- **Reproducible vintages**: Immutable weekly snapshots

## System Requirements

### Required R Packages
```r
install.packages(c(
  "midasr",      # MIDAS regression
  "dfms",        # Dynamic Factor Models (or nowcastDFM)
  "data.table",  # Data manipulation
  "dplyr",       # Data manipulation
  "tidyr",       # Data tidying
  "lubridate",   # Date handling
  "zoo",         # Time series
  "yaml",        # Config parsing
  "jsonlite",    # JSON I/O
  "digest"       # Hashing for model specs
))
```

### Optional Packages
```r
install.packages(c(
  "KFAS",        # State-space models
  "MARSS"        # Alternative state-space
))
```

## Folder Structure

```
gpm_now/
├── config/
│   ├── variables.yaml      # Target(s), indicators, transforms
│   ├── calendar.csv        # Release calendar
│   └── options.yaml        # Model options, selection, combination
├── data/
│   ├── monthly/            # Monthly indicators panel
│   ├── quarterly/          # Quarterly GDP
│   └── vintages/           # Immutable weekly snapshots
├── R/
│   ├── io.R                # Data I/O, vintage management
│   ├── utils.R             # Date utilities, logging
│   ├── transforms.R        # Transformations, seasonal adjustment
│   ├── lagmap.R            # Calendar-aware lag mapping
│   ├── midas_models.R      # U-MIDAS implementation
│   ├── tprf_models.R       # 3PF factor models
│   ├── dfm_models.R        # DFM with state-space
│   ├── selection.R         # Model selection logic
│   ├── combine.R           # Forecast combination
│   ├── news.R              # News decomposition
│   └── runner.R            # Weekly entry point
└── output/
    ├── weekly_reports/     # CSV/JSON nowcast summaries
    ├── logs/               # Execution logs
    └── models/             # Model registry

```

## Configuration

### 1. variables.yaml

Defines the target variable(s) and indicators:

```yaml
target:
  id_q: "gdp_q_qoq_sa"         # Quarterly GDP (primary target)
  id_m_proxy: "ibc_br_m"       # Monthly proxy (null if none)
  target_scale_q: "qoq"        # "qoq" or "yoy"
  transform_q: "pct_qoq"
  transform_m: "pct_mom_sa"
  seasonally_adjusted: true

indicators:
  - id: "ipi_mfg"
    freq: "monthly"
    transform: "pct_mom_sa"
    lag_max_months: 12
    midas: "unrestricted"
    in_tprf: true
    in_dfm: true
```

### 2. options.yaml

Controls model behavior:

```yaml
window:
  type: "rolling"
  length_quarters: 60

reestimate_on_new_data: true

combination:
  scheme: "inv_mse_shrink"     # "equal" | "inv_mse_shrink" | "bic_weights"
  shrinkage_lambda: 0.2

model_selection:
  primary: "rmse"
  secondary: "bic"

dfm:
  package: "dfms"
  factors_k_candidates: [2, 3, 4]
  refit_frequency: "monthly"
  handle_missing: "EM"

state_space:
  engine: "KFAS"
  use_quarterly_state: true

report:
  save_csv: true
  save_json: true
```

### 3. calendar.csv

Specifies release dates for data availability:

```csv
release_date,series_id,ref_period,source_url,note
2024-01-15,ipi_mfg,2023-12,https://example.com,Monthly release
2024-02-28,gdp_q_qoq_sa,2023Q4,https://example.com,Quarterly release
```

## Usage

### Basic Weekly Run

```r
# Set working directory to gpm_now
setwd("path/to/gpm_now")

# Source the runner
source("R/runner.R")

# Run weekly nowcast
result <- run_weekly_nowcast(as_of_date = Sys.Date())

# View results
print(result$combined_forecast)
print(result$news)
```

### Custom Date

```r
# Run for a specific date
result <- run_weekly_nowcast(as_of_date = as.Date("2024-01-15"))
```

### Access Individual Components

```r
# U-MIDAS forecasts by indicator
result$individual_forecasts$ipi_mfg

# TPRF forecast
result$individual_forecasts$tprf

# DFM forecasts
result$individual_forecasts$dfm_midas
result$individual_forecasts$dfm_ss

# News decomposition
result$news
```

## Methodology

### 1. U-MIDAS (Unrestricted MIDAS)

- One model per indicator
- Direct forecast of quarterly GDP growth
- Ragged edge: only released months included
- No imputation of missing data

**API:**
```r
model <- fit_midas_unrestricted(y_q, x_m, lag_map, spec_cfg, window_cfg)
forecast <- predict_midas_unrestricted(model, x_m_current, lag_map_current)
```

### 2. Three-Pass Regression Filter (3PF/TPRF)

- Extract common factors from monthly panel
- Forecast quarterly GDP using factors via U-MIDAS
- Handles mixed-frequency naturally

**API:**
```r
tprf <- build_tprf_factors(X_m_panel, k, as_of_date, window_cfg)
model <- fit_tprf_midas(y_q, tprf$factors_m, lag_map, window_cfg)
forecast <- predict_tprf_midas(model, factors_m_current, lag_map_current)
```

### 3. Dynamic Factor Models (DFM)

Two variants:

**A) DFM-MIDAS** (all countries):
- Extract monthly factors
- Use as MIDAS regressors for quarterly GDP

**B) DFM State-Space** (with monthly proxy):
- Quarterly state: GDP growth
- Monthly measurements: proxy + factors
- Kalman filtering for coherent nowcast

**API:**
```r
# DFM factor extraction
dfm_fit <- fit_dfm_monthly(X_m_panel, k_candidates, options)

# Option A: Factor-MIDAS
model <- fit_dfm_midas(y_q, dfm_fit$factors_m, lag_map, window_cfg)
forecast <- predict_dfm_midas(model, factors_m_current, lag_map_current)

# Option B: State-space (Brazil)
ss_model <- fit_dfm_state_space(y_q, y_m_proxy, factors_m, options)
forecast <- predict_dfm_state_space(ss_model, y_m_proxy_cur, factors_m_cur)
```

### Ragged Edge Handling

The system never imputes unreleased data. Instead:

1. **Lag map** built weekly based on release calendar
2. **Available lags** determined per indicator
3. **Design matrix** includes only released observations
4. **Weekly updates** incorporate new data as released

### Model Selection

- **Evaluation**: Rolling window RMSE (primary), BIC (secondary)
- **Persistence**: Specs frozen until triggered reselection
- **Registry**: Tracks spec hashes for auditability

```r
metrics_df <- rolling_evaluation(y_q, x_m, specs, window_length = 40)
best_spec <- select_model(metrics_df, primary = "rmse", secondary = "bic")
```

### Forecast Combination

Three schemes:
1. **Equal weights**: Simple average
2. **Inverse MSE with shrinkage**: Performance-based with robustness
3. **BIC weights**: Model complexity adjusted

Intervals account for:
- Within-model uncertainty (SEs)
- Between-model dispersion

```r
combo <- combine_forecasts(all_fcsts, scheme = "inv_mse_shrink", history = NULL)
```

### News Decomposition

Track changes vs. previous week:
- Overall nowcast revision
- Model-level contributions
- New data impact

```r
news_tbl <- compute_news(as_of_date, fcsts_now, fcsts_prev, combo_now)
```

## Output Files

### Weekly Summary (CSV)
```
date,combined_point,combined_lo,combined_hi
2024-01-15,2.35,1.80,2.90
```

### Weekly Summary (JSON)
```json
{
  "as_of_date": "2024-01-15",
  "combined_nowcast": 2.35,
  "combined_interval": [1.80, 2.90],
  "weights": {
    "ipi_mfg": 0.25,
    "tprf": 0.30,
    "dfm_midas": 0.45
  },
  "models_updated": ["midas_ipi_mfg", "tprf", "dfm_midas"],
  "individual_forecasts": [...]
}
```

### News Table (CSV)
```
as_of_date,series_id,ref_period,delta_nowcast_pp,prev_value,new_value
2024-01-15,COMBINED,current_quarter,0.15,2.20,2.35
2024-01-15,ipi_mfg,current_quarter,0.10,1.50,1.60
```

## Key Design Principles

1. **No bridging**: Never impute unreleased months
2. **Quarterly state**: Always maintain quarterly GDP target
3. **Reproducible vintages**: Immutable snapshots
4. **Calendar-aware**: Use actual release dates
5. **Country-agnostic**: Works with/without monthly proxy
6. **Modular**: Independent model tracks
7. **Auditable**: Spec hashing, registry tracking

## Testing

The system includes placeholder implementations for demonstration. In production:

1. Replace PCA with proper 3PF implementation
2. Use `midasr` package functions for actual MIDAS
3. Implement DFM with `dfms` or `nowcastDFM`
4. Add KFAS/MARSS for state-space models
5. Implement proper seasonal adjustment (X-13ARIMA-SEATS)

## Extensibility

Add new models by:
1. Creating new model module in `R/`
2. Implementing `fit_*` and `predict_*` functions
3. Updating `runner.R` to call new model
4. Adding to combination scheme

## References

- MIDAS: Ghysels, E., Santa-Clara, P., & Valkanov, R. (2004)
- Three-Pass Filter: Kelly, B., & Pruitt, S. (2015)
- Dynamic Factor Models: Stock, J. H., & Watson, M. W. (2002)
- State-Space Models: Durbin, J., & Koopman, S. J. (2012)

## License

This is a specification implementation for a nowcasting system. Adapt as needed for your use case.
