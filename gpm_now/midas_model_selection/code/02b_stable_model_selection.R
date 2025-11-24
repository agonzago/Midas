# Stable U-MIDAS model selection with evaluation periods
# - Select models at the START of each evaluation period (e.g., quarterly)
# - Keep model specifications CONSTANT during that period
# - This enables tracking "news" - what's driving forecast revisions
# - Output includes which models/specs were active at each vintage for news decomposition

suppressPackageStartupMessages({
  library(data.table)
  library(lubridate)
  library(stringr)
  library(parallel)
})

# Check for midasr
if (!requireNamespace("midasr", quietly = TRUE)) {
  cat("midasr not found. Attempting to install from CRAN...\n")
  install.packages("midasr", repos = "https://cloud.r-project.org")
  if (!requireNamespace("midasr", quietly = TRUE)) {
    stop("Failed to install midasr. Please install manually: install.packages('midasr')")
  }
}
suppressPackageStartupMessages(library(midasr))

args <- commandArgs(trailingOnly = TRUE)
param <- list(
  monthly_file   = ifelse(length(args) >= 1, args[[1]], file.path("..", "retriever", "brazil", "output", "transformed_data", "monthly.csv")),
  quarterly_file = ifelse(length(args) >= 2, args[[2]], file.path("..", "retriever", "brazil", "output", "transformed_data", "quarterly.csv")),
  vintages_dir   = ifelse(length(args) >= 3, args[[3]], file.path(".", "..", "midas_model_selection", "data", "vintages")),
  out_sel_dir    = ifelse(length(args) >= 4, args[[4]], file.path(".", "..", "midas_model_selection", "data", "selection")),
  out_now_dir    = ifelse(length(args) >= 5, args[[5]], file.path(".", "..", "midas_model_selection", "data", "nowcasts")),
  out_stable_dir = ifelse(length(args) >= 6, args[[6]], file.path(".", "..", "midas_model_selection", "data", "stable")),
  gdp_lags_grid  = if (length(args) >= 7) as.integer(strsplit(args[[7]], ",")[[1]]) else 0:4,
  k_grid         = if (length(args) >= 8) as.integer(strsplit(args[[8]], ",")[[1]]) else 3:9,
  transform_tags = if (length(args) >= 9) strsplit(args[[9]], ",")[[1]] else c("DA_", "DA3m_"),
  target_col     = ifelse(length(args) >= 10, args[[10]], "DA_GDP"),
  eval_period    = ifelse(length(args) >= 11, args[[11]], "quarter"),  # "quarter" or "month"
  n_cores        = if (length(args) >= 12) as.integer(args[[12]]) else max(1L, parallel::detectCores() - 1L),
  indicator_list = if (length(args) >= 13 && args[[13]] != "") strsplit(args[[13]], ",")[[1]] else NULL
)

for (d in c(param$out_sel_dir, param$out_now_dir, param$out_stable_dir)) {
  if (!dir.exists(d)) dir.create(d, recursive = TRUE, showWarnings = FALSE)
}

monthly <- fread(param$monthly_file)
monthly[, date := as.Date(date)]
quarterly <- fread(param$quarterly_file)
quarterly[, date := as.Date(date)]

stopifnot(param$target_col %in% names(quarterly))
setnames(quarterly, param$target_col, "value")

qstr <- function(d) paste0(year(d), "Q", quarter(d))
quarterly[, quarter := qstr(date)]

# Load vintages
vintage_files <- list.files(param$vintages_dir, pattern = "^pseudo_vintages_.*\\.rds$", full.names = TRUE)
if (length(vintage_files) == 0) stop("No vintage files found.")

q_extract <- function(fn) sub("pseudo_vintages_(.*)\\.rds", "\\1", basename(fn))
q_order <- function(q) { y <- as.integer(substr(q,1,4)); r <- as.integer(substr(q,6,6)); y*4 + r }
q_list <- q_extract(vintage_files)
q_list <- q_list[order(q_order(q_list))]

vmap <- setNames(lapply(vintage_files[order(q_order(q_extract(vintage_files)))], readRDS), q_list)
for (q in names(vmap)) {
  vi <- vmap[[q]]
  vmap[[q]] <- list(fridays = as.Date(names(vi)), data = vi)
}

all_vars <- setdiff(names(monthly), "date")

