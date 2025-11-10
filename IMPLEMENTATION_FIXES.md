# MIDAS Implementation Fixes - Summary

## Overview
This document summarizes the changes made to fix NaN forecasts in the gpm_now MIDAS implementation.

## Date: November 9, 2025

---

## Changes Made

### 1. Fixed `predict_midas_unrestricted()` Function (gpm_now/R/midas_models.R)

**Problem:** The function was using generic variable names ('y', 'x') instead of the actual variable names from the model formula, causing midasr's forecast() to fail.

**Solution:**
- Extract variable names from the fitted model's formula
- Use proper variable names when constructing the newdata list
- Include NA placeholder for the forecast period GDP value (as in Mexico_Midas.R)
- Ensure x_new is exactly 3 values (available data + NAs)

**Key Code Changes:**
```r
# Extract variable names from model
model_data <- model$fit$model
y_name <- names(model_data)[1]
# Extract X variable name from mls() call in formula
# ...

# Build newdata with proper names
newdata[[y_name]] <- c(y_hist, NA)  # Include NA for forecast
newdata[[x_name]] <- x_new  # 3 monthly values
```

### 2. Improved `extract_forecast_data()` Function (gpm_now/R/midas_models.R)

**Problem:** The function didn't properly handle ragged-edge data where some months are available and others aren't.

**Solution:**
- Added lag_map parameter for ragged-edge handling
- Implemented logic to check which months are available using lag_map information
- Properly pad with NAs for unavailable months
- Always return exactly 3 values (one quarter)

**Key Code Changes:**
```r
extract_forecast_data <- function(vintage, ind_id, is_lagged = FALSE, lag_map = NULL) {
  # Use lag_map to determine which months are available
  if (!is.null(lag_map) && ind_id %in% names(lag_map$indicators)) {
    available_months <- lag_map$indicators[[ind_id]]$available_months
    # Build forecast data based on availability
    # ...
  }
  # Always return 3 values
}
```

### 3. Enhanced Lag Specification Documentation (gpm_now/R/midas_models.R)

**Problem:** The lag specification logic needed better documentation to clarify how it works.

**Solution:**
- Added detailed comments explaining the lag specification
- Clarified that lags reference historical periods, not future
- Documented the month_of_quarter parameter meaning

**Key Comments Added:**
```r
# month_of_quarter specifies the ragged edge:
# - 0: end of quarter (all 3 months available)
# - 1: 2nd month of quarter available  
# - 2: 1st month of quarter available
# The lag specification should reference past data, not future
```

### 4. Improved Pseudo-Vintage Builder (gpm_now/midas_model_selection/code/01_build_pseudo_vintages.R)

**Problem:** Vintages stored only metadata (which months available) but not actual data slices, potentially causing inconsistencies.

**Solution:**
- Added explicit data slicing for each vintage
- Store both monthly_data and quarterly_data in each vintage
- Filter data by variable-specific release dates
- Added validation to check cumulative property (Week 2 should have more data than Week 1)

**Key Code Changes:**
```r
# Create actual data slices for this vintage
monthly_slice <- monthly[date <= td]

# For each variable, filter by its specific release date
monthly_vintage <- rbindlist(lapply(indicators, function(v) {
  var_avail <- avail_tbl[variable == v]
  last_month_date <- var_avail$last_month[1]
  var_data <- monthly_slice[date <= last_month_date, .(date, value = get(v))]
  # ...
}))

# Store both metadata and actual data
vintages[[i]] <- list(
  availability = avail_tbl,
  monthly_data = monthly_vintage,
  quarterly_data = quarterly_slice
)
```

### 5. Code Quality Improvements

**Fixed lint warnings:**
- Removed unused variable 'vars'
- Changed `1:min(...)` to `seq_len(min(...))` to avoid edge case issues
- Removed unused variable 'x_dates'

---

## Testing

Created test script: `gpm_now/test_midas_fixes.R`

**Tests included:**
1. Variable name extraction and proper newdata construction
2. Ragged-edge data extraction (with and without lag_map)
3. Lag specification in model fitting

**To run tests:**
```r
cd gpm_now
Rscript test_midas_fixes.R
```

---

## Expected Impact

These fixes should resolve the NaN forecasts by:

1. **Proper communication with midasr:** Using correct variable names ensures midasr can process the forecast request
2. **Correct data structure:** Including the NA placeholder for forecast period matches the expected format
3. **Better ragged-edge handling:** Properly identifying available vs. unavailable data prevents using invalid observations
4. **Explicit data slicing:** Storing actual data in vintages ensures consistency across the workflow

---

## Validation Checklist

To verify the fixes are working:

- [ ] Run test_midas_fixes.R - all tests should pass
- [ ] Run 01_build_pseudo_vintages.R - should see validation messages confirming cumulative behavior
- [ ] Run 02_umidas_model_selection.R - forecasts should be non-NaN
- [ ] Check that Week 2 datasets have more observations than Week 1
- [ ] Verify forecast values are reasonable (not NA, not extreme outliers)

---

## Next Steps

1. Test with actual Mexico data to ensure compatibility
2. Compare forecasts with original Mexico_Midas.R implementation
3. Add more comprehensive unit tests for edge cases
4. Document the expected vintage data structure
5. Consider adding diagnostic output to track which data is being used for each forecast

---

## Files Modified

1. `/home/andres/work/Midas/gpm_now/R/midas_models.R`
   - Fixed predict_midas_unrestricted()
   - Improved extract_forecast_data()
   - Enhanced documentation

2. `/home/andres/work/Midas/gpm_now/midas_model_selection/code/01_build_pseudo_vintages.R`
   - Added explicit data slicing
   - Added validation checks

3. `/home/andres/work/Midas/gpm_now/test_midas_fixes.R` (NEW)
   - Created test suite for verifying fixes

---

## References

- Original implementation: `/home/andres/work/Midas/Mexico_Midas.R`
- Analysis document: `/home/andres/work/Midas/MIDAS_ANALYSIS.md`
- midasr package documentation: https://github.com/mpiktas/midasr
