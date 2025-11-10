# MIDAS Implementation Analysis: NaN Forecasts Issue

## Executive Summary

After comparing the gpm_now MIDAS implementation with the original Mexico_Midas.R code, I've identified **several critical differences** that are likely causing NaN forecasts. Additionally, the pseudo-ragged vintage construction has **potential issues** with how weekly datasets are created.

---

## Task 1: MIDAS Implementation Comparison

### Key Differences Found

#### 1. **Forecast Data Preparation (CRITICAL)**

**Mexico_Midas.R (Working):**
```r
# Line 111-113
xn <- c(window(mex_m_ts[, "D_EAI"], start=c(2023,4), end=c(2023,4)), NA, NA)
fh1 <- forecast(eq_u_h1, newdata=list(D_EAI=c(xn), D_GDP=c(NA)), method = "static")
```
- Uses **3 values** for the monthly indicator (1 actual + 2 NAs)
- Passes `D_GDP=c(NA)` for the forecast quarter
- Uses `method = "static"` for one-step-ahead forecast

**gpm_now/R/midas_models.R (Problematic):**
```r
# Lines 243-276 in predict_midas_unrestricted()
newdata <- list()

if (y_lag > 0) {
    if (!is.null(y_new)) {
        newdata$y <- tail(y_new, y_lag)  # Historical GDP values
    } else {
        newdata$y <- tail(model$fit$model$y, y_lag)
    }
}

if (!is.null(x_new)) {
    # Only adds x_new to newdata
    newdata$x <- x_new  # Should be 3 values
}
```

**PROBLEM 1:** The newdata structure doesn't match midasr's expected format:
- Variable names should match the **original variable names** used in fitting (e.g., `D_EAI`, `D_GDP`)
- Currently uses generic names `y` and `x`
- Missing the NA placeholder for the forecast quarter GDP value

#### 2. **Lag Specification for Forecasting**

**Mexico_Midas.R:**
```r
eq_u_h1 <- midas_u(D_GDP ~ mls(D_GDP, 2,1) + mls(D_EAI, k = 4:6, m = 3))
```
- Uses lags 4:6 for monthly indicator (meaning months t-4, t-5, t-6)
- This represents using data from **previous quarters** plus the current quarter
- The `k` parameter specifies which months to use

**gpm_now/R/midas_models.R:**
```r
# Lines 60-64 in fit_midas_unrestricted()
if (y_lag == 0) {
    fit <- midasr::midas_u(y_q ~ midasr::mls(x_m, month_of_quarter:(month_of_quarter + x_lag), 3))
} else {
    fit <- midasr::midas_u(y_q ~ midasr::mls(y_q, 1:y_lag, 1) + 
                             midasr::mls(x_m, month_of_quarter:(month_of_quarter + x_lag), 3))
}
```

**PROBLEM 2:** The lag specification `month_of_quarter:(month_of_quarter + x_lag)` may not align properly with available data
- If `month_of_quarter = 2` (default) and `x_lag = 6`, this gives lags 2:8
- This might include future months that don't exist yet, causing NaN issues

#### 3. **Data Extraction for Forecast**

**gpm_now/R/midas_models.R:**
```r
# Lines 556-576 in extract_forecast_data()
extract_forecast_data <- function(vintage, ind_id, is_lagged = FALSE) {
    x_m <- extract_indicator_data(vintage, ind_id)
    
    if (is_lagged) {
        return(tail(x_m, 3))  # Last 3 months
    } else {
        last_obs <- tail(x_m, 3)
        if (length(last_obs) < 3) {
            last_obs <- c(last_obs, rep(NA, 3 - length(last_obs)))
        }
        return(last_obs)
    }
}
```

**PROBLEM 3:** This function doesn't account for **which months within the quarter** are actually available
- Should use the lag_map or vintage information to determine available months
- Padding with NA is correct, but the logic doesn't consider ragged-edge timing

#### 4. **Model Fitting with Time Series Objects**

**Mexico_Midas.R:**
```r
# Lines 86-92
mex_q_ts <- ts(mex_q, start = c(start_year, start_quarter), frequency = 4)
mex_m_ts <- ts(mex_m, start = c(start_year, start_month), frequency = 12)
```
- Uses proper `ts` objects with aligned start dates
- Ensures proper time alignment between quarterly and monthly data

**gpm_now implementations:**
- Use data frames or vectors without proper time series structure
- May cause alignment issues in midasr

---

## Task 2: Pseudo-Ragged Data Construction Analysis

### Current Implementation (01_build_pseudo_vintages.R)

The script creates vintages for **each Friday** within target quarters. Let me analyze the logic:

```r
# Lines 94-110
last_available_month <- function(var, test_date) {
  lag_days <- get_lag_days(var)
  releases <- data.table(date = monthly$date, 
                        est_release = month_end(monthly$date) + days(lag_days))
  avail <- releases[releases[["est_release"]] <= test_date]
  if (nrow(avail) == 0) return(as.Date(NA))
  max(avail$date)
}
```

**How it works:**
1. For each variable and test_date (Friday), it calculates when monthly data would be released
2. Release date = end of month + lag_days (from calendar)
3. Returns the last month whose data would be available by test_date

### Weekly Dataset Structure Verification

**Expected behavior (as you described):**
- **Week 1:** Previous month's complete data + Week 1 releases
- **Week 2:** Previous month's complete data + Week 1 & 2 releases
- **Week 3:** Previous month's complete data + Week 1, 2 & 3 releases  
- **Week 4:** Complete data for the entire quarter