if (!is.null(param$indicator_list)) {
  # Use explicit list of indicators
  sel_vars <- intersect(param$indicator_list, all_vars)
  if (length(sel_vars) < length(param$indicator_list)) {
    missing <- setdiff(param$indicator_list, all_vars)
    warning("Some requested indicators not found in data: ", paste(missing, collapse=", "))
  }
  if (length(sel_vars) == 0) stop("No requested indicators found in data.")
} else {
  # Fallback to transform tags
  sel_vars <- unique(unlist(lapply(param$transform_tags, function(tag) all_vars[str_detect(all_vars, fixed(tag))])))
  if (length(sel_vars) == 0) {
    warning("No variables matched transform tags; falling back to DA_ and DA3m_ prefixes.")
    sel_vars <- all_vars[str_detect(all_vars, "^(DA_|DA3m_)")]
  }
}

cat("Running stable U-MIDAS selection for", length(sel_vars), "indicators.\n")
cat("Evaluation period:", param$eval_period, "\n")
cat("GDP AR lags grid:", paste(param$gdp_lags_grid, collapse=","), "\n")
cat("Indicator lags grid (K):", paste(param$k_grid, collapse=","), "\n\n")

# Helper functions (reuse from 02_umidas_model_selection.R)
get_vintage_info <- function(var, q, idx) {
  vi <- vmap[[q]]
  frs <- sort(vi$fridays)
  if (length(frs) == 0 || idx > length(frs)) return(list(last_month = as.Date(NA), horizon = NA_integer_))
  vinfo <- vi$data[[as.character(frs[idx])]]$availability
  hit <- which(vinfo$variable == var)
  if (length(hit) == 0) return(list(last_month = as.Date(NA), horizon = NA_integer_))
  list(last_month = vinfo$last_month[hit[1]], horizon = vinfo$horizon_months[hit[1]])
}

quarter_last_month_start <- function(qdate) {
  lubridate::floor_date(qdate, unit = "quarter") %m+% months(2)
}

build_midas_design <- function(train_q_dates, z_dt, h, K) {
  offsets <- h + seq.int(0L, K - 1L)
  X_list <- vector("list", length(train_q_dates))
  keep <- rep(TRUE, length(train_q_dates))
  for (i in seq_along(train_q_dates)) {
    qd <- train_q_dates[i]
    lm_start <- quarter_last_month_start(qd)
    mdates <- lm_start %m-% months(offsets)
    vals_dt <- z_dt[date %in% mdates]
    if (nrow(vals_dt) < length(mdates)) {
      keep[i] <- FALSE
      X_list[[i]] <- rep(NA_real_, K)
      next
    }
    ord <- match(mdates, vals_dt$date)
    vals <- vals_dt$value[ord]
    if (any(is.na(vals))) {
      keep[i] <- FALSE
      X_list[[i]] <- rep(NA_real_, K)
    } else {
      X_list[[i]] <- as.numeric(vals)
    }
  }
  X <- do.call(rbind, X_list)
  list(X = X, keep = keep)
}

fit_umidas_ols <- function(train_y, train_q_dates, z_dt, p_gdp, K_ind, h_ind, test_q_date, last_month) {
  z_sub <- z_dt[date <= last_month]
  if (nrow(z_sub) == 0) return(NULL)
  des <- build_midas_design(train_q_dates, z_sub, h_ind, K_ind)
  keep <- des$keep
  X <- des$X
  if (p_gdp > 0) {
    Y_lag <- embed(train_y, p_gdp + 1)
    idx_offset <- length(train_y) - nrow(Y_lag)
    X_eff <- X[(idx_offset + 1):nrow(X), , drop = FALSE]
    keep_eff <- keep[(idx_offset + 1):length(keep)]
    rows <- which(keep_eff & rowSums(is.na(X_eff)) == 0)
    if (length(rows) < (p_gdp + K_ind + 2)) return(NULL)
    y_reg <- Y_lag[rows, 1]
    y_lags <- Y_lag[rows, -1, drop = FALSE]
    X_reg <- X_eff[rows, , drop = FALSE]
    df <- data.frame(y = y_reg, y_lags, X_reg)
    names(df) <- c("y", paste0("y_lag", 1:p_gdp), paste0("x_", 0:(K_ind - 1)))
    fit <- tryCatch(lm(y ~ ., data = df), error = function(e) NULL)
  } else {
    rows <- which(keep & rowSums(is.na(X)) == 0)
    if (length(rows) < (K_ind + 2)) return(NULL)
    y_reg <- train_y[rows]
    X_reg <- X[rows, , drop = FALSE]
    df <- data.frame(y = y_reg, X_reg)
    names(df) <- c("y", paste0("x_", 0:(K_ind - 1)))
    fit <- tryCatch(lm(y ~ ., data = df), error = function(e) NULL)
  }
  if (is.null(fit)) return(NULL)
  bic_val <- tryCatch(BIC(fit), error = function(e) NA_real_)
  if (p_gdp > 0) {
    y_lags_fc <- tail(train_y, p_gdp)
  }
  lm_start_test <- quarter_last_month_start(test_q_date)
  mdates_fc <- lm_start_test %m-% months(h_ind + seq.int(0L, K_ind - 1L))
  z_fc_dt <- z_sub[date %in% mdates_fc]
  if (nrow(z_fc_dt) < length(mdates_fc)) return(list(model = fit, bic = bic_val, forecast = NA_real_, coef = coef(fit)))
  z_fc <- z_fc_dt$value[match(mdates_fc, z_fc_dt$date)]
  if (any(is.na(z_fc))) return(list(model = fit, bic = bic_val, forecast = NA_real_, coef = coef(fit)))
  new_df <- as.list(setNames(as.numeric(z_fc), paste0("x_", 0:(K_ind - 1))))
  if (p_gdp > 0) for (i in 1:p_gdp) new_df[[paste0("y_lag", i)]] <- y_lags_fc[i]
  new_df <- as.data.frame(new_df)
  y_hat <- tryCatch(as.numeric(predict(fit, newdata = new_df)), error = function(e) NA_real_)
  list(model = fit, bic = bic_val, forecast = y_hat, coef = coef(fit))
}

