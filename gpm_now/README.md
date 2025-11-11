# GPM Now - Multi-Country Nowcasting Framework

A flexible, modular nowcasting framework supporting multiple countries with shared core functionality and country-specific implementations.

## 📁 Project Structure

```
gpm_now/
├── common/                          # Core functions (shared across countries)
│   ├── midas_models.R              # MIDAS model fitting and forecasting
│   ├── tprf_models.R               # Three-Pass Regression Filter models
│   ├── dfm_models.R                # Dynamic Factor Models
│   ├── combine.R                   # Model combination (equal, BIC, RMSE weights)
│   ├── structural_breaks.R         # Structural break detection & adjustment
│   ├── transforms.R                # Data transformations (YoY, MoM, etc.)
│   ├── utils.R                     # General utilities
│   ├── lagmap.R                    # Lag structure mapping
│   ├── selection.R                 # Model selection utilities
│   └── news.R                      # Nowcast news decomposition
│
├── countries/                       # Country-specific implementations
│   ├── mexico/                     # Mexico nowcasting
│   │   ├── config/                 # Mexico configurations
│   │   │   ├── variables.yaml      # Variable definitions
│   │   │   ├── options.yaml        # Model options
│   │   │   └── calendar.csv        # Release calendar
│   │   ├── data/                   # Mexico data
│   │   │   ├── monthly/            # Monthly indicators
│   │   │   └── quarterly/          # Quarterly GDP
│   │   ├── R/                      # Mexico-specific functions
│   │   │   ├── runner.R            # Nowcast runner
│   │   │   └── io.R                # I/O functions
│   │   ├── output/                 # Nowcast outputs
│   │   ├── plots/                  # Visualization outputs
│   │   ├── run_mexico_nowcast.R    # Main script
│   │   └── run_mexico_rolling_evaluation.R  # Evaluation script
│   │
│   └── brazil/                     # Brazil nowcasting
│       ├── config/                 # Brazil configurations
│       ├── data/                   # Brazil data
│       ├── R/                      # Brazil-specific functions
│       ├── output/                 # Nowcast outputs
│       ├── plots/                  # Visualization outputs
│       ├── run_brazil_nowcast.R    # Main script
│       └── run_brazil_rolling_evaluation.R  # Evaluation script
│
└── retriever/                      # Data retrieval system
    ├── utils.R                     # Common retrieval utilities
    └── brazil/                     # Brazil-specific data retrieval
        ├── config.R                # Brazilian series definitions
        ├── retriever.R             # Download functions
        └── csv_folder/             # Downloaded data
```

## 🚀 Quick Start

### Running Mexico Nowcast

```r
# Navigate to Mexico folder
setwd("gpm_now/countries/mexico")

# Run weekly nowcast
source("run_mexico_nowcast.R")

# Run rolling evaluation
source("run_mexico_rolling_evaluation.R")
```

### Running Brazil Nowcast

```r
# Navigate to Brazil folder
setwd("gpm_now/countries/brazil")

# Run weekly nowcast (includes data retrieval)
source("run_brazil_nowcast.R")

# Run rolling evaluation
source("run_brazil_rolling_evaluation.R")
```

## 🔧 Key Features

### 📊 **Model Types**
- **MIDAS Models**: Mixed Data Sampling for quarterly/monthly frequencies
  - Multiple lag structures (AR1, AR2, lag3-4, m2-3)
  - Beta polynomial restrictions
  - Model combination (equal weights, inverse BIC, inverse RMSE)
  - Structural break adjustment using recent forecast errors
  
- **TPRF Models**: Three-Pass Regression Filter
  - Factor extraction from monthly panels
  - AR specifications with factors
  
- **DFM Models**: Dynamic Factor Models
  - Common factor extraction
  - State-space framework

### 🔀 **Model Combination**
- **Trimming**: Remove worst 25% of models before combining
- **Weighting schemes**:
  - Equal weights (simple average)
  - Inverse BIC weights
  - Inverse RMSE weights
- 5-7.5% improvement over best individual MIDAS model

### 🔧 **Structural Break Handling**
- Detection of level shifts in GDP growth
- Intercept adjustment using recent forecast errors
- Rolling window adjustment (default: 4 quarters)
- Handles post-2021 systematic under-prediction

### 📈 **Evaluation Framework**
- Rolling out-of-sample forecasts
- Configurable initial window (default: 60 quarters)
- 1-quarter ahead forecasts
- RMSE comparison across models
- Automated plotting and reporting

## 🌍 Adding a New Country

### Step 1: Create Country Folder Structure

```bash
cd gpm_now/countries
mkdir -p new_country/{config,data/monthly,data/quarterly,R,output,plots}
```

### Step 2: Copy Template Files

```bash
# Copy runner and I/O templates from Mexico
cp mexico/R/runner.R new_country/R/
cp mexico/R/io.R new_country/R/

# Copy and customize configuration files
cp mexico/config/*.yaml new_country/config/
cp mexico/config/*.csv new_country/config/
```

