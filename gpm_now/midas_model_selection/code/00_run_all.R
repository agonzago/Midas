# Runner for gpm_now/midas_model_selection
# Usage: Rscript 00_run_all.R 2022Q1 2025Q2 [stable] [indicators]
# Add "stable" as third argument to run stable model selection with evaluation periods
# Add comma-separated list of indicators as fourth argument (optional)

args <- commandArgs(trailingOnly = TRUE)
start_q <- ifelse(length(args) >= 1, args[[1]], "2022Q1")
end_q   <- ifelse(length(args) >= 2, args[[2]], "2025Q2")
run_stable <- length(args) >= 3 && tolower(args[[3]]) == "stable"
indicators <- ifelse(length(args) >= 4, args[[4]], "")

# Get directories - assume we're in the workspace root
code_dir <- normalizePath(file.path(getwd(), "gpm_now", "midas_model_selection", "code"))
gpm_root <- normalizePath(file.path(getwd(), "gpm_now"))

build <- sprintf("Rscript %s %s %s %s %s %s %s",
                 file.path(code_dir, "01_build_pseudo_vintages.R"),
                 file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "monthly.csv"),
                 file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "quarterly.csv"),
                 file.path(gpm_root, "retriever", "Initial_calendar.csv"),
                 file.path(gpm_root, "midas_model_selection", "data", "vintages"),
                 start_q, end_q)
cat("Running:\n", build, "\n")
status1 <- system(build)
if (status1 != 0) stop("Vintage builder failed")

# Choose between standard and stable model selection
if (run_stable) {
  cat("\n=== Running STABLE model selection (evaluation periods) ===\n\n")
  select <- sprintf("Rscript %s %s %s %s %s %s %s %s %s %s %s %s %s",
                    file.path(code_dir, "02b_stable_model_selection.R"),
                    file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "monthly.csv"),
                    file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "quarterly.csv"),
                    file.path(gpm_root, "midas_model_selection", "data", "vintages"),
                    file.path(gpm_root, "midas_model_selection", "data", "selection"),
                    file.path(gpm_root, "midas_model_selection", "data", "nowcasts"),
                    file.path(gpm_root, "midas_model_selection", "data", "stable"),
                    "0,1,2,3,4",       # GDP AR lags grid (now includes 0)
                    "3,4,5,6,7,8,9",   # Indicator lags grid (K)
                    "DA_,DA3m_",       # Transform tags
                    "DA_GDP",          # Target column
                    "quarter",         # Evaluation period: "quarter" or "month"
                    "4",               # n_cores (default placeholder)
                    indicators)        # Indicator list (arg 13)
  cat("Running:\n", select, "\n")
  status2 <- system(select)
  if (status2 != 0) stop("Stable UMIDAS selection failed")
  
  # Use stable nowcasts for combination
  nowcasts_file <- file.path(gpm_root, "midas_model_selection", "data", "stable", "stable_nowcasts_by_vintage.csv")
  selection_file <- file.path(gpm_root, "midas_model_selection", "data", "stable", "stable_model_specs.csv")
} else {
  cat("\n=== Running STANDARD model selection ===\n\n")
  select <- sprintf("Rscript %s %s %s %s %s %s %s %s %s %s %s",
                    file.path(code_dir, "02_umidas_model_selection.R"),
                    file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "monthly.csv"),
                    file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "quarterly.csv"),
                    file.path(gpm_root, "midas_model_selection", "data", "vintages"),
                    file.path(gpm_root, "midas_model_selection", "data", "selection"),
                    file.path(gpm_root, "midas_model_selection", "data", "nowcasts"),
                    "0,1,2,3,4",       # GDP AR lags grid (now includes 0)
                    "3,4,5,6,7,8,9",   # Indicator lags grid (K)
                    "DA_,DA3m_",       # Transform tags
                    "DA_GDP",          # Target column
                    "4",               # n_cores (default placeholder)
                    indicators)        # Indicator list (arg 11)
  cat("Running:\n", select, "\n")
  status2 <- system(select)
  if (status2 != 0) stop("UMIDAS selection failed")
  
  # Use standard nowcasts for combination
  nowcasts_file <- file.path(gpm_root, "midas_model_selection", "data", "nowcasts", "umidas_nowcasts_by_vintage.csv")
  selection_file <- file.path(gpm_root, "midas_model_selection", "data", "selection", "umidas_selection_summary.csv")
}

# Combine nowcasts with BIC/RMSE/Equal/Trimmed weights and distribution stats
combine <- sprintf("Rscript %s %s %s %s %s %s %s",
                   file.path(code_dir, "03_combine_nowcasts.R"),
                   nowcasts_file,
                   selection_file,
                   file.path(gpm_root, "midas_model_selection", "data", "combination"),
                   "0.10",    # trim proportion
                   "0.15",    # drop worst proportion
                   "rmse")    # drop metric
cat("Running:\n", combine, "\n")
status3 <- system(combine)
if (status3 != 0) stop("Combination step failed")

# Plot summary graphs
plotcmd <- sprintf("Rscript %s %s %s %s",
                   file.path(code_dir, "04_plot_summary.R"),
                   file.path(gpm_root, "midas_model_selection", "data", "combination", "umidas_combined_nowcasts.csv"),
                   file.path(gpm_root, "midas_model_selection", "data", "combination", "umidas_combined_nowcasts_latest.csv"),
                   file.path(gpm_root, "midas_model_selection", "data", "combination"))
cat("Running:\n", plotcmd, "\n")
invisible(system(plotcmd))

# Generate executive summary
summary_cmd <- sprintf("Rscript %s %s %s %s %s %s",
                       file.path(code_dir, "05_executive_summary.R"),
                       file.path(gpm_root, "midas_model_selection", "data", "combination", "umidas_combined_nowcasts.csv"),
                       nowcasts_file,
                       selection_file,
                       file.path(gpm_root, "midas_model_selection", "data", "combination"),
                       "10")  # top N contributors
cat("Running:\n", summary_cmd, "\n")
invisible(system(summary_cmd))

cat("\nAll done.\n")
