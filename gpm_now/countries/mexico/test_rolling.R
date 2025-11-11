# Quick test to check if data loads correctly
library(zoo)

cat("Testing data load...\n")

# Load Mexico data
mex_Q <- read.csv("../../../Data/mex_Q.csv", row.names = 1)
mex_M <- read.csv("../../../Data/mex_M.csv", row.names = 1)

cat(sprintf("Quarterly data: %d rows, %d columns\n", nrow(mex_Q), ncol(mex_Q)))
cat(sprintf("Monthly data: %d rows, %d columns\n", nrow(mex_M), ncol(mex_M)))

# Check for DA_GDP and DA_EAI
cat(sprintf("DA_GDP present: %s\n", "DA_GDP" %in% names(mex_Q)))
cat(sprintf("DA_EAI present: %s\n", "DA_EAI" %in% names(mex_M)))

if ("DA_GDP" %in% names(mex_Q) && "DA_EAI" %in% names(mex_M)) {
  # Convert to time series
  y <- ts(mex_Q$DA_GDP, start = c(1993, 1), frequency = 4)
  x <- ts(mex_M$DA_EAI, start = c(1993, 1), frequency = 12)
  
  cat(sprintf("\nTime series created:\n"))
  cat(sprintf("  y: %d quarters, from %s to %s\n", 
              length(y), 
              format(as.Date(time(y)[1]), "%Y-Q%q"),
              format(as.Date(tail(time(y), 1)), "%Y-Q%q")))
  cat(sprintf("  x: %d months\n", length(x)))
  
  cat("\nData load successful!\n")
} else {
  cat("\nERROR: Required columns not found!\n")
}
