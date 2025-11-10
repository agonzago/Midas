# MIDAS Nowcasting: Evaluation Outputs

This directory contains the complete evaluation results comparing MIDAS and TPRF-MIDAS methods for Mexican GDP nowcasting.

## Generated Files

### 1. Main Reports

**`FORECAST_COMPARISON_SUMMARY.md`** 
Comprehensive markdown report with:
- Method descriptions (MIDAS vs TPRF)
- Performance comparison tables
- Technical analysis and recommendations
- When to use each method

**`forecast_evaluation_report.txt`**
Text-based report with:
- Executive summary
- Detailed results by model
- Statistical comparison
- Technical notes

### 2. Results Data

**`rolling_evaluation_results.csv`**
Contains:
- Model specifications
- Number of forecasts
- RMSE, MAE, Mean Error for each model
- Excludes forecast/actual series (too large for CSV)

Columns:
```
spec, n_forecasts, rmse, mae, me
```

### 3. Visualizations

**`rolling_evaluation_plots.pdf`**
8-page PDF with diagnostic plots:

1. **Forecast vs Actual (MIDAS)** - Time series comparison
2. **Forecast Errors (MIDAS)** - Error evolution over time
3. **Forecast vs Actual (TPRF)** - Time series comparison
4. **Forecast Errors (TPRF)** - Error evolution over time
5. **Error Distribution (MIDAS)** - Histogram + density
6. **Error Distribution (TPRF)** - Histogram + density
7. **RMSE Comparison** - Bar chart across all models
8. **Cumulative RMSE** - Error accumulation over time

### 4. Source Code

**Core Implementation:**
- `R/midas_models.R` - MIDAS regression functions (fixed NaN bug)
- `R/tprf_models.R` - Three-Pass Regression Filter with auto-factor selection

**Evaluation Scripts:**
- `run_rolling_evaluation.R` - Out-of-sample evaluation framework
- `generate_forecast_report.R` - Report generator
- `run_mexico_nowcast.R` - Single nowcast example

**Test Files:**
- `test_integration.R` - Integration tests for all models
- `test_tprf.R` - TPRF standalone tests

## Quick Start

### View Results
```r
# Load results
results <- read.csv("rolling_evaluation_results.csv")
print(results[order(results$rmse), ])

# View plots
# Open rolling_evaluation_plots.pdf in your PDF viewer
```

### Run Evaluation
```r
# Full evaluation (takes ~5 minutes)
source("run_rolling_evaluation.R")

# Generate report
source("generate_forecast_report.R")
```

### Single Nowcast
```r
# Quick nowcast with latest data
source("run_mexico_nowcast.R")
```

## Key Findings

**Best Model:** `MIDAS_AR1_lag3_m2`
- RMSE: 13.49
- MAE: 5.49
- Bias: -0.57

**MIDAS vs TPRF:**
- MIDAS outperforms TPRF by 61%
- Simpler is better for this dataset
- Single indicator (EAI) is highly informative

**Recommendation:** Use single-indicator MIDAS for Mexican GDP nowcasting.

## File Sizes

| File | Type | Size | Description |
|------|------|------|-------------|
| FORECAST_COMPARISON_SUMMARY.md | Report | ~8 KB | Main analysis document |
| forecast_evaluation_report.txt | Report | ~2 KB | Text summary |
| rolling_evaluation_results.csv | Data | <1 KB | Numeric results |
| rolling_evaluation_plots.pdf | Plots | ~50 KB | Visual diagnostics |

## Data Sources

- **GDP:** Mexican quarterly GDP (INEGI), 1993Q2-2023Q4, 123 observations
- **Indicators:** Monthly data from INEGI
  - DA_EAI: Economic Activity Index (main indicator)
  - DA_RETSALES: Retail Sales
  - DA_GVFI, DA_PMI_M, DA_PMI_NM, etc. (supplementary)

## Evaluation Setup

- **Method:** Out-of-sample rolling window
- **Initial training:** 60 quarters (1993Q2-2008Q1)
- **Forecast origin:** One month into quarter (ragged edge)
- **Number of forecasts:** 63 (2008Q2-2023Q4)
- **Window types:** Expanding (all history) and Rolling (40 quarters)

## Contact

For questions about methodology or implementation:
- MIDAS implementation: Based on `midasr` R package
- TPRF implementation: Custom (Kelly & Pruitt 2015)
- Integration: See `R/` directory for documented source code

## Version History

- **v1.0** (Nov 2025): Initial evaluation with fixed MIDAS implementation and TPRF
  - Fixed: MIDAS namespace prefix bug causing NaN forecasts
  - Added: TPRF with auto-factor selection
  - Added: Comprehensive evaluation framework
