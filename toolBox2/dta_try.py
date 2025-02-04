import pandas as pd
import numpy as np
from statsmodels.tsa.seasonal import STL
from sklearn.linear_model import LinearRegression
from sklearn.model_selection import train_test_split
from sklearn.metrics import mean_squared_error
from sklearn.preprocessing import StandardScaler

# Load data (example structure)
# monthly_data.csv columns: date, variable, value
# quarterly_gdp.csv columns: date, gdp_growth
monthly_data = pd.read_csv('monthly_data.csv', parse_dates=['date'])
quarterly_gdp = pd.read_csv('quarterly_gdp.csv', parse_dates=['date'])

# Variable metadata dictionary
variable_info = {
    'industrial_production': {
        'unit': 'index',
        'sa': True,
        'transformation': ['growth_rate', 'demean']
    },
    'retail_sales_nominal': {
        'unit': 'nominal',
        'sa': False,
        'transformation': ['convert_to_real', 'growth_rate', 'standardize']
    },
    'ipc': {
        'unit': 'index',
        'sa': True,
        'transformation': []
    },
}

def seasonal_adjust(series):
    """Apply STL seasonal adjustment."""
    stl = STL(series, period=12)
    res = stl.fit()
    return res.trend + res.resid

def convert_to_real(nominal, ipc):
    """Convert nominal to real values using IPC."""
    return nominal / ipc

def compute_growth_rate(series, periods=1):
    """Compute percentage growth rate."""
    return series.pct_change(periods=periods) * 100

# Process each variable
processed = {}
for var in variable_info:
    df = monthly_data[monthly_data['variable'] == var].set_index('date')['value']
    info = variable_info[var]
    
    # Seasonal adjustment
    if info['sa']:
        df = seasonal_adjust(df)
    
    # Convert nominal to real
    if 'convert_to_real' in info['transformation']:
        ipc_series = monthly_data[monthly_data['variable'] == 'ipc'].set_index('date')['value']
        df = convert_to_real(df, ipc_series)
    
    # Apply transformations
    for trans in info['transformation']:
        if trans == 'growth_rate':
            df = compute_growth_rate(df)
        elif trans == 'demean':
            df -= df.mean()
        elif trans == 'standardize':
            df = (df - df.mean()) / df.std()
    
    processed[var] = df.reset_index()

# Combine processed data
processed_df = pd.concat(processed.values()).pivot(index='date', columns='variable', values='value')

# Reshape to quarterly with monthly features
processed_df['quarter'] = processed_df.index.to_period('Q')
quarterly_features = processed_df.groupby('quarter').agg(lambda x: x.tolist()[-3:])  # Last 3 months

# Create feature columns (month1, month2, month3)
features = {}
for var in variable_info:
    features.update({
        f"{var}_m{i+1}": quarterly_features[var].str[i]
        for i in range(3)
    })
features_df = pd.DataFrame(features)

# Merge with GDP data
quarterly_gdp['quarter'] = quarterly_gdp['date'].dt.to_period('Q')
full_data = pd.merge(features_df, quarterly_gdp, on='quarter').dropna()

# Prepare data for modeling
X = full_data.drop(['gdp_growth', 'date', 'quarter'], axis=1)
y = full_data['gdp_growth']

# Train-test split
X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, shuffle=False)

# Standardize features
scaler = StandardScaler()
X_train_scaled = scaler.fit_transform(X_train)
X_test_scaled = scaler.transform(X_test)

# Train U-MIDAS model (linear regression)
model = LinearRegression()
model.fit(X_train_scaled, y_train)

# Evaluate
predictions = model.predict(X_test_scaled)
rmse = np.sqrt(mean_squared_error(y_test, predictions))
print(f"RMSE: {rmse:.2f}")

# Nowcast latest GDP
latest_data = features_df.iloc[-1].values.reshape(1, -1)
latest_scaled = scaler.transform(latest_data)
nowcast = model.predict(latest_scaled)
print(f"Nowcasted GDP Growth: {nowcast[0]:.2f}%")