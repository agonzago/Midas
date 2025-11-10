# Check if TPRF forecasts are correlated with lagged GDP
library(tools)
results <- read.csv("rolling_evaluation_results.csv", stringsAsFactors = FALSE)

# Extract TPRF and MIDAS forecasts - need to parse the forecast strings
parse_forecasts <- function(forecast_str) {
  # Remove trailing comma if present
  forecast_str <- gsub(",$", "", forecast_str)
  as.numeric(strsplit(forecast_str, ",")[[1]])
}

tprf_row <- results[results$spec == "TPRF_AR2_lag4_m2", ]
midas_row <- results[results$spec == "MIDAS_AR2_lag4_m2", ]

actuals <- parse_forecasts(tprf_row$actuals)
tprf_forecast <- parse_forecasts(tprf_row$forecasts)
midas_forecast <- parse_forecasts(midas_row$forecasts)

# Check correlation with lagged actual (this should be LOW if not lagging)
cat("=== Correlation with lagged GDP (should be low) ===\n")
cat("TPRF forecast vs lagged actual:", cor(tprf_forecast[-1], actuals[-length(actuals)]), "\n")
cat("MIDAS forecast vs lagged actual:", cor(midas_forecast[-1], actuals[-length(actuals)]), "\n")

cat("\n=== Correlation with current GDP (should be high) ===\n")
cat("TPRF forecast vs current actual:", cor(tprf_forecast, actuals), "\n")
cat("MIDAS forecast vs current actual:", cor(midas_forecast, actuals), "\n")

# Show first 10 forecasts for manual inspection
dates <- parse_forecasts(tprf_row$dates)
cat("\n=== First 10 forecasts vs actuals ===\n")
cat("Obs  | Actual | TPRF  | MIDAS | TPRF_err | MIDAS_err\n")
cat("-----|--------|-------|-------|----------|----------\n")
for(i in 1:min(10, length(actuals))) {
  cat(sprintf("%-4d | %6.2f | %5.2f | %5.2f | %8.2f | %9.2f\n",
              i,
              actuals[i],
              tprf_forecast[i],
              midas_forecast[i],
              tprf_forecast[i] - actuals[i],
              midas_forecast[i] - actuals[i]))
}