fit_umidas_midasr <- function(gdp_ts, indicator_ts, p_gdp, K_ind, h_ind) {
  tryCatch({
    ind_lags <- h_ind:(h_ind + K_ind - 1)
    if (p_gdp > 0) {
      fmla <- as.formula(sprintf("gdp_ts ~ mls(gdp_ts, %d:%d, 1) + mls(indicator_ts, %d:%d, 3)",
                                 1, p_gdp, min(ind_lags), max(ind_lags)))
    } else {
      fmla <- as.formula(sprintf("gdp_ts ~ mls(indicator_ts, %d:%d, 3)",
                                 min(ind_lags), max(ind_lags)))
    }
    environment(fmla) <- environment()
    fit <- midasr::midas_r(fmla, start = NULL)
    bic_val <- BIC(fit)
    fcst <- tryCatch({
      pred <- predict(fit, newdata = NULL)
      tail(pred, 1)
    }, error = function(e) NA_real_)
    list(model = fit, bic = bic_val, forecast = fcst, coef = coef(fit))
  }, error = function(e) {
    NULL
  })
}

# Determine evaluation periods
# Each evaluation period = one quarter or one month
# At the START of each period, select models on all prior data
# Then use those models for all vintages in that period

eval_periods <- data.table()
for (q in q_list) {
  frs <- sort(vmap[[q]]$fridays)
  if (length(frs) == 0) next
  
  if (param$eval_period == "quarter") {
    # One evaluation period per quarter
    eval_periods <- rbind(eval_periods, data.table(
      eval_period_id = q,
      quarter = q,
      selection_date = frs[1],  # Select models at start of quarter
      fridays = list(frs)
    ))
  } else if (param$eval_period == "month") {
    # Three evaluation periods per quarter (one per month)
    q_start <- floor_date(as.Date(paste0(q, "-01"), format = "%YQ%q-%d"), "quarter")
    for (m in 1:3) {
      month_start <- q_start %m+% months(m - 1)
      month_frs <- frs[month(frs) == month(month_start)]
      if (length(month_frs) > 0) {
        eval_periods <- rbind(eval_periods, data.table(
          eval_period_id = paste0(q, "M", m),
          quarter = q,
          selection_date = month_frs[1],
          fridays = list(month_frs)
        ))
      }
    }
  }
}

cat("Created", nrow(eval_periods), "evaluation periods.\n\n")

# For each evaluation period, select models ONCE at the start
# Then apply those models to all Fridays in that period

selected_specs <- list()  # Will store selected (p_gdp, K_ind) per indicator per eval period
all_nowcasts <- list()

