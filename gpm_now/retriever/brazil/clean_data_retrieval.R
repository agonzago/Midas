# ================================================================================
# CLEAN PRODUCTION DATA RETRIEVAL SYSTEM
# Final version for production use - rbcb + ipeadatar + fredr + CSV
# ================================================================================

source("/home/andres/work/Midas/gpm_now/retriever/brazil/config_reader.R")
library(rbcb)        # BCB data
library(ipeadatar)   # Ipeadata
library(fredr)       # FRED (optional - requires API key)
library(dplyr)
library(lubridate)
library(tidyr)

#' Main data download function - all sources
#' @param config_file Path to ODS configuration file
#' @param fred_api_key FRED API key (optional)
#' @return data.frame with columns: date, value, series_code
download_economic_data <- function(
  config_file = "/home/andres/work/Midas/gpm_now/retriever/brazil/data_to_retrive.ods",
  fred_api_key = NULL
) {
  
  cat("🚀 ECONOMIC DATA DOWNLOAD\n")
  cat(paste(rep("=", 40), collapse = ""), "\n\n")
  
  # Read configuration
  if (!file.exists(config_file)) {
    stop("Configuration file not found: ", config_file)
  }
  
  config_result <- read_data_config(config_file)
  config_data <- config_result$config
  
  # Set FRED API key - try environment variable first, then parameter
  if (!is.null(fred_api_key)) {
    fredr_set_key(fred_api_key)
  } else {
    # Try to get from environment variable
    env_key <- Sys.getenv("FRED_API_KEY")
    if (env_key != "") {
      fredr_set_key(env_key)
      fred_api_key <- env_key  # Mark as available
    }
  }
  
  # Split by source
  bcb_config <- config_data[config_data$api_source == "bcb", ]
  ipea_config <- config_data[config_data$api_source == "ipeadata", ]  
  fred_config <- config_data[config_data$api_source == "fred", ]
  csv_config <- config_data[config_data$api_source == "static_csv", ]
  
  all_data <- list()
  
  # Download BCB data
  if (nrow(bcb_config) > 0) {
    cat("📊 BCB Data...\n")
    bcb_data <- download_bcb(bcb_config)
    if (nrow(bcb_data) > 0) all_data[["bcb"]] <- bcb_data
  }
  
  # Download Ipeadata
  if (nrow(ipea_config) > 0) {
    cat("🏛️ Ipeadata...\n")
    ipea_data <- download_ipeadata(ipea_config)
    if (nrow(ipea_data) > 0) all_data[["ipea"]] <- ipea_data
  }
  
  # Download FRED (if API key available)
  if (nrow(fred_config) > 0 && (!is.null(fred_api_key) || Sys.getenv("FRED_API_KEY") != "")) {
    cat("🇺🇸 FRED Data...\n")
    fred_data <- download_fred(fred_config)
    if (nrow(fred_data) > 0) all_data[["fred"]] <- fred_data
  }
  
  # Load CSV data
  if (nrow(csv_config) > 0) {
    cat("📄 Static CSV...\n")
    csv_data <- download_csv(csv_config)
    if (nrow(csv_data) > 0) all_data[["csv"]] <- csv_data
  }
  
  # Combine all data
  if (length(all_data) > 0) {
    combined_data <- do.call(rbind, all_data)
    rownames(combined_data) <- NULL
    
    cat(sprintf("\n✅ SUCCESS: %d series, %d observations\n", 
               length(unique(combined_data$series_code)), nrow(combined_data)))
    cat(sprintf("📅 Range: %s to %s\n", 
               min(combined_data$date), max(combined_data$date)))
    
    return(combined_data)
  }
  
  return(data.frame())
}

# Helper functions for each source
download_bcb <- function(config) {
  all_data <- list()
  
  for (i in seq_len(nrow(config))) {
    series_id <- as.numeric(config$Code[i])
    user_code <- config$Name[i]
    periodicity <- toupper(config$Periodicity[i])
    
    tryCatch({
      # For daily series, use a more recent start date to avoid API issues
      if (periodicity == "D") {
        # Request last 10 years of daily data
        start_date <- format(Sys.Date() - 3650, "%d/%m/%Y")
        end_date <- format(Sys.Date(), "%d/%m/%Y")
        df <- get_series(series_id, start_date = start_date, end_date = end_date, as = "data.frame")
      } else {
        df <- get_series(series_id, as = "data.frame")
      }
      
      if (nrow(df) > 0 && as.character(series_id) %in% colnames(df)) {
        df_clean <- df %>%
          rename(value = !!as.character(series_id)) %>%
          mutate(
            date = as.Date(date),
            series_code = user_code
          ) %>%
          select(date, value, series_code) %>%
          filter(!is.na(value))
        
        all_data[[user_code]] <- df_clean
        cat(sprintf("   ✓ %s: %d obs (%s-%s)\n", 
                   user_code, nrow(df_clean), 
                   format(min(df_clean$date), "%Y"), 
                   format(max(df_clean$date), "%Y")))
      }
    }, error = function(e) {
      cat(sprintf("   ✗ %s: %s\n", user_code, conditionMessage(e)))
    })
    
    Sys.sleep(0.1)
  }
  
  if (length(all_data) > 0) {
    return(do.call(rbind, all_data))
  }
  return(data.frame())
}

