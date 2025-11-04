# Minimal script to read one vintage and inspect it

library(data.table)

# Read one vintage file
vfile <- "gpm_now/midas_model_selection/data/vintages/pseudo_vintages_2024Q4.rds"
cat("Reading:", vfile, "\n\n")

vt <- readRDS(vfile)

cat("Vintage structure:\n")
cat("  Number of Fridays:", length(vt), "\n")
cat("  Friday dates:", paste(names(vt), collapse = ", "), "\n\n")

# Pick the last Friday
friday_dates <- as.Date(names(vt))
last_friday <- max(friday_dates)
cat("Looking at last Friday:", as.character(last_friday), "\n\n")

# Get the availability data for that Friday
avail <- vt[[as.character(last_friday)]]$availability

cat("Availability data:\n")
cat("  Number of variables:", nrow(avail), "\n")
cat("  Columns:", paste(names(avail), collapse = ", "), "\n\n")

cat("First 10 rows:\n")
print(head(avail, 10))

cat("\n\nSample of horizon distribution:\n")
print(table(avail$horizon_months))
