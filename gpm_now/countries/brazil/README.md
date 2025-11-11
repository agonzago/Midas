# Brazil Nowcasting

Weekly nowcasting for Brazilian GDP using MIDAS and TPRF models with automated data retrieval.

## 📊 Data Sources

### Quarterly Data
- **GDP Growth**: Quarterly GDP growth rate
- **Source**: IBGE (Brazilian Institute of Geography and Statistics)

### Monthly Data
- **IBC-Br**: Central Bank Economic Activity Index (GDP proxy)
- **Industrial Production**: Manufacturing, mining, utilities
- **Retail Sales**: Volume and value indices
- **Credit**: Total credit to private sector
- **Labor Market**: Employment, unemployment rates
- **Inflation**: IPCA, IGP-M indices
- **Source**: BCB (Central Bank of Brazil), IBGE, Ipeadata

All data is automatically retrieved via the `retriever/brazil/` system.

## 🚀 Quick Start

### Run Weekly Nowcast with Data Update

```r
# From gpm_now/countries/brazil/
source("run_brazil_nowcast.R")
```

This will:
1. **Retrieve latest data** from Brazilian sources (BCB, IBGE, Ipeadata)
2. Load configurations from `config/`
3. Fit MIDAS models (multiple specifications)
4. Fit TPRF models with monthly panel
5. Combine MIDAS forecasts (equal, inv-BIC, inv-RMSE)
6. Generate nowcast report
7. Save outputs to `output/`

### Run Rolling Evaluation

```r
# From gpm_now/countries/brazil/
source("run_brazil_rolling_evaluation.R")
```

This will:
1. Set up rolling window (typically 40-60 quarters)
2. Forecast 1-quarter ahead recursively
3. Evaluate MIDAS, TPRF, and combination models
4. Calculate RMSE for all models
5. Generate comparison plots
6. Save results to `output/rolling_evaluation_results.csv`

## 📁 File Structure

```
brazil/
├── config/
│   ├── variables.yaml      # Variable definitions for Brazil
│   ├── options.yaml        # Model specifications
│   └── calendar.csv        # Release calendar
├── data/
│   ├── monthly/            # Monthly indicator data (auto-updated)
│   └── quarterly/          # Quarterly GDP data (auto-updated)
├── R/
│   ├── runner.R            # Weekly nowcast runner
│   └── io.R                # I/O functions
├── output/                 # Nowcast outputs (JSON, CSV)
├── plots/                  # Forecast plots
├── run_brazil_nowcast.R    # Main nowcast script (includes data retrieval)
└── run_brazil_rolling_evaluation.R  # Evaluation script
```

## 🔄 Data Retrieval System

Brazil implementation integrates with `gpm_now/retriever/brazil/`:

### Automated Data Downloads

The `run_brazil_nowcast.R` script automatically:
1. Connects to Brazilian APIs (BCB, IBGE, Ipeadata)
2. Downloads latest releases
3. Applies transformations (YoY, MoM, etc.)
4. Validates data quality
5. Saves to `data/` folders

### Manual Data Update

```r
# From gpm_now/retriever/brazil/
source("main_data_retrieval.R")

# Download all configured series
update_all_brazilian_data()

# Copy to Brazil nowcast data folder
file.copy(
  from = "static_csv/*.csv",
  to = "../../countries/brazil/data/monthly/",
  overwrite = TRUE
)
```

### Configure Data Series

Edit `retriever/brazil/variable_codes.csv`:

```csv
series_id,description,source,api_code,frequency,transformation
ibc_br_m,IBC-Br Monthly,BCB,24363,monthly,pct_yoy
pim_mfg,Industrial Production Manufacturing,IBGE,3653,monthly,pct_yoy
pmc_retail,Retail Sales Volume,IBGE,1475,monthly,pct_yoy
```

## 🔧 Model Specifications

### MIDAS Models

Typical specifications for Brazil:

1. **MIDAS_AR1_lag3_m2**: AR(1) with 3 quarterly lags, 2 lag periods
2. **MIDAS_AR2_lag4_m2**: AR(2) with 4 quarterly lags, 2 lag periods
3. **MIDAS_AR1_lag4_m3**: AR(1) with 4 quarterly lags, 3 lag periods
4. **MIDAS_AR2_lag4_m2_ADJ**: With structural break adjustment
5. **MIDAS_AR1_lag3_m2_ADJ**: With structural break adjustment

### TPRF Models

1. **TPRF_3F_AR1**: 3 factors, AR(1)
2. **TPRF_2F_AR2**: 2 factors, AR(2)

Panel typically includes: IBC-Br, industrial production, retail sales, credit, labor market indicators.

### Model Combination

- **Trimming**: Remove worst 25% of MIDAS models
- **Schemes**:
  - Equal weights (simple average)
  - Inverse BIC weights
  - Inverse RMSE weights

## ⚙️ Configuration

