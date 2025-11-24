
# Validation script for Calendar Logic and New Lag Values
# Checks if the updated calendar values result in correct availability status
# based on the "Friday COB" rule.

library(data.table)
library(lubridate)
library(testthat)

# --- Helper Functions ---
month_end <- function(d) as.Date(floor_date(d, unit = "month") + months(1) - days(1))

# Load Calendar
calendar_path <- "gpm_now/retriever/Initial_calendar.csv"
if (!file.exists(calendar_path)) stop("Calendar file not found")
calendar <- fread(calendar_path)

# Helper to get lag
get_lag <- function(code) {
  val <- calendar[variable_code == code]$approx_lag_days
  if (length(val) == 0) return(NA)
  as.integer(val)
}

# Simulation Function
check_availability <- function(code, ref_month_str, run_date_str) {
  # ref_month_str: "2024-01"
  # run_date_str: "2024-02-12" (Monday) -> Effective Test Date: "2024-02-09" (Friday)
  
  ref_date <- as.Date(paste0(ref_month_str, "-01"))
  run_date <- as.Date(run_date_str)
  
  # "Run on Monday with data released until previous Friday"
  # If run_date is Monday, test_date = run_date - 3
  # If run_date is Friday, test_date = run_date
  # We assume the input run_date is the Monday execution date.
  
  # Simple logic: find previous Friday
  # wday: 1=Sun, 2=Mon, ..., 6=Fri, 7=Sat
  # If Mon (2), prev Fri is -3 days.
  
  test_date <- run_date - 3 # Assuming run_date is Monday
  
  lag <- get_lag(code)
  if (is.na(lag)) return("UNKNOWN_LAG")
  
  est_release <- month_end(ref_date) + days(lag)
  
  is_available <- est_release <= test_date
  
  return(list(
    code = code,
    ref_month = ref_month_str,
    run_date = run_date_str,
    test_date = as.character(test_date),
    lag = lag,
    est_release = as.character(est_release),
    available = is_available
  ))
}

# --- Test Scenarios ---

test_that("Updated Calendar Lags produce expected availability", {
  
  # Scenario 1: UMCSENT (Lag 0)
  # Ref: Jan 2024. End: Jan 31. Release: Jan 31.
  # Run: Monday Feb 5. Test: Friday Feb 2.
  # Release (Jan 31) <= Test (Feb 2) -> AVAILABLE
  res1 <- check_availability("UMCSENT", "2024-01", "2024-02-05")
  expect_true(res1$available)
  
  # Scenario 2: HOUST (Lag 18)
  # Ref: Jan 2024. End: Jan 31. Release: Jan 31 + 18 = Feb 18.
  # Run: Monday Feb 12. Test: Friday Feb 9.
  # Release (Feb 18) > Test (Feb 9) -> NOT AVAILABLE
  res2 <- check_availability("HOUST", "2024-01", "2024-02-12")
  expect_false(res2$available)
  
  # Run: Monday Feb 26. Test: Friday Feb 23.
  # Release (Feb 18) <= Test (Feb 23) -> AVAILABLE
  res3 <- check_availability("HOUST", "2024-01", "2024-02-26")
  expect_true(res3$available)
  
  # Scenario 3: IBGE Industrial Production (Lag 25) - 28503
  # Ref: Jan 2024. End: Jan 31. Release: Feb 25.
  # Run: Monday Feb 26. Test: Friday Feb 23.
  # Release (Feb 25) > Test (Feb 23) -> NOT AVAILABLE
  res4 <- check_availability("28503", "2024-01", "2024-02-26")
  expect_false(res4$available)
  
  # Run: Monday Mar 4. Test: Friday Mar 1.
  # Release (Feb 25) <= Test (Mar 1) -> AVAILABLE
  res5 <- check_availability("28503", "2024-01", "2024-03-04")
  expect_true(res5$available)
  
})

cat("Running calendar validation tests...\n")
# Tests are executed as they are defined above.
cat("All calendar tests completed.\n")
