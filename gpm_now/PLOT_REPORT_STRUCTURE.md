# Rolling Evaluation Report Structure

## Overview

The `rolling_evaluation_plots.pdf` report is now organized into **three clear sections**:

1. **MIDAS Model Evaluation** (Pages 1-5)
2. **TPRF Model Evaluation** (Pages 6-10)
3. **MIDAS vs TPRF Comparison** (Pages 11-15)

Total: **15 pages**

---

## Section 1: MIDAS Model Evaluation (Pages 1-5)

### Page 1: MIDAS Title Page
- **Model name:** Best MIDAS specification
- **Performance metrics:** RMSE, MAE, Mean Error, Number of forecasts
- **Method description:** Single Indicator (Economic Activity Index)

### Page 2: MIDAS Forecast vs Actual
- **Time series plot** showing actual GDP growth vs MIDAS forecasts
- **Black line:** Actual GDP growth
- **Blue line:** MIDAS forecasts
- **Shows:** How well MIDAS tracks actual GDP over time

### Page 3: MIDAS Forecast Errors
- **Error time series** (vertical bars showing magnitude and direction)
- **Black line:** Zero line
- **Red dashed:** Mean error (bias)
- **Orange dashed:** ±2 standard deviations (confidence bands)
- **Shows:** Where and when MIDAS makes large errors

### Page 4: MIDAS Error Distribution
- **Histogram** with density curve showing error distribution
- **Red line:** Zero (perfect forecast)
- **Orange line:** Mean error
- **Text box:** Summary statistics (Mean, SD, RMSE)
- **Shows:** Whether errors are normally distributed and symmetric

### Page 5: MIDAS Scatter Plot
- **X-axis:** Actual GDP growth
- **Y-axis:** MIDAS forecast
- **Red dashed:** 45° line (perfect forecast)
- **Blue solid:** Fitted regression line
- **Text box:** Correlation, RMSE, R²
- **Shows:** Overall forecast accuracy and any systematic bias

---

## Section 2: TPRF Model Evaluation (Pages 6-10)

### Page 6: TPRF Title Page
- **Model name:** Best TPRF specification
- **Performance metrics:** RMSE, MAE, Mean Error, Number of forecasts
- **Method description:** Factor-Based (Three-Pass Regression Filter)

### Page 7: TPRF Forecast vs Actual
- **Time series plot** showing actual GDP growth vs TPRF forecasts
- **Black line:** Actual GDP growth
- **Green line:** TPRF forecasts
- **Shows:** How well TPRF tracks actual GDP over time

### Page 8: TPRF Forecast Errors
- **Error time series** (vertical bars)
- **Black line:** Zero line
- **Red dashed:** Mean error (bias)
- **Orange dashed:** ±2 standard deviations
- **Shows:** TPRF error patterns over time

### Page 9: TPRF Error Distribution
- **Histogram** with density curve (green theme)
- **Red line:** Zero
- **Orange line:** Mean error
- **Text box:** Summary statistics
- **Shows:** TPRF error distribution characteristics

### Page 10: TPRF Scatter Plot
- **X-axis:** Actual GDP growth
- **Y-axis:** TPRF forecast
- **Red dashed:** 45° line
- **Green solid:** Fitted regression line
- **Text box:** Correlation, RMSE, R²
- **Shows:** TPRF forecast accuracy

---

## Section 3: MIDAS vs TPRF Comparison (Pages 11-15)

### Page 11: Comparison Title Page
- **Summary of both methods**
- **MIDAS metrics** (blue theme)
- **TPRF metrics** (green theme)
- **Winner declaration:** Which method performs better and by how much

### Page 12: Direct Forecast Comparison
- **All three time series on one plot:**
  - Black: Actual GDP
  - Blue: MIDAS forecasts
  - Green: TPRF forecasts (dashed)
- **Legend shows RMSE** for each method
- **Shows:** Direct visual comparison of forecast performance

### Page 13: Error Comparison Over Time
- **Blue line:** MIDAS errors
- **Green dashed:** TPRF errors
- **Black line:** Zero
- **Shows:** Which method has larger errors at different time periods

### Page 14: RMSE Comparison Bar Chart
- **Bar chart** of all model specifications
- **Blue bars:** MIDAS models
- **Green bars:** TPRF models
- **Shows:** Relative performance of all specifications tested

### Page 15: Cumulative Squared Errors
- **Cumulative performance over time**
- **Blue line:** MIDAS cumulative squared error
- **Green dashed:** TPRF cumulative squared error
- **Text box:** Final RMSE comparison and winner
- **Shows:** How forecast performance accumulates over entire evaluation period

---

## Color Scheme

- **MIDAS:** Steel blue theme
- **TPRF:** Dark green theme
- **Actual data:** Black
- **Reference lines:** Red (zero/45°), Orange (confidence bands)

---

## Key Insights from Report

### MIDAS Performance
- ✅ **Best RMSE:** 13.49
- ✅ **Low bias:** -0.57 (slight underforecasting)
- ✅ **Stable errors:** Mostly within ±2 SD bands
- ✅ **High correlation:** Strong fit to actual data

### TPRF Performance
- ⚠️ **Higher RMSE:** 21.72 (61% worse than MIDAS)
- ⚠️ **Positive bias:** +2.45 (overforecasting)
- ⚠️ **More volatile:** Larger error swings
- ⚠️ **Lower correlation:** Weaker fit overall

### Comparison Verdict
**MIDAS wins** by a large margin. Single-indicator approach outperforms factor-based method for this dataset.

---

## How to Use This Report

### For Quick Review
1. Check **Page 11** (Comparison Title) for overall winner
2. Look at **Page 12** (Forecast Comparison) for visual evidence
3. Review **Page 15** (Cumulative Performance) for long-term trends

### For Detailed Analysis
1. **MIDAS:** Pages 1-5 for complete MIDAS diagnostics
2. **TPRF:** Pages 6-10 for complete TPRF diagnostics
3. **Comparison:** Pages 11-15 for head-to-head analysis

### For Presentation
- Use **Page 1** as MIDAS introduction
- Use **Page 6** as TPRF introduction
- Use **Page 11** as comparison summary
- Use **Page 12** as main comparison chart

---

## File Location

**Full report:** `/home/andres/work/Midas/gpm_now/rolling_evaluation_plots.pdf`

**Supporting files:**
- `rolling_evaluation_results.csv` - Numeric results table
- `forecast_evaluation_report.txt` - Text summary
- `FORECAST_COMPARISON_SUMMARY.md` - Detailed analysis

---

## Generation

This report is automatically generated by:
```r
source("run_rolling_evaluation.R")
```

The structure is:
1. Evaluate all models (MIDAS and TPRF)
2. Calculate performance metrics
3. Generate plots in organized sections
4. Save to PDF with proper titles and formatting

**Regenerate anytime** to update with new data or specifications!
