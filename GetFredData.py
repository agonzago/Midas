#%%
# import pyfredapi as pf
# import pandas as pd
# import os

# You'll need to set your FRED API key
# Get it from: https://fred.stlouisfed.org/docs/api/api_key.html
my_api_key ='00dc79d2344f645c74582837843f51c5'
#%%
from fredapi import Fred
import pandas as pd

# Initialize FRED with your API key
fred = Fred(api_key=my_api_key)

  # Search for series with 'Mexico' or 'MEX' in their metadata
mexico_series = fred.search('Mexico', filter=('frequency', 'Monthly'))
mex_prefix_series = fred.search('MEX', filter=('frequency', 'Monthly'))
#%%
us_series = fred.search(filter=('frequency', 'Monthly'))

us
# %%

from datetime import datetime, timedelta
import matplotlib.pyplot as plt

def get_key_mexican_indicators(fred):
    """
    Retrieve key Mexican manufacturing, business, and trade indicators
    """
    indicators = {
        "Manufacturing": {
            "MEXPRMNTO01IXOBM": "Manufacturing Production",
            "MEXPMIM": "Manufacturing PMI",
            "MEXMFGEMPLISMEI": "Manufacturing Employment"
        },
        "Business": {
            "MEXBSCICP02STSAM": "Business Confidence",
            "MEXPROINDMISMEI": "Industrial Production",
            "MEXCURMISMEI": "Capacity Utilization"
        },
        "Trade": {
            "MEXEXPORTMISMEI": "Exports",
            "MEXIMPORTMISMEI": "Imports",
            "MEXTBALKN": "Trade Balance"
        }
    }
    
    # Get data for each indicator
    data = {}
    for category, series_dict in indicators.items():
        for series_id, name in series_dict.items():
            try:
                series = fred.get_series(series_id)
                data[name] = series
                print(f"Retrieved {name} ({series_id})")
            except Exception as e:
                print(f"Error retrieving {name} ({series_id}): {str(e)}")
    
    return pd.DataFrame(data)

def analyze_indicators(data):
    """
    Analyze the indicators and return summary statistics
    """
    # Basic statistics
    summary = data.describe()
    
    # Year-over-year growth rates
    yoy_growth = data.pct_change(periods=12) * 100
    
    # Latest values
    latest = data.iloc[-1]
    
    # 3-month trend (positive/negative)
    trend = data.iloc[-1] - data.iloc[-4]
    
    return summary, yoy_growth, latest, trend

def save_to_excel(data, summary, yoy_growth, filename='mexican_indicators_analysis.xlsx'):
    """
    Save the data and analysis to Excel
    """
    with pd.ExcelWriter(filename) as writer:
        # Raw data
        data.to_excel(writer, sheet_name='Raw Data')
        
        # Summary statistics
        summary.to_excel(writer, sheet_name='Summary Statistics')
        
        # Latest YoY growth rates
        yoy_growth.iloc[-12:].to_excel(writer, sheet_name='YoY Growth')
        
        # Latest values
        pd.DataFrame({
            'Latest Value': data.iloc[-1],
            'Latest YoY Growth': yoy_growth.iloc[-1],
            '3M Change': data.iloc[-1] - data.iloc[-4]
        }).to_excel(writer, sheet_name='Latest Values')

if __name__ == "__main__":
    # Initialize FRED with your API key
    fred = Fred(api_key=my_api_key)
    
    # Get the data
    data = get_key_mexican_indicators(fred)
    
    # Analyze the data
    summary, yoy_growth, latest, trend = analyze_indicators(data)
    
    # Save to Excel
    save_to_excel(data, summary, yoy_growth)
    
    # Print latest values
    print("\nLatest Values:")
    for column in data.columns:
        print(f"{column}: {latest[column]:.2f}")
        
    print("\nLatest YoY Growth Rates:")
    for column in yoy_growth.columns:
        print(f"{column}: {yoy_growth[column].iloc[-1]:.2f}%")



# %%
