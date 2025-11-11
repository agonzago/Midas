# 🚀 Quick Start Guide - Multi-Country Nowcasting

## Choose Your Country

### 🇲🇽 Mexico
```bash
cd gpm_now/countries/mexico
```

### 🇧🇷 Brazil
```bash
cd gpm_now/countries/brazil
```

---

## Run Weekly Nowcast

### In R or RStudio:

**Mexico:**
```r
setwd("gpm_now/countries/mexico")
source("run_mexico_nowcast.R")
```

**Brazil:**
```r
setwd("gpm_now/countries/brazil")
source("run_brazil_nowcast.R")
```

**Output**: 
- `output/nowcast_YYYY-MM-DD.json` - Full results
- `output/nowcast_YYYY-MM-DD.csv` - Summary
- `plots/nowcast_YYYY-MM-DD.png` - Visualization

---

## Run Model Evaluation

### Rolling Out-of-Sample Evaluation:

**Mexico:**
```r
setwd("gpm_now/countries/mexico")
source("run_mexico_rolling_evaluation.R")
```

**Brazil:**
```r
setwd("gpm_now/countries/brazil")
source("run_brazil_rolling_evaluation.R")
```

**Output**:
- `output/rolling_evaluation_results.csv` - All forecasts
- `plots/midas_comparison.png` - Model comparison
- Console shows RMSE for all models

---

## What You Get

### Models
- ✅ **MIDAS Models**: 3-5 specifications with different lag structures
- ✅ **TPRF Models**: Factor-based models with monthly panels
- ✅ **Model Combination**: Equal, Inverse-BIC, Inverse-RMSE weights
- ✅ **Structural Breaks**: Adjustment for post-2021 level shifts

### Outputs
- ✅ **Forecasts**: Point forecasts for next quarter
- ✅ **Model Info**: BIC, AIC, RMSE for each model
- ✅ **Combinations**: 3 weighted averages (5-7.5% improvement)
- ✅ **Evaluation**: Historical forecast accuracy

### Features
- ✅ **Automatic trimming**: Removes worst 25% of models
- ✅ **Break adjustment**: Handles structural changes
- ✅ **Logging**: Detailed execution logs
- ✅ **Visualization**: Automatic plot generation

---

## Typical Workflow

### 1. Weekly Nowcast (Production)
```r
# Update and forecast
source("run_mexico_nowcast.R")

# Review output
result <- jsonlite::fromJSON("output/nowcast_2025-11-10.json")
print(result$forecasts$midas_combination)
```

### 2. Model Evaluation (Research)
```r
# Run evaluation
source("run_mexico_rolling_evaluation.R")

# Analyze results
results <- read.csv("output/rolling_evaluation_results.csv")
summary(results)
```

### 3. Customize Models (Advanced)
```r
# Edit model specifications in run_mexico_rolling_evaluation.R
model_specs <- list(
  list(name = "MIDAS_Custom", type = "midas", ar_q = 3, lag_y = 5, lag_x = 3)
)
```

---

## Directory Reference

```
gpm_now/
├── common/                  # Core functions (DON'T EDIT unless adding features)
├── countries/
│   ├── mexico/             # 🇲🇽 Work here for Mexico
│   │   ├── config/         # Edit: variables.yaml, options.yaml
│   │   ├── data/           # Place: GDP and indicator data
│   │   ├── output/         # Output: nowcast results
│   │   └── run_*.R         # Run: main scripts
│   └── brazil/             # ��🇷 Work here for Brazil
│       └── ...             # (same structure)
└── retriever/
    └── brazil/             # Brazil data auto-download
```

---

## Need Help?

**Documentation:**
- Framework: `gpm_now/README.md`
- Mexico: `gpm_now/countries/mexico/README.md`
- Brazil: `gpm_now/countries/brazil/README.md`
- Functions: `gpm_now/common/README.md`

**Common Issues:**
1. **Missing packages**: Install `midasr`, `zoo`, `yaml`, `jsonlite`
2. **Data not found**: Check data paths in config files
3. **Model errors**: Check logs in `output/logs/`

**Examples:**
- See `run_mexico_rolling_evaluation.R` for model specifications
- See `config/options.yaml` for configuration options

---

## Performance Tips

### Faster Execution
- Use fewer models in initial testing
- Reduce evaluation window size
- Disable plotting for speed

### Better Forecasts
- Add more monthly indicators
- Try different lag structures
- Enable structural break adjustment
- Use model combination

### Production Use
- Schedule weekly runs
- Archive outputs with dates
- Monitor logs for errors
- Track forecast accuracy over time

---

**Last Updated**: November 2025  
**Countries**: Mexico 🇲🇽, Brazil 🇧🇷  
**Status**: ✅ Ready to Use
