# MIDAS Implementation: Issues Fixed and Solutions

## Summary

This document tracks all issues discovered and fixed during the MIDAS nowcasting implementation for Mexican GDP forecasting.

---

## Issue #1: MIDAS Returns NaN Forecasts

**Date Discovered:** Initial implementation  
**Status:** ✅ FIXED

### Problem
MIDAS model returned `NaN` for all forecasts despite successful model fitting.

### Root Cause
Using `midasr::` namespace prefix in formula construction:
```r
# BROKEN CODE:
formula <- as.formula(sprintf("y ~ midasr::mls(y, 1:%d, 1) + midasr::mls(x, %d:%d, 3)", 
                              y_lag, moq, moq+x_lag))
```

The `midasr::` prefix worked during model fitting but caused `forecast()` to fail with error:
```
Error in if (any(x.is.na)) { : the condition has length > 1
```

### Solution
Remove namespace prefix from formula:
```r
# FIXED CODE:
formula <- as.formula(sprintf("y ~ mls(y, 1:%d, 1) + mls(x, %d:%d, 3)", 
                              y_lag, moq, moq+x_lag))
```

Use `sprintf()` to inject actual numeric values instead of variable names.

### Files Modified
- `gpm_now/R/midas_models.R` (lines 175-219)

### Verification
- ✅ All unit tests pass
- ✅ Integration test successful  
- ✅ 63/63 forecasts valid in rolling evaluation

---

## Issue #2: Variable Extraction from Formula

**Date Discovered:** During debugging  
**Status:** ✅ FIXED

### Problem
Original code tried to extract variable names from formula terms, but with AR lags this extracted both Y and X variables incorrectly.

### Root Cause
```r
# BROKEN: Extracted both Y and X from "y ~ mls(y, ...) + mls(x, ...)"
vars <- all.vars(model$formula)
x_var <- vars[2]  # Could get 'y' instead of 'x'
```

### Solution
Skip AR terms (mls involving Y) and only extract X variable:
```r
# FIXED:
terms_list <- attr(terms(model$formula), "term.labels")
# Find the X term (not AR term)
x_term_idx <- which(!grepl("^mls\\(y,", terms_list))[1]
x_var_name <- extract_var_name(terms_list[x_term_idx])
```

### Files Modified
- `gpm_now/R/midas_models.R` (lines 270-295)

---

## Issue #3: Time Series Extension for Forecasting

**Date Discovered:** During prediction testing  
**Status:** ✅ FIXED

### Problem
Simple `c()` concatenation lost time series attributes (start date, frequency).

### Root Cause
```r
# BROKEN: Lost ts attributes
y_extended <- c(model$model$y, y_new)
x_extended <- c(x_data, x_new)
```

### Solution
Proper time series concatenation:
```r
# FIXED: Preserves ts attributes
y_extended <- ts(c(as.numeric(model$model$y), as.numeric(y_new)),
                 start = start(model$model$y),
                 frequency = frequency(model$model$y))

x_extended <- ts(c(as.numeric(x_data), as.numeric(x_new)),
                 start = start(x_data),
                 frequency = frequency(x_data))
```

### Files Modified
- `gpm_now/R/midas_models.R` (lines 325-345)

---

## Issue #4: TPRF with Extremely Low R²

**Date Discovered:** Initial TPRF evaluation  
**Status:** ✅ FIXED

### Problem
TPRF factor extraction showed R² of 0.002-0.045 (should be 0.5-0.8).

### Root Cause Analysis

**Sub-issue 4a: Missing Data in Early Sample**
```
First 180 months: 1564/1980 values missing (79%)
Many indicators completely missing in 1993-2008
```

**Sub-issue 4b: Too Many Series, Too Few Factors**
```
With 2 series and extracting 2 factors → overfitting
Need at least 3-4 series per factor
```

**Sub-issue 4c: Incorrect R² Calculation**
```r
# BROKEN: Didn't account for NAs properly
explained_var <- sum((X_fitted)^2, na.rm = TRUE)
r_squared <- explained_var / total_var
```

### Solutions

**Fix 4a: Stricter Missing Data Filter**
```r
# Filter indicators with >30% missing (relaxes to 50% if needed)
na_prop <- colMeans(is.na(X_m_panel))
valid_cols <- na_prop < 0.3
```

**Fix 4b: Auto-Adjust Number of Factors**
```r
# Auto-select based on available series
if (is.null(k)) {
  k <- min(2, max(1, floor(N / 3)))  # 1 factor per 3-4 series
}
```

**Fix 4c: Correct R² Formula**
```r
# FIXED: Only compare at non-missing observations
valid_mask <- !is.na(X_std)
total_var <- sum(X_std[valid_mask]^2)
residual_var <- sum((X_std[valid_mask] - X_fitted[valid_mask])^2)
r_squared <- 1 - (residual_var / total_var)
```

### Results After Fix
- Early sample (2 series): R² = 0.68 with 1 factor
- Later sample (6 series): R² = 0.77 with 2 factors

