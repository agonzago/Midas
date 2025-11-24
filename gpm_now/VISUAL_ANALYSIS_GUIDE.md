# Visual Analysis Tools for Variable Selection

We have created a new tool `gpm_now/visual_analysis.R` to help you select monthly indicators and verify their relationship with the target (GDP).

## Features

1.  **Correlation Heatmap**:
    *   **Purpose**: Quickly identify which monthly indicators have the strongest relationship with the quarterly target.
    *   **Method**: Aggregates monthly data to quarterly (mean) and computes correlation.

2.  **Scatter Plots**:
    *   **Purpose**: Visually check linearity and outliers.
    *   **Plot**: Quarterly Aggregated Indicator (X) vs GDP Growth (Y). Includes a regression line.

3.  **Cross-Correlation Function (CCF)**:
    *   **Purpose**: Determine the optimal lag or lead.
    *   **Plot**: Correlation at different quarterly lags (t-4 to t+4).
    *   **Interpretation**: A peak at Lag < 0 implies the indicator leads GDP. A peak at Lag 0 implies contemporaneous correlation.

4.  **Standardized Time Series**:
    *   **Purpose**: Check co-movement and stationarity.
    *   **Plot**: Both series scaled to Z-scores (Mean=0, SD=1) to overlay them on the same scale.

## How to Run

```bash
Rscript gpm_now/visual_analysis.R
```

## Output
*   Generates `visual_analysis_report.pdf` in the current directory.

## Data Used
*   Reads `data/monthly/monthly_data.csv` and `data/quarterly/quarterly_data.csv`.
*   If these are not found, it falls back to `../Data/mex_M.csv` and `../Data/mex_Q.csv`.
*   **Note**: The script analyzes the data *as found in these files*. If you want to test different transformations (e.g., log vs level), ensure your input data reflects that or modify the script to apply transformations on the fly.