download_ipeadata <- function(config) {
  all_data <- list()
  
  for (i in seq_len(nrow(config))) {
    series_code <- config$Code[i]
    user_code <- config$Name[i]
    
    tryCatch({
      df <- ipeadata(series_code)
      
      if (nrow(df) > 0) {
        df_clean <- df %>%
          mutate(
            date = as.Date(date),
            series_code = user_code
          ) %>%
          select(date, value, series_code) %>%
          filter(!is.na(value))
        
        all_data[[user_code]] <- df_clean
        cat(sprintf("   ✓ %s: %d obs (%s-%s)\n", 
                   user_code, nrow(df_clean),
                   format(min(df_clean$date), "%Y"), 
                   format(max(df_clean$date), "%Y")))
      }
    }, error = function(e) {
      cat(sprintf("   ✗ %s: %s\n", user_code, conditionMessage(e)))
    })
    
    Sys.sleep(0.1)
  }
  
  if (length(all_data) > 0) {
    return(do.call(rbind, all_data))
  }
  return(data.frame())
}

download_fred <- function(config) {
  all_data <- list()
  
  for (i in seq_len(nrow(config))) {
    series_id <- config$Code[i]
    user_code <- config$Name[i]
    
    tryCatch({
      df <- fredr(series_id = series_id)
      
      if (nrow(df) > 0) {
        df_clean <- df %>%
          select(date, value) %>%
          mutate(
            date = as.Date(date),
            series_code = user_code
          ) %>%
          filter(!is.na(value))
        
        all_data[[user_code]] <- df_clean
        cat(sprintf("   ✓ %s: %d obs (%s-%s)\n", 
                   user_code, nrow(df_clean),
                   format(min(df_clean$date), "%Y"), 
                   format(max(df_clean$date), "%Y")))
      }
    }, error = function(e) {
      cat(sprintf("   ✗ %s: %s\n", user_code, conditionMessage(e)))
    })
    
    Sys.sleep(0.1)
  }
  
  if (length(all_data) > 0) {
    return(do.call(rbind, all_data))
  }
  return(data.frame())
}

download_csv <- function(config) {
  pmi_file <- "/home/andres/work/Midas/gpm_now/retriever/brazil/static_csv/Brazil_PMI.csv"
  
  if (!file.exists(pmi_file)) {
    cat("   ✗ PMI file not found\n")
    return(data.frame())
  }
  
  # Read PMI file (transposed format: dates as rows, series as columns)
  pmi_raw <- read.csv(pmi_file, stringsAsFactors = FALSE, check.names = FALSE)
  
  # Find where actual data starts (skip metadata rows starting with .)
  data_start_row <- which(grepl("^[0-9]{6}", pmi_raw[, 1]))[1]
  if (is.na(data_start_row)) {
    cat("   ✗ No date data found in PMI file\n")
    return(data.frame())
  }
  
  # Extract data and convert dates
  data_rows <- pmi_raw[data_start_row:nrow(pmi_raw), ]
  data_rows[, 1] <- as.Date(paste0(data_rows[, 1], "01"), format = "%Y%m%d")
  
  all_data <- list()
  
  for (i in seq_len(nrow(config))) {
    pmi_code <- config$Code[i]
    series_name <- config$Name[i] 
    long_name <- config$`Long Name`[i]
    
    if (pmi_code %in% names(pmi_raw)) {
      # Extract series data
      series_data <- data_rows[, c(1, which(names(pmi_raw) == pmi_code))]
      names(series_data) <- c("date", "value")
      
      # Format output (match structure of other download functions)
      df_clean <- series_data %>%
        mutate(
          value = as.numeric(value),
          series_code = series_name
        ) %>%
        filter(!is.na(value) & !is.na(date)) %>%
        arrange(date) %>%
        select(date, value, series_code)
      
      if (nrow(df_clean) > 0) {
        all_data[[series_name]] <- df_clean
        cat(sprintf("   ✓ %s: %d obs (%s-%s)\n", 
                   series_name, nrow(df_clean),
                   format(min(df_clean$date), "%Y"), 
                   format(max(df_clean$date), "%Y")))
      }
    } else {
      cat(sprintf("   ✗ %s: PMI code '%s' not found\n", series_name, pmi_code))
    }
  }
  
  if (length(all_data) > 0) {
    return(do.call(rbind, all_data))
  }
  return(data.frame())
}

