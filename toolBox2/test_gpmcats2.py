#%%
# --- Start of test_gpmcast.py ---

import pandas as pd
import numpy as np
import pandas as pd
from datetime import datetime, timedelta

from sklearn.linear_model import LinearRegression
from gpmcast_config import NowcastConfig  # Import NowcastConfig
from gpmcast_data_handling import NowcastData  # Import NowcastData
#from gopmcast_models import NowcastModel  # Import NowcastModel

# --- Synthetic Data Generation ---
def generate_synthetic_data():
    """
    Generate synthetic monthly and quarterly data for testing.
    Saves the data to 'synthetic_monthly.csv' and 'synthetic_gdp.csv'.
    """
    # Generate monthly data (2010-01 to 2013-12)
    dates = pd.date_range("2010-01-01", "2013-12-31", freq="MS")
    variables = ["industrial_production", "retail_sales_nominal", "ipc"]
    monthly_data = []
    for date in dates:
        for var in variables:
            value = np.random.normal(loc=100, scale=5)  # Synthetic data
            monthly_data.append({"date": date, "variable": var, "value": value})
    monthly_df = pd.DataFrame(monthly_data)

    # Generate quarterly GDP growth (mocked relationship)
    quarters = monthly_df["date"].dt.to_period("Q").unique()
    gdp = []
    for q in quarters:
        # GDP depends on industrial_production + retail_sales (mock relationship)
        ip = monthly_df[
            (monthly_df["variable"] == "industrial_production") & 
            (monthly_df["date"].dt.to_period("Q") == q)
        ]["value"].mean()
        rs = monthly_df[
            (monthly_df["variable"] == "retail_sales_nominal") & 
            (monthly_df["date"].dt.to_period("Q") == q)
        ]["value"].mean()
        gdp_growth = 0.5 * (ip - 100) + 0.3 * (rs - 100) + np.random.normal(0, 0.5)
        gdp.append({"date": q.end_time, "gdp_growth": gdp_growth})
    gdp_df = pd.DataFrame(gdp)

    # Save to CSV
    monthly_df.to_csv("synthetic_monthly.csv", index=False)
    gdp_df.to_csv("synthetic_gdp.csv", index=False)

# # Step 2: Define configuration using explicit file paths
# raw_monthly_path = "synthetic_monthly.csv"
# raw_gdp_path = "synthetic_gdp.csv"

# Initialize configuration with file paths
# config = NowcastConfig.from_paths(
#     raw_monthly_path=raw_monthly_path,
#     raw_gdp_path=raw_gdp_path,
#     variable_info={
#         "industrial_production": {"seasonal_adjust": True, "growth_rate": True},
#         "retail_sales_nominal": {"standardize": True},
#         "ipc": {"seasonal_adjust": False, "growth_rate": True}
#     },
#     release_calendar=pd.DataFrame()  # Placeholder for release calendar
# )


def generate_release_calendar(config):
    # Extract quarter start dates
    quarter_start_dates = {
        'Q1': datetime(2013, 1, 1),
        'Q2': datetime(2013, 4, 1),
        'Q3': datetime(2013, 7, 1),
        'Q4': datetime(2013, 10, 1)
    }

    # Initialize an empty list to store release calendar entries
    release_calendar = []

    # Loop through each variable in the configuration
    for variable, info in config['variable_info'].items():
        if 'release_schedule' in info:
            week_of_quarter = info['release_schedule']['week_of_quarter']
            day_of_month = info['release_schedule']['day_of_month']

            # Calculate release dates for each quarter
            for quarter, start_date in quarter_start_dates.items():
                # Calculate the release date
                week_offset = (week_of_quarter - 1) * 7
                release_date = start_date + timedelta(days=week_offset + day_of_month - 1)

                # Append to the release calendar
                release_calendar.append({
                    'variable': variable,
                    'quarter': quarter,
                    'release_date': release_date
                })

    # Convert to DataFrame
    return pd.DataFrame(release_calendar)

# # Example usage
# config = {
#     "variable_info": {
#         "industrial_production": {
#             "seasonal_adjust": True,
#             "growth_rate": True,
#             "release_schedule": {"week_of_quarter": 2, "day_of_month": 11}
#         },
#         "retail_sales_nominal": {
#             "standardize": True,
#             "release_schedule": {"week_of_quarter": 2, "day_of_month": 14}
#         },
#         "ipc": {
#             "seasonal_adjust": False,
#             "growth_rate": True,
#             "release_schedule": {"week_of_quarter": 4, "day_of_month": 24}
#         }
#     }
#}

import os 
current_directory = "/Volumes/TOSHIBA EXT/main_work/Work/Projects/Midas_rep/toolBox2/"
os.chdir(current_directory)
print(os.getcwd())
config =  NowcastConfig.from_json(".gpmcast_config.jason")
release_calendar = generate_release_calendar(config)
print(release_calendar)

# # Step 3: Initialize data handler
# print("\nInitializing data handler...")
# data_handler = NowcastData(config)

# # Step 4: Check processed data
# print("\nProcessed monthly data sample:")
# print(data_handler.monthly_data.head())

# print("\nGDP data sample:")
# print(data_handler.gdp_data.head())

# # Step 5: Prepare training data
# nowcast_date = datetime(2013, 6, 1)  # Example nowcast date
# print(f"\nPreparing training data as of {nowcast_date}...")
# X_train, y_train = data_handler.prepare_training_data(nowcast_date)
# print(f"Training data shape: {X_train.shape}")

    # # Step 6: Train a simple UMIDAS model
    # print("\nTraining UMIDAS model...")
    # model = NowcastModel({"UMIDAS": LinearRegression()})
    # model.train(X_train, y_train)

    # # Step 7: Generate summary table
    # print("\nModel Performance Summary:")
    # print(model.summary_table())

    # # Step 8: Plot variables vs GDP
    # print("\nPlotting industrial_production vs GDP growth...")
    # data_handler.plot_variable_vs_gdp("industrial_production", start_date="2010-01-01")