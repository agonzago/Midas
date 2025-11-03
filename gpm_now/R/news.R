# news.R
# News decomposition - changes in nowcast vs. previous week

#' Compute news decomposition
#' @param as_of_date Current date
#' @param fcsts_now Current week's forecasts
#' @param fcsts_prev Previous week's forecasts
#' @param combo_now Current combined forecast
#' @return Data frame with news decomposition
compute_news <- function(as_of_date, fcsts_now, fcsts_prev, combo_now) {
  if (is.null(fcsts_prev)) {
    message("No previous forecasts available for news decomposition")
    return(NULL)
  }
  
  # Initialize news table
  news_records <- list()
  
  # Get previous combined forecast
  combo_prev <- if (!is.null(fcsts_prev$combined)) {
    fcsts_prev$combined$point
  } else {
    NA
  }
  
  # Overall nowcast change
  if (!is.na(combo_prev) && !is.na(combo_now$point)) {
    delta_nowcast <- combo_now$point - combo_prev
    
    news_records[[1]] <- data.frame(
      as_of_date = as.character(as_of_date),
      series_id = "COMBINED",
      ref_period = "current_quarter",
      delta_nowcast_pp = delta_nowcast,
      prev_value = combo_prev,
      new_value = combo_now$point,
      stringsAsFactors = FALSE
    )
  }
  
  # Model-level news
  for (model_name in names(fcsts_now)) {
    if (model_name == "combined") next
    
    curr_fcst <- fcsts_now[[model_name]]
    
    # Check if model existed in previous week
    if (model_name %in% names(fcsts_prev)) {
      prev_fcst <- fcsts_prev[[model_name]]
      
      curr_point <- if (!is.null(curr_fcst$point)) curr_fcst$point else NA
      prev_point <- if (!is.null(prev_fcst$point)) prev_fcst$point else NA
      
      if (!is.na(curr_point) && !is.na(prev_point)) {
        delta <- curr_point - prev_point
        
        news_records[[length(news_records) + 1]] <- data.frame(
          as_of_date = as.character(as_of_date),
          series_id = model_name,
          ref_period = "current_quarter",
          delta_nowcast_pp = delta,
          prev_value = prev_point,
          new_value = curr_point,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  
  # Combine all news records
  if (length(news_records) > 0) {
    news_tbl <- do.call(rbind, news_records)
    rownames(news_tbl) <- NULL
  } else {
    news_tbl <- data.frame(
      as_of_date = character(),
      series_id = character(),
      ref_period = character(),
      delta_nowcast_pp = numeric(),
      prev_value = numeric(),
      new_value = numeric(),
      stringsAsFactors = FALSE
    )
  }
  
  return(news_tbl)
}

#' Load previous week's forecasts
#' @param as_of_date Current date
#' @param lookback_days Days to look back for previous forecast
#' @param output_path Path to output directory
#' @return Previous forecasts or NULL
load_previous_forecasts <- function(as_of_date, lookback_days = 7, output_path = "output/weekly_reports") {
  prev_date <- as_of_date - lookback_days
  
  # Try to find the most recent forecast before current date
  # Check for files in output directory
  
  if (!dir.exists(output_path)) {
    return(NULL)
  }
  
  json_files <- list.files(output_path, pattern = "^summary_.*\\.json$", full.names = TRUE)
  
  if (length(json_files) == 0) {
    return(NULL)
  }
  
  # Extract dates from filenames
  dates <- gsub(".*summary_([0-9-]+)\\.json", "\\1", basename(json_files))
  dates <- as.Date(dates)
  
  # Find most recent date before current date
  valid_dates <- dates[dates < as_of_date]
  
  if (length(valid_dates) == 0) {
    return(NULL)
  }
  
  most_recent <- max(valid_dates)
  most_recent_file <- json_files[dates == most_recent][1]
  
  # Load JSON
  if (requireNamespace("jsonlite", quietly = TRUE)) {
    tryCatch({
      prev_data <- jsonlite::read_json(most_recent_file, simplifyVector = TRUE)
      return(prev_data)
    }, error = function(e) {
      warning("Failed to load previous forecasts: ", e$message)
      return(NULL)
    })
  } else {
    warning("Package 'jsonlite' required to load previous forecasts")
    return(NULL)
  }
}

#' Decompose nowcast change into contributions
#' @param fcsts_now Current forecasts
#' @param fcsts_prev Previous forecasts
#' @param weights Current combination weights
#' @return Data frame with contribution decomposition
decompose_nowcast_change <- function(fcsts_now, fcsts_prev, weights) {
  if (is.null(fcsts_prev) || is.null(weights)) {
    return(NULL)
  }
  
  contributions <- list()
  
  for (model_name in names(weights)) {
    if (model_name %in% names(fcsts_now) && model_name %in% names(fcsts_prev)) {
      curr_point <- if (!is.null(fcsts_now[[model_name]]$point)) {
        fcsts_now[[model_name]]$point
      } else {
        NA
      }
      
      prev_point <- if (!is.null(fcsts_prev[[model_name]]$point)) {
        fcsts_prev[[model_name]]$point
      } else {
        NA
      }
      
      if (!is.na(curr_point) && !is.na(prev_point)) {
        model_delta <- curr_point - prev_point
        weight <- weights[[model_name]]
        
        contribution <- weight * model_delta
        
        contributions[[model_name]] <- data.frame(
          model = model_name,
          weight = weight,
          model_delta = model_delta,
          contribution = contribution,
          stringsAsFactors = FALSE
        )
      }
    }
  }
  
  if (length(contributions) > 0) {
    contrib_df <- do.call(rbind, contributions)
    rownames(contrib_df) <- NULL
    return(contrib_df)
  } else {
    return(NULL)
  }
}

#' Create news summary report
#' @param news_tbl News table from compute_news
#' @param contrib_df Contribution decomposition
#' @return Formatted summary text
create_news_summary <- function(news_tbl, contrib_df = NULL) {
  if (is.null(news_tbl) || nrow(news_tbl) == 0) {
    return("No news to report.")
  }
  
  # Find overall change
  combined_row <- news_tbl[news_tbl$series_id == "COMBINED", ]
  
  if (nrow(combined_row) > 0) {
    delta <- combined_row$delta_nowcast_pp[1]
    direction <- if (delta > 0) "increased" else "decreased"
    
    summary_lines <- c(
      sprintf("Nowcast %s by %.2f pp", direction, abs(delta)),
      sprintf("  Previous: %.2f", combined_row$prev_value[1]),
      sprintf("  Current:  %.2f", combined_row$new_value[1])
    )
  } else {
    summary_lines <- c("Combined nowcast not available")
  }
  
  # Add model-level changes
  model_rows <- news_tbl[news_tbl$series_id != "COMBINED", ]
  
  if (nrow(model_rows) > 0) {
    summary_lines <- c(summary_lines, "", "Model-level changes:")
    
    for (i in 1:nrow(model_rows)) {
      row <- model_rows[i, ]
      summary_lines <- c(
        summary_lines,
        sprintf("  %s: %.2f → %.2f (Δ %.2f pp)", 
                row$series_id, row$prev_value, row$new_value, row$delta_nowcast_pp)
      )
    }
  }
  
  # Add contributions if available
  if (!is.null(contrib_df) && nrow(contrib_df) > 0) {
    summary_lines <- c(summary_lines, "", "Contributions to change:")
    
    # Sort by absolute contribution
    contrib_df <- contrib_df[order(abs(contrib_df$contribution), decreasing = TRUE), ]
    
    for (i in 1:nrow(contrib_df)) {
      row <- contrib_df[i, ]
      summary_lines <- c(
        summary_lines,
        sprintf("  %s: %.3f pp (weight: %.2f, model Δ: %.2f)", 
                row$model, row$contribution, row$weight, row$model_delta)
      )
    }
  }
  
  paste(summary_lines, collapse = "\n")
}
