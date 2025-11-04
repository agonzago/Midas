# =============================================================================
# Spreadsheet Configuration Reader
# Reads ODS file and parses variable configurations for different sources
# =============================================================================

library(readODS)
library(dplyr)
library(GetBCBData)
library(ipeadatar)

#' Read and parse the data retrieval configuration from ODS file
#' @param ods_file_path Path to the ODS configuration file
#' @param validate_codes Whether to validate API codes against sources
read_data_config <- function(ods_file_path, validate_codes = FALSE) {
  
  if (!file.exists(ods_file_path)) {
    stop("Configuration file not found: ", ods_file_path)
  }
  
  cat("Reading data configuration from:", ods_file_path, "\n")
  
  # Get available sheets
  sheets <- list_ods_sheets(ods_file_path)
  cat("Available sheets:", paste(sheets, collapse = ", "), "\n")
  
  config <- list()
  
  # Read each sheet
  for (sheet in sheets) {
    
    cat("Processing sheet:", sheet, "\n")
    
    sheet_data <- read_ods(ods_file_path, sheet = sheet)
    
    # Validate required columns
    required_cols <- c("Code", "Long Name", "units", "Periodicity", "Source", "Transformation", "Name")
    missing_cols <- setdiff(required_cols, names(sheet_data))
    
    if (length(missing_cols) > 0) {
      warning("Missing columns in sheet ", sheet, ": ", paste(missing_cols, collapse = ", "))
      next
    }
    
    # Clean and standardize the data
    sheet_data_clean <- sheet_data %>%
      filter(!is.na(Code) & !is.na(Name)) %>%  # Remove rows with missing essential data
      mutate(
        Code = as.character(Code),
        Periodicity = toupper(trimws(Periodicity)),
        Source = tolower(trimws(Source)),
        Name = trimws(Name),
        Transformation = trimws(Transformation)
      ) %>%
      # Add sheet source information
      mutate(
        config_source = sheet,
        api_source = case_when(
          grepl("ipea", Source, ignore.case = TRUE) ~ "ipeadata",
          grepl("ibge", Source, ignore.case = TRUE) ~ "bcb",  # IBGE data via BCB
          grepl("bcb", Source, ignore.case = TRUE) ~ "bcb",
          grepl("copom", Source, ignore.case = TRUE) ~ "bcb",  # Copom (BCB)
          grepl("sisba", Source, ignore.case = TRUE) ~ "bcb",  # Sisbacen (BCB)
          grepl("fred", Source, ignore.case = TRUE) ~ "fred",
          tolower(Source) == "fred" ~ "fred",  # Direct match for 'fred' (case-insensitive)
          grepl("static_csv", Source, ignore.case = TRUE) ~ "static_csv",
          tolower(Source) == "static_csv" ~ "static_csv",  # Static CSV files
          tolower(Source) == "gpmorgan" ~ "static_csv",  # GP Morgan PMI data (static CSV)
          TRUE ~ "unknown"
        )
      )
    
    cat("  - Parsed", nrow(sheet_data_clean), "variables\n")
    
    config[[sheet]] <- sheet_data_clean
  }
  
  # Combine all sheets into master configuration
  master_config <- bind_rows(config, .id = "sheet")
  
  # Validate codes if requested
  if (validate_codes) {
    master_config <- validate_api_codes(master_config)
  }
  
  cat("Total variables configured:", nrow(master_config), "\n")
  
  return(list(
    config = master_config,
    by_sheet = config,
    summary = summarize_config(master_config)
  ))
}

