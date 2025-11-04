# =============================================================================
# GPM NOW - Data Retriever Utilities
# General-purpose functions for data retrieval, validation, and storage
# =============================================================================

library(data.table)
library(dplyr)
library(lubridate)
library(zoo)
library(yaml)
library(jsonlite)

#' Check and install required packages
#' @param packages Vector of package names to check/install
check_install_packages <- function(packages) {
  for (pkg in packages) {
    if (!require(pkg, character.only = TRUE)) {
      cat("Installing package:", pkg, "\n")
      install.packages(pkg)
      library(pkg, character.only = TRUE)
    }
  }
}

#' Standardize date format across different sources
#' @param date_col Date column (various formats accepted)
#' @param freq Frequency: "monthly", "quarterly", "daily"
standardize_dates <- function(date_col, freq = "monthly") {
  
  # Convert to Date if not already
  if (!inherits(date_col, "Date")) {
    # Try different formats
    date_col <- tryCatch({
      as.Date(date_col)
    }, error = function(e) {
      # Try year-month format
      if (freq == "monthly") {
        as.Date(paste0(date_col, "-01"))
      } else if (freq == "quarterly") {
        # Handle quarterly formats like "2024Q1"
        if (grepl("Q", date_col[1])) {
          quarters_to_dates(date_col)
        } else {
          as.Date(date_col)
        }
      } else {
        as.Date(date_col)
      }
    })
  }
  
  return(date_col)
}

#' Convert quarterly strings to dates
#' @param quarters Vector like c("2024Q1", "2024Q2", ...)
quarters_to_dates <- function(quarters) {
  year_quarter <- strsplit(as.character(quarters), "Q")
  dates <- sapply(year_quarter, function(x) {
    year <- as.numeric(x[1])
    quarter <- as.numeric(x[2])
    month <- (quarter - 1) * 3 + 1
    as.Date(paste(year, sprintf("%02d", month), "01", sep = "-"))
  })
  return(as.Date(dates, origin = "1970-01-01"))
}

#' Validate data structure for nowcasting system
#' @param data Data frame with date and value columns
#' @param series_id Series identifier
#' @param freq Expected frequency
validate_data <- function(data, series_id, freq = "monthly") {
  
  errors <- character(0)
  warnings <- character(0)
  
  # Check required columns
  required_cols <- c("date", "value")
  if (!all(required_cols %in% names(data))) {
    missing_cols <- required_cols[!required_cols %in% names(data)]
    errors <- c(errors, paste("Missing required columns:", paste(missing_cols, collapse = ", ")))
  }
  
  # Check for missing values
  if (any(is.na(data$value))) {
    na_count <- sum(is.na(data$value))
    warnings <- c(warnings, paste("Found", na_count, "missing values"))
  }
  
  # Check date consistency
  if ("date" %in% names(data)) {
    if (!inherits(data$date, "Date")) {
      errors <- c(errors, "Date column is not in Date format")
    }
    
    # Check for duplicates
    if (any(duplicated(data$date))) {
      dup_count <- sum(duplicated(data$date))
      errors <- c(errors, paste("Found", dup_count, "duplicate dates"))
    }
    
    # Check frequency consistency
    if (freq == "monthly" && nrow(data) > 1) {
      date_diffs <- diff(data$date[order(data$date)])
      if (any(date_diffs < 25 | date_diffs > 35)) {
        warnings <- c(warnings, "Irregular monthly frequency detected")
      }
    }
  }
  
  # Return validation results
  list(
    valid = length(errors) == 0,
    errors = errors,
    warnings = warnings,
    series_id = series_id,
    n_obs = nrow(data),
    date_range = if ("date" %in% names(data)) range(data$date, na.rm = TRUE) else c(NA, NA)
  )
}

