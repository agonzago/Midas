# MIDAS model selection (gpm_now)

This module builds pseudo-real-time ragged vintages using the release calendar and performs per-indicator U‑MIDAS model selection with BIC and RMSE for 2022Q1–2025Q2.

- Data source (transformed): `gpm_now/retriever/brazil/output/transformed_data/`
  - `monthly.csv`: wide monthly indicators including transformed versions (e.g., `DA_`, `DA3m_` prefixes)
  - `quarterly.csv`: quarterly GDP target columns (default target: `DA_GDP`)
- Calendar: `gpm_now/retriever/Initial_calendar.csv` (falls back to end-of-month if missing)

## Run

From within `gpm_now/midas_model_selection/code` or repository root:

```bash
Rscript gpm_now/midas_model_selection/code/00_run_all.R 2022Q1 2025Q2
```

Outputs in `gpm_now/midas_model_selection/data/`:
- `vintages/`: `pseudo_vintages_<quarter>.rds` per quarter containing Friday vintages and availability tables
- `selection/umidas_selection_summary.csv`: selected K per indicator and RMSE
- `nowcasts/umidas_nowcasts_by_vintage.csv`: all nowcasts by quarter-Friday for each selected model

## Notes

- We use unrestricted MIDAS (UMIDAS): last K monthly lags directly as regressors (no bridging). By default, K is chosen from 1–12 by BIC on an expanding backtest.
- If the `rmidas` package is available, it will be preferred; otherwise a numerically equivalent OLS fallback is used for UMIDAS (since UMIDAS reduces to OLS on lagged regressors).
- The same pseudo vintages can be reused for the 3PF workflow to ensure identical ragged edges.
