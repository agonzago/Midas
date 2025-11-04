# Extract codes, names, long names, and sources from all ODS sheets

suppressPackageStartupMessages({
  library(readODS)
  library(dplyr)
})

# Extract variable codes utility
# - Reads all sheets in an ODS file
# - Normalizes column names
# - Selects/code, name, long_name, source, and sheet
# - Writes combined results to CSV

extract_variable_codes <- function(
  ods_file = "data_to_retrive.ods",
  output_csv = "variable_codes.csv"
) {
  if (!file.exists(ods_file)) {
    stop("ODS file not found: ", ods_file)
  }

  message("Reading ODS: ", ods_file)
  sheets <- list_ods_sheets(ods_file)
  message("Found sheets: ", paste(sheets, collapse = ", "))

  results <- lapply(sheets, function(sh) {
    df <- tryCatch(read_ods(ods_file, sheet = sh), error = function(e) NULL)
    if (is.null(df) || nrow(df) == 0) return(NULL)

    # Normalize column names (lowercase, replace spaces/dots with underscore)
    nms <- names(df)
    nms <- tolower(gsub("[ .]+", "_", nms))
    names(df) <- nms

    # Ensure expected fields exist; create missing as NA_character_
    for (col in c("code", "name", "long_name", "source")) {
      if (!col %in% names(df)) df[[col]] <- NA_character_
    }

    out <- df %>%
      mutate(
        code = as.character(code),
        name = as.character(name),
        long_name = as.character(long_name),
        source = as.character(source)
      ) %>%
      select(code, name, long_name, source) %>%
      filter(!is.na(code) & code != "") %>%
      mutate(sheet = sh)

    if (nrow(out) == 0) return(NULL)
    out
  })

  combined <- bind_rows(results)

  # Drop duplicates if any
  combined <- combined %>% distinct()

  # Write CSV next to working directory (or path provided)
  write.csv(combined, output_csv, row.names = FALSE)
  message("Saved ", nrow(combined), " rows to ", normalizePath(output_csv, mustWork = FALSE))

  invisible(combined)
}

# Run immediately if sourced directly (typical use)
if (sys.nframe() == 0) {
  extract_variable_codes(
    ods_file = "data_to_retrive.ods",
    output_csv = "variable_codes.csv"
  )
}

