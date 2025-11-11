#!/usr/bin/env Rscript
#
# Generates a PDF with multi-panel time series plots that overlay the quarterly
# target series with each monthly indicator and its configured transformations.

suppressPackageStartupMessages({
  required_pkgs <- c(
    "yaml", "readr", "dplyr", "tidyr", "purrr",
    "ggplot2", "scales"
  )
  
  missing_pkgs <- required_pkgs[!sapply(required_pkgs, requireNamespace, quietly = TRUE)]
  if (length(missing_pkgs) > 0) {
    stop(
      "Install the missing packages before running this script: ",
      paste(missing_pkgs, collapse = ", ")
    )
  }
  
  library(yaml)
  library(readr)
  library(dplyr)
  library(tidyr)
  library(purrr)
  library(ggplot2)
  library(scales)
})

`%||%` <- function(x, y) if (!is.null(x)) x else y

# Derive project root from script location when possible
args_all <- commandArgs(trailingOnly = FALSE)
script_path <- sub("--file=", "", args_all[grep("--file=", args_all)])
project_root <- if (length(script_path) == 0) {
  getwd()
} else {
  dirname(normalizePath(script_path))
}

rel_path <- function(...) file.path(project_root, ...)

transforms_path <- rel_path("R", "transforms.R")
if (!file.exists(transforms_path)) {
  stop("Could not find R/transforms.R at ", transforms_path)
}
source(transforms_path, chdir = FALSE)

# Allow passing a custom output path, defaulting to project_root/preselection_variable_plots.pdf
args_trailing <- commandArgs(trailingOnly = TRUE)
output_path <- if (length(args_trailing) >= 1) args_trailing[1] else "preselection_variable_plots.pdf"
output_path <- normalizePath(file.path(project_root, output_path), mustWork = FALSE)
dir.create(dirname(output_path), recursive = TRUE, showWarnings = FALSE)

variables_cfg_path <- rel_path("config", "variables.yaml")
if (!file.exists(variables_cfg_path)) {
  stop("variables.yaml not found at ", variables_cfg_path)
}

variables_cfg <- yaml::read_yaml(variables_cfg_path)

rolling_monthly_path <- rel_path("..", "Data", "mex_M.csv")
rolling_quarterly_path <- rel_path("..", "Data", "mex_Q.csv")
use_rolling_data <- file.exists(rolling_monthly_path) && file.exists(rolling_quarterly_path)

monthly_path <- if (use_rolling_data) rolling_monthly_path else rel_path("data", "monthly", "monthly_data.csv")
quarterly_path <- if (use_rolling_data) rolling_quarterly_path else rel_path("data", "quarterly", "quarterly_data.csv")

if (!file.exists(quarterly_path)) {
  stop("Quarterly data file not found at ", quarterly_path)
}
if (!file.exists(monthly_path)) {
  stop("Monthly data file not found at ", monthly_path)
}

if (use_rolling_data) {
  message("Using rolling evaluation dataset from ../Data/mex_*.csv")
}

quarterly_df <- readr::read_csv(quarterly_path, show_col_types = FALSE)
if (!"date" %in% names(quarterly_df)) {
  names(quarterly_df)[1] <- "date"
}
quarterly_df$date <- as.Date(quarterly_df$date)

monthly_wide <- readr::read_csv(monthly_path, show_col_types = FALSE)
if (!"date" %in% names(monthly_wide)) {
  names(monthly_wide)[1] <- "date"
}
monthly_wide$date <- as.Date(monthly_wide$date)

if (!"date" %in% names(monthly_wide)) {
  stop("Monthly data must contain a 'date' column")
}

non_indicator_cols <- c("date")
monthly_long_base <- monthly_wide %>%
  tidyr::pivot_longer(
    cols = dplyr::all_of(setdiff(names(monthly_wide), non_indicator_cols)),
    names_to = "series_key",
    values_to = "value"
  ) %>%
  mutate(series_key = as.character(series_key))

config_indicators <- variables_cfg$indicators %||% list()
config_indicator_map <- list()
if (length(config_indicators) > 0) {
  for (cfg in config_indicators) {
    if (!is.null(cfg$id)) {
      config_indicator_map[[cfg$id]] <- cfg
    }
  }
}

parse_transform_codes <- function(raw_transforms) {
  if (is.null(raw_transforms)) {
    return("level")
  }
  if (length(raw_transforms) > 1) {
    transforms <- unlist(raw_transforms)
  } else {
    transforms <- strsplit(raw_transforms, ",")[[1]]
  }
  transforms <- unique(trimws(transforms))
  transforms <- transforms[transforms != ""]
  if (length(transforms) == 0) {
    transforms <- "level"
  }
  if (!"level" %in% transforms) {
    transforms <- c("level", transforms)
  }
  transforms
}

