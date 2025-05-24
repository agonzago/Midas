import pandas as pd
import numpy as np
# datetime might not be directly used by generate_synthetic_data, but pd.date_range uses it.
# from datetime import datetime 

def generate_synthetic_data(monthly_csv_path="synthetic_monthly.csv", gdp_csv_path="synthetic_gdp.csv"):
    """
    Generate synthetic monthly and quarterly data for testing.
    Saves the data to the specified CSV paths.

    Args:
        monthly_csv_path (str): Path to save the synthetic monthly data.
        gdp_csv_path (str): Path to save the synthetic GDP data.
    """
    # Generate monthly data (2010-01 to 2013-12)
    dates = pd.date_range("2010-01-01", "2013-12-31", freq="MS")
    variables = ["industrial_production", "retail_sales_nominal", "ipc"]
    monthly_data = []
    for date in dates:
        for var in variables:
            value = np.random.normal(loc=100, scale=5)  # Synthetic data
            # Adding a release_date column, as it's used in other parts of the system
            # For simplicity, let's assume release is 15 days after the reference month start
            # In a real scenario, this would be more complex or defined externally.
            release_date = date + pd.Timedelta(days=14) # Example: released mid-month
            monthly_data.append({"date": date, "variable": var, "value": value, "release_date": release_date})
    monthly_df = pd.DataFrame(monthly_data)

    # Generate quarterly GDP growth (mocked relationship)
    quarters = monthly_df["date"].dt.to_period("Q").unique()
    gdp = []
    for q in quarters:
        # GDP depends on industrial_production + retail_sales (mock relationship)
        ip_mean = monthly_df[
            (monthly_df["variable"] == "industrial_production") & 
            (monthly_df["date"].dt.to_period("Q") == q)
        ]["value"].mean()
        rs_mean = monthly_df[
            (monthly_df["variable"] == "retail_sales_nominal") & 
            (monthly_df["date"].dt.to_period("Q") == q)
        ]["value"].mean()
        
        # Handle potential NaN if a variable is missing for a quarter (though unlikely with this generation)
        ip_mean = ip_mean if pd.notna(ip_mean) else 100 # fallback to avoid NaN in calculation
        rs_mean = rs_mean if pd.notna(rs_mean) else 100 # fallback

        gdp_growth = 0.5 * (ip_mean - 100) + 0.3 * (rs_mean - 100) + np.random.normal(0, 0.5)
        # Adding a gdp_value column as well, assuming gdp_growth is a percentage change
        # For simplicity, let's assume a base GDP and apply growth.
        # This part is illustrative as the original only had gdp_growth.
        base_gdp_value = 1000 # Arbitrary base
        gdp_value = base_gdp_value * (1 + gdp_growth / 100) if not gdp else gdp[-1]["gdp_value"] * (1 + gdp_growth / 100)

        gdp.append({"date": q.end_time.to_timestamp(), "gdp_value": gdp_value, "gdp_growth": gdp_growth})
    gdp_df = pd.DataFrame(gdp)

    # Save to CSV
    monthly_df.to_csv(monthly_csv_path, index=False)
    gdp_df.to_csv(gdp_csv_path, index=False)
    print(f"Synthetic monthly data saved to '{monthly_csv_path}'")
    print(f"Synthetic GDP data saved to '{gdp_csv_path}'")
