# GPM Now - Data Retriever System

A modular data retrieval system for the GPM Now weekly nowcasting framework. This system provides automated downloading, validation, and storage of economic indicators from various national statistical agencies.

## Overview

The retriever system is designed with a country-agnostic architecture that can be easily extended to support multiple countries and data sources. Currently implemented for Brazil, with the framework ready for expansion to other countries.

## Architecture

```
retriever/
├── utils.R              # General utility functions (all countries)
└── brazil/              # Brazil-specific implementation
    ├── config.R         # Brazilian series definitions  
    ├── retriever.R      # Brazilian data download functions
    ├── setup.R          # Installation and configuration
    ├── example_usage.R  # Usage demonstrations
    ├── csv_folder/      # Local data storage
    └── README.md        # Brazil-specific documentation
```

## Key Features

### 🌍 **Multi-Country Ready**
- Modular design allows easy addition of new countries
- Shared utilities for common operations
- Country-specific implementations for local data sources

### 📊 **Comprehensive Data Sources** 
- **Brazil**: Central Bank (BCB), Ipeadata, IBGE
- **Future**: Fed (US), ECB (EU), Bank of Japan, etc.

### 🔧 **Robust Data Handling**
- Automatic data validation and quality checks
- Standardized CSV output format across all sources
- Rich metadata preservation in JSON format
- Error handling and retry logic

### 🔄 **GPM Now Integration**
- Series IDs match GPM Now configuration files
- Compatible with existing calendar and variables setup
- Seamless data pipeline for nowcasting workflows

### 📈 **Economic Indicator Coverage**
- GDP and GDP proxies (monthly/quarterly)
- Production indicators (industrial, retail, services)
- Labor market indicators (employment, unemployment)
- Financial indicators (credit, exchange rates, interest rates)
- Price indicators (inflation measures)
- External sector (trade, commodities)
- Confidence and survey indicators

## Quick Start

### 1. Brazil Setup

```r
# Navigate to Brazil retriever
setwd("retriever/brazil")

# Install packages and test connections
source("setup.R")

# Download core indicators
source("retriever.R")
results <- download_all_brazilian_data(
  series_ids = c("ibc_br_m", "ipi_mfg", "retail_real", "credit_total"),
  start_date = "2020-01-01"
)
```

### 2. Integration with GPM Now

```r
# Update GPM Now data files directly
update_gpm_now_data(output_folder = "../data")

# Now run GPM Now nowcasting
setwd("..")  # Back to gpm_now root
source("R/runner.R")
result <- run_weekly_nowcast(as_of_date = Sys.Date())
```

## General Utilities (`utils.R`)

The shared utility functions provide:

### Data Validation
```r
validation <- validate_data(data, series_id, freq = "monthly")
# Checks: required columns, missing values, date consistency, duplicates
```

### Date Standardization  
```r
dates <- standardize_dates(date_col, freq = "monthly")
# Handles: various date formats, quarterly codes ("2024Q1")
```

### Data Transformations
```r
transformed <- apply_transformation(x, transform = "pct_mom", freq = "monthly")
# Supports: level, log, diff, pct_change, mom, yoy
```

### CSV Storage with Metadata
```r
save_data_csv(data, file_path, metadata)
# Creates: standardized CSV + JSON metadata
```

### Logging and Monitoring
```r
log_entry <- log_retrieval(series_id, source, status, n_obs, date_range, notes)
print_retrieval_summary(results)
```

## Country Implementation Template

To add a new country, create:

```
retriever/
└── [country]/
    ├── config.R         # Series definitions for the country
    ├── retriever.R      # Download functions using local APIs  
    ├── setup.R          # Package installation and testing
    └── README.md        # Country-specific documentation
```

### Required Functions

Each country implementation should provide:

```r
# Download single series
download_[country]_series(series_id, start_date, end_date, save_csv)

# Download multiple series  
download_all_[country]_data(series_ids, start_date, end_date, save_csv)

# Update GPM Now data files
update_gpm_now_data(output_folder)

# Configuration helpers
get_series_config(series_id)
get_series_by_source(source)
```

