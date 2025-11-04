# Pseudo-real-time vintage builder for U-MIDAS nowcasting
# - Builds ragged vintages for each Friday in target quarters
# - Uses approx_lag_days from calendar (default 1 day when missing)
# - Saves one RDS per quarter with all Friday vintages and metadata

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(stringr)
  library(readr)
  library(dplyr)
})

# Silence NSE notes for data.table
utils::globalVariables(c(".", "est_release"))

# --------- Parameters (can be overridden via command line) ---------
args <- commandArgs(trailingOnly = TRUE)
param <- list(
  monthly_file = ifelse(length(args) >= 1, args[[1]], file.path("..", "..", "gpm_now", "data", "monthly", "monthly_data.csv")),
  quarterly_file = ifelse(length(args) >= 2, args[[2]], file.path("..", "..", "gpm_now", "data", "quarterly", "quarterly_data.csv")),
  calendar_file = ifelse(length(args) >= 3, args[[3]], file.path("..", "..", "gpm_now", "retriever", "Initial_calendar.csv")),
  out_dir = ifelse(length(args) >= 4, args[[4]], file.path("..", "data", "vintages")),
  start_quarter = ifelse(length(args) >= 5, args[[5]], "2022Q1"),
  end_quarter   = ifelse(length(args) >= 6, args[[6]], "2025Q2"),
  # For variables without explicit calendar info assume data is available at end-of-month -> lag 0
  default_lag_days = ifelse(length(args) >= 7, as.integer(args[[7]]), 0L)
)

# Ensure output dir exists
if (!dir.exists(param$out_dir)) dir.create(param$out_dir, recursive = TRUE, showWarnings = FALSE)

message("Parameters:")
print(param)

# --------- Load data ---------
monthly <- fread(param$monthly_file)
# Expect wide format: date + columns = indicators (possibly transformed)
if (!"date" %in% names(monthly)) stop("monthly data must contain a 'date' column (month-end dates)")
monthly[, date := as.Date(date)]

quarterly <- fread(param$quarterly_file)
if (!"date" %in% names(quarterly)) stop("quarterly data must contain a 'date' column (quarter-end dates)")
quarterly[, date := as.Date(date)]

# Map columns to approx_lag_days via calendar when available
lag_map <- list()
if (file.exists(param$calendar_file)) {
  cal <- suppressWarnings(fread(param$calendar_file))
  # Try to use column 'variable_code' if present; otherwise fall back to 'series_id'
  code_col <- intersect(c("variable_code", "series_id"), names(cal))
  lag_col <- intersect(c("approx_lag_days"), names(cal))
  if (length(code_col) == 1 && length(lag_col) == 1) {
    cal_sub <- cal[, .SD, .SDcols = c(code_col, lag_col)]
    setnames(cal_sub, c("code", "lag"))
    # Keep the latest non-NA lag per code
    cal_sub <- cal_sub[!is.na(lag), .(lag = as.integer(lag[1L])), by = code]
    lag_map <- setNames(cal_sub$lag, cal_sub$code)
  }
}

# Build list of indicators to process (exclude 'date')
indicators <- setdiff(names(monthly), "date")

# Helper: get approx lag for a variable (default when missing)
get_lag_days <- function(var) {
  if (length(lag_map) > 0 && var %in% names(lag_map)) return(as.integer(lag_map[[var]]))
  # Try loose match when calendar uses different naming (e.g., underscores vs dots)
  if (length(lag_map) > 0) {
    key <- names(lag_map)[str_to_lower(names(lag_map)) == str_to_lower(var)]
    if (length(key) == 1) return(as.integer(lag_map[[key]]))
  }
  # Not found -> default
  return(param$default_lag_days)
}

# Helper: quarter string to quarter end date
q_end_date <- function(qstr) {
  y <- as.integer(substr(qstr, 1, 4))
  q <- as.integer(substr(qstr, 6, 6))
  mm <- c(3, 6, 9, 12)[q]
  as.Date(paste0(y, "-", sprintf("%02d", mm), "-", days_in_month(mm)))
}

# Helper: list all Fridays within quarter
quarter_fridays <- function(qstr) {
  y <- as.integer(substr(qstr, 1, 4))
  q <- as.integer(substr(qstr, 6, 6))
  start_month <- c(1, 4, 7, 10)[q]
  start_date <- as.Date(paste0(y, "-", sprintf("%02d", start_month), "-01"))
  end_date <- q_end_date(qstr)
  days <- seq.Date(start_date, end_date, by = "day")
  days[weekdays(days) == "Friday"]
}

# Helper: vectorized month-end
month_end <- function(d) as.Date(floor_date(d, unit = "month") + months(1) - days(1))

# Given a variable and test_date, compute last available monthly observation date
last_available_month <- function(var, test_date) {
  lag_days <- get_lag_days(var)
  # For each monthly observation date, compute estimated release date = month_end(date) + lag_days
  releases <- data.table(
    date = monthly$date,
    est_release = month_end(monthly$date) + days(lag_days)
  )
  # Keep rows with release <= test_date
  avail <- releases[releases[["est_release"]] <= test_date]
  if (nrow(avail) == 0) return(as.Date(NA))
  return(max(avail$date))
}

# Build list of quarters to process
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

# Main loop: build vintages per quarter
for (q in quarters) {
  cat("Building vintages for", q, "...\n")
  fridays <- quarter_fridays(q)
  q_end <- q_end_date(q)

  vintages <- vector("list", length(fridays))
  names(vintages) <- as.character(fridays)

  for (td in fridays) {
    # For each variable, find last available month and compute horizon h = months between last available and quarter end
    avail_tbl <- lapply(indicators, function(v) {
      lm <- last_available_month(v, td)
      h <- if (is.na(lm)) NA_integer_ else interval(month_end(lm), month_end(q_end)) %/% months(1)
      data.table(variable = v, last_month = lm, horizon_months = as.integer(h))
    }) %>% rbindlist()

    vintages[[as.character(td)]] <- list(
      test_date = td,
      quarter = q,
      quarter_end = q_end,
      availability = avail_tbl
    )
  }

  out_file <- file.path(param$out_dir, paste0("pseudo_vintages_", q, ".rds"))
  saveRDS(vintages, out_file)
  cat("Saved:", out_file, "\n")
}

cat("Done.\n")