# =============================================================================
# Transformation and export utilities
# =============================================================================

# Apply a single transformation code to a numeric vector
# Supported codes (compose with commas in order):
# - "log": natural log
# - "dm": first difference (lag 1)
# - "dq": first difference for quarterly (same as dm but kept for clarity)
# - "d12": 12-lag difference (useful for YoY levels)
# - "d4": 4-lag difference (YoY for quarterly)
# - "mom": percent change vs previous period (100*(x/lag1-1))
# - "yoy": percent change vs 12 or 4 lags based on frequency
apply_transform_code <- function(x, code, freq = "M") {
  if (is.null(code) || is.na(code) || nchar(trimws(code)) == 0) {
    return(x)
  }
  code <- tolower(trimws(code))
  if (code == "log") {
    return(log(x))
  }
  if (code == "dm" || code == "dq") {
    return(c(NA, diff(x, lag = 1)))
  }
  if (code == "d12") {
    return(c(rep(NA, 12), x[13:length(x)] - x[1:(length(x)-12)]))
  }
  if (code == "d4") {
    return(c(rep(NA, 4), x[5:length(x)] - x[1:(length(x)-4)]))
  }
  if (code == "mom") {
    lag1 <- dplyr::lag(x, 1)
    return(as.numeric(100 * (x/lag1 - 1)))
  }
  if (code == "yoy") {
    k <- ifelse(toupper(freq) == "Q", 4, 12)
    lagk <- dplyr::lag(x, k)
    return(as.numeric(100 * (x/lagk - 1)))
  }
  # Unknown code => identity
  return(x)
}

# Apply a composite transformation string like "log_dm" or "log, dm"
apply_composite_transform <- function(x, transform_str, freq = "M") {
  if (is.null(transform_str) || is.na(transform_str) || nchar(trimws(transform_str)) == 0) {
    return(x)
  }
  # Normalize separators to commas and split
  s <- gsub("_", ",", tolower(transform_str))
  parts <- unlist(strsplit(s, ",[\t ]*|[\t ]+"))
  parts <- parts[nchar(parts) > 0]
  y <- x
  for (p in parts) {
    y <- apply_transform_code(y, p, freq)
  }
  return(y)
}

# Build transformed dataset joining metadata and applying per-series transforms
build_transformed_dataset <- function(raw_df, config_df) {
  meta <- config_df %>%
    dplyr::select(Name, Periodicity, Transformation) %>%
    dplyr::distinct(Name, .keep_all = TRUE)
  df <- raw_df %>%
    dplyr::left_join(meta, by = c("series_code" = "Name"))
  if (!all(c("Periodicity", "Transformation") %in% names(df))) {
    warning("Missing Periodicity/Transformation in metadata join; returning original only")
    df$transformed_value <- df$value
    df$transform_applied <- NA_character_
    return(df)
  }
  # Apply per-series
  df <- df %>%
    dplyr::group_by(series_code) %>%
    dplyr::mutate(
      transformed_value = apply_composite_transform(value, first(Transformation), first(Periodicity)),
      transform_applied = first(Transformation)
    ) %>%
    dplyr::ungroup()
  return(df)
}

