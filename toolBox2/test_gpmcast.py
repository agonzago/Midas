from datetime import datetime
import json
import pandas as pd
from sklearn.linear_model import LinearRegression
from config import NowcastConfig
from data_handler import NowcastData
from model import NowcastModel

# Load config
config = NowcastConfig.from_json("config.json")

# Initialize data handler
data = NowcastData(config)

# Check processed data
print("Processed monthly data sample:")
print(data.monthly_data.head())

# Check GDP data
print("\nGDP data sample:")
print(data.gdp_data.head())

# Prepare training data
X_train, y_train = data.prepare_training_data()
print(f"\nTraining data shape: {X_train.shape}")

# Train simple model
model = NowcastModel({"UMIDAS": LinearRegression()})
model.train(X_train, y_train)

# Generate summary
print("\nModel Performance Summary:")
print(model.summary_table())

# Plot variables vs GDP
data.plot_variable_vs_gdp("industrial_production", start_date="2010-01-01")