# runner.R
# Weekly nowcast runner - main entry point

#' Run weekly nowcast
#' @param as_of_date Date for the nowcast (default: today)
#' @param config_path Path to config directory
#' @param data_path Path to data directory
#' @param output_path Path to output directory
#' @return List with nowcast results
run_weekly_nowcast <- function(as_of_date = Sys.Date(), 
                                config_path = "config",
                                data_path = "data",
                                output_path = "output") {
  
  # Source all required modules
  source("R/utils.R")
  source("R/io.R")
  source("R/transforms.R")
  source("R/lagmap.R")
  source("R/midas_models.R")
  source("R/tprf_models.R")
  source("R/dfm_models.R")
  source("R/selection.R")
  source("R/combine.R")
  source("R/news.R")
  
  log_file <- file.path(output_path, "logs", paste0("nowcast_", as_of_date, ".log"))
  dir.create(dirname(log_file), showWarnings = FALSE, recursive = TRUE)
  
  log_message("Starting weekly nowcast", "INFO", log_file)
  log_message(paste("As-of date:", as_of_date), "INFO", log_file)
  
  # Load configurations
  tryCatch({
    log_message("Loading configurations...", "INFO", log_file)
    
    cfg <- list(
      variables = read_variables(config_path),
      options = read_options(config_path),
      calendar = read_calendar(config_path)
    )
    
    # Merge options into cfg for easier access
    cfg <- c(cfg, cfg$options)
    
    vars <- cfg$variables
    cal <- cfg$calendar
    
    log_message("Configurations loaded successfully", "INFO", log_file)
    
  }, error = function(e) {
    log_message(paste("Failed to load configurations:", e$message), "ERROR", log_file)
    stop(e)
  })
  
  # Load data
  tryCatch({
    log_message("Loading data...", "INFO", log_file)
    
    target_id_q <- if (!is.null(vars$target$id_q)) vars$target$id_q else NULL
    target_id_m <- if (!is.null(vars$target$id_m_proxy)) vars$target$id_m_proxy else NULL
    
    y_q <- load_quarterly_target(
      data_path = file.path(data_path, "quarterly"),
      target_id = target_id_q
    )
    
    X_m <- load_monthly_panel(
      data_path = file.path(data_path, "monthly")
    )
    
    y_m_proxy <- load_monthly_proxy(
      data_path = file.path(data_path, "monthly"),
      proxy_id = target_id_m
    )
    
    log_message(paste("Loaded quarterly data:", nrow(y_q), "observations"), "INFO", log_file)
    log_message(paste("Loaded monthly panel:", nrow(X_m), "observations"), "INFO", log_file)
    
  }, error = function(e) {
    log_message(paste("Failed to load data:", e$message), "ERROR", log_file)
    stop(e)
  })
  
  # Build vintage snapshot
  tryCatch({
    log_message("Building vintage snapshot...", "INFO", log_file)
    
    vint <- build_vintage_snapshot(X_m, y_q, y_m_proxy, cal, as_of_date)
    
    # Save vintage
    vintage_file <- file.path(data_path, "vintages", paste0(as_of_date, ".rds"))
    save_vintage(vint, vintage_file)
    
    log_message(paste("Vintage saved to:", vintage_file), "INFO", log_file)
    
  }, error = function(e) {
    log_message(paste("Failed to build vintage:", e$message), "ERROR", log_file)
    stop(e)
  })
  
  # Build lag map
  tryCatch({
    log_message("Building lag map...", "INFO", log_file)
    
    lag_map <- build_lag_map(as_of_date, vars, cal)
    
    log_message(paste("Lag map built for quarter:", lag_map$current_quarter), "INFO", log_file)
    
  }, error = function(e) {
    log_message(paste("Failed to build lag map:", e$message), "WARN", log_file)
    # Continue with NULL lag_map
    lag_map <- NULL
  })
  
  # Initialize results
  all_fcsts <- list()
  models_updated <- c()
  
  # U-MIDAS per indicator
  tryCatch({
    log_message("Fitting/updating U-MIDAS models...", "INFO", log_file)
    
    midas_indiv <- fit_or_update_midas_set(vint, lag_map, cfg)
    
    if (length(midas_indiv) > 0) {
      all_fcsts <- c(all_fcsts, midas_indiv)
      models_updated <- c(models_updated, paste0("midas_", names(midas_indiv)))
      log_message(paste("U-MIDAS models fitted:", length(midas_indiv)), "INFO", log_file)
    }
    
  }, error = function(e) {
    log_message(paste("U-MIDAS fitting failed:", e$message), "WARN", log_file)
  })
  
  # 3PF/TPRF
  tryCatch({
    log_message("Updating TPRF model...", "INFO", log_file)
    
    tprf_fcst <- maybe_update_tprf(vint, lag_map, cfg)
    
    if (!is.null(tprf_fcst)) {
      all_fcsts$tprf <- tprf_fcst
      models_updated <- c(models_updated, "tprf")
      log_message("TPRF model updated", "INFO", log_file)
    }
    
  }, error = function(e) {
    log_message(paste("TPRF update failed:", e$message), "WARN", log_file)
  })
  
  # DFM
  tryCatch({
    log_message("Updating DFM model...", "INFO", log_file)
    
    dfm <- maybe_update_dfm(vint, cfg)
    
    if (!is.null(dfm)) {
      log_message(paste("DFM fitted with k =", dfm$k_selected, "factors"), "INFO", log_file)
      
      # DFM-MIDAS forecast
      dfm_midas_fcst <- predict_dfm_midas(
        fit_dfm_midas(vint$y_q$value, dfm$factors_m, lag_map, cfg$window),
        dfm$factors_m,
        lag_map
      )
      
      if (!is.null(dfm_midas_fcst)) {
        all_fcsts$dfm_midas <- dfm_midas_fcst
        models_updated <- c(models_updated, "dfm_midas")
      }
      
      # DFM State-Space forecast (if enabled and proxy available)
      dfm_ss_fcst <- maybe_predict_dfm_state_space(dfm, vint, lag_map, cfg)
      
      if (!is.null(dfm_ss_fcst)) {
        all_fcsts$dfm_ss <- dfm_ss_fcst
        models_updated <- c(models_updated, "dfm_ss")
        log_message("DFM state-space forecast generated", "INFO", log_file)
      }
    }
    
  }, error = function(e) {
    log_message(paste("DFM update failed:", e$message), "WARN", log_file)
  })
  
  # Combine forecasts
  tryCatch({
    log_message("Combining forecasts...", "INFO", log_file)
    
    if (length(all_fcsts) == 0) {
      log_message("No forecasts available to combine", "ERROR", log_file)
      combo <- list(point = NA, lo = NA, hi = NA, weights = NA)
    } else {
      combo_scheme <- if (!is.null(cfg$combination$scheme)) {
        cfg$combination$scheme
      } else {
        "equal"
      }
      
      combo <- combine_forecasts(all_fcsts, scheme = combo_scheme, history = NULL)
      
      log_message(paste("Combined nowcast:", round(combo$point, 2)), "INFO", log_file)
      log_message(paste("95% interval: [", round(combo$lo, 2), ",", round(combo$hi, 2), "]"), "INFO", log_file)
    }
    
  }, error = function(e) {
    log_message(paste("Forecast combination failed:", e$message), "ERROR", log_file)
    combo <- list(point = NA, lo = NA, hi = NA, weights = NA)
  })
  
  # News decomposition
  news_tbl <- NULL
  tryCatch({
    log_message("Computing news decomposition...", "INFO", log_file)
    
    fcsts_prev <- load_previous_forecasts(as_of_date, output_path = file.path(output_path, "weekly_reports"))
    
    if (!is.null(fcsts_prev)) {
      # Reconstruct previous forecasts structure
      fcsts_prev_list <- list()
      
      if (!is.null(fcsts_prev$individual_forecasts)) {
        for (i in seq_along(fcsts_prev$individual_forecasts)) {
          model_data <- fcsts_prev$individual_forecasts[[i]]
          if (!is.null(model_data$model)) {
            fcsts_prev_list[[model_data$model]] <- list(
              point = model_data$point,
              se = model_data$se
            )
          }
        }
      }
      
      fcsts_prev_list$combined <- list(point = fcsts_prev$combined_nowcast)
      
      news_tbl <- compute_news(as_of_date, all_fcsts, fcsts_prev_list, combo)
      
      if (!is.null(news_tbl) && nrow(news_tbl) > 0) {
        log_message(paste("News computed:", nrow(news_tbl), "changes"), "INFO", log_file)
      }
    } else {
      log_message("No previous forecasts found for news decomposition", "INFO", log_file)
    }
    
  }, error = function(e) {
    log_message(paste("News decomposition failed:", e$message), "WARN", log_file)
  })
  
  # Write outputs
  tryCatch({
    log_message("Writing weekly summary...", "INFO", log_file)
    
    write_weekly_summary(
      as_of_date = as_of_date,
      combo = combo,
      all_fcsts = all_fcsts,
      news_tbl = news_tbl,
      models_updated = models_updated,
      output_path = file.path(output_path, "weekly_reports")
    )
    
    log_message("Weekly summary written successfully", "INFO", log_file)
    
  }, error = function(e) {
    log_message(paste("Failed to write outputs:", e$message), "ERROR", log_file)
  })
  
  log_message("Weekly nowcast completed", "INFO", log_file)
  
  # Return results
  result <- list(
    as_of_date = as_of_date,
    combined_forecast = combo,
    individual_forecasts = all_fcsts,
    news = news_tbl,
    models_updated = models_updated,
    current_quarter = if (!is.null(lag_map)) lag_map$current_quarter else NA
  )
  
  return(invisible(result))
}

# Example usage (commented out)
# result <- run_weekly_nowcast(as_of_date = Sys.Date())
# print(result$combined_forecast)