# Save outputs: raw and transformed, split by frequency (M/Q)
save_outputs <- function(raw_df, config_df, output_dir = 
                           "/home/andres/work/Midas/gpm_now/retriever/brazil/output") {
  # Ensure dirs
  raw_dir <- file.path(output_dir, "raw_csv")
  trn_dir <- file.path(output_dir, "transformed_data")
  dir.create(raw_dir, recursive = TRUE, showWarnings = FALSE)
  dir.create(trn_dir, recursive = TRUE, showWarnings = FALSE)
  
  # Annotate frequency
  freq_map <- config_df %>% dplyr::select(Name, Periodicity)
  freq_map <- freq_map %>% dplyr::distinct(Name, .keep_all = TRUE)
  raw_annot <- raw_df %>% dplyr::left_join(freq_map, by = c("series_code" = "Name"))
  # Split raw: include native monthly plus daily aggregated to monthly
  raw_monthly_native <- raw_annot %>% dplyr::filter(toupper(Periodicity) == "M") %>% dplyr::select(date, series_code, value)
  raw_monthly_from_daily <- aggregate_daily_to_monthly(raw_annot) %>% dplyr::select(date, series_code, value)
  raw_monthly <- dplyr::bind_rows(raw_monthly_native, raw_monthly_from_daily) %>% dplyr::arrange(series_code, date)
  raw_quarterly <- raw_annot %>% dplyr::filter(toupper(Periodicity) == "Q") %>% dplyr::arrange(series_code, date)
  # Write raw
  write.csv(raw_monthly %>% dplyr::select(date, series_code, value),
            file.path(raw_dir, "monthly.csv"), row.names = FALSE)
  write.csv(raw_quarterly %>% dplyr::select(date, series_code, value),
            file.path(raw_dir, "quarterly.csv"), row.names = FALSE)
  
  # Build transformed panel (wide), applying DA/DA3m convention
  panel <- build_transformed_panel(raw_df, config_df)
  write.csv(panel$monthly, file.path(trn_dir, "monthly.csv"), row.names = FALSE)
  write.csv(panel$quarterly, file.path(trn_dir, "quarterly.csv"), row.names = FALSE)
  
  invisible(list(
    raw = list(monthly = raw_monthly, quarterly = raw_quarterly),
    transformed = list(monthly = panel$monthly, quarterly = panel$quarterly)
  ))
}

# Convenience wrapper: download then save
download_and_save <- function(
  config_file = "/home/andres/work/Midas/gpm_now/retriever/brazil/data_to_retrive.ods",
  output_dir = "/home/andres/work/Midas/gpm_now/retriever/brazil/output",
  fred_api_key = NULL
) {
  raw <- download_economic_data(config_file, fred_api_key)
  if (nrow(raw) == 0) {
    stop("No data downloaded to save")
  }
  config_result <- read_data_config(config_file)
  save_outputs(raw, config_result$config, output_dir)
  cat(sprintf("\n📦 Saved outputs to: %s\n- raw_csv/monthly.csv\n- raw_csv/quarterly.csv\n- transformed_data/monthly.csv\n- transformed_data/quarterly.csv\n", output_dir))
}

# =============================================================================
# Build transformed panel in wide (time series matrix) format
# Columns: Date plus original and transformed variants per series
# - For monthly: S, DA_S, DA3m_S
# - For quarterly: S, DA_S
# =============================================================================

safe_lag <- function(x, k) {
  if (length(x) == 0) return(x)
  c(rep(NA, k), head(x, -k))
}

compute_DA <- function(x, freq) {
  # Annualized growth from previous period
  if (all(is.na(x))) return(x)
  k <- 1
  if (all(x > 0, na.rm = TRUE)) {
    # log-annualized
    factor <- ifelse(toupper(freq) == "Q", 400, 1200)
    lagx <- safe_lag(x, k)
    out <- factor * (log(x) - log(lagx))
  } else {
    # percent-change annualized
    factor <- ifelse(toupper(freq) == "Q", 4, 12)
    lagx <- safe_lag(x, k)
    out <- 100 * factor * (x/lagx - 1)
  }
  return(as.numeric(out))
}

compute_DA3m <- function(x) {
  # 3-month annualized from 3-month lag (monthly only)
  if (all(is.na(x))) return(x)
  k <- 3
  if (all(x > 0, na.rm = TRUE)) {
    factor <- 1200/3 # 400
    lagx <- safe_lag(x, k)
    out <- factor * (log(x) - log(lagx))
  } else {
    factor <- 12/3 # 4
    lagx <- safe_lag(x, k)
    out <- 100 * factor * (x/lagx - 1)
  }
  return(as.numeric(out))
}

# Aggregate daily series to monthly by average.
# Rule for current (incomplete) month: if there are 7 or fewer daily observations,
# average only the last up-to-7 available days; otherwise use month-to-date average.
aggregate_daily_to_monthly <- function(df_with_freq) {
  if (!all(c("date", "value", "series_code", "Periodicity") %in% names(df_with_freq))) {
    return(data.frame(date = as.Date(character()), series_code = character(), value = numeric()))
  }
  ddf <- df_with_freq %>% dplyr::filter(toupper(Periodicity) == "D")
  if (nrow(ddf) == 0) return(data.frame(date = as.Date(character()), series_code = character(), value = numeric()))
  ddf <- ddf %>% dplyr::mutate(mon = lubridate::floor_date(date, "month"))
  current_mon <- lubridate::floor_date(Sys.Date(), "month")
  out <- ddf %>% dplyr::group_by(series_code, mon) %>% dplyr::summarise(
    value = {
      vals <- value[!is.na(value)]
      if (length(vals) == 0) {
        as.numeric(NA)
      } else if (unique(mon) < current_mon) {
        mean(vals, na.rm = TRUE)
      } else {
        # current month: fallback to last up-to-7 days if very sparse
        n <- length(vals)
        if (n <= 7) mean(tail(vals, n), na.rm = TRUE) else mean(vals, na.rm = TRUE)
      }
    }, .groups = "drop"
  ) %>% dplyr::transmute(date = mon, series_code, value)
  out
}

