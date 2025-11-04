# Runner: build pseudo vintages then run U-MIDAS selection

args <- commandArgs(trailingOnly = TRUE)
start_q <- ifelse(length(args) >= 1, args[[1]], "2022Q1")
end_q   <- ifelse(length(args) >= 2, args[[2]], "2025Q2")

root <- dirname(normalizePath("."))
code_dir <- file.path(root, "midas model selection", "code")

# 1) Build vintages
cmd1 <- sprintf("Rscript %s %s %s %s %s %s %s %s",
                file.path(code_dir, "01_build_pseudo_vintages.R"),
                file.path(root, "gpm_now", "data", "monthly", "monthly_data.csv"),
                file.path(root, "gpm_now", "data", "quarterly", "quarterly_data.csv"),
                file.path(root, "gpm_now", "retriever", "Initial_calendar.csv"),
                file.path(root, "midas model selection", "data", "vintages"),
                start_q,
                end_q,
                0)
cat("Running:\n", cmd1, "\n")
status1 <- system(cmd1)
if (status1 != 0) stop("Vintage builder failed")

# 2) UMIDAS selection
cmd2 <- sprintf("Rscript %s %s %s %s %s %s %s",
                file.path(code_dir, "02_umidas_model_selection.R"),
                file.path(root, "gpm_now", "data", "monthly", "monthly_data.csv"),
                file.path(root, "gpm_now", "data", "quarterly", "quarterly_data.csv"),
                file.path(root, "midas model selection", "data", "vintages"),
                file.path(root, "midas model selection", "data", "selection"),
                file.path(root, "midas model selection", "data", "nowcasts"),
                "1,2,3,4,5,6,7,8,9,10,11,12")
cat("Running:\n", cmd2, "\n")
status2 <- system(cmd2)
if (status2 != 0) stop("UMIDAS selection failed")

cat("All done.\n")
