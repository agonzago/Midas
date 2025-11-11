# Project Structure Overview

## 📂 Complete Directory Tree

```
Midas/
├── Data/                            # Shared data folder (legacy)
│   ├── mex_Q.csv                   # Mexico quarterly GDP
│   ├── mex_M.csv                   # Mexico monthly indicators
│   └── ...
│
├── gpm_now/                         # Main nowcasting framework
│   │
│   ├── common/                      # ⭐ Core functions (country-agnostic)
│   │   ├── README.md               # Common functions documentation
│   │   ├── midas_models.R          # MIDAS estimation & forecasting
│   │   ├── tprf_models.R           # Three-Pass Regression Filter
│   │   ├── dfm_models.R            # Dynamic Factor Models
│   │   ├── combine.R               # Model combination logic
│   │   ├── structural_breaks.R     # Structural break handling
│   │   ├── transforms.R            # Data transformations
│   │   ├── utils.R                 # General utilities
│   │   ├── lagmap.R                # MIDAS lag structures
│   │   ├── selection.R             # Model selection
│   │   └── news.R                  # News decomposition
│   │
│   ├── countries/                   # ⭐ Country implementations
│   │   │
│   │   ├── mexico/                 # 🇲🇽 Mexico nowcasting
│   │   │   ├── README.md           # Mexico-specific docs
│   │   │   ├── config/             # Mexico configs
│   │   │   │   ├── variables.yaml  # Variable definitions
│   │   │   │   ├── options.yaml    # Model options
│   │   │   │   └── calendar.csv    # Release calendar
│   │   │   ├── data/               # Mexico data
│   │   │   │   ├── monthly/        # Monthly indicators
│   │   │   │   └── quarterly/      # Quarterly GDP
│   │   │   ├── R/                  # Mexico-specific functions
│   │   │   │   ├── runner.R        # Nowcast runner
│   │   │   │   └── io.R            # I/O functions
│   │   │   ├── output/             # Nowcast results
│   │   │   ├── plots/              # Visualizations
│   │   │   ├── run_mexico_nowcast.R              # Main script
│   │   │   └── run_mexico_rolling_evaluation.R   # Evaluation
│   │   │
│   │   └── brazil/                 # 🇧🇷 Brazil nowcasting
│   │       ├── README.md           # Brazil-specific docs
│   │       ├── config/             # Brazil configs
│   │       ├── data/               # Brazil data (auto-updated)
│   │       ├── R/                  # Brazil-specific functions
│   │       ├── output/             # Nowcast results
│   │       ├── plots/              # Visualizations
│   │       ├── run_brazil_nowcast.R              # Main script
│   │       └── run_brazil_rolling_evaluation.R   # Evaluation
│   │
│   ├── retriever/                   # ⭐ Data retrieval system
│   │   ├── README.md               # Retriever documentation
│   │   ├── utils.R                 # Common retrieval utilities
│   │   └── brazil/                 # Brazil data retrieval
│   │       ├── README.md           # Brazil retriever docs
│   │       ├── config_reader.R     # Configuration reader
│   │       ├── data_transformations.R  # Transformations
│   │       ├── clean_data_retrieval.R  # Clean API wrapper
│   │       ├── main_data_retrieval.R   # Main retrieval script
│   │       ├── variable_codes.csv      # Series definitions
│   │       └── static_csv/         # Downloaded data
│   │
│   ├── R/                           # Legacy R files (kept for reference)
│   │   └── ...
│   │
│   ├── config/                      # Legacy config (kept for reference)
│   │   └── ...
│   │
│   ├── Old_files/                   # Archived implementations
│   │   └── ...
│   │
│   ├── README.md                    # Main documentation (NEW)
│   └── README_old.md                # Original README (backup)
│
├── examples/                        # Usage examples
│   ├── mexico_umidas_example.py
│   └── ...
│
├── tests/                           # Python tests
│   └── ...
│
└── midas_nowcasting/                # Python implementation (separate)
    └── ...
```

## 🎯 Quick Navigation

### For Users

**Run Mexico Nowcast:**
```bash
cd gpm_now/countries/mexico
# Open R and run:
source("run_mexico_nowcast.R")
```

**Run Brazil Nowcast:**
```bash
cd gpm_now/countries/brazil
# Open R and run:
source("run_brazil_nowcast.R")
```

**Evaluate Models:**
```bash
# Mexico
cd gpm_now/countries/mexico
source("run_mexico_rolling_evaluation.R")

# Brazil
cd gpm_now/countries/brazil
source("run_brazil_rolling_evaluation.R")
```

### For Developers

**Add New Country:**
1. Read: `gpm_now/README.md` - "Adding a New Country" section
2. Copy: `gpm_now/countries/mexico/` as template
3. Customize: configs, data paths, specific features

