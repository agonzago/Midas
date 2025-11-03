# io.R
# Functions for loading and saving data, building vintages

#' Load configuration from YAML file
#' @param config_path Path to YAML config file
#' @return List with configuration parameters
load_config <- function(config_path) {
  if (!requireNamespace("yaml", quietly = TRUE)) {
    stop("Package 'yaml' is required. Install with: install.packages('yaml')")
  }
  yaml::read_yaml(config_path)
}

#' Read variables configuration
#' @param base_path Base path to config directory
#' @return List with variables configuration
read_variables <- function(base_path = "config") {
  config_file <- file.path(base_path, "variables.yaml")
  load_config(config_file)
}

#' Read options configuration
#' @param base_path Base path to config directory
#' @return List with options configuration
read_options <- function(base_path = "config") {
  config_file <- file.path(base_path, "options.yaml")
  load_config(config_file)
}

#' Read release calendar
#' @param base_path Base path to config directory
#' @return Data frame with release calendar
read_calendar <- function(base_path = "config") {
  calendar_file <- file.path(base_path, "calendar.csv")
  if (!file.exists(calendar_file)) {
    warning("Calendar file not found: ", calendar_file)
    return(data.frame(
      release_date = as.Date(character()),
      series_id = character(),
      ref_period = character(),
      source_url = character(),
      note = character()
    ))
  }
  
  if (!requireNamespace("data.table", quietly = TRUE)) {
    cal <- read.csv(calendar_file, stringsAsFactors = FALSE)
    cal$release_date <- as.Date(cal$release_date)
  } else {
    cal <- data.table::fread(calendar_file)
    cal$release_date <- as.Date(cal$release_date)
  }
  
  return(cal)
}

#' Load quarterly target data
#' @param data_path Path to quarterly data directory
#' @param target_id ID of target variable
#' @return Data frame with quarterly target
load_quarterly_target <- function(data_path = "data/quarterly", target_id = NULL) {
  # Placeholder: Load quarterly GDP data
  # In practice, this would read from CSV/RDS files
  
  quarterly_file <- file.path(data_path, "quarterly_data.csv")
  if (!file.exists(quarterly_file)) {
    warning("Quarterly data file not found: ", quarterly_file)
    return(data.frame(
      date = as.Date(character()),
      quarter = character(),
      value = numeric()
    ))
  }
  
  q_data <- read.csv(quarterly_file, stringsAsFactors = FALSE)
  q_data$date <- as.Date(q_data$date)
  
  return(q_data)
}

#' Load monthly panel data
#' @param data_path Path to monthly data directory
#' @return Data frame with monthly indicators
load_monthly_panel <- function(data_path = "data/monthly") {
  # Placeholder: Load monthly panel data
  # In practice, this would read from CSV/RDS files
  
  monthly_file <- file.path(data_path, "monthly_data.csv")
  if (!file.exists(monthly_file)) {
    warning("Monthly data file not found: ", monthly_file)
    return(data.frame(
      date = as.Date(character()),
      series_id = character(),
      value = numeric()
    ))
  }
  
  m_data <- read.csv(monthly_file, stringsAsFactors = FALSE)
  m_data$date <- as.Date(m_data$date)
  
  return(m_data)
}

#' Load monthly GDP proxy (if available)
#' @param data_path Path to monthly data directory
#' @param proxy_id ID of proxy variable
#' @return Data frame with monthly proxy or NULL
load_monthly_proxy <- function(data_path = "data/monthly", proxy_id = NULL) {
  if (is.null(proxy_id)) {
    return(NULL)
  }
  
  # Placeholder: Load monthly proxy data (e.g., IBC-Br for Brazil)
  proxy_file <- file.path(data_path, paste0(proxy_id, ".csv"))
  if (!file.exists(proxy_file)) {
    warning("Monthly proxy file not found: ", proxy_file)
    return(NULL)
  }
  
  proxy_data <- read.csv(proxy_file, stringsAsFactors = FALSE)
  proxy_data$date <- as.Date(proxy_data$date)
  
  return(proxy_data)
}

