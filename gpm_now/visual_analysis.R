
# Visual Analysis Report for Variable Selection and Transformation Checking
# Generates: visual_analysis_report.pdf
# Includes:
# 1. Correlation Heatmap (Indicators vs Target)
# 2. Cross-Correlation Functions (CCF) - Lead/Lag analysis
# 3. Scatter Plots (Quarterly Aggregated Indicator vs Target)
# 4. Stationarity/Transformation Checks (Raw vs Transformed)

suppressPackageStartupMessages({
  library(yaml)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(ggplot2)
  library(gridExtra)
  library(lubridate)
  library(zoo)
})

# --- Setup Paths ---
args <- commandArgs(trailingOnly = FALSE)
script_path <- sub("--file=", "", args[grep("--file=", args)])
project_root <- if (length(script_path) == 0) getwd() else dirname(normalizePath(script_path))

# Load Config
variables_cfg_path <- file.path(project_root, "config", "variables.yaml")
if (!file.exists(variables_cfg_path)) stop("variables.yaml not found")
variables_cfg <- yaml::read_yaml(variables_cfg_path)

# Load Data
monthly_path <- file.path(project_root, "retriever", "brazil", "output", "transformed_data", "monthly.csv")
quarterly_path <- file.path(project_root, "retriever", "brazil", "output", "transformed_data", "quarterly.csv")

if (!file.exists(monthly_path) || !file.exists(quarterly_path)) {
  # Fallback to rolling data if standard paths don't exist
  monthly_path <- file.path(project_root, "..", "Data", "mex_M.csv")
  quarterly_path <- file.path(project_root, "..", "Data", "mex_Q.csv")
}

if (!file.exists(monthly_path)) stop("Monthly data not found")
if (!file.exists(quarterly_path)) stop("Quarterly data not found")

# Read Data
monthly <- read_csv(monthly_path, show_col_types = FALSE)
quarterly <- read_csv(quarterly_path, show_col_types = FALSE)

# Ensure Date columns
if (!"date" %in% names(monthly)) names(monthly)[1] <- "date"
if (!"date" %in% names(quarterly)) names(quarterly)[1] <- "date"
monthly$date <- as.Date(monthly$date)
quarterly$date <- as.Date(quarterly$date)

# Filter Data from 2003-01-01
start_date <- as.Date("2003-01-01")
monthly <- monthly %>% filter(date >= start_date)
quarterly <- quarterly %>% filter(date >= start_date)

cat("Monthly data range:", as.character(min(monthly$date)), "to", as.character(max(monthly$date)), "\n")
cat("Quarterly data range:", as.character(min(quarterly$date)), "to", as.character(max(quarterly$date)), "\n")
cat("Quarterly columns:", paste(names(quarterly), collapse=", "), "\n")

# Identify Target
target_col <- variables_cfg$target$id_q
if (is.null(target_col) || !target_col %in% names(quarterly)) {
  # Try to guess
  if ("DA_GDP" %in% names(quarterly)) {
    target_col <- "DA_GDP"
  } else if ("value" %in% names(quarterly)) {
    target_col <- "value"
  } else {
    stop("Target column not found in quarterly data. Available: ", paste(names(quarterly), collapse=", "))
  }
}
cat("Target Variable:", target_col, "\n")

# --- Helper Functions ---

# Aggregate Monthly to Quarterly (Mean)
monthly_to_quarterly <- function(m_df) {
  m_df %>%
    mutate(q_date = as.Date(as.yearqtr(date))) %>%
    group_by(q_date) %>%
    summarise(across(where(is.numeric), function(x) mean(x, na.rm = TRUE))) %>%
    rename(date = q_date)
}

# Apply Transform (Simple version for analysis)
apply_transform <- function(x, type) {
  switch(type,
         "level" = x,
         "log" = log(x),
         "diff" = c(NA, diff(x)),
         "pct_change" = c(NA, diff(x)/head(x, -1) * 100),
         "diff4" = c(rep(NA, 4), diff(x, 4)),
         "pct_yoy" = c(rep(NA, 12), (x[13:length(x)]/x[1:(length(x)-12)] - 1) * 100),
         x)
}

# --- Prepare Data for Analysis ---

# 1. Aggregate Monthly to Quarterly for Correlation/Scatter
monthly_q <- monthly_to_quarterly(monthly)

# Normalize Quarterly Dates to Start of Quarter for Joining
quarterly_norm <- quarterly %>%
  mutate(date = as.Date(as.yearqtr(date)))

