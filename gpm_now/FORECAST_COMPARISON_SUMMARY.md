# MIDAS Nowcasting: Method Comparison Summary

**Date:** November 9, 2025  
**Dataset:** Mexican Quarterly GDP (1993-2023) with Monthly Indicators  
**Evaluation:** Out-of-sample rolling window (63 forecasts)

---

## Executive Summary

**Best Overall Model:** `MIDAS_AR1_lag3_m2` (RMSE: 13.49)

**Key Finding:** Single-indicator MIDAS outperforms factor-based TPRF-MIDAS by **61%** in this application.

---

## Models Evaluated

### 1. MIDAS (Mixed Data Sampling)

**Concept:** Direct regression of quarterly GDP on monthly indicator (EAI - Economic Activity Index)

**Specifications Tested:**
- `MIDAS_AR1_lag3_m2`: 1 AR lag, 3 X lags, expanding window
- `MIDAS_AR2_lag4_m2`: 2 AR lags, 4 X lags, expanding window  
- `MIDAS_AR2_lag4_m2_roll40`: Same as above but 40-quarter rolling window

**How it works:**
```
GDP_t = α + β₁*GDP_{t-1} + β₂*EAI_{t,m} + β₃*EAI_{t-1,m} + ... + ε_t
```
where `m` denotes month within quarter (m=2 for 1 month into current quarter)

**Strengths:**
- Simple and interpretable
- Directly uses most informative indicator (EAI)
- Computationally efficient
- Robust to data limitations

**Limitations:**
- Uses only one indicator
- Cannot leverage information from multiple series
- May miss complementary signals

---

### 2. TPRF-MIDAS (Three-Pass Regression Filter + MIDAS)

**Concept:** Extract latent factors from panel of monthly indicators using Three-Pass Filter, then use factors in MIDAS

**Specifications Tested:**
- `TPRF_AR2_lag4_m2`: Auto-selected factors (1-2), expanding window
- `TPRF_AR2_lag4_m2_roll40`: Same with 40-quarter rolling window

**How it works:**
1. **Pass 1:** Time-series regressions → estimate factor loadings
2. **Pass 2:** Cross-sectional regressions → extract factors  
3. **Pass 3:** Refine loadings given factors
4. **MIDAS:** Use extracted factors as regressors

**Indicator Panel Used:**
- DA_EAI (Economic Activity Index)
- DA_RETSALES (Retail Sales)
- Additional indicators when available (varies by time period)

**Factor Selection Logic:**
- Filters indicators with >30% missing data
- Auto-selects 1-2 factors based on available series
- Early periods (2008): Only 2 series available → 1 factor (R²=0.68)
- Recent periods (2023): 6 series available → 2 factors (R²=0.77)

**Strengths:**
- Handles missing data
- Extracts common variation from multiple indicators
- Theoretically more information-rich

**Limitations:**
- More complex estimation
- Factor quality depends on data availability
- May introduce noise when indicators have weak comovement
- Requires sufficient cross-sectional dimension

---

## Performance Comparison

### Forecast Accuracy Metrics

| Model | RMSE | MAE | Mean Error (Bias) | N Forecasts |
|-------|------|-----|------------------|-------------|
| **MIDAS_AR1_lag3_m2** | **13.49** | **5.49** | -0.57 | 63 |
| MIDAS_AR2_lag4_m2 | 13.62 | 5.73 | -0.89 | 63 |
| TPRF_AR2_lag4_m2 | 21.72 | 8.54 | 2.45 | 63 |
| MIDAS_AR2_lag4_m2_roll40 | 22.61 | 9.90 | -1.12 | 63 |
| TPRF_AR2_lag4_m2_roll40 | 50.09 | 15.05 | 8.31 | 63 |

### Key Observations

1. **MIDAS Dominates:**
   - Best MIDAS (13.49) vs Best TPRF (21.72)
   - TPRF RMSE is 61% worse

2. **Expanding vs Rolling Windows:**
   - Expanding windows perform better for both methods
   - Rolling 40Q introduces instability (worse performance)

3. **Bias Analysis:**
   - Best MIDAS: -0.57 (slight downward bias)
   - Best TPRF: +2.45 (upward bias - over-forecasting)

4. **AR Lag Selection:**
   - AR(1) slightly outperforms AR(2) for MIDAS
   - Suggests GDP dynamics are relatively simple

