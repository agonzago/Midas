# Optional dependency check/installer
pkgs <- c("data.table","lubridate","stringr","rmidas")
missing <- pkgs[!sapply(pkgs, requireNamespace, quietly = TRUE)]
if (length(missing) == 0) {
  cat("All packages available:\n", paste(pkgs, collapse=", "), "\n")
  quit(status = 0)
}
cat("Missing packages:", paste(missing, collapse=", "), "\n")
ans <- Sys.getenv("AUTO_INSTALL_PKGS", unset = "no")
if (tolower(ans) %in% c("yes","true","1")) {
  install.packages(missing, repos = "https://cloud.r-project.org")
} else {
  cat("Set AUTO_INSTALL_PKGS=yes to auto-install from CRAN.\n")
}
