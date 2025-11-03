# GPM Now - Weekly Nowcasting System

A new R-based weekly nowcasting toolbox has been added to this repository in the `gpm_now/` directory.

## What is GPM Now?

GPM Now is a comprehensive nowcasting system implementing three parallel modeling approaches:

1. **U-MIDAS** - Unrestricted MIDAS models per indicator
2. **3PF/TPRF** - Three-Pass Regression Filter with factor models  
3. **DFM** - Dynamic Factor Models with optional state-space support

## Key Features

✓ **Country-agnostic**: Works for Brazil (with monthly IBC-Br proxy) and countries with quarterly GDP only  
✓ **Direct forecasting**: No bridging; no imputation of unreleased data  
✓ **Calendar-aware**: Uses only released monthly observations  
✓ **Model selection**: RMSE/BIC-based with persistence tracking  
✓ **Forecast combination**: Multiple schemes with uncertainty intervals  
✓ **Reproducible**: Immutable weekly data snapshots  
✓ **News decomposition**: Track changes vs. previous week  

## Quick Start

```bash
cd gpm_now
Rscript check_dependencies.R  # Check/install required packages
Rscript main.R                # Run weekly nowcast
```

Or in R:
```r
setwd("gpm_now")
source("R/runner.R")
result <- run_weekly_nowcast()
print(result$combined_forecast)
```

## Documentation

- **[gpm_now/README.md](gpm_now/README.md)** - Full methodology and API reference
- **[gpm_now/QUICKSTART.md](gpm_now/QUICKSTART.md)** - Quick start guide with examples
- **[gpm_now/IMPLEMENTATION.md](gpm_now/IMPLEMENTATION.md)** - Implementation details

## System Components

```
gpm_now/
├── R/                    # 11 modules, 2,408 lines
│   ├── utils.R          # Date utilities, logging
│   ├── io.R             # Data I/O, vintage management
│   ├── transforms.R     # Transformations
│   ├── lagmap.R         # Ragged edge handling
│   ├── midas_models.R   # U-MIDAS
│   ├── tprf_models.R    # 3PF factors
│   ├── dfm_models.R     # DFM + state-space
│   ├── selection.R      # Model selection
│   ├── combine.R        # Forecast combination
│   ├── news.R           # News decomposition
│   └── runner.R         # Weekly orchestration
├── config/              # YAML/CSV configuration
├── data/                # Monthly/quarterly data
└── output/              # Reports, logs, models
```

## Requirements

- R >= 4.0.0
- Required packages: midasr, dfms, data.table, dplyr, tidyr, lubridate, zoo, yaml, jsonlite, digest
- Optional: KFAS, MARSS (for advanced state-space features)

## Existing Systems

This repository also contains:
- **midas_nowcasting/** - Python-based nowcasting system
- **Mexico_Midas.R** - Mexico-specific MIDAS analysis
- **run_nowcast.py** - Python nowcast runner

The new `gpm_now/` system provides an R-based alternative with additional features and modeling approaches.

## Next Steps

1. Review [gpm_now/QUICKSTART.md](gpm_now/QUICKSTART.md) for setup
2. Configure your data in `gpm_now/data/`
3. Edit `gpm_now/config/variables.yaml` for your indicators
4. Run `gpm_now/check_dependencies.R` to verify setup
5. Execute `gpm_now/main.R` for your first nowcast

## Support

For questions or issues with GPM Now, refer to:
- Documentation in `gpm_now/` directory
- Example scripts in `gpm_now/example_run.R`
- Logs in `gpm_now/output/logs/`
