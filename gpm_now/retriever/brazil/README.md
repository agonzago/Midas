# GPM Now - Brazilian Data Retriever

This module provides automated data retrieval for Brazilian economic indicators used in the GPM Now nowcasting system. It interfaces with the APIs of major Brazilian statistical agencies to download real-time economic data.

## Directory Structure

```
retriever/
├── utils.R              # General utility functions
├── brazil/              # Brazil-specific retriever
│   ├── config.R         # Series definitions and metadata
│   ├── retriever.R      # Main retrieval functions
│   ├── setup.R          # Installation and setup
│   ├── example_usage.R  # Usage examples
│   ├── csv_folder/      # Downloaded data storage
│   └── README.md        # This file
```

## Quick Start

### 1. Setup and Installation

Run the setup script to install required packages and test connections:

```r
# Navigate to the brazil folder
setwd("retriever/brazil")

# Run setup
source("setup.R")
```

This will:
- Install required R packages (`GetBCBData`, `ipeadatar`, `sidrar`, etc.)
- Test API connections to BCB, Ipeadata, and IBGE
- Create the `csv_folder` directory for data storage

### 2. Download Individual Series

```r
# Source the retrieval functions
source("retriever.R")

# Download IBC-Br (monthly GDP proxy)
result <- download_brazilian_series(
  series_id = "ibc_br_m",
  start_date = "2020-01-01",
  save_csv = TRUE
)

# Check the result
print(head(result$data))
```

### 3. Download Multiple Series

```r
# Download core nowcasting indicators
core_series <- c("ibc_br_m", "ipi_mfg", "retail_real", "credit_total")

results <- download_all_brazilian_data(
  series_ids = core_series,
  start_date = "2020-01-01",
  save_csv = TRUE
)
```

### 4. Update GPM Now Data Files

```r
# Update the main GPM Now data directory
update_gpm_now_data(output_folder = "../../data")
```

## Available Data Series

### Target Variables
- `ibc_br_m`: IBC-Br Economic Activity Index (monthly GDP proxy)
- `gdp_q_qoq_sa`: Quarterly GDP growth (seasonally adjusted)

### Monthly Indicators

#### Production & Activity
- `ipi_mfg`: Industrial Production - Manufacturing
- `retail_real`: Retail Sales Volume
- `electricity`: Electricity Consumption  
- `cement`: Cement Sales
- `auto_prod`: Automobile Production

#### Labor Market
- `unemployment`: Unemployment Rate (PNAD Continua)

#### Financial & Monetary
- `credit_total`: Total Outstanding Credit
- `exchange_rate`: USD/BRL Exchange Rate
- `selic`: Selic Interest Rate
- `m1`: Monetary Aggregate M1

#### Prices & Inflation  
- `ipca`: IPCA Headline Inflation
- `ipca_core`: IPCA Core Inflation (Trimmed Mean)

#### External Sector
- `exports`: Exports (FOB)
- `imports`: Imports (FOB)
- `commodity_idx`: BCB Commodity Price Index

#### Confidence & Surveys
- `consumer_conf`: Consumer Confidence Index (FGV)
- `capacity_util`: Manufacturing Capacity Utilization

#### Financial Markets
- `ibovespa`: Ibovespa Stock Index

## Data Sources

### Central Bank of Brazil (BCB)
- **Package**: `GetBCBData`
- **API**: SGS (Sistema Gerenciador de Séries Temporais)
- **Series**: IBC-Br, industrial production, credit, monetary aggregates, exchange rates, interest rates, trade data

### Ipeadata (Ipea)
- **Package**: `ipeadatar`  
- **API**: Ipeadata API
- **Series**: Electricity, cement, unemployment, consumer confidence, capacity utilization, automobile production, stock market

### IBGE
- **Package**: `sidrar`
- **API**: SIDRA API
- **Series**: Detailed industrial production, employment data (future enhancement)

## Configuration System

