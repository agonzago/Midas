# Runner for gpm_now/midas_model_selection
# Usage: Rscript 00_run_all.R 2022Q1 2025Q2

args <- commandArgs(trailingOnly = TRUE)
start_q <- ifelse(length(args) >= 1, args[[1]], "2022Q1")
end_q   <- ifelse(length(args) >= 2, args[[2]], "2025Q2")

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

select <- sprintf("Rscript %s %s %s %s %s %s %s %s %s",
                  file.path(code_dir, "02_umidas_model_selection.R"),
                  file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "monthly.csv"),
                  file.path(gpm_root, "retriever", "brazil", "output", "transformed_data", "quarterly.csv"),
                  file.path(gpm_root, "midas_model_selection", "data", "vintages"),
                  file.path(gpm_root, "midas_model_selection", "data", "selection"),
                  file.path(gpm_root, "midas_model_selection", "data", "nowcasts"),
                  "1,2,3,4",         # GDP AR lags grid
                  "3,4,5,6,7,8,9",  # Indicator lags grid (K)
                  "DA_GDP")          # Target column
cat("Running:\n", select, "\n")
status2 <- system(select)
if (status2 != 0) stop("UMIDAS selection failed")

# Combine nowcasts with BIC/RMSE weights and distribution stats
combine <- sprintf("Rscript %s %s %s %s %s %s %s",
                   file.path(code_dir, "03_combine_nowcasts.R"),
                   file.path(gpm_root, "midas_model_selection", "data", "nowcasts", "umidas_nowcasts_by_vintage.csv"),
                   file.path(gpm_root, "midas_model_selection", "data", "selection", "umidas_selection_summary.csv"),
                   file.path(gpm_root, "midas_model_selection", "data", "combination"),
                   "0.10",
                   "0.15",
                   "rmse")
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

cat("All done.\n")