for (ep_idx in seq_len(nrow(eval_periods))) {
  ep <- eval_periods[ep_idx, ]
  cat("\n=== Evaluation Period:", ep$eval_period_id, "===\n")
  cat("Selection date:", as.character(ep$selection_date), "\n")
  
  # Find all quarters BEFORE this period for training
  q_order_ep <- q_order(ep$quarter)
  train_quarters <- q_list[q_order(q_list) < q_order_ep]
  
  if (length(train_quarters) < 2) {
    cat("Not enough training data for period", ep$eval_period_id, "\n")
    next
  }
  
  cat("Training on", length(train_quarters), "prior quarters.\n")
  
  # Select models for each indicator
  specs_this_period <- mclapply(sel_vars, function(var) {
    cat("  Selecting model for", var, "...\n")
    
    # Get BIC for each (p, K) combo averaged over training quarters
    bic_grid <- expand.grid(p_gdp = param$gdp_lags_grid, K_ind = param$k_grid)
    bic_grid$bic_sum <- 0
    bic_grid$n_valid <- 0
    
    for (ti in seq_along(train_quarters)) {
      q_t <- train_quarters[ti]
      if (ti == 1) next  # Need at least one prior quarter for AR terms
      
      train_q <- train_quarters[1:(ti-1)]
      train_gdp <- quarterly[quarter %in% train_q][order(date)][["value"]]
      if (any(is.na(train_gdp)) || length(train_gdp) < 2) next
      
      first_train_q_date <- quarterly[quarter == train_q[1], date][1]
      N_q <- length(train_gdp)
      gdp_ts <- ts(train_gdp, start = c(year(first_train_q_date), quarter(first_train_q_date)), frequency = 4)
      q_start_date <- lubridate::floor_date(first_train_q_date, unit = "quarter")
      
      # Get vintage info for this variable at the first Friday of q_t
      frs_t <- sort(vmap[[q_t]]$fridays)
      if (length(frs_t) == 0) next
      vinfo <- get_vintage_info(var, q_t, 1)
      if (is.na(vinfo$last_month) || is.na(vinfo$horizon)) next
      h_ind <- vinfo$horizon
      
      for (cfg_idx in seq_len(nrow(bic_grid))) {
        p_gdp <- bic_grid$p_gdp[cfg_idx]
        K_ind <- bic_grid$K_ind[cfg_idx]
        if (length(train_gdp) <= p_gdp) next
        
        max_k <- h_ind + K_ind - 1
        needed_hf_len <- N_q * 3 + max_k + 3
        hf_start_date <- q_start_date %m-% months(max_k)
        hf_end_date <- vinfo$last_month
        mon_sub_cfg <- monthly[date >= hf_start_date & date <= hf_end_date][order(date)]
        if (nrow(mon_sub_cfg) < needed_hf_len) next
        
        indicator_vals_cfg <- mon_sub_cfg[[var]][seq_len(needed_hf_len)]
        indicator_ts <- ts(indicator_vals_cfg, start = c(year(hf_start_date), month(hf_start_date)), frequency = 12)
        
        fit_result <- fit_umidas_midasr(gdp_ts, indicator_ts, p_gdp, K_ind, h_ind)
        if (is.null(fit_result)) {
          z_dt <- data.table(date = monthly$date, value = monthly[[var]])
          fit_result <- fit_umidas_ols(
            train_y = train_gdp,
            train_q_dates = quarterly[quarter %in% train_q][order(date), date],
            z_dt = z_dt,
            p_gdp = p_gdp,
            K_ind = K_ind,
            h_ind = h_ind,
            test_q_date = quarterly[quarter == q_t, date][1],
            last_month = vinfo$last_month
          )
        }
        if (!is.null(fit_result)) {
          bic_grid$bic_sum[cfg_idx] <- bic_grid$bic_sum[cfg_idx] + fit_result$bic
          bic_grid$n_valid[cfg_idx] <- bic_grid$n_valid[cfg_idx] + 1
        }
      }
    }
    
    bic_grid <- bic_grid[bic_grid$n_valid > 0, ]
    if (nrow(bic_grid) == 0) {
      cat("    No valid fits for", var, "\n")
      return(NULL)
    }
    bic_grid$bic_avg <- bic_grid$bic_sum / bic_grid$n_valid
    best_idx <- which.min(bic_grid$bic_avg)
    best_cfg <- bic_grid[best_idx, ]
    
    cat("    Selected p=", best_cfg$p_gdp, ", K=", best_cfg$K_ind, ", BIC=", round(best_cfg$bic_avg, 2), "\n")
    
    data.table(
      variable = var,
      eval_period_id = ep$eval_period_id,
      selected_p_gdp = best_cfg$p_gdp,
      selected_K_ind = best_cfg$K_ind,
      bic_avg = best_cfg$bic_avg
    )
  }, mc.cores = param$n_cores)
  
  specs_this_period <- rbindlist(Filter(Negate(is.null), specs_this_period))
  if (nrow(specs_this_period) == 0) {
    cat("No models selected for this period.\n")
    next
  }
  
  selected_specs[[ep$eval_period_id]] <- specs_this_period
  
  # Now apply these FIXED specs to all Fridays in this period
  fridays_list <- ep$fridays[[1]]
  cat("Applying to", length(fridays_list), "Fridays in period.\n")
  
  for (fri in fridays_list) {
    cat("  Nowcasting for Friday:", as.character(fri), "\n")
    
    # Find which quarter and Friday index this corresponds to
    q_curr <- ep$quarter
    frs_curr <- sort(vmap[[q_curr]]$fridays)
    fri_idx <- which(frs_curr == fri)
    if (length(fri_idx) == 0) next
    
    # For each indicator, use its selected spec
    for (v_idx in seq_len(nrow(specs_this_period))) {
      var <- specs_this_period$variable[v_idx]
      p_sel <- specs_this_period$selected_p_gdp[v_idx]
      K_sel <- specs_this_period$selected_K_ind[v_idx]
      
      vinfo <- get_vintage_info(var, q_curr, fri_idx)
      if (is.na(vinfo$last_month) || is.na(vinfo$horizon)) next
      h_ind <- vinfo$horizon
      
      # Get training data up to this Friday
      q_order_curr <- q_order(q_curr)
      train_q_all <- q_list[q_order(q_list) < q_order_curr]
      if (length(train_q_all) < 1) next
      
      train_gdp <- quarterly[quarter %in% train_q_all][order(date)][["value"]]
      if (any(is.na(train_gdp)) || length(train_gdp) < 2) next
      
      first_train_q_date <- quarterly[quarter == train_q_all[1], date][1]
      N_q <- length(train_gdp)
      gdp_ts <- ts(train_gdp, start = c(year(first_train_q_date), quarter(first_train_q_date)), frequency = 4)
      q_start_date <- lubridate::floor_date(first_train_q_date, unit = "quarter")
      
      max_k <- h_ind + K_sel - 1
      needed_hf_len <- N_q * 3 + max_k + 3
      hf_start_date <- q_start_date %m-% months(max_k)
      hf_end_date <- vinfo$last_month
      mon_sub_cfg <- monthly[date >= hf_start_date & date <= hf_end_date][order(date)]
      if (nrow(mon_sub_cfg) < needed_hf_len) next
      
      indicator_vals_cfg <- mon_sub_cfg[[var]][seq_len(needed_hf_len)]
      indicator_ts <- ts(indicator_vals_cfg, start = c(year(hf_start_date), month(hf_start_date)), frequency = 12)
      
      fit_result <- fit_umidas_midasr(gdp_ts, indicator_ts, p_sel, K_sel, h_ind)
      if (is.null(fit_result)) {
        z_dt <- data.table(date = monthly$date, value = monthly[[var]])
        fit_result <- fit_umidas_ols(
          train_y = train_gdp,
          train_q_dates = quarterly[quarter %in% train_q_all][order(date), date],
          z_dt = z_dt,
          p_gdp = p_sel,
          K_ind = K_sel,
          h_ind = h_ind,
          test_q_date = quarterly[quarter == q_curr, date][1],
          last_month = vinfo$last_month
        )
      }
      
      if (!is.null(fit_result) && !is.na(fit_result$forecast)) {
        y_true <- quarterly[quarter == q_curr][["value"]]
        y_true <- if (length(y_true) > 0) y_true[1] else NA_real_
        
        all_nowcasts[[length(all_nowcasts) + 1]] <- data.table(
          variable = var,
          eval_period_id = ep$eval_period_id,
          quarter = q_curr,
          test_date = fri,
          p_gdp = p_sel,
          K_ind = K_sel,
          horizon = h_ind,
          y_true = y_true,
          y_hat = fit_result$forecast
        )
      }
    }
  }
}

# Save outputs
if (length(selected_specs) > 0) {
  specs_dt <- rbindlist(selected_specs)
  fwrite(specs_dt, file.path(param$out_stable_dir, "stable_model_specs.csv"))
  cat("\nSaved:", file.path(param$out_stable_dir, "stable_model_specs.csv"), "\n")
}

if (length(all_nowcasts) > 0) {
  nowcasts_dt <- rbindlist(all_nowcasts)
  fwrite(nowcasts_dt, file.path(param$out_stable_dir, "stable_nowcasts_by_vintage.csv"))
  cat("Saved:", file.path(param$out_stable_dir, "stable_nowcasts_by_vintage.csv"), "\n")
}

cat("\nDone.\n")