# Merge with Target
analysis_df <- inner_join(monthly_q, quarterly_norm %>% select(date, all_of(target_col)), by = "date")
target_vec <- analysis_df[[target_col]]

# Get Indicators (only those present in analysis_df)
indicators <- setdiff(names(analysis_df), c("date", target_col))
cat("Number of indicators to analyze:", length(indicators), "\n")

# --- Generate PDF Report ---
output_file <- "visual_analysis_report.pdf"
pdf(output_file, width = 10, height = 8)

# 1. Correlation Heatmap (Top 20 correlated)
cor_vals <- sapply(indicators, function(ind) {
  res <- tryCatch(
    cor(analysis_df[[ind]], target_vec, use = "complete.obs"),
    error = function(e) NA
  )
  if (is.na(res)) return(0) # Handle NA
  return(res)
})
cor_df <- data.frame(indicator = names(cor_vals), correlation = cor_vals) %>%
  arrange(desc(abs(correlation))) %>%
  head(20)

p1 <- ggplot(cor_df, aes(x = reorder(indicator, correlation), y = correlation, fill = correlation)) +
  geom_col() +
  coord_flip() +
  scale_fill_gradient2(low = "red", mid = "white", high = "blue", midpoint = 0) +
  labs(title = "Top 20 Indicators Correlated with Target (Quarterly Aggregated)",
       x = "Indicator", y = "Correlation") +
  theme_minimal()

print(p1)

# 2. Scatter Plots & CCF for each Indicator
for (ind in indicators) {
  
  # Check for sufficient data
  valid_data <- analysis_df %>% 
    select(all_of(c(ind, target_col))) %>% 
    na.omit()
  
  if (nrow(valid_data) < 10) {
    cat("Skipping", ind, "- insufficient overlapping data\n")
    next
  }
  
  # A. Scatter Plot (Quarterly)
  p_scatter <- ggplot(analysis_df, aes_string(x = ind, y = target_col)) +
    geom_point(alpha = 0.6) +
    geom_smooth(method = "lm", se = FALSE, color = "blue", linetype = "dashed") +
    labs(title = paste("Scatter:", ind, "vs Target"),
         subtitle = paste("Corr:", round(cor(valid_data[[ind]], valid_data[[target_col]]), 2))) +
    theme_minimal()
  
  # B. CCF Plot (Monthly Interpolated Target vs Monthly Indicator)
  # We interpolate target to monthly to do a finer lag analysis
  # Or better: We just use the quarterly aggregated data for CCF (Lags are in Quarters)
  
  ccf_res <- tryCatch(
    ccf(valid_data[[ind]], valid_data[[target_col]], plot = FALSE, lag.max = 4),
    error = function(e) NULL
  )
  
  if (!is.null(ccf_res)) {
    ccf_df <- data.frame(lag = ccf_res$lag, acf = ccf_res$acf)
    
    p_ccf <- ggplot(ccf_df, aes(x = lag, y = acf)) +
      geom_col(fill = "steelblue") +
      geom_hline(yintercept = c(0.2, -0.2), linetype = "dashed", color = "red") + # Approx significance
      labs(title = paste("Cross-Correlation (Quarterly Lags):", ind),
           x = "Lag (Quarters)", y = "Correlation") +
      theme_minimal()
  } else {
    p_ccf <- ggplot() + labs(title = "CCF Failed") + theme_void()
  }
  
  # C. Time Series Overlay (Scaled)
  # Scale both to mean 0 sd 1 for comparison
  ts_df <- analysis_df %>%
    select(date, ind_val = all_of(ind), target_val = all_of(target_col)) %>%
    mutate(
      ind_scaled = scale(ind_val),
      target_scaled = scale(target_val)
    ) %>%
    pivot_longer(cols = c(ind_scaled, target_scaled), names_to = "series", values_to = "value")
  
  p_ts <- ggplot(ts_df, aes(x = date, y = value, color = series)) +
    geom_line() +
    labs(title = paste("Standardized Time Series:", ind),
         y = "Z-Score") +
    theme_minimal() +
    theme(legend.position = "bottom")
  
  # Arrange on one page
  grid.arrange(p_scatter, p_ccf, p_ts, ncol = 2, layout_matrix = rbind(c(1, 2), c(3, 3)))
}

dev.off()
cat("Visual analysis report saved to:", output_file, "\n")