### Files Modified
- `gpm_now/R/tprf_models.R` (lines 30-70, 165-175)

---

## Issue #5: TPRF Look-Ahead Bias

**Date Discovered:** During evaluation  
**Status:** ✅ FIXED

### Problem
TPRF factors anticipated COVID crash by several months - impossible in real-time.

### Root Cause
Factors were extracted once from full sample:
```r
# BROKEN: Used future information
factors_full <- build_tprf_factors(X_full_sample, k=2)
# Then used these factors for all forecasts
```

### Solution
Re-extract factors at each forecast origin using only training data:
```r
# FIXED: Pseudo-real-time factor extraction
for (h in 1:n_forecasts) {
  X_train <- X_full[1:train_end_idx, ]
  factors_train <- build_tprf_factors(X_train, k=NULL)  # No future info
  # Use factors_train for this forecast only
}
```

### Files Modified
- `gpm_now/run_rolling_evaluation.R` (lines 200-250)

---

## Issue #6: TPRF Worse than MIDAS

**Status:** ✅ NOT A BUG - Expected Result

### Observation
TPRF RMSE (21.7) is 61% worse than MIDAS (13.5).

### Analysis
This is **not an implementation bug**. TPRF is working correctly:
- Factors explain 67-77% of indicator variance (good)
- No look-ahead bias (verified)
- Proper handling of missing data

### Explanation
TPRF performs worse because:
1. **Data constraints:** Only 2 series available in early sample
2. **Signal dilution:** EAI alone is more informative than averaged factors
3. **Estimation noise:** Factor extraction adds uncertainty
4. **Bias-variance tradeoff:** TPRF has higher variance

This is a valid research finding, not a bug.

---

## Implementation Status

### Working Features
✅ MIDAS unrestricted regression  
✅ MIDAS forecast with ragged edge  
✅ Three-Pass Regression Filter  
✅ Auto-factor selection  
✅ Missing data handling  
✅ Rolling window evaluation  
✅ Expanding vs rolling windows  
✅ Comprehensive diagnostics  

### Test Coverage
✅ Unit tests for MIDAS (3/3 passing)  
✅ Integration test (MIDAS + TPRF)  
✅ Rolling evaluation (63 forecasts)  
✅ Real data application (Mexico GDP)  

---

## Lessons Learned

### 1. Namespace Prefixes in Formulas
**Lesson:** Don't use `package::function()` in formula objects passed to `forecast()`

**Why:** Formula evaluation context differs between fitting and forecasting

**Solution:** Load functions into namespace or use bare function names

### 2. Time Series Attributes
**Lesson:** Simple vector operations lose `ts` attributes

**Why:** `c()`, arithmetic operations return plain vectors

**Solution:** Always use `ts()` constructor to preserve start/frequency

### 3. Factor Models Aren't Always Better
**Lesson:** More sophisticated ≠ better forecasts

**Why:** Depends on data quality, cross-sectional dimension, indicator correlation

**Rule of thumb:** Start simple (single indicator) before adding complexity

### 4. Real-time Evaluation is Critical
**Lesson:** Always check for look-ahead bias in factor models

**Why:** Factors estimated from full sample use future information

**Solution:** Re-estimate factors at each forecast origin

### 5. Missing Data Matters
**Lesson:** Factor quality degrades severely with sparse data

**Why:** Early sample had 79% missing values

**Solution:** Filter indicators by completeness, auto-adjust factor count

---

## Code Quality Improvements

### Before vs After

**Before:**
- NaN forecasts (unusable)
- Look-ahead bias (invalid evaluation)
- Poor factor quality (R²<0.05)
- Hard-coded factor count
- No data quality checks

**After:**
- ✅ 63/63 valid forecasts
- ✅ Pseudo-real-time evaluation
- ✅ R²=0.67-0.77 (appropriate)
- ✅ Auto-adjust factors (1-2 based on data)
- ✅ Comprehensive diagnostics

### Documentation Added
- `FORECAST_COMPARISON_SUMMARY.md` - Method comparison
- `EVALUATION_OUTPUTS.md` - File guide
- `BUGS_FIXED.md` - This document
- `forecast_evaluation_report.txt` - Statistical report
- Inline code comments throughout

---

## References

**MIDAS:**
- Ghysels, E., Santa-Clara, P., & Valkanov, R. (2004). The MIDAS touch.
- `midasr` package: https://cran.r-project.org/package=midasr

**TPRF:**
- Kelly, B., & Pruitt, S. (2015). The three-pass regression filter.

**Time Series in R:**
- R Documentation: `?ts`, `?forecast`
- Hyndman & Athanasopoulos (2021). Forecasting: Principles and Practice.

---

## Version History

**v1.0** (Nov 2025)
- Fixed MIDAS namespace bug
- Implemented TPRF with auto-factor selection
- Fixed look-ahead bias
- Added comprehensive evaluation framework
- Generated comparison report