#' Save data to CSV with metadata
#' @param data Data frame to save
#' @param file_path Full path to CSV file
#' @param metadata List with series information
#' @param append_timestamp Whether to add timestamp to filename
save_data_csv <- function(data, file_path, metadata = NULL, append_timestamp = FALSE) {
  
  # Add timestamp to filename if requested
  if (append_timestamp) {
    file_parts <- strsplit(basename(file_path), "\\.")[[1]]
    timestamp <- format(Sys.time(), "%Y%m%d_%H%M%S")
    new_name <- paste0(file_parts[1], "_", timestamp, ".", file_parts[2])
    file_path <- file.path(dirname(file_path), new_name)
  }
  
  # Ensure directory exists
  dir.create(dirname(file_path), recursive = TRUE, showWarnings = FALSE)
  
  # Sort by date before saving
  if ("date" %in% names(data)) {
    data <- data[order(data$date), ]
  }
  
  # Write CSV
  write.csv(data, file_path, row.names = FALSE)
  
  # Save metadata as JSON if provided
  if (!is.null(metadata)) {
    metadata_path <- gsub("\\.csv$", "_metadata.json", file_path)
    metadata$saved_at <- Sys.time()
    metadata$file_path <- file_path
    write_json(metadata, metadata_path, auto_unbox = TRUE, pretty = TRUE)
  }
  
  cat("Data saved to:", file_path, "\n")
  if (!is.null(metadata)) {
    cat("Metadata saved to:", metadata_path, "\n")
  }
  
  return(file_path)
}

#' Load configuration from YAML
#' @param config_path Path to YAML configuration file
load_config <- function(config_path) {
  if (!file.exists(config_path)) {
    stop("Configuration file not found: ", config_path)
  }
  yaml::read_yaml(config_path)
}

#' Apply basic transformations to time series
#' @param x Numeric vector
#' @param transform Transformation type: "level", "log", "diff", "pct_change", "yoy", "mom"
#' @param freq Frequency for percentage calculations
apply_transformation <- function(x, transform = "level", freq = "monthly") {
  
  result <- switch(transform,
    "level" = x,
    "log" = log(x),
    "diff" = c(NA, diff(x)),
    "pct_change" = c(NA, diff(x) / x[-length(x)] * 100),
    "mom" = c(NA, diff(x) / x[-length(x)] * 100),  # Month-over-month
    "yoy" = {  # Year-over-year
      lags <- if (freq == "monthly") 12 else if (freq == "quarterly") 4 else 1
      if (length(x) > lags) {
        c(rep(NA, lags), (x[(lags+1):length(x)] / x[1:(length(x)-lags)] - 1) * 100)
      } else {
        rep(NA, length(x))
      }
    },
    x  # Default: return unchanged
  )
  
  return(result)
}

#' Create retrieval log entry
#' @param series_id Series identifier
#' @param source Data source (e.g., "BCB", "IBGE", "Ipea")
#' @param status Success status
#' @param n_obs Number of observations retrieved
#' @param date_range Date range of data
#' @param notes Additional notes
log_retrieval <- function(series_id, source, status, n_obs = NA, date_range = c(NA, NA), notes = "") {
  
  log_entry <- data.frame(
    timestamp = Sys.time(),
    series_id = series_id,
    source = source,
    status = status,
    n_obs = n_obs,
    start_date = date_range[1],
    end_date = date_range[2],
    notes = notes,
    stringsAsFactors = FALSE
  )
  
  return(log_entry)
}

#' Handle missing data with different strategies
#' @param data Data frame with date and value columns
#' @param method Method: "na", "forward_fill", "interpolate", "drop"
handle_missing_data <- function(data, method = "na") {
  
  if (!"value" %in% names(data)) {
    warning("No 'value' column found")
    return(data)
  }
  
  switch(method,
    "na" = data,  # Keep as is
    "forward_fill" = {
      data$value <- zoo::na.fill(data$value, "extend")
      data
    },
    "interpolate" = {
      data$value <- zoo::na.approx(data$value, na.rm = FALSE)
      data
    },
    "drop" = {
      data[!is.na(data$value), ]
    },
    data  # Default: return unchanged
  )
}

#' Print retrieval summary
#' @param results List of retrieval results
print_retrieval_summary <- function(results) {
  cat("\n=== Data Retrieval Summary ===\n")
  
  total_series <- length(results)
  successful <- sum(sapply(results, function(x) x$status == "success"))
  
  cat("Total series attempted:", total_series, "\n")
  cat("Successful retrievals:", successful, "\n")
  cat("Failed retrievals:", total_series - successful, "\n\n")
  
  # Print individual results
  for (result in results) {
    status_symbol <- if (result$status == "success") "✓" else "✗"
    cat(sprintf("%s %s: %s\n", status_symbol, result$series_id, result$notes))
  }
  
  cat("\n")
}