---

## Why Does MIDAS Outperform TPRF?

### Data Constraints
- **Limited cross-section:** Many indicators have extensive missing data in early sample
- **Dominant indicator:** EAI is highly informative for Mexican GDP
- **Weak comovement:** Other indicators may not add much signal

### Factor Quality Issues
- **Early sample (2008-2014):** Only 2 series → 1 factor
  - Factor essentially averages EAI and RETSALES
  - May dilute strong EAI signal with weaker RETSALES information

- **Later sample (2020-2023):** 6 series → 2 factors
  - Better cross-sectional dimension
  - But still produces worse forecasts

### Potential Explanations
1. **Signal dilution:** Averaging across indicators loses information
2. **Estimation noise:** Factor extraction adds estimation error
3. **Overfitting:** More parameters in TPRF model
4. **Indicator quality:** EAI may genuinely be sufficient for GDP nowcasting

---

## Recommendations

### For Operational Nowcasting

**Use: `MIDAS_AR1_lag3_m2`**

Rationale:
- Best forecast accuracy (RMSE: 13.49)
- Simple and interpretable
- Computationally fast
- Robust specification

Configuration:
- AR lags: 1
- X lags: 3  
- Month of quarter: 2 (forecast with 1 month of data)
- Window: Expanding

### When to Consider TPRF

TPRF may be preferable when:
1. **Rich cross-section:** Many high-quality indicators (>10 series)
2. **Balanced panel:** Minimal missing data
3. **Complementary signals:** Indicators capture different GDP components
4. **No dominant indicator:** No single series is clearly superior

### Future Improvements

1. **Indicator Selection:**
   - Add more early-available monthly indicators
   - Focus on series with minimal missing data
   - Consider survey data (PMIs, confidence indices)

2. **Model Enhancements:**
   - Test dynamic factor models (DFM)
   - Try forecast combinations (MIDAS + TPRF)
   - Experiment with bridge equations

3. **Real-time Considerations:**
   - Account for data revisions
   - Test different publication lag assumptions
   - Evaluate forecast combinations

---

## Technical Implementation

### Data Availability by Period

| Period | Available Indicators | TPRF Factors | Factor R² |
|--------|---------------------|--------------|-----------|
| 2008-2010 | 2 (EAI, RETSALES) | 1 | 0.68 |
| 2011-2015 | 2-3 | 1 | 0.67 |
| 2016-2020 | 4-5 | 1 | 0.71 |
| 2021-2023 | 6 | 2 | 0.77 |

### Code Implementation Status

✅ **Fixed Issues:**
- MIDAS NaN forecasts (namespace prefix bug)
- Time series alignment and extension
- TPRF factor extraction with missing data
- Auto-adjustment of factor count based on data availability
- Look-ahead bias prevention (factors re-extracted each period)

✅ **Deliverables:**
- `rolling_evaluation_results.csv`: Full results table
- `rolling_evaluation_plots.pdf`: 8 diagnostic plots
- `forecast_evaluation_report.txt`: Detailed text report
- `FORECAST_COMPARISON_SUMMARY.md`: This document

---

## Conclusion

For Mexican GDP nowcasting with available data (1993-2023), **single-indicator MIDAS clearly outperforms factor-based TPRF-MIDAS**. The Economic Activity Index (EAI) alone provides sufficient information, and factor extraction introduces more noise than signal.

**Recommended specification:** `MIDAS_AR1_lag3_m2` with expanding window achieves RMSE of 13.49 and should be used for operational nowcasts.

The TPRF implementation is working correctly (factors explain 67-77% of indicator variance), but in this particular application, simpler is better. This result is consistent with the bias-variance tradeoff: TPRF has higher variance due to factor estimation uncertainty.

---

## References

**Methods:**
- Ghysels, E., Santa-Clara, P., & Valkanov, R. (2004). The MIDAS touch: Mixed data sampling regression models.
- Kelly, B., & Pruitt, S. (2015). The three-pass regression filter: A new approach to forecasting using many predictors.

**Implementation:**
- R package: `midasr` (https://cran.r-project.org/package=midasr)
- Custom TPRF implementation in `gpm_now/R/tprf_models.R`

**Data:**
- Mexican quarterly GDP: INEGI
- Monthly indicators: INEGI (Economic Activity Index, Retail Sales, etc.)
