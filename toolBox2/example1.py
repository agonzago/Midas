# 1. Initialize
config = NowcastConfig.from_json("nowcast_config.json")
data_handler = NowcastData(config)

# 2. Prepare training data
X_train, y_train = data_handler.prepare_training_data()

# 3. Train models
models = {
    "U-MIDAS (Linear)": LinearRegression(),
    "U-MIDAS (Ridge)": Ridge(alpha=0.5),
    "Random Forest": RandomForestRegressor(n_estimators=100)
}
nowcaster = NowcastModel(models)
nowcaster.train(X_train, y_train)

# 4. Generate summary table
print(nowcaster.summary_table())

# 5. Plot variables vs GDP
data_handler.plot_variable_vs_gdp("industrial_production", start_date="2020-01-01")