# =============================================================================
# Main Data Retrieval Orchestration System
# Coordinates downloading, storing, loading, and transforming Brazilian economic data
# =============================================================================

# Source required modules
source("config_reader.R")
source("data_transformations.R")
source("retriever.R")

# Load required libraries
library(readODS)
library(dplyr)
library(GetBCBData)
library(ipeadatar)
library(fredr)
library(lubridate)
library(jsonlite)

#' Main data retrieval orchestration function
#' @param config_file Path to ODS configuration file
#' @param start_date Start date for data retrieval (YYYY-MM-DD) - NULL for earliest available
#' @param end_date End date for data retrieval (YYYY-MM-DD)  
#' @param raw_data_dir Directory to store raw downloaded data
#' @param processed_data_dir Directory to store transformed data
#' @param validate_apis Whether to validate API codes before downloading
#' @param apply_transformations Whether to apply specified transformations
#' @param save_intermediate Whether to save intermediate steps
main_data_retrieval <- function(config_file = "data_to_retrive.ods",
                               start_date = NULL,  # NULL means earliest available
                               end_date = Sys.Date(),
                               raw_data_dir = "raw_data",
                               processed_data_dir = "processed_data", 
                               validate_apis = FALSE,
                               apply_transformations = TRUE,
                               save_intermediate = TRUE) {
  
  cat("=== Brazilian Economic Data Retrieval System ===\n")
  cat("Start time:", format(Sys.time()), "\n")
  cat("Configuration file:", config_file, "\n")
  date_range_msg <- if(is.null(start_date)) {
    paste("Date range: EARLIEST AVAILABLE to", end_date, "(Full Historical Data)")
  } else {
    paste("Date range:", start_date, "to", end_date)
  }
  cat(date_range_msg, "\n\n")
  
  # Create directories
  dir.create(raw_data_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(processed_data_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Step 1: Read and validate configuration
  cat("Step 1: Reading configuration...\n")
  config <- read_data_config(config_file, validate_codes = validate_apis)
  print_config_summary(config)
  
  # Check required packages
  if (!check_required_packages(config)) {
    stop("Missing required packages. Please install them first.")
  }
  
  # Step 2: Download raw data by source
  cat("Step 2: Downloading raw data...\n")
  raw_data_results <- download_all_sources(config, start_date, end_date, raw_data_dir)
  
  # Step 3: Combine and standardize raw data
  cat("Step 3: Combining and standardizing data...\n")
  combined_raw_data <- combine_raw_data(raw_data_results, config)
  
  if (save_intermediate) {
    raw_combined_path <- file.path(processed_data_dir, "combined_raw_data.csv")
    write.csv(combined_raw_data, raw_combined_path, row.names = FALSE)
    cat("Combined raw data saved to:", raw_combined_path, "\n")
  }
  
  # Step 4: Apply transformations
  if (apply_transformations) {
    cat("Step 4: Applying transformations...\n")
    transformed_data <- apply_all_transformations(combined_raw_data, config)
    
    # Validate transformations
    validation_results <- validate_transformations(combined_raw_data, transformed_data)
    print_transformation_summary(validation_results)
    
  } else {
    cat("Step 4: Skipping transformations (disabled)\n")
    transformed_data <- combined_raw_data
    transformed_data$transformation <- "none"
  }
  
  # Step 5: Save final datasets
  cat("Step 5: Saving final datasets...\n")
  final_results <- save_final_datasets(transformed_data, config, processed_data_dir)
  
  # Step 6: Generate summary report
  cat("Step 6: Generating summary report...\n")
  summary_report <- generate_summary_report(config, raw_data_results, transformed_data, 
                                          validation_results, final_results)
  
  # Save summary report
  report_path <- file.path(processed_data_dir, paste0("retrieval_report_", format(Sys.Date(), "%Y%m%d"), ".json"))
  write_json(summary_report, report_path, auto_unbox = TRUE, pretty = TRUE)
  cat("Summary report saved to:", report_path, "\n")
  
  cat("\n=== Data Retrieval Completed Successfully ===\n")
  cat("End time:", format(Sys.time()), "\n")
  
  return(list(
    config = config,
    raw_data = combined_raw_data,
    transformed_data = transformed_data,
    validation = if(apply_transformations) validation_results else NULL,
    summary = summary_report,
    file_paths = final_results
  ))
}

#' Download data from all configured sources
#' @param config Configuration object from read_data_config()
#' @param start_date Start date
#' @param end_date End date
#' @param raw_data_dir Output directory
download_all_sources <- function(config, start_date, end_date, raw_data_dir) {
  
  sources <- unique(config$config$api_source)
  results <- list()
  
  for (source in sources) {
    
    cat("Downloading from", source, "...\n")
    
    if (source == "bcb") {
      results[[source]] <- download_bcb_variables(config, start_date, end_date, raw_data_dir)
    } else if (source == "ipeadata") {
      results[[source]] <- download_ipea_variables(config, start_date, end_date, raw_data_dir)
    } else if (source == "fred") {
      results[[source]] <- download_fred_variables(config, start_date, end_date, raw_data_dir)
    } else if (source == "static_csv") {
      results[[source]] <- download_static_csv_variables(config, start_date, end_date, raw_data_dir)
    } else {
      cat("  Warning: Unknown source", source, "- skipping\n")
    }
  }
  
  return(results)
}

#' Download BCB variables based on configuration
#' @param config Configuration object
#' @param start_date Start date
#' @param end_date End date  
#' @param raw_data_dir Output directory
download_bcb_variables <- function(config, start_date, end_date, raw_data_dir) {
  
  bcb_vars <- get_variables_by_source(config, "bcb")
  
  if (nrow(bcb_vars) == 0) {
    cat("  No BCB variables configured\n")
    return(NULL)
  }
  
  cat("  Downloading", nrow(bcb_vars), "BCB variables...\n")
  
  bcb_results <- list()
  
  for (i in seq_len(nrow(bcb_vars))) {
    var <- bcb_vars[i, ]
    
    cat("    ", var$Name, "(", var$Code, ")...\n")
    
    tryCatch({
      # Download data - use earliest available if start_date is NULL
      raw_data <- gbcbd_get_series(
        id = as.numeric(var$Code),
        first.date = if(is.null(start_date)) "1900-01-01" else start_date,  # BCB will return from earliest available
        last.date = end_date
      )
      
      if (nrow(raw_data) > 0) {
        # Standardize format
        std_data <- data.frame(
          date = as.Date(raw_data$ref.date),
          value = as.numeric(raw_data$value),
          series_id = var$Name,
          source = "bcb",
          api_code = var$Code,
          stringsAsFactors = FALSE
        )
        
        # Save raw data
        raw_file <- file.path(raw_data_dir, paste0(var$Name, "_raw.csv"))
        write.csv(std_data, raw_file, row.names = FALSE)
        
        bcb_results[[var$Name]] <- list(
          data = std_data,
          status = "success",
          file_path = raw_file,
          n_obs = nrow(std_data)
        )
        
        cat("      ✓ Downloaded", nrow(std_data), "observations\n")
        
      } else {
        cat("      ✗ No data returned\n")
        bcb_results[[var$Name]] <- list(data = NULL, status = "no_data")
      }
      
    }, error = function(e) {
      cat("      ✗ Error:", e$message, "\n")
      bcb_results[[var$Name]] <- list(data = NULL, status = "error", error = e$message)
    })
    
    # Rate limiting
    Sys.sleep(0.3)
  }
  
  return(bcb_results)
}

#' Download Ipeadata variables based on configuration
#' @param config Configuration object
#' @param start_date Start date
#' @param end_date End date
#' @param raw_data_dir Output directory  
download_ipea_variables <- function(config, start_date, end_date, raw_data_dir) {
  
  ipea_vars <- get_variables_by_source(config, "ipeadata")
  
  if (nrow(ipea_vars) == 0) {
    cat("  No Ipeadata variables configured\n")
    return(NULL)
  }
  
  cat("  Downloading", nrow(ipea_vars), "Ipeadata variables...\n")
  
  ipea_results <- list()
  
  for (i in seq_len(nrow(ipea_vars))) {
    var <- ipea_vars[i, ]
    
    cat("    ", var$Name, "(", var$Code, ")...\n")
    
    tryCatch({
      # Download data
      raw_data <- ipeadata(var$Code)
      
      if (!is.null(raw_data) && nrow(raw_data) > 0) {
        
        # Filter by date range - use all data if start_date is NULL
        if (is.null(start_date)) {
          filtered_data <- raw_data %>%
            filter(.data$date <= as.Date(end_date))
        } else {
          filtered_data <- raw_data %>%
            filter(
              .data$date >= as.Date(start_date),
              .data$date <= as.Date(end_date)
            )
        }
        
        if (nrow(filtered_data) > 0) {
          # Standardize format
          std_data <- data.frame(
            date = as.Date(filtered_data$date),
            value = as.numeric(filtered_data$value),
            series_id = var$Name,
            source = "ipeadata",
            api_code = var$Code,
            stringsAsFactors = FALSE
          )
          
          # Remove missing values
          std_data <- std_data[!is.na(std_data$value), ]
          
          if (nrow(std_data) > 0) {
            # Save raw data
            raw_file <- file.path(raw_data_dir, paste0(var$Name, "_raw.csv"))
            write.csv(std_data, raw_file, row.names = FALSE)
            
            ipea_results[[var$Name]] <- list(
              data = std_data,
              status = "success",
              file_path = raw_file,
              n_obs = nrow(std_data)
            )
            
            cat("      ✓ Downloaded", nrow(std_data), "observations\n")
          } else {
            cat("      ✗ No valid data in date range\n")
            ipea_results[[var$Name]] <- list(data = NULL, status = "no_valid_data")
          }
        } else {
          cat("      ✗ No data in specified date range\n") 
          ipea_results[[var$Name]] <- list(data = NULL, status = "no_data_in_range")
        }
      } else {
        cat("      ✗ No data returned\n")
        ipea_results[[var$Name]] <- list(data = NULL, status = "no_data")
      }
      
    }, error = function(e) {
      cat("      ✗ Error:", e$message, "\n")
      ipea_results[[var$Name]] <- list(data = NULL, status = "error", error = e$message)
    })
    
    # Rate limiting
    Sys.sleep(0.3)
  }
  
  return(ipea_results)
}

#' Download FRED variables based on configuration
#' @param config Configuration object
#' @param start_date Start date
#' @param end_date End date
#' @param raw_data_dir Output directory  
download_fred_variables <- function(config, start_date, end_date, raw_data_dir) {
  
  fred_vars <- get_variables_by_source(config, "fred")
  
  if (nrow(fred_vars) == 0) {
    cat("  No FRED variables configured\n")
    return(NULL)
  }
  
  cat("  Downloading", nrow(fred_vars), "FRED variables...\n")
  
  # Set FRED API key
  api_key <- Sys.getenv("FRED_API_KEY")
  if (nchar(api_key) == 0) {
    cat("  ✗ FRED API key not found in environment\n")
    return(NULL)
  }
  
  fredr_set_key(api_key)
  
  fred_results <- list()
  
  for (i in seq_len(nrow(fred_vars))) {
    var <- fred_vars[i, ]
    
    cat("    ", var$Name, "(", var$Code, ")...\n")
    
    tryCatch({
      # Download data - FRED handles date ranges automatically
      if (is.null(start_date)) {
        # Get all available data
        raw_data <- fredr(
          series_id = var$Code,
          observation_end = as.Date(end_date)
        )
      } else {
        # Get data from specific start date
        raw_data <- fredr(
          series_id = var$Code,
          observation_start = as.Date(start_date),
          observation_end = as.Date(end_date)
        )
      }
      
      if (!is.null(raw_data) && nrow(raw_data) > 0) {
        
        # Remove missing values
        raw_data <- raw_data[!is.na(raw_data$value), ]
        
        if (nrow(raw_data) > 0) {
          # Standardize format
          std_data <- data.frame(
            date = as.Date(raw_data$date),
            value = as.numeric(raw_data$value),
            series_id = var$Name,
            source = "fred",
            api_code = var$Code,
            stringsAsFactors = FALSE
          )
          
          # Save raw data
          raw_file <- file.path(raw_data_dir, paste0(var$Name, "_raw.csv"))
          write.csv(std_data, raw_file, row.names = FALSE)
          
          fred_results[[var$Name]] <- list(
            data = std_data,
            status = "success",
            file_path = raw_file,
            n_obs = nrow(std_data)
          )
          
          cat("      ✓ Downloaded", nrow(std_data), "observations\n")
        } else {
          cat("      ✗ No valid data after removing NAs\n")
          fred_results[[var$Name]] <- list(data = NULL, status = "no_valid_data")
        }
      } else {
        cat("      ✗ No data returned\n")
        fred_results[[var$Name]] <- list(data = NULL, status = "no_data")
      }
      
    }, error = function(e) {
      cat("      ✗ Error:", e$message, "\n")
      fred_results[[var$Name]] <- list(data = NULL, status = "error", error = e$message)
    })
    
    # Rate limiting for FRED API
    Sys.sleep(0.2)
  }
  
  return(fred_results)
}

#' Download static CSV variables based on configuration
#' @param config Configuration object
#' @param start_date Start date
#' @param end_date End date
#' @param raw_data_dir Output directory  
download_static_csv_variables <- function(config, start_date, end_date, raw_data_dir) {
  
  csv_vars <- get_variables_by_source(config, "static_csv")
  
  if (nrow(csv_vars) == 0) {
    cat("  No static CSV variables configured\n")
    return(NULL)
  }
  
  cat("  Loading", nrow(csv_vars), "static CSV variables...\n")
  
  csv_results <- list()
  
  # PMI Code mapping from user codes to S223* codes in CSV
  pmi_mapping <- list(
    "PMI_MFG" = "S223MG.MKTPMI",
    "PMI_OUT" = "S223MO.MKTPMI", 
    "PMI_NO" = "S223ME.MKTPMI",
    "PMI_NEO" = "S223MX.MKTPMI", 
    "PMI_FOUT" = "S223MSF.MKTPMI",
    "PMI_BCK" = "S223MB.MKTPMI",
    "PMI_EMP" = "S223ME.MKTPMI", 
    "PMI_QP" = "S223MQP.MKTPMI",
    "PMI_SDT" = "S223MD.MKTPMI",
    "PMI_SP" = "S223MSP.MKTPMI",
    "PMI_SFG" = "S223MSF.MKTPMI",
    "PMI_IP" = "S223MPI.MKTPMI",
    "PMI_OP" = "S223MPO.MKTPMI"
  )
  
  # Read the PMI CSV file
  csv_file <- "static_csv/Brazil_PMI.csv"
  
  if (!file.exists(csv_file)) {
    cat("  ✗ CSV file not found:", csv_file, "\n")
    return(NULL)
  }
  
  tryCatch({
    # Read the CSV file
    raw_csv <- read.csv(csv_file, stringsAsFactors = FALSE)
    
    cat("  ✓ Loaded CSV file with", nrow(raw_csv), "rows and", ncol(raw_csv), "columns\n")
    
    # Process each configured variable
    for (i in seq_len(nrow(csv_vars))) {
      var <- csv_vars[i, ]
      
      cat("    ", var$Name, "(", var$Code, ")...\n")
      
      # Map user code to actual CSV column name
      actual_code <- pmi_mapping[[var$Code]]
      if (is.null(actual_code)) {
        cat("      ✗ No mapping found for code:", var$Code, "\n")
        csv_results[[var$Name]] <- list(data = NULL, status = "no_mapping")
        next
      }
      
      # Find the column that matches the actual code
      matching_cols <- grep(actual_code, names(raw_csv), value = TRUE, fixed = TRUE)
      
      if (length(matching_cols) == 0) {
        cat("      ✗ Column not found in CSV:", actual_code, "\n")
        csv_results[[var$Name]] <- list(data = NULL, status = "column_not_found")
        next
      }
      
      # Use the first matching column
      data_col <- matching_cols[1]
      
      # Extract time series data (skip metadata rows)
      # Look for rows that start with dates (YYYYMM format)
      date_rows <- grep("^[0-9]{6}$", raw_csv[[1]])
      
      if (length(date_rows) == 0) {
        cat("      ✗ No date rows found\n")
        csv_results[[var$Name]] <- list(data = NULL, status = "no_date_rows")
        next
      }
      
      # Extract the data
      ts_data <- raw_csv[date_rows, ]
      
      # Convert dates and values
      dates <- as.Date(paste0(ts_data[[1]], "01"), format = "%Y%m%d")
      values <- as.numeric(ts_data[[data_col]])
      
      # Remove missing values
      valid_idx <- !is.na(values) & !is.na(dates)
      
      if (sum(valid_idx) == 0) {
        cat("      ✗ No valid data points\n")
        csv_results[[var$Name]] <- list(data = NULL, status = "no_valid_data")
        next
      }
      
      # Filter by date range if specified
      if (!is.null(start_date)) {
        date_filter <- dates >= as.Date(start_date) & dates <= as.Date(end_date)
        valid_idx <- valid_idx & date_filter
      } else {
        date_filter <- dates <= as.Date(end_date)
        valid_idx <- valid_idx & date_filter
      }
      
      if (sum(valid_idx) == 0) {
        cat("      ✗ No data in specified date range\n")
        csv_results[[var$Name]] <- list(data = NULL, status = "no_data_in_range")
        next
      }
      
      # Create standardized data frame
      std_data <- data.frame(
        date = dates[valid_idx],
        value = values[valid_idx],
        series_id = var$Name,
        source = "static_csv",
        api_code = var$Code,
        stringsAsFactors = FALSE
      )
      
      # Save raw data
      raw_file <- file.path(raw_data_dir, paste0(var$Name, "_raw.csv"))
      write.csv(std_data, raw_file, row.names = FALSE)
      
      csv_results[[var$Name]] <- list(
        data = std_data,
        status = "success",
        file_path = raw_file,
        n_obs = nrow(std_data)
      )
      
      cat("      ✓ Loaded", nrow(std_data), "observations\n")
    }
    
  }, error = function(e) {
    cat("  ✗ Error reading CSV file:", e$message, "\n")
    return(NULL)
  })
  
  return(csv_results)
}

#' Combine raw data from all sources into standardized format
#' @param raw_data_results Results from download_all_sources()
#' @param config Configuration object
combine_raw_data <- function(raw_data_results, config) {
  
  all_data <- list()
  
  for (source in names(raw_data_results)) {
    source_data <- raw_data_results[[source]]
    
    if (!is.null(source_data)) {
      for (var_name in names(source_data)) {
        var_result <- source_data[[var_name]]
        
        if (var_result$status == "success" && !is.null(var_result$data)) {
          all_data[[var_name]] <- var_result$data
        }
      }
    }
  }
  
  if (length(all_data) == 0) {
    stop("No data was successfully downloaded")
  }
  
  # Combine all data
  combined_data <- bind_rows(all_data)
  
  # Sort by series and date
  combined_data <- combined_data %>%
    arrange(.data$series_id, .data$date)
  
  cat("Combined data: ", nrow(combined_data), "observations from", 
      length(unique(combined_data$series_id)), "variables\n")
  
  return(combined_data)
}

#' Apply transformations to all variables based on configuration
#' @param raw_data Combined raw data
#' @param config Configuration object
apply_all_transformations <- function(raw_data, config) {
  
  # Get transformation specifications
  transform_specs <- config$config %>%
    select(.data$Name, .data$Transformation) %>%
    distinct()
  
  # Apply transformations using the transform_dataset function
  transformed_data <- transform_dataset(raw_data, transform_specs, keep_original = TRUE)
  
  return(transformed_data)
}

#' Save final processed datasets
#' @param transformed_data Transformed data
#' @param config Configuration object
#' @param output_dir Output directory
save_final_datasets <- function(transformed_data, config, output_dir) {
  
  file_paths <- list()
  
  # Save complete transformed dataset
  complete_path <- file.path(output_dir, "transformed_data_complete.csv")
  write.csv(transformed_data, complete_path, row.names = FALSE)
  file_paths$complete <- complete_path
  cat("Complete transformed dataset saved to:", complete_path, "\n")
  
  # Save by variable (wide format for analysis)
  wide_data <- transformed_data %>%
    select(.data$date, .data$series_id, .data$value) %>%
    tidyr::pivot_wider(names_from = .data$series_id, values_from = .data$value)
  
  wide_path <- file.path(output_dir, "transformed_data_wide.csv")
  write.csv(wide_data, wide_path, row.names = FALSE)
  file_paths$wide <- wide_path
  cat("Wide format dataset saved to:", wide_path, "\n")
  
  # Save metadata
  metadata <- config$config %>%
    select(.data$Name, .data$`Long Name`, .data$units, .data$Transformation, 
           .data$api_source, .data$Code) %>%
    distinct()
  
  metadata_path <- file.path(output_dir, "variable_metadata.csv")
  write.csv(metadata, metadata_path, row.names = FALSE)
  file_paths$metadata <- metadata_path
  cat("Variable metadata saved to:", metadata_path, "\n")
  
  return(file_paths)
}

#' Generate comprehensive summary report
#' @param config Configuration object
#' @param raw_data_results Raw download results
#' @param transformed_data Final transformed data
#' @param validation_results Transformation validation
#' @param final_results File paths
generate_summary_report <- function(config, raw_data_results, transformed_data, 
                                  validation_results, final_results) {
  
  # Count successes and failures
  total_configured <- nrow(config$config)
  successful_downloads <- 0
  failed_downloads <- 0
  
  for (source in names(raw_data_results)) {
    if (!is.null(raw_data_results[[source]])) {
      for (var in names(raw_data_results[[source]])) {
        if (raw_data_results[[source]][[var]]$status == "success") {
          successful_downloads <- successful_downloads + 1
        } else {
          failed_downloads <- failed_downloads + 1
        }
      }
    }
  }
  
  report <- list(
    timestamp = Sys.time(),
    configuration = list(
      total_variables = total_configured,
      by_source = table(config$config$api_source),
      by_transformation = table(config$config$Transformation)
    ),
    download_results = list(
      successful = successful_downloads,
      failed = failed_downloads,
      success_rate = round(successful_downloads / (successful_downloads + failed_downloads) * 100, 1)
    ),
    final_dataset = list(
      total_observations = nrow(transformed_data),
      variables = length(unique(transformed_data$series_id)),
      date_range = range(transformed_data$date, na.rm = TRUE)
    ),
    file_paths = final_results
  )
  
  if (!is.null(validation_results)) {
    report$transformation_validation <- validation_results
  }
  
  return(report)
}

# =============================================================================
# Convenience functions
# =============================================================================

#' Quick setup - download and process all configured data
#' @param config_file Path to ODS configuration file
quick_setup <- function(config_file = "data_to_retrive.ods") {
  
  result <- main_data_retrieval(
    config_file = config_file,
    start_date = "2020-01-01",
    end_date = Sys.Date()
  )
  
  return(result)
}

#' Download complete historical data (all available data from APIs)
#' @param config_file Configuration file
#' @param end_date End date (default: today)
download_full_history <- function(config_file = "data_to_retrive.ods", end_date = Sys.Date()) {
  
  cat("🕰️  DOWNLOADING COMPLETE HISTORICAL DATA\n")
  cat("This will retrieve ALL available data from the beginning of each series\n\n")
  
  result <- main_data_retrieval(
    config_file = config_file,
    start_date = NULL,  # NULL = earliest available
    end_date = end_date
  )
  
  return(result)
}

#' Update existing data with new observations  
#' @param config_file Configuration file
#' @param days_back How many days back to update
update_data <- function(config_file = "data_to_retrive.ods", days_back = 30) {
  
  end_date <- Sys.Date()
  start_date <- end_date - days_back
  
  result <- main_data_retrieval(
    config_file = config_file,
    start_date = start_date,
    end_date = end_date
  )
  
  return(result)
}

# Print usage information when loaded
if (interactive() && !exists("main_retrieval_loaded")) {
  main_retrieval_loaded <- TRUE
  cat("🇧🇷 Brazilian Economic Data Retrieval System loaded successfully.\n\n")
  cat("📊 58 variables configured | All transformations ready\n\n")
  cat("🚀 Usage Options:\n")
  cat("  🕰️  COMPLETE HISTORY:  result <- download_full_history()\n")
  cat("     ↳ Downloads ALL available data from 1980s-present\n\n")
  cat("  📅 Custom date range: result <- main_data_retrieval(start_date='2020-01-01')\n")
  cat("     ↳ Downloads from specific date to present\n\n") 
  cat("  🔄 Update recent:     result <- update_data()\n")
  cat("     ↳ Downloads only last 30 days\n\n")
  cat("💡 TIP: For complete historical analysis, use download_full_history()\n\n")
}