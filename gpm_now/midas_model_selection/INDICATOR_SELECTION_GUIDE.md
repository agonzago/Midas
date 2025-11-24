# MIDAS Model Selection Guide

## How to Select Specific Indicators

You can now specify exactly which indicators to use in the MIDAS model selection process. This overrides the default behavior of selecting all variables with `DA_` or `DA3m_` prefixes.

### Usage

Run the `00_run_all.R` script with a 4th argument containing a comma-separated list of indicators.

```bash
# Standard Mode
Rscript gpm_now/midas_model_selection/code/00_run_all.R 2022Q1 2025Q2 standard "DA_IPI,DA_RETAIL,DA_CREDIT"

# Stable Mode
Rscript gpm_now/midas_model_selection/code/00_run_all.R 2022Q1 2025Q2 stable "DA_IPI,DA_RETAIL,DA_CREDIT"
```

### Arguments
1.  **Start Quarter**: e.g., `2022Q1`
2.  **End Quarter**: e.g., `2025Q2`
3.  **Mode**: `standard` (default) or `stable`
4.  **Indicators**: Comma-separated list of variable names (e.g., `DA_IPI,DA_RETAIL`). If omitted or empty, the script defaults to using all variables with `DA_` and `DA3m_` prefixes.

### Example

To run the model selection using only `DA_IPI` and `DA_RETAIL`:

```bash
cd /home/andres/work/Midas
Rscript gpm_now/midas_model_selection/code/00_run_all.R 2022Q1 2025Q2 standard "DA_IPI,DA_RETAIL"
```

### Notes
- Ensure the indicator names match exactly what is in the `monthly.csv` file (including prefixes like `DA_`).
- If you provide a list, ONLY those indicators will be processed.
- If you want to go back to using all indicators, simply omit the 4th argument.