All series are defined in `config.R` with metadata including:

```r
series_config <- list(
  series_id = "ibc_br_m",           # Internal identifier
  description = "IBC-Br Index",    # Human-readable name
  source = "BCB",                  # Data source
  api_id = 24369,                  # Source-specific ID
  frequency = "monthly",           # Data frequency
  transform = "pct_mom_sa",        # Default transformation
  seasonal_adj = TRUE,             # Whether seasonally adjusted
  release_lag_days = 45,           # Typical release lag
  units = "Index (2002=100)",      # Units of measurement
  start_date = "2003-01-01"        # Available from date
)
```

## Output Format

### CSV Files
Each series is saved as a standardized CSV with columns:
- `date`: Date in YYYY-MM-DD format
- `value`: Numeric value
- `series_id`: Series identifier

### Metadata Files
JSON metadata files provide additional information:
```json
{
  "series_id": "ibc_br_m",
  "description": "IBC-Br Economic Activity Index",
  "source": "BCB",
  "frequency": "monthly", 
  "transform": "pct_mom_sa",
  "units": "Index (2002=100)",
  "download_date": "2025-11-03T10:30:00Z",
  "n_observations": 156,
  "date_range": ["2003-01-01", "2024-10-01"]
}
```

## Error Handling

The system includes comprehensive error handling:

- **API Connection Failures**: Graceful handling of network issues
- **Data Validation**: Checks for missing values, date consistency, duplicates
- **Logging**: Detailed logs of all download attempts
- **Retry Logic**: Built-in delays to respect API rate limits

## Integration with GPM Now

The retriever is designed to integrate seamlessly with the GPM Now nowcasting system:

1. **Series Mapping**: Series IDs match those in `gpm_now/config/variables.yaml`
2. **Data Format**: CSV outputs are compatible with GPM Now data loading
3. **Calendar Integration**: Release lag information matches `gpm_now/config/calendar.csv`
4. **Transformations**: Raw data is retrieved; transformations applied by GPM Now

## Usage Examples

### Example 1: Basic Download
```r
source("retriever.R")

# Download single series
result <- download_brazilian_series("ibc_br_m")
```

### Example 2: Custom Date Range
```r  
# Download last 2 years only
result <- download_brazilian_series(
  series_id = "ipi_mfg",
  start_date = "2022-01-01", 
  end_date = "2024-01-01"
)
```

### Example 3: Batch Download
```r
# Download all financial indicators
financial_series <- c("selic", "exchange_rate", "m1", "credit_total")

results <- download_all_brazilian_data(
  series_ids = financial_series,
  start_date = "2020-01-01"
)

# Print summary
print(results$summary)
```

### Example 4: Health Check
```r
source("setup.R")
health_check()  # Verify system is working
```

## Troubleshooting

### Common Issues

1. **Package Installation Failures**
   ```r
   # Try installing from different repos
   install.packages("GetBCBData", repos = "https://cloud.r-project.org/")
   ```

2. **API Connection Issues**
   ```r
   # Check internet connection and try again
   # Some APIs may have temporary outages
   ```

3. **Missing Data**
   ```r
   # Check series configuration for correct date ranges
   # Some series have limited historical data
   ```

4. **Path Issues**
   ```r
   # Ensure you're in the correct directory
   getwd()  # Should end with "/retriever/brazil"
   ```

### Getting Help

- Run `show_available_series()` to see all available data
- Run `health_check()` to diagnose issues  
- Check the download logs in `csv_folder/download_log_YYYYMMDD.csv`
- Review metadata JSON files for series-specific information

## Contributing

To add new Brazilian data series:

1. Add series configuration to `config.R`
2. Ensure the source API is supported (`GetBCBData`, `ipeadatar`, or `sidrar`)
3. Test the new series with the download functions
4. Update this README with the new series information

## License

This module is part of the GPM Now nowcasting system. See the main project license for details.