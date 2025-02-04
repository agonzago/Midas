import pandas as pd
import numpy as np

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