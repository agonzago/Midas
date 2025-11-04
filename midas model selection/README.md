# MIDAS model selection

This module builds pseudo-real-time ragged vintages for each Friday within target quarters and runs per-indicator U‑MIDAS (unrestricted monthly lags) model selection using BIC, recording RMSE for backtest.

## Layout

- `code/`
  - `00_run_all.R` – orchestrates the pipeline (vintages + selection)
  - `01_build_pseudo_vintages.R` – constructs ragged vintages using `Initial_calendar.csv` lags
  - `02_umidas_model_selection.R` – BIC-based lag selection and nowcast backtest per indicator
- `data/`
  - `vintages/` – RDS per quarter with all Friday vintages
  - `selection/` – `umidas_selection_summary.csv` with selected K and RMSE
  - `nowcasts/` – `umidas_nowcasts_by_vintage.csv` with every nowcast by Friday

## Inputs

- Monthly indicators (wide): `gpm_now/data/monthly/monthly_data.csv` with column `date` and one column per indicator (use transformed variables like `*_DA`, `*_DA3m`, `*_log_dm`, `*_dm`, `*_3m` when available; otherwise all columns are used).
- Quarterly GDP target: `gpm_now/data/quarterly/quarterly_data.csv` with columns `date,quarter,value` (quarter-end dates).
- Release calendar: `gpm_now/retriever/Initial_calendar.csv` providing `approx_lag_days` per `variable_code` or `series_id`. When missing, availability is assumed at end-of-month (lag 0 days).

## Run

Optional: install R deps once (data.table, lubridate, stringr).

Run the pipeline from repository root:

```bash
Rscript "midas model selection/code/00_run_all.R" 2022Q1 2025Q2
```

Artifacts will be written under `midas model selection/data/`.

## Notes

- Direct forecasting only (no bridging). Regressors are the last K monthly lags available at each Friday; K is selected by BIC on an expanding backtest. Predictions and RMSE use the fixed per-indicator K with minimal aggregate BIC.
- The same pseudo vintages can be reused by other methods (e.g., 3PF) to ensure identical ragged edges.
