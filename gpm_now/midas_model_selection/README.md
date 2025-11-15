# MIDAS model selection (gpm_now)

This module builds pseudo-real-time ragged vintages using the release calendar and performs per-indicator U‑MIDAS model selection with BIC for 2022Q1–2025Q2.

**Key features:**
- Uses `midasr` package for proper mixed-frequency modeling
- **Tests models with and without GDP AR lags** (p = 0 to 4, includes no-AR option)
- Adjusts monthly indicator lags based on horizon (ragged edge)
- BIC selection over joint lag structure (GDP AR + indicator lags)
- **Multiple combination schemes**: BIC-weighted, RMSE-weighted, Equal-weighted, **Trimmed mean**
- **Stable model selection** option with evaluation periods for news analysis
- **Executive summary** with ranked forecasts and top contributors

- Data source (transformed): `gpm_now/retriever/brazil/output/transformed_data/`
  - `monthly.csv`: wide monthly indicators including transformed versions (e.g., `DA_`, `DA3m_` prefixes)
  - `quarterly.csv`: quarterly GDP target columns (default target: `DA_GDP`)
- Calendar: `gpm_now/retriever/Initial_calendar.csv` (falls back to end-of-month if missing)

## Model specification

For each indicator, we estimate U-MIDAS models of the form:

**GDP_t = α + Σ β_i·GDP_{t-i} + Σ γ_j·X_{m-h-j+1} + ε**

Where:
- GDP_{t-i}: quarterly GDP lags (i = 0 to p, **now includes p=0 for no-AR models**)
- X_{m-h-j+1}: monthly indicator lags starting from horizon h (j = 0 to K-1)
- h = months between last available data and quarter end

The lag specification `mls(indicator, h:(h+K-1), 3)` ensures we only use available monthly data at each nowcast vintage.

## Run

From within `gpm_now/midas_model_selection/code` or repository root:

**Standard mode** (re-selects models at each vintage):
```bash
Rscript gpm_now/midas_model_selection/code/00_run_all.R 2022Q1 2025Q2
```

**Stable mode** (selects models once per evaluation period, enables news analysis):
```bash
Rscript gpm_now/midas_model_selection/code/00_run_all.R 2022Q1 2025Q2 stable
```

Outputs in `gpm_now/midas_model_selection/data/`:
- `vintages/`: `pseudo_vintages_<quarter>.rds` per quarter containing Friday vintages and availability tables
- `selection/umidas_selection_summary.csv`: selected GDP lags (p) and indicator lags (K) per indicator, plus RMSE
- `nowcasts/umidas_nowcasts_by_vintage.csv`: all nowcasts by quarter-Friday for each selected model
- `stable/`: (if using stable mode) model specs and nowcasts with fixed selections per evaluation period
- `combination/`:
  - `umidas_combined_nowcasts.csv`: all vintages with **4 combination schemes** (BIC, RMSE, Equal, Trimmed)
  - `umidas_combined_nowcasts_latest.csv`: latest per quarter
  - `executive_summary_<quarter>.txt`: formatted report with rankings and top contributors
  - Plots: fan charts and time series

## Parameters

**Runner arguments:**
- Arg 1: Start quarter (default: 2022Q1)
- Arg 2: End quarter (default: 2025Q2)
- Arg 3: "stable" (optional) - Use stable model selection with evaluation periods

**Model selection parameters** (`02_umidas_model_selection.R`):
- GDP AR lags grid (default: **0,1,2,3,4** - now includes no-AR option)
- Indicator lags grid K (default: 3,4,5,6,7,8,9)
- Transform tags to filter variables (default: DA_, DA3m_)
- Target column name (default: DA_GDP)

**Stable selection parameters** (`02b_stable_model_selection.R`):
- Same as above, plus:
- Evaluation period: "quarter" or "month" (default: quarter)
  - "quarter": Select models once per quarter, apply to all Fridays in that quarter
  - "month": Select models once per month, apply to all Fridays in that month

**Combination parameters** (`03_combine_nowcasts.R`):
- Trim proportion (default: 0.10 = 10%)
- Drop worst proportion (default: 0.15 = drop worst 15% of models)
- Drop metric: "rmse" or "bic" (default: rmse)

## Combination Schemes

All four schemes are computed and saved:

1. **BIC-weighted**: `exp(-0.5 * delta_BIC)` - Information-theoretic weights
2. **RMSE-weighted**: `1/RMSE²` - Precision weights (more extreme than simple inverse)
3. **Equal-weighted**: Simple average of all indicators
4. **Trimmed mean**: Simple trimmed mean (10% trim by default) - Gene's approach

The executive summary ranks all schemes by historical RMSE performance.

## Stable Model Selection for News Analysis

The stable selection mode (`02b_stable_model_selection.R`) addresses a key requirement:

**Problem**: When models are re-selected at every vintage, it's hard to decompose forecast revisions into "news" (new data arrivals) vs "model changes".

**Solution**: 
- Select models at the **start** of each evaluation period (e.g., start of quarter)
- Keep model specifications **constant** throughout that period
- All forecast revisions within the period are due to **new data only**
- This enables clean news decomposition and tracks which indicators/specs drive changes

**Output files** (`data/stable/`):
- `stable_model_specs.csv`: Which (p, K) was selected for each indicator in each period
- `stable_nowcasts_by_vintage.csv`: All nowcasts using those fixed specs

Use this for:
- Understanding what drives forecast revisions (news analysis)
- Stable reporting periods where model specs don't change unexpectedly
- Comparing performance when models are fixed vs adaptive

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