**Modify Core Functions:**
1. Read: `gpm_now/common/README.md`
2. Edit: Functions in `gpm_now/common/`
3. Test: With both Mexico and Brazil implementations

**Add Data Retrieval (New Country):**
1. Read: `gpm_now/retriever/README.md`
2. Create: `gpm_now/retriever/new_country/`
3. Implement: Similar to `retriever/brazil/`

## 📚 Documentation Hierarchy

```
gpm_now/README.md                    # Start here - Main framework docs
├── common/README.md                 # Core functions reference
├── countries/mexico/README.md       # Mexico implementation guide
├── countries/brazil/README.md       # Brazil implementation guide
└── retriever/README.md              # Data retrieval system docs
    └── retriever/brazil/README.md   # Brazil data sources
```

## 🔄 Data Flow

```
┌─────────────────────────────────────────────────────────────────┐
│                     DATA SOURCES                                 │
├─────────────────────────────────────────────────────────────────┤
│  Mexico: ../Data/mex_Q.csv, ../Data/mex_M.csv (manual)         │
│  Brazil: retriever/brazil/ → API downloads (automated)          │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                  COUNTRY DATA FOLDERS                            │
├─────────────────────────────────────────────────────────────────┤
│  countries/mexico/data/monthly/    ← Symlink or copy            │
│  countries/mexico/data/quarterly/  ← Symlink or copy            │
│  countries/brazil/data/monthly/    ← Auto-updated by retriever  │
│  countries/brazil/data/quarterly/  ← Auto-updated by retriever  │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                  COUNTRY CONFIGURATIONS                          │
├─────────────────────────────────────────────────────────────────┤
│  countries/{country}/config/variables.yaml                      │
│  countries/{country}/config/options.yaml                        │
│  countries/{country}/config/calendar.csv                        │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                     COMMON FUNCTIONS                             │
├─────────────────────────────────────────────────────────────────┤
│  common/midas_models.R     → MIDAS fitting & forecasting        │
│  common/tprf_models.R      → Factor-based models                │
│  common/combine.R          → Model combination                  │
│  common/structural_breaks.R → Break adjustment                  │
│  common/transforms.R       → Data transformations               │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                  COUNTRY RUNNER SCRIPTS                          │
├─────────────────────────────────────────────────────────────────┤
│  countries/mexico/run_mexico_nowcast.R                          │
│  countries/mexico/run_mexico_rolling_evaluation.R               │
│  countries/brazil/run_brazil_nowcast.R                          │
│  countries/brazil/run_brazil_rolling_evaluation.R               │
└─────────────────────────────────────────────────────────────────┘
                              ↓
┌─────────────────────────────────────────────────────────────────┐
│                      OUTPUTS                                     │
├─────────────────────────────────────────────────────────────────┤
│  countries/{country}/output/nowcast_YYYY-MM-DD.json            │
│  countries/{country}/output/nowcast_YYYY-MM-DD.csv             │
│  countries/{country}/output/rolling_evaluation_results.csv     │
│  countries/{country}/plots/midas_comparison.png                │
└─────────────────────────────────────────────────────────────────┘
```

## ⚙️ Key Design Principles

### 1. Separation of Concerns
- **Common**: Country-agnostic core functions
- **Countries**: Country-specific implementations
- **Retriever**: Data acquisition (separate from modeling)

### 2. Modularity
- Each country is self-contained
- Adding new country doesn't affect existing ones
- Common functions can be enhanced without breaking countries

### 3. Consistency
- All countries follow same folder structure
- Same configuration file format (YAML, CSV)
- Same output format (JSON, CSV)

### 4. Flexibility
- Each country can customize runner logic
- Each country can have specific indicators
- Each country can adjust model specifications

## 🚀 Migration from Legacy

The old structure (`gpm_now/R/`, `gpm_now/config/`) is preserved but new work should use:

**Old (Legacy):**
```r
setwd("gpm_now")
source("R/runner.R")
```

**New (Modular):**
```r
setwd("gpm_now/countries/mexico")
source("run_mexico_nowcast.R")
```

## 🔧 Maintenance Tasks

### Regular Tasks
1. **Update data**: Brazil auto-updates; Mexico needs manual refresh
2. **Run evaluations**: Monthly rolling evaluations to check performance
3. **Review logs**: Check `output/logs/` for warnings/errors

### Development Tasks
1. **Add features**: Enhance common functions
2. **Fix bugs**: Test with both countries
3. **Update docs**: Keep READMEs in sync with code

### Quality Assurance
1. **Test common functions**: Use synthetic data
2. **Validate outputs**: Compare against previous versions
3. **Check consistency**: Mexico and Brazil should produce similar output structure

---

**Last Updated**: November 2025  
**Framework Version**: 2.0 (Multi-Country)  
**Countries Supported**: Mexico 🇲🇽, Brazil 🇧🇷
