# Plot summary graphs for U-MIDAS combined nowcasts
# Outputs:
# - data/combination/umidas_fanchart_current_quarter.png
# - data/combination/umidas_latest_by_quarter.png

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
})

# Ensure ggplot2 is available
if (!requireNamespace("ggplot2", quietly = TRUE)) {
  install.packages("ggplot2", repos = "https://cloud.r-project.org")
}
library(ggplot2)

args <- commandArgs(trailingOnly = TRUE)
param <- list(
  combined_file = ifelse(length(args) >= 1, args[[1]], file.path("..", "midas_model_selection", "data", "combination", "umidas_combined_nowcasts.csv")),
  latest_file   = ifelse(length(args) >= 2, args[[2]], file.path("..", "midas_model_selection", "data", "combination", "umidas_combined_nowcasts_latest.csv")),
  out_dir       = ifelse(length(args) >= 3, args[[3]], file.path("..", "midas_model_selection", "data", "combination"))
)

for (d in c(param$out_dir)) if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)

if (!file.exists(param$combined_file)) stop("Combined file not found: ", param$combined_file)
if (!file.exists(param$latest_file)) stop("Latest file not found: ", param$latest_file)

all_dt <- fread(param$combined_file)
all_dt[, test_date := as.Date(test_date)]
latest <- fread(param$latest_file)

# Helper to parse quarter string to end-of-quarter date
q_end <- function(qstr) {
  y <- as.integer(substr(qstr, 1, 4))
  q <- as.integer(substr(qstr, 6, 6))
  m <- c(3, 6, 9, 12)[q]
  as.Date(sprintf("%04d-%02d-%02d", y, m, days_in_month(ymd(sprintf("%04d-%02d-01", y, m)))))
}

# 1) Fan chart for the current/latest quarter (over Fridays)
# Pick the most recent quarter available in combined data (by max test_date)
latest_q <- all_dt[which.max(test_date), quarter]
fc <- all_dt[quarter == latest_q]
if (nrow(fc) > 0) {
  p1 <- ggplot(fc, aes(x = test_date)) +
    geom_ribbon(aes(ymin = p10, ymax = p90), fill = "#2c7fb86E", color = NA) +
    geom_line(aes(y = median), color = "#1b9e77", linewidth = 0.8, linetype = "dashed") +
    geom_line(aes(y = comb_bic), color = "#d95f02", linewidth = 1.0) +
    geom_point(aes(y = y_true), color = "#7570b3", size = 2, alpha = 0.7) +
    labs(title = paste0("U-MIDAS nowcast distribution and BIC-weighted path — ", latest_q),
         subtitle = "Ribbon: p10–p90, dashed: median, orange: BIC-weighted, purple: actual if available",
         x = "Friday vintage", y = "Nowcast") +
    theme_minimal(base_size = 12)
  outf1 <- file.path(param$out_dir, "umidas_fanchart_current_quarter.png")
  ggsave(outf1, p1, width = 10, height = 5.5, dpi = 120)
  cat("Saved:", outf1, "\n")
}

# 2) Latest-per-quarter view: show comb_bic with trimmed range as error bars and actuals
if (nrow(latest) > 0) {
  latest[, q_end_date := q_end(quarter)]
  p2 <- ggplot(latest, aes(x = q_end_date, y = comb_bic)) +
    geom_errorbar(aes(ymin = trimmed_low, ymax = trimmed_high), width = 15, color = "#2c7fb8") +
    geom_line(color = "#d95f02", linewidth = 1.0) +
    geom_point(color = "#d95f02", size = 2) +
    geom_point(aes(y = y_true), color = "#7570b3", size = 2, alpha = 0.85) +
    labs(title = "U-MIDAS combined nowcasts (latest per quarter)",
         subtitle = "Orange: BIC-weighted latest; error bars: trimmed (10%) range; purple: actual",
         x = "Quarter (end date)", y = "Nowcast / Actual") +
    theme_minimal(base_size = 12)
  outf2 <- file.path(param$out_dir, "umidas_latest_by_quarter.png")
  ggsave(outf2, p2, width = 10, height = 5.5, dpi = 120)
  cat("Saved:", outf2, "\n")
}