#' Validate API codes against actual data sources
#' @param config_data Data frame with configuration
validate_api_codes <- function(config_data) {
  
  cat("Validating API codes...\n")
  
  config_data$code_valid <- FALSE
  config_data$validation_message <- ""
  
  # Validate BCB codes
  bcb_codes <- config_data[config_data$api_source == "bcb", ]
  if (nrow(bcb_codes) > 0) {
    cat("  Validating", nrow(bcb_codes), "BCB codes...\n")
    
    for (i in 1:nrow(bcb_codes)) {
      code <- as.numeric(bcb_codes$Code[i])
      
      tryCatch({
        # Try to get just the last observation to test validity
        test_data <- gbcbd_get_series(id = code, first.date = Sys.Date() - 30)
        if (nrow(test_data) > 0) {
          config_data$code_valid[config_data$Code == bcb_codes$Code[i]] <- TRUE
          config_data$validation_message[config_data$Code == bcb_codes$Code[i]] <- "Valid"
        } else {
          config_data$validation_message[config_data$Code == bcb_codes$Code[i]] <- "No recent data"
        }
      }, error = function(e) {
        config_data$validation_message[config_data$Code == bcb_codes$Code[i]] <<- paste("Error:", e$message)
      })
      
      # Small delay to be respectful to API
      Sys.sleep(0.2)
    }
  }
  
  # Validate Ipeadata codes
  ipea_codes <- config_data[config_data$api_source == "ipeadata", ]
  if (nrow(ipea_codes) > 0) {
    cat("  Validating", nrow(ipea_codes), "Ipeadata codes...\n")
    
    # Get available series once
    tryCatch({
      available_series <- available_series()
      
      for (i in 1:nrow(ipea_codes)) {
        code <- ipea_codes$Code[i]
        
        if (code %in% available_series$code) {
          config_data$code_valid[config_data$Code == code] <- TRUE
          config_data$validation_message[config_data$Code == code] <- "Valid"
        } else {
          config_data$validation_message[config_data$Code == code] <- "Code not found in Ipeadata"
        }
      }
    }, error = function(e) {
      cat("  Warning: Could not validate Ipeadata codes:", e$message, "\n")
    })
  }
  
  return(config_data)
}

#' Summarize configuration for reporting
#' @param config_data Master configuration data frame
summarize_config <- function(config_data) {
  
  summary <- list()
  
  # Overall statistics
  summary$total_variables <- nrow(config_data)
  summary$by_source <- table(config_data$api_source)
  summary$by_periodicity <- table(config_data$Periodicity)
  summary$by_transformation <- table(config_data$Transformation)
  
  # Sheet breakdown
  summary$by_sheet <- config_data %>%
    group_by(sheet, api_source) %>%
    summarise(count = n(), .groups = "drop")
  
  return(summary)
}

#' Get variables for specific API source
#' @param config_result Result from read_data_config()
#' @param api_source Source to filter: "bcb", "ipeadata", etc.
get_variables_by_source <- function(config_result, api_source) {
  
  config_result$config %>%
    filter(api_source == !!api_source) %>%
    arrange(Name)
}

#' Get transformation specifications for variables
#' @param config_result Result from read_data_config() 
get_transformation_specs <- function(config_result) {
  
  specs <- config_result$config %>%
    select(Name, Transformation) %>%
    distinct()
  
  # Convert to named list
  spec_list <- setNames(specs$Transformation, specs$Name)
  
  return(spec_list)
}

#' Create download configuration for retrieval functions
#' @param config_result Result from read_data_config()
#' @param api_source Specific API source to create config for
create_download_config <- function(config_result, api_source) {
  
  variables <- get_variables_by_source(config_result, api_source)
  
  if (nrow(variables) == 0) {
    return(list())
  }
  
  # Create list of series configurations
  series_configs <- list()
  
  for (i in 1:nrow(variables)) {
    var <- variables[i, ]
    
    series_config <- list(
      series_id = var$Name,
      description = var$`Long Name`,
      source = api_source,
      api_id = var$Code,
      frequency = switch(var$Periodicity,
        "M" = "monthly",
        "Q" = "quarterly", 
        "A" = "annual",
        "D" = "daily",
        "monthly"  # default
      ),
      transform = var$Transformation,
      units = var$units,
      config_source = var$config_source
    )
    
    series_configs[[var$Name]] <- series_config
  }
  
  return(series_configs)
}

