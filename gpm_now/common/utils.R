# utils.R
# Utility functions for date handling, quarter operations, and logging

#' Convert date to quarter
#' @param date A Date object
#' @return A character string in format "YYYYQQ"
date_to_quarter <- function(date) {
  year <- format(date, "%Y")
  quarter <- ceiling(as.numeric(format(date, "%m")) / 3)
  paste0(year, "Q", quarter)
}

#' Convert quarter string to Date (first day of quarter)
#' @param quarter_str A string in format "YYYYQQ"
#' @return A Date object
quarter_to_date <- function(quarter_str) {
  year <- as.numeric(substr(quarter_str, 1, 4))
  q <- as.numeric(substr(quarter_str, 6, 6))
  month <- (q - 1) * 3 + 1
  as.Date(paste0(year, "-", sprintf("%02d", month), "-01"))
}

#' Get current quarter for a given date
#' @param as_of_date A Date object
#' @return A character string representing the current quarter
get_current_quarter <- function(as_of_date = Sys.Date()) {
  date_to_quarter(as_of_date)
}

#' Get quarter for a month
#' @param year Integer year
#' @param month Integer month (1-12)
#' @return Character string quarter "YYYYQQ"
month_to_quarter <- function(year, month) {
  quarter <- ceiling(month / 3)
  paste0(year, "Q", quarter)
}

#' Check if a quarter is complete given an as_of_date
#' @param quarter_str Quarter string "YYYYQQ"
#' @param as_of_date Date object
#' @return Logical indicating if quarter is complete
is_quarter_complete <- function(quarter_str, as_of_date) {
  quarter_end <- quarter_to_date(quarter_str)
  year <- as.numeric(substr(quarter_str, 1, 4))
  q <- as.numeric(substr(quarter_str, 6, 6))
  last_month <- q * 3
  quarter_end <- as.Date(paste0(year, "-", sprintf("%02d", last_month), "-01"))
  # Add one month and subtract one day to get last day of quarter
  quarter_end <- seq(quarter_end, by = "1 month", length.out = 2)[2] - 1
  
  return(as_of_date > quarter_end)
}

#' Log a message with timestamp
#' @param msg Message to log
#' @param level Log level (INFO, WARN, ERROR)
#' @param log_file Optional file path to write log
log_message <- function(msg, level = "INFO", log_file = NULL) {
  timestamp <- format(Sys.time(), "%Y-%m-%d %H:%M:%S")
  log_line <- sprintf("[%s] %s: %s", timestamp, level, msg)
  message(log_line)
  
  if (!is.null(log_file)) {
    write(log_line, file = log_file, append = TRUE)
  }
}

#' Get months in a quarter
#' @param quarter_str Quarter string "YYYYQQ"
#' @return Vector of month numbers (1-12)
get_quarter_months <- function(quarter_str) {
  q <- as.numeric(substr(quarter_str, 6, 6))
  ((q - 1) * 3 + 1):(q * 3)
}

#' Get year-month string
#' @param year Integer year
#' @param month Integer month
#' @return Character string "YYYY-MM"
make_yearmon <- function(year, month) {
  paste0(year, "-", sprintf("%02d", month))
}
