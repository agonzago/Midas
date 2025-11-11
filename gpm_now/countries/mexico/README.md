# Mexico Nowcasting

Weekly nowcasting for Mexican GDP using MIDAS and TPRF models.

## 📊 Data Sources

### Quarterly Data
- **GDP Growth** (`DA_GDP`): Annualized quarterly GDP growth rate
- **Source**: INEGI (National Statistics Office)
- **Sample**: 1993Q1 - 2023Q4

### Monthly Data
- **Economic Activity Index** (`DA_EAI`): Main GDP proxy, similar to industrial production
- **Investment Indicators**: `DA_GVFI` (Government Fixed Investment)
- **PMI Indices**: `DA_PMI_M` (Manufacturing), `DA_PMI_NM` (Non-Manufacturing)
- **Retail Indicators**: `DA_RETSALES`, `DA_RETGRO`, `DA_RETSUP`
- **Source**: INEGI, Banco de México
- **Sample**: 1993-01 to 2024-01

All variables are in annualized growth rates (DA_ prefix).

## 🚀 Quick Start

### Run Weekly Nowcast

```r
# From gpm_now/countries/mexico/
source("run_mexico_nowcast.R")
```

This will:
1. Load configurations from `config/`
2. Read data from Mexican sources
3. Fit MIDAS models (multiple specifications)
4. Fit TPRF models with monthly panel
5. Combine MIDAS forecasts (equal, inv-BIC, inv-RMSE)
6. Generate nowcast report
7. Save outputs to `output/`

### Run Rolling Evaluation

```r
# From gpm_now/countries/mexico/
source("run_mexico_rolling_evaluation.R")
```

This will:
1. Set up rolling window (60 quarters initial)
2. Forecast 1-quarter ahead recursively
3. Evaluate MIDAS, TPRF, and combination models
4. Calculate RMSE for all models
5. Generate comparison plots
6. Save results to `output/rolling_evaluation_results.csv`

## 📁 File Structure

```
mexico/
├── config/
│   ├── variables.yaml      # Variable definitions for Mexico
│   ├── options.yaml        # Model specifications
│   └── calendar.csv        # Release calendar
├── data/
│   ├── monthly/            # Monthly indicator data
│   └── quarterly/          # Quarterly GDP data
├── R/
│   ├── runner.R            # Weekly nowcast runner
│   └── io.R                # I/O functions
├── output/                 # Nowcast outputs (JSON, CSV)
├── plots/                  # Forecast plots
├── run_mexico_nowcast.R    # Main nowcast script
└── run_mexico_rolling_evaluation.R  # Evaluation script
```

## 🔧 Model Specifications

### MIDAS Models

Current specifications in `run_mexico_rolling_evaluation.R`:

1. **MIDAS_AR1_lag3_m2**: AR(1) with 3 quarterly lags, 2 lag periods
2. **MIDAS_AR2_lag4_m2**: AR(2) with 4 quarterly lags, 2 lag periods
3. **MIDAS_AR1_lag4_m3**: AR(1) with 4 quarterly lags, 3 lag periods
4. **MIDAS_AR2_lag4_m2_ADJ**: With structural break adjustment
5. **MIDAS_AR1_lag3_m2_ADJ**: With structural break adjustment

All use beta polynomial restrictions for monthly lag structure.

### TPRF Models

1. **TPRF_3F_AR1**: 3 factors, AR(1)
2. **TPRF_2F_AR2**: 2 factors, AR(2)

Panel includes: EAI, GVFI, PMI_M, PMI_NM, RETSALES, RETGRO, RETSUP

### Model Combination

- **Trimming**: Remove worst 25% of MIDAS models
- **Schemes**:
  - Equal weights (simple average)
  - Inverse BIC weights
  - Inverse RMSE weights

## 📈 Results Summary

### Rolling Evaluation (15-year initial window)

**RMSE Performance** (example from recent evaluation):