#' Print configuration summary
#' @param config_result Result from read_data_config()
print_config_summary <- function(config_result) {
  
  cat("=== Data Configuration Summary ===\n")
  
  summary <- config_result$summary
  
  cat("Total variables:", summary$total_variables, "\n\n")
  
  cat("By API source:\n")
  for (source in names(summary$by_source)) {
    cat("  ", source, ":", summary$by_source[source], "\n")
  }
  
  cat("\nBy periodicity:\n")
  for (period in names(summary$by_periodicity)) {
    cat("  ", period, ":", summary$by_periodicity[period], "\n")
  }
  
  cat("\nBy transformation:\n")
  for (transform in names(summary$by_transformation)) {
    cat("  ", transform, ":", summary$by_transformation[transform], "\n")
  }
  
  cat("\nBy sheet:\n")
  for (i in 1:nrow(summary$by_sheet)) {
    row <- summary$by_sheet[i, ]
    cat("  ", row$sheet, "(", row$api_source, "):", row$count, "\n")
  }
  
  cat("\n")
}

#' Validate that all required packages are available for configured sources
#' @param config_result Result from read_data_config()
check_required_packages <- function(config_result) {
  
  sources <- unique(config_result$config$api_source)
  
  required_packages <- list(
    "bcb" = c("GetBCBData"),
    "ipeadata" = c("ipeadatar"),
    "sidrar" = c("sidrar")
  )
  
  missing_packages <- c()
  
  for (source in sources) {
    if (source %in% names(required_packages)) {
      for (pkg in required_packages[[source]]) {
        if (!require(pkg, character.only = TRUE, quietly = TRUE)) {
          missing_packages <- c(missing_packages, pkg)
        }
      }
    }
  }
  
  if (length(missing_packages) > 0) {
    cat("Missing required packages:", paste(missing_packages, collapse = ", "), "\n")
    cat("Install with: install.packages(c(", 
        paste(paste0("'", missing_packages, "'"), collapse = ", "), "))\n")
    return(FALSE)
  }
  
  cat("All required packages are available.\n")
  return(TRUE)
}

#' Export configuration to different formats
#' @param config_result Result from read_data_config()  
#' @param output_dir Directory to save exports
export_config <- function(config_result, output_dir = "processed_data") {
  
  dir.create(output_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Export master configuration as CSV
  master_csv <- file.path(output_dir, "master_config.csv")
  write.csv(config_result$config, master_csv, row.names = FALSE)
  cat("Master configuration exported to:", master_csv, "\n")
  
  # Export by API source
  for (source in unique(config_result$config$api_source)) {
    source_data <- get_variables_by_source(config_result, source)
    if (nrow(source_data) > 0) {
      source_csv <- file.path(output_dir, paste0(source, "_config.csv"))
      write.csv(source_data, source_csv, row.names = FALSE)
      cat("Configuration for", source, "exported to:", source_csv, "\n")
    }
  }
  
  # Export transformation specifications
  transform_specs <- get_transformation_specs(config_result)
  if (length(transform_specs) > 0) {
    transform_df <- data.frame(
      Variable = names(transform_specs),
      Transformation = unname(transform_specs),
      stringsAsFactors = FALSE
    )
    transform_csv <- file.path(output_dir, "transformation_specs.csv")
    write.csv(transform_df, transform_csv, row.names = FALSE)
    cat("Transformation specifications exported to:", transform_csv, "\n")
  }
}

# =============================================================================
# Example usage
# =============================================================================

if (interactive() && !exists("config_reader_loaded")) {
  config_reader_loaded <- TRUE
  cat("Configuration reader functions loaded successfully.\n")
  cat("Usage example:\n")
  cat("  config <- read_data_config('data_to_retrive.ods')\n")
  cat("  print_config_summary(config)\n")
}