### Variables Configuration

Edit `config/variables.yaml`:

```yaml
target:
  id_q: "gdp_q_yoy"         # Quarterly GDP YoY growth
  id_m_proxy: "ibc_br_m"    # IBC-Br as monthly proxy
  name: "GDP Growth"
  
indicators:
  - id: "ibc_br_m"          # Economic Activity Index
    name: "IBC-Br"
    freq: "monthly"
    transform: "pct_yoy"
    source: "BCB"
    
  - id: "pim_mfg"           # Manufacturing production
    name: "Industrial Production"
    freq: "monthly"
    transform: "pct_yoy"
    source: "IBGE"
    
  - id: "pmc_retail"        # Retail sales
    name: "Retail Sales"
    freq: "monthly"
    transform: "pct_yoy"
    source: "IBGE"
```

### Model Options

Edit `config/options.yaml`:

```yaml
midas:
  model_specs:
    - name: "MIDAS_AR1_lag3_m2"
      ar_q: 1
      lag_y: 3
      lag_x: 2
    - name: "MIDAS_AR2_lag4_m2"
      ar_q: 2
      lag_y: 4
      lag_x: 2
      
midas_combination:
  enabled: true
  schemes: ["equal", "inv_bic", "inv_rmse"]
  trim_percentile: 0.25
  
structural_breaks:
  enabled: true
  adjustment_method: "recent_errors"
  adjustment_window: 4

data_retrieval:
  enabled: true
  sources: ["BCB", "IBGE", "Ipeadata"]
  update_frequency: "weekly"
```

## 📊 Output Files

### Weekly Nowcast Outputs

- `output/nowcast_YYYY-MM-DD.json` - Full nowcast results
- `output/nowcast_YYYY-MM-DD.csv` - Forecast summary
- `output/logs/nowcast_YYYY-MM-DD.log` - Execution log
- `output/logs/data_retrieval_YYYY-MM-DD.log` - Data download log
- `plots/nowcast_YYYY-MM-DD.png` - Forecast visualization

### Rolling Evaluation Outputs

- `output/rolling_evaluation_results.csv` - All forecasts and actuals
- `plots/midas_comparison.png` - Time series comparison
- `plots/rmse_comparison.png` - RMSE bar chart

## 🔍 Data Notes

### Real-Time Data
The retriever system provides **real-time data** as published by Brazilian sources:
- Data reflects latest releases
- Revisions are automatically incorporated
- For vintage analysis, save historical snapshots

### Data Availability
- **IBC-Br**: Released ~45 days after reference month
- **Industrial Production**: Released ~40 days after reference month
- **Retail Sales**: Released ~35 days after reference month
- **GDP**: Released ~60 days after reference quarter

### Handling Missing Data
- Recent months may have missing data
- MIDAS handles ragged-edge naturally
- TPRF imputes missing values in factor extraction

## 🛠️ Customization

### Add New Data Series

1. **Add to retriever configuration**:

Edit `retriever/brazil/variable_codes.csv`:
```csv
new_series_id,Description,BCB,12345,monthly,pct_yoy
```

2. **Add to variables configuration**:

Edit `config/variables.yaml`:
```yaml
indicators:
  - id: "new_series_id"
    name: "New Economic Indicator"
    freq: "monthly"
    transform: "pct_yoy"
```

3. **Run data retrieval**:
```r
source("../../retriever/brazil/main_data_retrieval.R")
```

### Change Data Transformations

Available transformations in retriever:
- `level` - No transformation
- `pct_mom` - Month-over-month percent change
- `pct_yoy` - Year-over-year percent change
- `diff` - First difference
- `log` - Natural logarithm
- `log_diff` - Log difference

## 📞 Support

For Brazil-specific questions:
- **Data sources**: See `gpm_now/retriever/brazil/README.md`
- **API issues**: Check BCB/IBGE API documentation
- **Model specifications**: See `run_brazil_rolling_evaluation.R`
- **Common functions**: See `../../common/README.md`

## 🔗 Related Files

- **Data retrieval system**: `gpm_now/retriever/brazil/`
- **Common functions**: `gpm_now/common/`
- **Main documentation**: `gpm_now/README.md`

## 📚 Brazilian Data Sources

### BCB (Central Bank of Brazil)
- API: GetBCBData package
- Series: IBC-Br, credit, interest rates, exchange rates
- URL: https://www3.bcb.gov.br/sgspub/

### IBGE (Brazilian Statistics Office)
- API: sidrar package
- Series: GDP, industrial production, retail sales, inflation
- URL: https://www.ibge.gov.br/

### Ipeadata
- API: ipeadatar package
- Series: Various macroeconomic indicators
- URL: http://www.ipeadata.gov.br/

---

**Last Updated**: November 2025  
**Data Update**: Automated via retriever  
**Forecast Frequency**: Weekly (or on-demand)
