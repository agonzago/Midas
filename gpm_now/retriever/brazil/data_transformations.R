# =============================================================================
# Data Transformations Module
# Implements all required transformations for Brazilian economic data
# =============================================================================

library(dplyr)
library(zoo)
library(purrr)

#' Apply DA transformation: 100 * log differences  
#' @param x Numeric vector (time series)
#' @param na_fill How to handle leading NA: "drop", "zero", or "keep"
transform_DA <- function(x, na_fill = "keep") {
  
  if (length(x) < 2) {
    return(rep(NA, length(x)))
  }
  
  # Calculate 100 * (log(x_t) - log(x_{t-1}))
  log_x <- log(x)
  diff_log <- c(NA, diff(log_x))
  result <- 100 * diff_log
  
  # Handle NA values
  if (na_fill == "drop") {
    result <- result[!is.na(result)]
  } else if (na_fill == "zero") {
    result[is.na(result)] <- 0
  }
  
  return(result)
}

#' Apply DA3m transformation: 3-month growth rate  
#' Sum 3 months of current data vs sum of previous 3 months, then 100*log difference
#' @param x Numeric vector (monthly time series)
#' @param na_fill How to handle leading NAs
transform_DA3m <- function(x, na_fill = "keep") {
  
  if (length(x) < 6) {  # Need at least 6 observations for 3m vs 3m comparison
    return(rep(NA, length(x)))
  }
  
  # Create 3-month rolling sums
  x_3m_current <- zoo::rollsum(x, k = 3, align = "right", fill = NA)
  
  # Shift by 3 to get previous 3-month sum
  x_3m_previous <- c(rep(NA, 3), x_3m_current[1:(length(x_3m_current) - 3)])
  
  # Calculate 100 * log(current_3m / previous_3m)
  result <- 100 * log(x_3m_current / x_3m_previous)
  
  # Handle NA values
  if (na_fill == "drop") {
    result <- result[!is.na(result)]
  } else if (na_fill == "zero") {
    result[is.na(result)] <- 0
  }
  
  return(result)
}

#' Apply log_dm transformation: log(x) - mean(log(x))
#' @param x Numeric vector
#' @param na_rm Remove NAs when calculating mean
transform_log_dm <- function(x, na_rm = TRUE) {
  
  log_x <- log(x)
  mean_log_x <- mean(log_x, na.rm = na_rm)
  
  result <- log_x - mean_log_x
  
  return(result)
}

#' Apply dm transformation: x - mean(x) (demean)
#' @param x Numeric vector  
#' @param na_rm Remove NAs when calculating mean
transform_dm <- function(x, na_rm = TRUE) {
  
  mean_x <- mean(x, na.rm = na_rm)
  result <- x - mean_x
  
  return(result)
}

#' Apply 3m transformation: 3-month moving average
#' Current month + previous 2 months, divided by 3
#' @param x Numeric vector (monthly time series)
transform_3m <- function(x) {
  
  if (length(x) < 3) {
    return(rep(NA, length(x)))
  }
  
  # 3-month moving average (current + previous 2)
  result <- zoo::rollmean(x, k = 3, align = "right", fill = NA)
  
  return(result)
}

#' Apply SA transformation: Seasonal adjustment (placeholder)
#' @param x Numeric vector (monthly time series)
#' @param method Seasonal adjustment method
transform_SA <- function(x, method = "x13") {
  
  # For now, return the original series
  # In production, implement proper seasonal adjustment
  # using X-13ARIMA-SEATS or similar
  
  warning("SA transformation not yet implemented. Returning original series.")
  return(x)
}

#' Main transformation function - applies transformation based on string specification
#' @param x Numeric vector (time series data)
#' @param transform_spec Transformation specification string (e.g., "DA", "DA3m", "log_dm", etc.)
#' @param date_col Optional date vector for time series context
apply_transformation <- function(x, transform_spec, date_col = NULL) {
  
  # Handle multiple transformations separated by commas
  transforms <- trimws(strsplit(transform_spec, ",")[[1]])
  
  # Apply each transformation in sequence
  result <- x
  transform_names <- c()
  
  for (transform in transforms) {
    
    transform <- trimws(transform)
    transform_names <- c(transform_names, transform)
    
    result <- switch(transform,
      "DA" = transform_DA(result),
      "DA3m" = transform_DA3m(result), 
      "log_dm" = transform_log_dm(result),
      "dm" = transform_dm(result),
      "3m" = transform_3m(result),
      "SA" = transform_SA(result),
      {
        warning(paste("Unknown transformation:", transform, ". Skipping."))
        result
      }
    )
  }
  
  # Add attributes for tracking
  attr(result, "transformations") <- transform_names
  attr(result, "original_length") <- length(x)
  attr(result, "final_length") <- length(result)
  
  return(result)
}

