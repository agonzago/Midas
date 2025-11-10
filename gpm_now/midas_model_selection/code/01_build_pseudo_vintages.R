# Pseudo-real-time vintage builder for U-MIDAS nowcasting (gpm_now)
# - Builds ragged vintages for each Friday in target quarters
# - Uses approx_lag_days from calendar (default 0 days => end-of-month availability)
# - Input monthly/quarterly from retriever/brazil/output/transformed_data
# - Saves one RDS per quarter under gpm_now/midas_model_selection/data/vintages

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(stringr)
})

utils::globalVariables(c("est_release"))

# --------- Parameters ---------
args <- commandArgs(trailingOnly = TRUE)
param <- list(
  monthly_file = ifelse(length(args) >= 1, args[[1]], file.path("..", "retriever", "brazil", "output", "transformed_data", "monthly.csv")),
  quarterly_file = ifelse(length(args) >= 2, args[[2]], file.path("..", "retriever", "brazil", "output", "transformed_data", "quarterly.csv")),
  calendar_file = ifelse(length(args) >= 3, args[[3]], file.path("..", "retriever", "Initial_calendar.csv")),
  out_dir = ifelse(length(args) >= 4, args[[4]], file.path(".", "..", "midas_model_selection", "data", "vintages")),
  start_quarter = ifelse(length(args) >= 5, args[[5]], "2022Q1"),
  end_quarter   = ifelse(length(args) >= 6, args[[6]], "2025Q2"),
  default_lag_days = ifelse(length(args) >= 7, as.integer(args[[7]]), 0L)
)

if (!dir.exists(param$out_dir)) dir.create(param$out_dir, recursive = TRUE, showWarnings = FALSE)

monthly <- fread(param$monthly_file)
stopifnot("date" %in% names(monthly))
monthly[, date := as.Date(date)]

quarterly <- fread(param$quarterly_file)
stopifnot("date" %in% names(quarterly))
quarterly[, date := as.Date(date)]

# Calendar to lag map (may not match names -> default lag 0)
lag_map <- list()
if (file.exists(param$calendar_file)) {
  cal <- suppressWarnings(fread(param$calendar_file))
  code_col <- intersect(c("variable_code", "series_id"), names(cal))
  if (length(code_col) == 1 && "approx_lag_days" %in% names(cal)) {
    cal_sub <- unique(cal[, .SD, .SDcols = c(code_col, "approx_lag_days")])
    setnames(cal_sub, c("code", "lag"))
    cal_sub <- cal_sub[!is.na(lag), .(lag = as.integer(lag[1L])), by = code]
    lag_map <- setNames(cal_sub$lag, cal_sub$code)
  }
}

indicators <- setdiff(names(monthly), "date")

get_lag_days <- function(var) {
  if (length(lag_map) > 0 && var %in% names(lag_map)) return(as.integer(lag_map[[var]]))
  if (length(lag_map) > 0) {
    key <- names(lag_map)[tolower(names(lag_map)) == tolower(var)]
    if (length(key) == 1) return(as.integer(lag_map[[key]]))
  }
  param$default_lag_days
}

q_end_date <- function(qstr) {
  y <- as.integer(substr(qstr, 1, 4))
  q <- as.integer(substr(qstr, 6, 6))
  mm <- c(3, 6, 9, 12)[q]
  as.Date(paste0(y, "-", sprintf("%02d", mm), "-", days_in_month(mm)))
}

quarter_fridays <- function(qstr) {
  y <- as.integer(substr(qstr, 1, 4))
  q <- as.integer(substr(qstr, 6, 6))
  start_month <- c(1, 4, 7, 10)[q]
  start_date <- as.Date(paste0(y, "-", sprintf("%02d", start_month), "-01"))
  end_date <- q_end_date(qstr)
  days <- seq.Date(start_date, end_date, by = "day")
  days[weekdays(days) == "Friday"]
}

month_end <- function(d) as.Date(floor_date(d, unit = "month") + months(1) - days(1))

last_available_month <- function(var, test_date) {
  lag_days <- get_lag_days(var)
  releases <- data.table(date = monthly$date, est_release = month_end(monthly$date) + days(lag_days))
  avail <- releases[releases[["est_release"]] <= test_date]
  if (nrow(avail) == 0) return(as.Date(NA))
  max(avail$date)
}

q_seq <- function(q1, q2) {
  y1 <- as.integer(substr(q1, 1, 4)); q1n <- as.integer(substr(q1, 6, 6))
  y2 <- as.integer(substr(q2, 1, 4)); q2n <- as.integer(substr(q2, 6, 6))
  n <- (y2 - y1) * 4 + (q2n - q1n)
  out <- character(n + 1)
  y <- y1; q <- q1n
  for (i in 0:n) {
    out[i + 1] <- paste0(y, "Q", q)
    q <- q + 1
    if (q == 5) { q <- 1; y <- y + 1 }
  }
  out
}

quarters <- q_seq(param$start_quarter, param$end_quarter)

for (q in quarters) {
  fridays <- quarter_fridays(q)
  q_end <- q_end_date(q)
  vintages <- vector("list", length(fridays)); names(vintages) <- as.character(fridays)
  for (i in seq_along(fridays)) {
    td <- fridays[i]
    avail_tbl <- rbindlist(lapply(indicators, function(v) {
      lm <- last_available_month(v, td)
      h <- if (is.na(lm)) NA_integer_ else interval(month_end(lm), month_end(q_end)) %/% months(1)
      data.table(variable = v, last_month = lm, horizon_months = as.integer(h))
    }), fill = TRUE)
    
    # Create actual data slices for this vintage
    # Filter monthly data to only include observations available as of test_date
    monthly_slice <- monthly[date <= td]
    
    # For each variable, further filter by its specific release date
    monthly_vintage <- rbindlist(lapply(indicators, function(v) {
      var_avail <- avail_tbl[variable == v]
      if (nrow(var_avail) == 0 || is.na(var_avail$last_month[1])) {
        return(NULL)
      }
      last_month_date <- var_avail$last_month[1]
      var_data <- monthly_slice[date <= last_month_date, .(date, value = get(v))]
      var_data[, variable := v]
      return(var_data)
    }), fill = TRUE)
    
    # Filter quarterly data up to test_date (only complete quarters)
    quarterly_slice <- quarterly[date <= td]
    
    # Store both metadata and actual data
    vintages[[i]] <- list(
      test_date = td, 
      quarter = q, 
      quarter_end = q_end, 
      availability = avail_tbl,
      monthly_data = monthly_vintage,
      quarterly_data = quarterly_slice
    )
    names(vintages)[i] <- as.character(td)
  }
  out_file <- file.path(param$out_dir, paste0("pseudo_vintages_", q, ".rds"))
  saveRDS(vintages, out_file)
  cat("Saved:", out_file, "with", length(vintages), "weekly vintages\n")
  
  # Validation: check cumulative property
  if (length(vintages) >= 2) {
    v1_rows <- nrow(vintages[[1]]$monthly_data)
    v2_rows <- nrow(vintages[[2]]$monthly_data)
    if (v2_rows >= v1_rows) {
      cat("  Validation: Week 2 has", v2_rows - v1_rows, "more rows than Week 1 (cumulative OK)\n")
    } else {
      cat("  WARNING: Week 2 has fewer rows than Week 1 - check cumulative logic!\n")
    }
  }
}

cat("Done.\n")