get_indicator_label <- function(indicator_id) {
  cfg <- config_indicator_map[[indicator_id]]
  if (!is.null(cfg$label)) {
    return(cfg$label)
  }
  if (grepl("^[A-Z0-9_]+$", indicator_id)) {
    return(indicator_id)
  }
  tools::toTitleCase(gsub("_", " ", indicator_id))
}

pretty_transform_label <- function(code) {
  lookup <- c(
    level = "Level",
    log = "Log level",
    diff = "Difference",
    log_diff = "Log difference",
    pct_mom = "MoM %",
    pct_mom_sa = "MoM % (SA)",
    pct_qoq = "QoQ %",
    pct_yoy = "YoY %",
    pct_yoy_q = "YoY % (Q)",
    pct_change = "Percent change",
    ann_diff = "Annualized diff",
    diff4 = "4-lag difference"
  )
  labels <- lookup[code]
  missing_idx <- is.na(labels)
  if (any(missing_idx)) {
    labels[missing_idx] <- toupper(code[missing_idx])
  }
  labels
}

monthly_long_default <- NULL

build_indicator_spec <- function(indicator_id) {
  cfg <- config_indicator_map[[indicator_id]]
  transforms <- parse_transform_codes(cfg$transform %||% NULL)
  display_name <- get_indicator_label(indicator_id)
  
  list(
    id = indicator_id,
    label = display_name,
    transforms = transforms
  )
}

build_series_panel <- function(spec) {
  series_df <- dplyr::filter(monthly_long_default, indicator_id == spec$id)
  if (nrow(series_df) == 0) {
    return(NULL)
  }
  
  purrr::map_dfr(spec$transforms, function(trans_code) {
    values <- tryCatch(
      apply_transform(series_df$value, trans_code),
      error = function(e) {
        warning(sprintf("Could not apply transform '%s' to %s: %s", trans_code, spec$id, e$message))
        rep(NA_real_, nrow(series_df))
      }
    )
    
    tibble(
      date = series_df$date,
      value = as.numeric(values),
      indicator_id = spec$id,
      indicator_label = spec$label,
      transform_code = trans_code,
      transform_label = pretty_transform_label(trans_code),
      facet_label = sprintf("%s · %s", spec$label, pretty_transform_label(trans_code))
    )
  })
}

plot_data <- NULL

if (use_rolling_data) {
  prefix_lookup <- list(
    "D4_" = list(code = "diff4", label = "4-lag difference"),
    "DA_" = list(code = "ann_diff", label = "Annualized diff"),
    "D_" = list(code = "diff", label = "Difference")
  )
  prefix_order <- names(prefix_lookup)[order(nchar(names(prefix_lookup)), decreasing = TRUE)]
  
  detect_transform_info <- function(series_names) {
    base <- series_names
    code <- rep("level", length(series_names))
    label <- rep("Level", length(series_names))
    
    for (pref in prefix_order) {
      idx <- startsWith(series_names, pref)
      if (any(idx)) {
        base[idx] <- substring(series_names[idx], nchar(pref) + 1)
        code[idx] <- prefix_lookup[[pref]]$code
        label[idx] <- prefix_lookup[[pref]]$label
      }
    }
    
    list(base = base, code = code, label = label)
  }
  
  transform_info <- detect_transform_info(monthly_long_base$series_key)
  indicator_labels <- vapply(transform_info$base, get_indicator_label, character(1))
  
  plot_data <- monthly_long_base %>%
    mutate(
      indicator_id = transform_info$base,
      indicator_label = indicator_labels,
      transform_code = transform_info$code,
      transform_label = transform_info$label,
      facet_label = sprintf("%s · %s", indicator_label, transform_label)
    )
} else {
  if (length(config_indicators) == 0) {
    stop("No indicators found in config/variables.yaml")
  }
  
  indicator_ids <- purrr::map_chr(config_indicators, "id")
  indicator_ids <- indicator_ids[!is.na(indicator_ids)]
  if (length(indicator_ids) == 0) {
    stop("Indicator entries in config/variables.yaml are missing 'id' fields")
  }
  
  monthly_long_default <- monthly_long_base %>%
    dplyr::rename(indicator_id = series_key)
  
  indicator_specs <- purrr::map(indicator_ids, build_indicator_spec)
  names(indicator_specs) <- indicator_ids
  
  missing_series <- setdiff(indicator_ids, unique(monthly_long_default$indicator_id))
  if (length(missing_series) > 0) {
    warning(
      "Monthly data is missing the following indicators: ",
      paste(missing_series, collapse = ", ")
    )
  }
  
  plot_data <- purrr::map_dfr(indicator_specs, build_series_panel)
}