| Model | RMSE | Notes |
|-------|------|-------|
| MIDAS_AR2_lag4_m2 | 2.45 | Best individual |
| MIDAS combination (equal) | 2.32 | 5.2% improvement |
| MIDAS combination (inv-RMSE) | 2.26 | 7.5% improvement |
| TPRF_3F_AR1 | 2.58 | Factor-based |

### Structural Break Findings

Post-2021 period shows systematic under-prediction by MIDAS models, likely due to COVID-19 structural break. The adjusted models (MIDAS_*_ADJ) use recent 4-quarter forecast errors to correct for this level shift.

**Adjustment Impact**:
- Pre-adjustment: -1.5pp average error (2021-2023)
- Post-adjustment: -0.3pp average error (2021-2023)

## ⚙️ Configuration

### Edit Model Specifications

Modify `run_mexico_rolling_evaluation.R` to change model specifications:

```r
model_specs <- list(
  # Add your custom MIDAS specification
  list(name = "MIDAS_AR3_lag5_m3", 
       type = "midas", 
       ar_q = 3, 
       lag_y = 5, 
       lag_x = 3),
  
  # Add structural break adjustment
  list(name = "MIDAS_AR3_lag5_m3_ADJ", 
       type = "midas", 
       ar_q = 3, 
       lag_y = 5, 
       lag_x = 3,
       intercept_adjustment = "recent_errors", 
       adjustment_window = 4)
)
```

### Edit Combination Settings

Modify `config/options.yaml`:

```yaml
midas_combination:
  enabled: true
  schemes: ["equal", "inv_bic", "inv_rmse"]
  trim_percentile: 0.25  # Remove worst 25%
```

## 📊 Output Files

### Weekly Nowcast Outputs

- `output/nowcast_YYYY-MM-DD.json` - Full nowcast results
- `output/nowcast_YYYY-MM-DD.csv` - Forecast summary
- `output/logs/nowcast_YYYY-MM-DD.log` - Execution log
- `plots/nowcast_YYYY-MM-DD.png` - Forecast visualization

### Rolling Evaluation Outputs

- `output/rolling_evaluation_results.csv` - All forecasts and actuals
- `plots/midas_comparison.png` - Time series comparison
- `plots/rmse_comparison.png` - RMSE bar chart

## 🔍 Data Notes

### Vintage Data
Current implementation uses **final revised data**. For real-time nowcasting, implement vintage data handling:
- Save data snapshots at each forecast date
- Use only information available at forecast time
- Account for data revisions in evaluation

### Missing Data
The framework handles missing data automatically:
- MIDAS: Uses available monthly observations
- TPRF: Imputes missing values in factor extraction
- Combination: Excludes models that fail to produce forecasts

## 🛠️ Customization

### Add New Indicators

1. Add to `config/variables.yaml`:
```yaml
indicators:
  - id: "new_indicator_m"
    name: "New Monthly Indicator"
    freq: "monthly"
    transform: "pct_mom"
```

2. Place data in `data/monthly/new_indicator_m.csv`

3. Update TPRF panel in evaluation script:
```r
tprf_panel <- cbind(
  mex_M$DA_EAI,
  mex_M$DA_NEW_INDICATOR,  # Add your indicator
  # ... other indicators
)
```

### Change Forecast Horizon

Current: 1-quarter ahead (`h = 1`)

For multi-step forecasts, modify:
```r
result <- fit_or_update_midas_set(
  y = y_train,
  x = x_train,
  # ...
  h = 2  # 2-quarter ahead
)
```

## 📞 Support

For Mexico-specific questions:
- Data sources: Contact INEGI
- Model specifications: See `run_mexico_rolling_evaluation.R`
- Common functions: See `../../common/README.md`

## 🔗 Related Files

- Common functions: `gpm_now/common/`
- Data retrieval: `gpm_now/retriever/` (for Brazil; Mexico uses manual data)
- Main documentation: `gpm_now/README.md`

---

**Last Updated**: November 2025  
**Sample Period**: 1993Q1 - 2023Q4  
**Forecast Frequency**: Weekly (or on-demand)
