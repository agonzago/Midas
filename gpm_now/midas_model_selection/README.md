# MIDAS model selection (gpm_now)

This module builds pseudo-real-time ragged vintages using the release calendar and performs per-indicator U‑MIDAS model selection with BIC for 2022Q1–2025Q2.

**Key features:**
- Uses `midasr` package for proper mixed-frequency modeling
- Includes GDP autoregressive lags (minimum 1, selected via BIC)
- Adjusts monthly indicator lags based on horizon (ragged edge)
- BIC selection over joint lag structure (GDP AR + indicator lags)

- Data source (transformed): `gpm_now/retriever/brazil/output/transformed_data/`
  - `monthly.csv`: wide monthly indicators including transformed versions (e.g., `DA_`, `DA3m_` prefixes)
  - `quarterly.csv`: quarterly GDP target columns (default target: `DA_GDP`)
- Calendar: `gpm_now/retriever/Initial_calendar.csv` (falls back to end-of-month if missing)

## Model specification

For each indicator, we estimate U-MIDAS models of the form:

**GDP_t = α + Σ β_i·GDP_{t-i} + Σ γ_j·X_{m-h-j+1} + ε**

Where:
- GDP_{t-i}: quarterly GDP lags (i = 1 to p, with p ≥ 1)
- X_{m-h-j+1}: monthly indicator lags starting from horizon h (j = 0 to K-1)
- h = months between last available data and quarter end

The lag specification `mls(indicator, h:(h+K-1), 3)` ensures we only use available monthly data at each nowcast vintage.

## Run

From within `gpm_now/midas_model_selection/code` or repository root:

```bash
Rscript gpm_now/midas_model_selection/code/00_run_all.R 2022Q1 2025Q2
```

Outputs in `gpm_now/midas_model_selection/data/`:
- `vintages/`: `pseudo_vintages_<quarter>.rds` per quarter containing Friday vintages and availability tables
- `selection/umidas_selection_summary.csv`: selected GDP lags (p) and indicator lags (K) per indicator, plus RMSE
- `nowcasts/umidas_nowcasts_by_vintage.csv`: all nowcasts by quarter-Friday for each selected model

## Parameters

The runner accepts two arguments:
- Arg 1: Start quarter (default: 2022Q1)
- Arg 2: End quarter (default: 2025Q2)

The selection script parameters:
- GDP AR lags grid (default: 1,2,3,4)
- Indicator lags grid K (default: 3,4,5,6,7,8,9)
- Transform tags to filter variables (default: DA_, DA3m_)
- Target column name (default: DA_GDP)

## Dependencies

- Required: `data.table`, `lubridate`, `stringr`, `midasr`
- The script will attempt to auto-install `midasr` from CRAN if not found

To manually install:
```r
install.packages("midasr")
```

## Notes

- We use unrestricted MIDAS (U-MIDAS): each lag gets its own coefficient (no polynomial restrictions).
- The horizon-adjusted lag specification ensures we never use "future" monthly data at any nowcast vintage.
- The same pseudo vintages can be reused for 3PF workflow to ensure identical ragged edges across methods.