#' Build vintage snapshot
#' @param X_m Monthly panel data
#' @param y_q Quarterly target data
#' @param y_m_proxy Monthly proxy data (optional)
#' @param calendar Release calendar
#' @param as_of_date Date of the vintage snapshot
#' @return List with vintage data
build_vintage_snapshot <- function(X_m, y_q, y_m_proxy, calendar, as_of_date) {
  # Filter data based on as_of_date
  # Only include data that would have been available as of as_of_date
  
  # Filter monthly data
  X_m_vintage <- X_m[X_m$date <= as_of_date, ]
  
  # Apply calendar constraints
  if (!is.null(calendar) && nrow(calendar) > 0) {
    # For each series, check if it would have been released
    # This is a simplified implementation
    calendar_filtered <- calendar[calendar$release_date <= as_of_date, ]
    available_series <- unique(calendar_filtered$series_id)
    
    if (length(available_series) > 0 && "series_id" %in% names(X_m_vintage)) {
      X_m_vintage <- X_m_vintage[X_m_vintage$series_id %in% available_series, ]
    }
  }
  
  # Filter quarterly data
  y_q_vintage <- y_q[y_q$date <= as_of_date, ]
  
  # Filter monthly proxy
  y_m_proxy_vintage <- NULL
  if (!is.null(y_m_proxy)) {
    y_m_proxy_vintage <- y_m_proxy[y_m_proxy$date <= as_of_date, ]
  }
  
  vintage <- list(
    as_of_date = as_of_date,
    X_m = X_m_vintage,
    y_q = y_q_vintage,
    y_m_proxy = y_m_proxy_vintage,
    calendar = calendar
  )
  
  return(vintage)
}

#' Save vintage snapshot
#' @param vintage Vintage list object
#' @param file_path Path to save the vintage
save_vintage <- function(vintage, file_path) {
  dir.create(dirname(file_path), showWarnings = FALSE, recursive = TRUE)
  saveRDS(vintage, file = file_path)
  message("Vintage saved to: ", file_path)
}

#' Load vintage snapshot
#' @param file_path Path to vintage file
#' @return Vintage list object
load_vintage <- function(file_path) {
  if (!file.exists(file_path)) {
    stop("Vintage file not found: ", file_path)
  }
  readRDS(file_path)
}

#' Write weekly summary outputs
#' @param as_of_date Date of the nowcast
#' @param combo Combined forecast object
#' @param all_fcsts List of all individual forecasts
#' @param news_tbl News table
#' @param models_updated Vector of updated model names
#' @param output_path Path to output directory
write_weekly_summary <- function(as_of_date, combo, all_fcsts, news_tbl, 
                                  models_updated = c(), output_path = "output/weekly_reports") {
  if (!requireNamespace("jsonlite", quietly = TRUE)) {
    warning("Package 'jsonlite' required for JSON output. Install with: install.packages('jsonlite')")
  }
  
  dir.create(output_path, showWarnings = FALSE, recursive = TRUE)
  
  # Prepare summary data
  summary <- list(
    as_of_date = as.character(as_of_date),
    combined_nowcast = combo$point,
    combined_interval = c(combo$lo, combo$hi),
    weights = combo$weights,
    models_updated = models_updated,
    individual_forecasts = lapply(names(all_fcsts), function(name) {
      f <- all_fcsts[[name]]
      list(
        model = name,
        point = if (!is.null(f$point)) f$point else NA,
        se = if (!is.null(f$se)) f$se else NA
      )
    })
  )
  
  # Save CSV
  csv_file <- file.path(output_path, paste0("summary_", as_of_date, ".csv"))
  summary_df <- data.frame(
    date = as_of_date,
    combined_point = combo$point,
    combined_lo = combo$lo,
    combined_hi = combo$hi,
    stringsAsFactors = FALSE
  )
  write.csv(summary_df, file = csv_file, row.names = FALSE)
  
  # Save JSON
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    json_file <- file.path(output_path, paste0("summary_", as_of_date, ".json"))
    jsonlite::write_json(summary, json_file, pretty = TRUE, auto_unbox = TRUE)
  }
  
  # Save news table
  if (!is.null(news_tbl) && nrow(news_tbl) > 0) {
    news_file <- file.path(output_path, paste0("news_", as_of_date, ".csv"))
    write.csv(news_tbl, file = news_file, row.names = FALSE)
  }
  
  message("Weekly summary written to: ", output_path)
}
