# lagmap.R
# Calendar-aware lag mapping for ragged edge handling

#' Build lag map for current quarter
#' @param as_of_date Date as of which to build the lag map
#' @param vars Variables configuration
#' @param calendar Release calendar
#' @return List with lag map information
build_lag_map <- function(as_of_date, vars, calendar) {
  source("R/utils.R")  # For date utilities
  
  current_quarter <- get_current_quarter(as_of_date)
  
  # Extract quarter info
  year <- as.numeric(substr(current_quarter, 1, 4))
  q <- as.numeric(substr(current_quarter, 6, 6))
  
  # Get months in current quarter
  quarter_months <- get_quarter_months(current_quarter)
  
  # Initialize lag map structure
  lag_map <- list(
    as_of_date = as_of_date,
    current_quarter = current_quarter,
    quarter_months = quarter_months,
    indicators = list()
  )
  
  # For each indicator, determine which months are available
  if (!is.null(vars$indicators)) {
    for (indicator in vars$indicators) {
      ind_id <- indicator$id
      
      # Check calendar for release dates
      ind_calendar <- calendar[calendar$series_id == ind_id, ]
      
      # Determine available months up to as_of_date
      available_months <- list()
      
      # Check which months in current quarter have been released
      for (m in quarter_months) {
        month_date <- as.Date(paste0(year, "-", sprintf("%02d", m), "-01"))
        
        # Check if this month's data would be available
        # Simple rule: data available if month has ended and release lag has passed
        month_end <- seq(month_date, by = "1 month", length.out = 2)[2] - 1
        
        # Default release lag (can be overridden by calendar)
        release_lag <- 30  # days
        
        # Check calendar for specific release date
        month_str <- format(month_date, "%Y-%m")
        calendar_entry <- ind_calendar[grepl(month_str, ind_calendar$ref_period), ]
        
        if (nrow(calendar_entry) > 0) {
          release_date <- calendar_entry$release_date[1]
          is_available <- as_of_date >= release_date
        } else {
          # Use default rule
          release_date <- month_end + release_lag
          is_available <- as_of_date >= release_date
        }
        
        available_months[[as.character(m)]] <- is_available
      }
      
      # Store in lag map
      lag_map$indicators[[ind_id]] <- list(
        available_months = available_months,
        lag_max = indicator$lag_max_months
      )
    }
  }
  
  return(lag_map)
}

#' Get available lags for an indicator in the current quarter
#' @param lag_map Lag map object
#' @param indicator_id ID of the indicator
#' @return Vector of available lag positions (0 = current month of quarter)
get_available_lags <- function(lag_map, indicator_id) {
  if (!indicator_id %in% names(lag_map$indicators)) {
    warning("Indicator not found in lag map: ", indicator_id)
    return(integer(0))
  }
  
  ind_info <- lag_map$indicators[[indicator_id]]
  available_months <- ind_info$available_months
  
  # Convert to lag positions
  # Month 1 of quarter = lag 0, month 2 = lag 1, month 3 = lag 2
  lags <- c()
  for (i in seq_along(available_months)) {
    if (available_months[[i]]) {
      lags <- c(lags, i - 1)
    }
  }
  
  return(lags)
}

#' Create ragged-edge design matrix for MIDAS
#' @param monthly_data Monthly data vector or matrix
#' @param lag_map Lag map object
#' @param indicator_id Indicator ID
#' @param lag_max Maximum number of lags to include
#' @return Matrix with only available lags (no imputation)
create_ragged_midas_matrix <- function(monthly_data, lag_map, indicator_id, lag_max = 12) {
  available_lags <- get_available_lags(lag_map, indicator_id)
  
  if (length(available_lags) == 0) {
    warning("No available lags for indicator: ", indicator_id)
    return(matrix(NA, nrow = 1, ncol = 0))
  }
  
  # Build matrix including only available lags
  # This is a simplified version - actual implementation would handle
  # multiple quarters and proper lag construction
  
  n_obs <- length(monthly_data)
  max_available_lag <- max(available_lags, lag_max)
  
  # Create lag matrix
  lag_matrix <- matrix(NA, nrow = n_obs, ncol = length(available_lags))
  
  for (i in seq_along(available_lags)) {
    lag_pos <- available_lags[i]
    if (lag_pos < n_obs) {
      lag_matrix[, i] <- c(rep(NA, lag_pos), monthly_data[1:(n_obs - lag_pos)])
    }
  }
  
  colnames(lag_matrix) <- paste0("L", available_lags)
  
  return(lag_matrix)
}

#' Map monthly observations to quarterly target periods
#' @param monthly_dates Vector of monthly dates
#' @param quarterly_dates Vector of quarterly dates
#' @return List mapping each quarterly period to its constituent months
map_monthly_to_quarterly_periods <- function(monthly_dates, quarterly_dates) {
  if (!requireNamespace("lubridate", quietly = TRUE)) {
    stop("Package 'lubridate' required")
  }
  
  mapping <- list()
  
  for (q_date in quarterly_dates) {
    q_date <- as.Date(q_date)
    year <- lubridate::year(q_date)
    quarter <- lubridate::quarter(q_date)
    
    # Get months in this quarter
    months_in_q <- ((quarter - 1) * 3 + 1):(quarter * 3)
    
    # Find corresponding monthly observations
    monthly_in_q <- monthly_dates[
      lubridate::year(monthly_dates) == year &
      lubridate::month(monthly_dates) %in% months_in_q
    ]
    
    q_str <- paste0(year, "Q", quarter)
    mapping[[q_str]] <- as.character(monthly_in_q)
  }
  
  return(mapping)
}

#' Get lag specification for current forecast
#' @param lag_map Lag map object
#' @param indicator_id Indicator ID
#' @param include_past_quarters Whether to include lags from previous quarters
#' @return List with lag specification
get_lag_spec <- function(lag_map, indicator_id, include_past_quarters = TRUE) {
  available_current <- get_available_lags(lag_map, indicator_id)
  
  lag_spec <- list(
    current_quarter_lags = available_current,
    total_available = length(available_current)
  )
  
  if (include_past_quarters && indicator_id %in% names(lag_map$indicators)) {
    lag_max <- lag_map$indicators[[indicator_id]]$lag_max
    if (!is.null(lag_max)) {
      lag_spec$max_lags_requested <- lag_max
    }
  }
  
  return(lag_spec)
}