### Step 3: Create Main Runner Script

Create `run_new_country_nowcast.R`:

```r
library(midasr)
library(zoo)
library(yaml)
library(jsonlite)

# Set working directory to country folder
setwd(dirname(rstudioapi::getSourceEditorContext()$path))

# Source all common core functions
common_path <- "../../common"
source(file.path(common_path, "utils.R"))
source(file.path(common_path, "transforms.R"))
source(file.path(common_path, "lagmap.R"))
source(file.path(common_path, "midas_models.R"))
source(file.path(common_path, "tprf_models.R"))
source(file.path(common_path, "dfm_models.R"))
source(file.path(common_path, "selection.R"))
source(file.path(common_path, "combine.R"))
source(file.path(common_path, "structural_breaks.R"))
source(file.path(common_path, "news.R"))

# Source country-specific functions
source("R/io.R")
source("R/runner.R")

# Run nowcast
result <- run_weekly_nowcast(
  as_of_date = Sys.Date(),
  config_path = "config",
  data_path = "data",
  output_path = "output"
)
```

### Step 4: Configure Country-Specific Settings

Edit `config/variables.yaml`:

```yaml
target:
  id_q: "gdp_q"              # Quarterly GDP series ID
  id_m_proxy: "ip_m"         # Monthly GDP proxy series ID
  name: "GDP Growth"
  
indicators:
  - id: "ip_m"               # Industrial production
    name: "Industrial Production"
    freq: "monthly"
    transform: "pct_mom"
    
  - id: "retail_m"           # Retail sales
    name: "Retail Sales"
    freq: "monthly"
    transform: "pct_mom"
```

Edit `config/options.yaml`:

```yaml
midas:
  model_specs:
    - name: "MIDAS_AR1_lag3_m2"
      ar_q: 1
      lag_y: 3
      lag_x: 2
      
midas_combination:
  enabled: true
  schemes: ["equal", "inv_bic", "inv_rmse"]
  trim_percentile: 0.25
  
structural_breaks:
  enabled: true
  adjustment_method: "recent_errors"
  adjustment_window: 4
```

### Step 5: Add Country Data

Place data files in:
- `data/quarterly/` - Quarterly GDP data
- `data/monthly/` - Monthly indicator data

Format:
```csv
date,value
2020-01-01,2.5
2020-04-01,-8.2
```

### Step 6: Test Your Implementation

```r
# Test weekly nowcast
source("run_new_country_nowcast.R")

# Test rolling evaluation
source("run_new_country_rolling_evaluation.R")
```

## 📦 Dependencies

### Core R Packages
```r
install.packages(c(
  "midasr",      # MIDAS models
  "zoo",         # Time series
  "yaml",        # Configuration
  "jsonlite",    # JSON I/O
  "ggplot2",     # Plotting (optional)
  "reshape2"     # Data reshaping (optional)
))
```

### Country-Specific (Brazil)
```r
install.packages(c(
  "GetBCBData",  # Brazilian Central Bank API
  "ipeadatar",   # Ipeadata API
  "sidrar"       # IBGE API
))
```

## 📊 Model Combination Results (Mexico Example)

From rolling evaluation (post-2015):

| Model | RMSE | Improvement |
|-------|------|-------------|
| Best Individual MIDAS | 2.45 | Baseline |
| Equal Weights | 2.32 | 5.2% |
| Inverse BIC | 2.35 | 4.1% |
| Inverse RMSE | 2.26 | 7.5% |

## 🔍 Common Functions Reference

### MIDAS Models (`common/midas_models.R`)
```r
fit_or_update_midas_set(y, x, ar_q, lag_y, lag_x, poly_degree, h)
```

### Model Combination (`common/combine.R`)
```r
combine_midas_forecasts(forecasts, model_info, schemes, trim_percentile)
trim_midas_models(model_info, trim_percentile)
```

### Structural Breaks (`common/structural_breaks.R`)
```r
detect_structural_break(y, method, min_segment_length)
calculate_intercept_adjustment(y_train, y_fitted, method, window_size)
```

### TPRF Models (`common/tprf_models.R`)
```r
fit_tprf_model(y, X_panel, n_factors, ar_q, h)
```

## 📝 Configuration Files

### `variables.yaml`
Defines target variables and indicators with transformations.

### `options.yaml`
Specifies model configurations, combination schemes, and options.

### `calendar.csv`
Release calendar for data updates and nowcast scheduling.

## 🤝 Contributing

1. **Add new models**: Extend common functions in `common/`
2. **Add new countries**: Follow the template structure in `countries/`
3. **Improve documentation**: Update README files with examples
4. **Enhance features**: Submit PRs with tests

## 📄 License

Part of the GPM Now project. See main project license.

## 🆘 Support

For issues or questions:
1. Check country-specific README files
2. Review configuration examples in Mexico/Brazil
3. Consult common function documentation

---

**Last Updated**: November 2025