build_transformed_panel <- function(raw_df, config_df) {
  # Attach frequency
  freq_map <- config_df %>% dplyr::select(Name, Periodicity) %>% dplyr::distinct(Name, .keep_all = TRUE)
  rdf <- raw_df %>% dplyr::left_join(freq_map, by = c("series_code" = "Name"))
  rdf$Periodicity <- toupper(rdf$Periodicity)
  # Normalize dates to period start
  rdf <- rdf %>% dplyr::mutate(
    date = dplyr::case_when(
      Periodicity == "M" ~ floor_date(date, unit = "month"),
      Periodicity == "Q" ~ floor_date(date, unit = "quarter"),
      TRUE ~ as.Date(date)
    )
  )

  # Date skeletons from 1940-01-01 to today
  start_date <- as.Date("1940-01-01")
  end_month <- floor_date(Sys.Date(), unit = "month")
  end_quarter <- floor_date(Sys.Date(), unit = "quarter")
  monthly_skel <- data.frame(date = seq(start_date, end_month, by = "month"))
  quarterly_skel <- data.frame(date = seq(floor_date(start_date, "quarter"), end_quarter, by = "quarter"))

  # Monthly wide: include native monthly plus daily aggregated to monthly
  monthly_m_long <- rdf %>% dplyr::filter(Periodicity == "M") %>% dplyr::select(date, series_code, value)
  monthly_d_long <- aggregate_daily_to_monthly(rdf) %>% dplyr::select(date, series_code, value)
  monthly_long <- dplyr::bind_rows(monthly_m_long, monthly_d_long)
  monthly_wide <- if (nrow(monthly_long) > 0) {
    w <- tidyr::pivot_wider(monthly_long, names_from = series_code, values_from = value)
    w <- dplyr::left_join(monthly_skel, w, by = "date") %>% dplyr::arrange(date)
  } else data.frame(date = monthly_skel$date)
  
  # Quarterly wide
  quarterly_long <- rdf %>% dplyr::filter(Periodicity == "Q") %>% dplyr::select(date, series_code, value)
  quarterly_wide <- if (nrow(quarterly_long) > 0) {
    w <- tidyr::pivot_wider(quarterly_long, names_from = series_code, values_from = value)
    w <- dplyr::left_join(quarterly_skel, w, by = "date") %>% dplyr::arrange(date)
  } else data.frame(date = quarterly_skel$date)
  
  # Compute transforms on wide
  if (nrow(monthly_wide) > 0) {
    base_cols <- setdiff(colnames(monthly_wide), "date")
    base_cols <- sort(base_cols)
    for (col in base_cols) {
      x <- monthly_wide[[col]]
      monthly_wide[[paste0("DA_", col)]] <- compute_DA(x, "M")
      monthly_wide[[paste0("DA3m_", col)]] <- compute_DA3m(x)
    }
    # Order columns: date, originals..., DA_..., DA3m_...
    da_cols <- paste0("DA_", base_cols)
    da3_cols <- paste0("DA3m_", base_cols)
    monthly_wide <- monthly_wide[, c("date", base_cols, da_cols, da3_cols), drop = FALSE]
  } else {
    monthly_wide <- data.frame(date = as.Date(character()))
  }
  
  if (nrow(quarterly_wide) > 0) {
    base_cols <- setdiff(colnames(quarterly_wide), "date")
    base_cols <- sort(base_cols)
    for (col in base_cols) {
      x <- quarterly_wide[[col]]
      quarterly_wide[[paste0("DA_", col)]] <- compute_DA(x, "Q")
    }
    da_cols <- paste0("DA_", base_cols)
    quarterly_wide <- quarterly_wide[, c("date", base_cols, da_cols), drop = FALSE]
  } else {
    quarterly_wide <- data.frame(date = as.Date(character()))
  }
  
  list(monthly = monthly_wide, quarterly = quarterly_wide)
}
