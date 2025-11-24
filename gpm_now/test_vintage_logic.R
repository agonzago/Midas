
# Test script for verifying pseudo-vintage generation logic
# This script mocks the logic found in gpm_now/midas_model_selection/code/01_build_pseudo_vintages.R

library(data.table)
library(lubridate)
library(testthat)

# --- Mock Functions from 01_build_pseudo_vintages.R ---

month_end <- function(d) as.Date(floor_date(d, unit = "month") + months(1) - days(1))

# Mock get_lag_days
get_lag_days <- function(var, lag_map) {
  if (var %in% names(lag_map)) return(as.integer(lag_map[[var]]))
  return(30L) # Default
}

# Core logic to test
get_available_data <- function(monthly_data, test_date, lag_map) {
  
  indicators <- setdiff(names(monthly_data), "date")
  
  # Calculate last available month for each indicator
  avail_list <- lapply(indicators, function(var) {
    lag_days <- get_lag_days(var, lag_map)
    
    # Calculate estimated release date for each data point
    # Logic: Release Date = End of Reference Month + Lag Days
    releases <- data.table(
      ref_date = monthly_data$date, 
      est_release = month_end(monthly_data$date) + days(lag_days)
    )
    
    # Filter what is released by test_date
    avail <- releases[est_release <= test_date]
    
    if (nrow(avail) == 0) return(NULL)
    
    last_month_date <- max(avail$ref_date)
    
    # Return the data slice
    var_data <- monthly_data[date <= last_month_date, .(date, value = get(var))]
    var_data[, variable := var]
    return(var_data)
  })
  
  rbindlist(avail_list)
}

# --- Test Cases ---

test_that("Vintage logic correctly respects lag days", {
  
  # Setup mock data
  # Reference dates: Jan, Feb, Mar 2024
  dates <- as.Date(c("2024-01-01", "2024-02-01", "2024-03-01"))
  monthly_data <- data.table(
    date = dates,
    VAR_A = c(10, 11, 12), # Lag 10 days
    VAR_B = c(20, 21, 22)  # Lag 40 days
  )
  
  lag_map <- list(VAR_A = 10, VAR_B = 40)
  
  # Case 1: Test Date = Feb 5th
  # VAR_A (Jan) released: Jan 31 + 10 = Feb 10. NOT AVAILABLE yet.
  # VAR_B (Jan) released: Jan 31 + 40 = Mar 11. NOT AVAILABLE yet.
  # Expected: Empty
  
  # WAIT: Logic check. 
  # Jan 2024 ends Jan 31.
  # VAR_A release: Jan 31 + 10 days = Feb 10.
  # If test_date is Feb 5, VAR_A(Jan) is NOT available.
  
  res1 <- get_available_data(monthly_data, as.Date("2024-02-05"), lag_map)
  expect_equal(nrow(res1), 0)
  
  # Case 2: Test Date = Feb 15th
  # VAR_A (Jan) released Feb 10. AVAILABLE.
  # VAR_B (Jan) released Mar 11. NOT AVAILABLE.
  
  res2 <- get_available_data(monthly_data, as.Date("2024-02-15"), lag_map)
  expect_true("VAR_A" %in% res2$variable)
  expect_false("VAR_B" %in% res2$variable)
  expect_equal(max(res2[variable == "VAR_A"]$date), as.Date("2024-01-01"))
  
  # Case 3: Test Date = Mar 15th
  # VAR_A (Feb) released: Feb 29 + 10 = Mar 10. AVAILABLE.
  # VAR_B (Jan) released: Jan 31 + 40 = Mar 11. AVAILABLE.
  
  res3 <- get_available_data(monthly_data, as.Date("2024-03-15"), lag_map)
  expect_true("VAR_A" %in% res3$variable)
  expect_true("VAR_B" %in% res3$variable)
  expect_equal(max(res3[variable == "VAR_A"]$date), as.Date("2024-02-01"))
  expect_equal(max(res3[variable == "VAR_B"]$date), as.Date("2024-01-01"))
  
})

test_that("Friday COB logic check", {
  # User requirement: "run on Monday with data released until the previous Friday"
  # The code uses `test_date` as the cutoff.
  # If we run for a Monday (e.g., Feb 12, 2024), we should pass the previous Friday (Feb 9, 2024) as test_date.
  
  dates <- as.Date(c("2024-01-01"))
  monthly_data <- data.table(date = dates, VAR_A = c(10))
  lag_map <- list(VAR_A = 10) # Release: Jan 31 + 10 = Feb 10 (Saturday)
  
  # If we run on Monday Feb 12, we use data up to Friday Feb 9.
  # Release is Feb 10 (Saturday).
  # Should NOT be available on Friday Feb 9.
  
  res <- get_available_data(monthly_data, as.Date("2024-02-09"), lag_map)
  expect_equal(nrow(res), 0)
  
  # If we run on Monday Feb 19, we use data up to Friday Feb 16.
  # Release Feb 10 is available.
  res2 <- get_available_data(monthly_data, as.Date("2024-02-16"), lag_map)
  expect_equal(nrow(res2), 1)
})

cat("Running tests...\n")
# Tests are executed as they are defined above.
cat("All tests completed.\n")