## Data Standards

All country implementations must follow these standards:

### CSV Format
```csv
date,value,series_id
2024-01-01,123.45,gdp_q_qoq_sa
2024-02-01,124.12,gdp_q_qoq_sa
```

### Metadata Format
```json
{
  "series_id": "gdp_q_qoq_sa",
  "description": "GDP Quarterly Growth",
  "source": "National Statistics Office",
  "frequency": "quarterly",
  "transform": "pct_qoq", 
  "units": "Percent change",
  "download_date": "2024-11-03T10:30:00Z",
  "n_observations": 100,
  "date_range": ["2000-01-01", "2024-09-01"]
}
```

### Series Configuration
```r
series_config <- list(
  series_id = "unique_identifier",      # For internal use
  description = "Human readable name",  # For documentation
  source = "API_NAME",                 # Data source
  api_id = "source_specific_id",       # Source API identifier  
  frequency = "monthly|quarterly",     # Data frequency
  transform = "level|pct_mom|pct_yoy", # Suggested transformation
  seasonal_adj = TRUE|FALSE,           # Seasonal adjustment status
  release_lag_days = 30,              # Typical release lag
  units = "Index|Percent|Million USD", # Units of measurement
  start_date = "YYYY-MM-DD"           # Data availability start
)
```

## Integration with GPM Now

### Series ID Mapping
Retriever series IDs should match GPM Now `variables.yaml`:

```yaml
# In variables.yaml
target:
  id_q: "gdp_q_qoq_sa"      # Matches retriever series_id
  id_m_proxy: "ibc_br_m"    # Matches retriever series_id

indicators:
  - id: "ipi_mfg"            # Matches retriever series_id
    freq: "monthly"
    transform: "pct_mom_sa"
```

### Calendar Integration  
Release lag information feeds into GPM Now calendar:

```csv
# In calendar.csv  
release_date,series_id,ref_period,source_url,note
2024-01-15,ipi_mfg,2023-12,https://example.com,45-day lag from config
```

### Data Directory Structure
```
gpm_now/
├── data/
│   ├── monthly/
│   │   ├── ibc_br_m.csv      # From retriever  
│   │   ├── ipi_mfg.csv       # From retriever
│   │   └── retail_real.csv   # From retriever
│   └── quarterly/
│       └── gdp_q_qoq_sa.csv  # From retriever
└── retriever/                # This system
    └── brazil/
        └── csv_folder/       # Raw downloads
```

## Future Enhancements

### Planned Country Additions
- **United States**: Fed APIs (FRED, BEA, BLS)
- **Eurozone**: ECB, Eurostat APIs
- **United Kingdom**: ONS, Bank of England
- **Japan**: Cabinet Office, Bank of Japan
- **Mexico**: INEGI, Banxico

### Enhanced Features
- **Real-time monitoring**: Automated daily/weekly updates
- **Data quality dashboards**: Visual monitoring of data issues
- **API rate limit management**: Intelligent request throttling
- **Data reconciliation**: Cross-source validation
- **Vintage management**: Historical data snapshot preservation

## Dependencies

### Core R Packages
```r
# Data manipulation
data.table, dplyr, tidyr, lubridate, zoo

# Configuration and I/O  
yaml, jsonlite

# Country-specific packages (Brazil example)
GetBCBData, ipeadatar, sidrar
```

### System Requirements
- R >= 4.0.0
- Internet connection for API access
- Sufficient disk space for data storage

## Contributing

1. **Add New Countries**: Follow the template structure
2. **Enhance Utilities**: Improve shared functions in `utils.R`  
3. **Add Data Sources**: Extend existing country implementations
4. **Improve Documentation**: Update README files and examples

## License

This retriever system is part of the GPM Now project. See the main project license for details.

---

**Getting Started**: Navigate to `brazil/` folder and run `source("setup.R")` to begin downloading Brazilian economic data for nowcasting.