#' Transform a complete dataset based on specifications
#' @param data Data frame with columns: date, value, series_id
#' @param transform_specs Named list or data frame with series_id -> transformation mapping
#' @param keep_original Whether to keep original values alongside transformed
transform_dataset <- function(data, transform_specs, keep_original = TRUE) {
  
  # Ensure data is sorted by date within each series
  data <- data %>%
    arrange(.data$series_id, .data$date)
  
  # Split by series and apply transformations
  transformed_list <- data %>%
    split(data$series_id) %>%
    purrr::map(~{
      series_id <- unique(.x$series_id)
      
      # Get transformation specification
      if (is.data.frame(transform_specs)) {
        spec_row <- transform_specs[transform_specs$Name == series_id | 
                                   transform_specs$series_id == series_id, ]
        if (nrow(spec_row) > 0) {
          transform_spec <- spec_row$Transformation[1]
        } else {
          transform_spec <- "none"
        }
      } else if (is.list(transform_specs)) {
        transform_spec <- transform_specs[[series_id]] %||% "none"
      } else {
        transform_spec <- "none"
      }
      
      # Apply transformation
      if (transform_spec != "none" && !is.na(transform_spec)) {
        
        transformed_values <- apply_transformation(.x$value, transform_spec, .x$date)
        
        # Create result data frame
        result <- .x
        
        if (keep_original) {
          result$value_original <- result$value
          result$value <- transformed_values
          result$transformation <- transform_spec
        } else {
          result$value <- transformed_values
          result$transformation <- transform_spec
        }
        
      } else {
        result <- .x
        result$transformation <- "none"
        if (keep_original) {
          result$value_original <- result$value
        }
      }
      
      return(result)
    })
  
  # Combine back into single data frame
  transformed_data <- bind_rows(transformed_list)
  
  return(transformed_data)
}

#' Validate transformation results
#' @param original_data Original data frame
#' @param transformed_data Transformed data frame  
validate_transformations <- function(original_data, transformed_data) {
  
  validation_results <- list()
  
  # Check series coverage
  orig_series <- unique(original_data$series_id)
  trans_series <- unique(transformed_data$series_id)
  
  validation_results$missing_series <- setdiff(orig_series, trans_series)
  validation_results$extra_series <- setdiff(trans_series, orig_series)
  
  # Check for each series
  series_validation <- list()
  
  for (series in orig_series) {
    
    orig_subset <- original_data[original_data$series_id == series, ]
    trans_subset <- transformed_data[transformed_data$series_id == series, ]
    
    series_validation[[series]] <- list(
      original_obs = nrow(orig_subset),
      transformed_obs = nrow(trans_subset),
      missing_values_original = sum(is.na(orig_subset$value)),
      missing_values_transformed = sum(is.na(trans_subset$value)),
      transformation_applied = if(nrow(trans_subset) > 0) trans_subset$transformation[1] else "none"
    )
  }
  
  validation_results$series_details <- series_validation
  
  return(validation_results)
}

#' Helper function for null coalescing
`%||%` <- function(x, y) if (is.null(x)) y else x

#' Print transformation summary
#' @param validation_results Output from validate_transformations()
print_transformation_summary <- function(validation_results) {
  
  cat("=== Transformation Summary ===\n")
  cat("Series processed:", length(validation_results$series_details), "\n")
  
  if (length(validation_results$missing_series) > 0) {
    cat("Missing series:", paste(validation_results$missing_series, collapse = ", "), "\n")
  }
  
  if (length(validation_results$extra_series) > 0) {
    cat("Extra series:", paste(validation_results$extra_series, collapse = ", "), "\n")
  }
  
  cat("\nSeries details:\n")
  for (series in names(validation_results$series_details)) {
    details <- validation_results$series_details[[series]]
    cat(sprintf("  %s: %s -> %d obs (was %d), transform: %s\n",
               series,
               if(details$missing_values_transformed > details$missing_values_original) "✓" else "?",
               details$transformed_obs,
               details$original_obs,
               details$transformation_applied))
  }
}

# =============================================================================
# Example usage and testing functions
# =============================================================================

#' Test all transformation functions with sample data
test_transformations <- function() {
  
  cat("=== Testing Transformation Functions ===\n")
  
  # Create sample monthly data (2 years)
  set.seed(123)
  dates <- seq.Date(from = as.Date("2022-01-01"), by = "month", length.out = 24)
  
  # Simulated economic indicator (with trend and seasonality)
  trend <- 100 + 0.5 * seq_along(dates)
  seasonal <- 5 * sin(2 * pi * seq_along(dates) / 12)
  noise <- rnorm(length(dates), 0, 2)
  values <- trend + seasonal + noise
  
  cat("Original data (first 6 values):", head(values), "\n")
  
  # Test DA transformation
  da_result <- transform_DA(values)
  cat("DA transformation (first 6):", head(da_result), "\n")
  
  # Test DA3m transformation  
  da3m_result <- transform_DA3m(values)
  cat("DA3m transformation (first 6):", head(da3m_result), "\n")
  
  # Test 3m transformation
  ma3_result <- transform_3m(values)
  cat("3m moving average (first 6):", head(ma3_result), "\n")
  
  # Test log_dm transformation
  logdm_result <- transform_log_dm(values)
  cat("log_dm transformation (first 6):", head(logdm_result), "\n")
  
  # Test dm transformation
  dm_result <- transform_dm(values)
  cat("dm transformation (first 6):", head(dm_result), "\n")
  
  cat("All transformation tests completed.\n")
}

# Run tests if this file is sourced directly
if (interactive() && !exists("transformations_loaded")) {
  transformations_loaded <- TRUE
  cat("Data transformation functions loaded successfully.\n")
  cat("Run test_transformations() to test all functions.\n")
}