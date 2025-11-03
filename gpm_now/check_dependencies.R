#!/usr/bin/env Rscript
# check_dependencies.R
# Check and optionally install required R packages for GPM Now

cat("Checking GPM Now dependencies...\n\n")

# Required packages
required_packages <- c(
  "midasr",
  "dfms",
  "data.table",
  "dplyr",
  "tidyr",
  "lubridate",
  "zoo",
  "yaml",
  "jsonlite",
  "digest"
)

# Optional packages
optional_packages <- c(
  "KFAS",
  "MARSS",
  "nowcastDFM"
)

check_package <- function(pkg) {
  if (requireNamespace(pkg, quietly = TRUE)) {
    return(TRUE)
  } else {
    return(FALSE)
  }
}

cat("REQUIRED PACKAGES:\n")
cat("==================\n\n")

missing_required <- c()
for (pkg in required_packages) {
  status <- check_package(pkg)
  symbol <- if (status) "\u2713" else "\u2717"
  cat(sprintf("  %s %-15s %s\n", symbol, pkg, if (status) "OK" else "MISSING"))
  
  if (!status) {
    missing_required <- c(missing_required, pkg)
  }
}

cat("\n")
cat("OPTIONAL PACKAGES:\n")
cat("==================\n\n")

missing_optional <- c()
for (pkg in optional_packages) {
  status <- check_package(pkg)
  symbol <- if (status) "\u2713" else "\u2717"
  cat(sprintf("  %s %-15s %s\n", symbol, pkg, if (status) "OK" else "MISSING"))
  
  if (!status) {
    missing_optional <- c(missing_optional, pkg)
  }
}

cat("\n")
cat("SUMMARY:\n")
cat("========\n\n")

if (length(missing_required) == 0) {
  cat("  \u2713 All required packages are installed!\n")
} else {
  cat(sprintf("  \u2717 %d required package(s) missing\n", length(missing_required)))
}

if (length(missing_optional) > 0) {
  cat(sprintf("  ! %d optional package(s) missing\n", length(missing_optional)))
}

# Offer to install missing packages
if (length(missing_required) > 0) {
  cat("\n")
  cat("Missing required packages:\n")
  for (pkg in missing_required) {
    cat(sprintf("  - %s\n", pkg))
  }
  
  cat("\n")
  cat("To install missing packages, run:\n")
  cat('  install.packages(c("', paste(missing_required, collapse = '", "'), '"))\n', sep = "")
  
  # Interactive installation
  if (interactive()) {
    cat("\n")
    response <- readline(prompt = "Install missing required packages now? (y/n): ")
    
    if (tolower(response) == "y") {
      cat("\nInstalling packages...\n")
      install.packages(missing_required)
      cat("\nInstallation complete!\n")
    }
  }
}

if (length(missing_optional) > 0) {
  cat("\n")
  cat("Missing optional packages (for advanced features):\n")
  for (pkg in missing_optional) {
    cat(sprintf("  - %s\n", pkg))
  }
  
  cat("\n")
  cat("To install optional packages, run:\n")
  cat('  install.packages(c("', paste(missing_optional, collapse = '", "'), '"))\n', sep = "")
}

cat("\n")

# Check R version
r_version <- getRversion()
if (r_version < "4.0.0") {
  cat("\u2717 Warning: R version ", as.character(r_version), " detected.\n", sep = "")
  cat("  GPM Now is designed for R >= 4.0.0\n")
  cat("  Consider upgrading R for best compatibility.\n\n")
} else {
  cat("\u2713 R version ", as.character(r_version), " is compatible.\n\n", sep = "")
}

# Return status code
if (length(missing_required) > 0) {
  quit(status = 1)
} else {
  quit(status = 0)
}