**Actual implementation:**
```r
# Lines 119-131
for (i in seq_along(fridays)) {
    td <- fridays[i]
    avail_tbl <- rbindlist(lapply(indicators, function(v) {
        lm <- last_available_month(v, td)
        h <- if (is.na(lm)) NA_integer_ else interval(month_end(lm), month_end(q_end)) %/% months(1)
        data.table(variable = v, last_month = lm, horizon_months = as.integer(h))
    }), fill = TRUE)
    vintages[[i]] <- list(test_date = td, quarter = q, quarter_end = q_end, availability = avail_tbl)
}
```

### Issues Identified:

#### Issue 1: **No Actual Data Slicing**
The vintage structure only stores **metadata** about what's available:
- `last_month`: The last month with available data
- `horizon_months`: Months until quarter end

But it **does NOT store the actual data slices**. The data is filtered later when used, which could lead to inconsistencies.

#### Issue 2: **Per-Variable Timing Not Properly Handled**
Different variables have different release lags (`approx_lag_days` from calendar), but the downstream code may not properly handle this:

```r
# In 02_umidas_model_selection.R, line 258
vinfo <- get_vintage_info(var, q_t, idx)
if (is.na(vinfo$last_month) || is.na(vinfo$horizon)) next
h_ind <- vinfo$horizon
```

The `h_ind` (horizon) is used to specify lags, but the **actual data filtering** happens much later and may not respect the vintage boundaries properly.

#### Issue 3: **Cumulative Release Logic Missing**
The current implementation doesn't explicitly show cumulative behavior:
- Each Friday gets its own availability table
- But there's no guarantee that Friday 2 includes all data from Friday 1

**Verification needed:** Check if `last_available_month()` naturally produces cumulative behavior (it should, since it takes the max of all available dates up to test_date).

#### Issue 4: **Data Alignment in Model Fitting**

In `02_umidas_model_selection.R`, lines 250-280:
```r
# Build monthly series for indicator
mon_sub_cfg <- monthly[date >= hf_start_date & date <= hf_end_date][order(date)]
if (nrow(mon_sub_cfg) < needed_hf_len) next
indicator_vals_cfg <- mon_sub_cfg[[var]][seq_len(needed_hf_len)]
indicator_ts <- ts(indicator_vals_cfg, start = c(year(hf_start_date), month(hf_start_date)), frequency = 12)
```

**PROBLEM:** The data is filtered by `hf_end_date` which is `vinfo$last_month`, BUT:
1. This creates a ts object with the exact length needed
2. However, when NAs should exist (for unavailable future months), they're not explicitly added
3. The code assumes data exists up to `last_month`, but doesn't pad for the forecast quarter

---

## Root Causes of NaN Forecasts

Based on the analysis, the NaN forecasts are likely caused by:

### 1. **Incorrect newdata Structure in Forecasting**
The `predict_midas_unrestricted()` function doesn't create the newdata list in the format expected by midasr's `forecast()` function.

**Fix needed:**
```r
# Instead of:
newdata <- list(y = ..., x = ...)

# Should be:
newdata <- list(
    y_series_name = c(historical_y_values, NA),  # Include NA for forecast
    x_series_name = c(available_x_values, NA, NA, ...)  # Pad to 3 months
)
```

### 2. **Time Series Alignment Issues**
The code doesn't use proper ts objects consistently, leading to misalignment between quarterly and monthly data.

### 3. **Missing Data Not Properly Represented**
When forecasting, the code should explicitly add NAs for:
- The forecast quarter GDP value
- Unavailable months in the current quarter for monthly indicators

### 4. **Lag Specification May Reference Non-Existent Periods**
The lag range `month_of_quarter:(month_of_quarter + x_lag)` could reference future periods that don't exist in the data.

---

## Recommendations

### Immediate Fixes for NaN Issue:

1. **Fix `predict_midas_unrestricted()` in gpm_now/R/midas_models.R:**
   - Extract the actual variable names from the model formula
   - Create newdata with proper variable names
   - Include NA for forecast quarter GDP
   - Ensure x_new is exactly 3 values (available + NAs)

2. **Fix lag specification in `fit_midas_unrestricted()`:**
   - Review the lag specification logic
   - Ensure lags reference actually available historical data
   - Consider using the same pattern as Mexico_Midas (e.g., k=4:6)

3. **Improve data extraction:**
   - Use lag_map information to determine available months
   - Create proper ragged-edge data with NAs for unavailable months

### For Pseudo-Vintage Construction:

1. **Add explicit data slicing:**
   - Store actual data slices in each vintage, not just metadata
   - Ensure cumulative behavior is explicit

2. **Add validation:**
   - Verify that Week 2 contains all data from Week 1 + new releases
   - Add tests to ensure ragged-edge structure is correct

3. **Document the expected structure:**
   - Create examples showing what each week's dataset should contain
   - Add assertions to catch malformed vintages early

---

## Next Steps

1. **Test the original Mexico_Midas.R code** to confirm it produces non-NaN forecasts
2. **Create a minimal reproduction case** using gpm_now code with same data
3. **Apply the fixes** to predict_midas_unrestricted() function
4. **Add unit tests** for vintage construction to verify cumulative behavior
5. **Create diagnostic output** to show what data is being used for each forecast

Would you like me to implement any of these fixes?