if (is.null(plot_data) || nrow(plot_data) == 0) {
  stop("No indicator data available to plot.")
}

non_empty_facets <- plot_data %>%
  dplyr::group_by(indicator_id, transform_code) %>%
  dplyr::summarise(all_na = all(is.na(value)), .groups = "drop") %>%
  dplyr::filter(!all_na) %>%
  dplyr::select(indicator_id, transform_code)

if (nrow(non_empty_facets) == 0) {
  stop("All indicator transformations are empty.")
}

plot_data <- plot_data %>%
  dplyr::semi_join(non_empty_facets, by = c("indicator_id", "transform_code"))

target_column <- variables_cfg$target$id_q
if (is.null(target_column) || !target_column %in% names(quarterly_df)) {
  if (use_rolling_data && "DA_GDP" %in% names(quarterly_df)) {
    target_column <- "DA_GDP"
  } else if ("value" %in% names(quarterly_df)) {
    target_column <- "value"
  } else {
    stop("Unable to identify target column in quarterly data.")
  }
}

target_transform <- variables_cfg$target$transform_q %||% "level"
target_raw <- quarterly_df[[target_column]]
if (target_column == "value") {
  target_values <- tryCatch(
    apply_transform(target_raw, target_transform),
    error = function(e) {
      warning(sprintf("Could not apply target transform '%s': %s", target_transform, e$message))
      target_raw
    }
  )
  target_transform_display <- target_transform
} else {
  target_values <- target_raw
  target_transform_display <- sprintf("provided (%s)", target_column)
}

target_df <- tibble(
  date = quarterly_df$date,
  target_value = as.numeric(target_values)
)

target_label <- variables_cfg$target$label %||% variables_cfg$target$id_q %||% target_column %||% "Quarterly target"

transform_priority <- c(
  "level", "log", "log_diff", "diff", "pct_mom", "pct_mom_sa",
  "pct_qoq", "pct_yoy", "pct_yoy_q", "pct_change", "ann_diff", "diff4"
)

rank_transform <- function(code) {
  match(code, transform_priority, nomatch = length(transform_priority) + 1L)
}

indicator_sequence <- plot_data %>%
  dplyr::distinct(indicator_id, indicator_label) %>%
  dplyr::arrange(indicator_label) %>%
  dplyr::pull(indicator_id)

indicator_sequence <- unique(indicator_sequence)

build_indicator_plot <- function(indicator_id) {
  indicator_plot <- dplyr::filter(plot_data, indicator_id == !!indicator_id)
  if (nrow(indicator_plot) == 0) {
    return(NULL)
  }
  
  indicator_label <- indicator_plot$indicator_label[1]
  facet_levels <- indicator_plot %>%
    dplyr::distinct(facet_label, transform_code) %>%
    dplyr::mutate(order = rank_transform(transform_code)) %>%
    dplyr::arrange(order, facet_label) %>%
    dplyr::pull(facet_label)
  
  indicator_plot$facet_label <- factor(indicator_plot$facet_label, levels = facet_levels)
  
  target_facets <- purrr::map_dfr(levels(indicator_plot$facet_label), function(lbl) {
    target_df %>% mutate(facet_label = lbl)
  })
  
  color_values <- c("Indicator" = "#1f78b4", "#d62728")
  names(color_values)[2] <- target_label
  
  ggplot(indicator_plot, aes(x = date)) +
    geom_line(aes(y = value, color = "Indicator"), linewidth = 0.9, na.rm = TRUE) +
    geom_point(
      data = target_facets,
      aes(y = target_value, color = target_label),
      size = 1.4,
      alpha = 0.85,
      na.rm = TRUE
    ) +
    facet_wrap(~ facet_label, ncol = 1, scales = "free_y") +
    scale_color_manual(
      values = color_values,
      breaks = c("Indicator", target_label),
      name = NULL
    ) +
    labs(
      title = sprintf("Indicator: %s", indicator_label),
      subtitle = sprintf("Target transform: %s", target_transform_display),
      x = NULL,
      y = NULL
    ) +
    theme_minimal(base_size = 9) +
    theme(
      legend.position = "bottom",
      strip.text = element_text(face = "bold"),
      plot.title = element_text(face = "bold"),
      plot.subtitle = element_text(size = 9)
    )
}

pdf(output_path, width = 8.5, height = 11)
for (indicator_id in indicator_sequence) {
  plt <- build_indicator_plot(indicator_id)
  if (!is.null(plt)) {
    print(plt)
  }
}
dev.off()

cat("Preselection plot report saved to:", output_path, "\n")
