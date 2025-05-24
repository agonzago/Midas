# examples/example1_updated.py
import pandas as pd
from datetime import datetime

# Imports from the midas_nowcasting structure
from midas_nowcasting.config.gpmcast_config import NowcastConfig
from midas_nowcasting.data_handling.gpmcast_data_handling import NowcastData
from midas_nowcasting.models.core import NowcastModel as NowcastModelManager
from midas_nowcasting.models.umidas import UMIDASModel # Using our integrated UMIDAS model
from sklearn.linear_model import LinearRegression     # As a comparison simple model
from midas_nowcasting.reporting.tables import generate_model_summary_table
from midas_nowcasting.reporting.charts import plot_variable_vs_target

def main():
    print("--- Starting Midas Nowcasting Example 1 (Updated) ---")

    # --- 1. Load Configuration ---
    print("\n--- 1. Loading Configuration ---")
    # This example uses dummy_config.json and synthetic data files (synthetic_monthly.csv, synthetic_gdp.csv)
    # These files are expected to be in the root of the project.
    
    # Create a dummy release calendar DataFrame (as in run_nowcast.py)
    # NowcastConfig expects a DataFrame for release_calendar.
    release_calendar_df = pd.DataFrame([
        {'date': pd.to_datetime('2023-01-15'), 'variable': 'industrial_production', 'release_lag_days': 15},
        {'date': pd.to_datetime('2023-01-20'), 'variable': 'retail_sales', 'release_lag_days': 20}
    ])
    
    try:
        config = NowcastConfig(
            variable_info={ # From dummy_config.json
                "industrial_production": {"seasonal_adjust": False, "growth_rate": True, "transformations": ["level"]},
                "retail_sales": {"seasonal_adjust": False, "growth_rate": True, "transformations": ["level"]}
            },
            release_calendar=release_calendar_df,
            raw_monthly_path="synthetic_monthly.csv",
            raw_gdp_path="synthetic_gdp.csv"
        )
        print("Configuration loaded successfully.")
        print(f"Monthly data path: {config.raw_monthly_path}")
        print(f"GDP data path: {config.raw_gdp_path}")
    except Exception as e:
        print(f"Error loading configuration: {e}")
        return

    # --- 2. Initialize Data Handling ---
    print("\n--- 2. Initializing Data Handling ---")
    try:
        data_handler = NowcastData(config)
        # Ensure release_date in monthly_data is datetime for get_real_time_features
        data_handler.monthly_data['release_date'] = pd.to_datetime(data_handler.monthly_data['release_date'])
        print("Data handler initialized successfully.")
    except FileNotFoundError as e:
        print(f"Error initializing data handler: {e}")
        print("Please ensure 'synthetic_monthly.csv' and 'synthetic_gdp.csv' exist in the project root.")
        return
    except Exception as e:
        print(f"An unexpected error occurred during data handling initialization: {e}")
        return
        
    # --- 3. Prepare Training Data ---
    print("\n--- 3. Preparing Training Data ---")
    nowcast_date = datetime(2023, 1, 1) # Example nowcast date from synthetic data
    print(f"Preparing data for nowcast date: {nowcast_date.strftime('%Y-%m-%d')}")
    
    try:
        # Get real-time features.
        # Note: _apply_transformations in NowcastData is complex and might need specific variable setup
        # in variable_info beyond what dummy_config provides for full functionality.
        # get_real_time_features pivots data, creating many columns.
        features_df = data_handler.get_real_time_features(nowcast_date)
        
        if features_df.empty or 'gdp_growth' not in features_df.columns:
             print("Could not generate features or 'gdp_growth' (target) is missing. Exiting.")
             return
        
        y_train = features_df['gdp_growth']
        # Select feature columns: Exclude target, date, and quarter identifiers
        # The specific feature columns depend on how get_real_time_features structures the pivot table.
        # Example: 'industrial_production_10', 'industrial_production_11', etc.
        feature_cols = [col for col in features_df.columns if col not in ['gdp_growth', 'date', 'quarter']]
        X_train = features_df[feature_cols].fillna(0) # Simple imputation for example

        print(f"X_train shape: {X_train.shape}, y_train shape: {y_train.shape}")
        if X_train.empty:
            print("X_train is empty after feature selection. Cannot proceed.")
            return
        # print("\nX_train head:\n", X_train.head())
        # print("\ny_train head:\n", y_train.head())

    except Exception as e:
        print(f"Error preparing training data: {e}")
        import traceback
        traceback.print_exc()
        return

    # --- 4. Specify and Train Models ---
    print("\n--- 4. Specifying and Training Models ---")
    
    # Define models to run
    # Note: UMIDASModel expects specific data shapes and `month_in_quarter` for its fit method.
    # The X_train from get_real_time_features is wide. UMIDAS typically takes one high-freq series.
    # For this example, LinearRegression is more straightforward with the wide X_train.
    # We'll demonstrate UMIDASModel conceptually, but it might error with this X_train.
    
    # Determine month_in_quarter for UMIDASModel (0, 1, or 2)
    # This is a simplified way; a proper date utility function might be better.
    current_month_in_quarter_for_umidas = (nowcast_date.month - 1) % 3

    models_to_run = {
        "LinearRegression": LinearRegression()
        # "UMIDAS_IP": UMIDASModel(max_y_lags=1, max_x_lags=3), # Needs careful X selection
    }
    # print(f"Models to train: {list(models_to_run.keys())}")
    
    # To use UMIDASModel, you'd typically select a single high-frequency indicator series from your data
    # *before* it's pivoted into the wide `features_df`.
    # For example:
    # ip_series = data_handler.monthly_data[data_handler.monthly_data['variable'] == 'industrial_production']['value']
    # Then call umidas_model.fit(ip_series, y_train_quarterly, month_in_quarter=...)
    # This example focuses on models that work with the wide `X_train` from `get_real_time_features`.

    nowcaster_manager = NowcastModelManager(models=models_to_run)
    
    try:
        # NowcastModelManager's train method expects X_train to be NumPy array
        nowcaster_manager.train(X_train.to_numpy(), y_train.to_numpy())
        print("Models training completed by NowcastModelManager.")
    except Exception as e:
        print(f"Error training models with NowcastModelManager: {e}")
        import traceback
        traceback.print_exc()
        return

    # --- 5. Generate Summary Table ---
    print("\n--- 5. Generating Summary Table ---")
    if hasattr(nowcaster_manager, 'metrics') and nowcaster_manager.metrics:
        # For latest_nowcasts, we'd typically predict on the most recent data point (X_test)
        # Here, using a subset of X_train for demonstration if X_test isn't prepared.
        X_pred_sample = X_train.head(1).to_numpy() if not X_train.empty else pd.DataFrame().to_numpy()
        
        latest_nowcasts_report = {}
        if X_pred_sample.shape[0] > 0:
             predictions_dict = nowcaster_manager.predict(X_pred_sample)
             for name, pred_array in predictions_dict.items():
                latest_nowcasts_report[name] = pred_array[0] if len(pred_array) > 0 else float('nan')
        
        summary_df = generate_model_summary_table(nowcaster_manager.metrics, latest_nowcasts_report)
        print("\nModel Summary Table:")
        print(summary_df)
    else:
        print("Skipping summary table: Metrics not available from model manager.")

    # --- 6. Plot Variables vs Target (Example) ---
    print("\n--- 6. Plotting Variables vs Target (Example) ---")
    # This demonstrates plotting one of the original monthly variables against the target (GDP growth)
    # Requires 'gdp_data' to have a 'value' column for the target.
    try:
        gdp_plot_data = data_handler.gdp_data.copy()
        if 'value' not in gdp_plot_data.columns and 'gdp_growth' in gdp_plot_data.columns:
            gdp_plot_data['value'] = gdp_plot_data['gdp_growth'] # Use gdp_growth as the value to plot

        # Select one variable from the original monthly data for plotting
        # The 'transformed_monthly_data' for plotting should ideally be data after transformations.
        # Here, we use a subset of the raw monthly data for simplicity.
        monthly_plot_data = data_handler.monthly_data[
            data_handler.monthly_data['variable'] == 'industrial_production'
        ].copy()

        if not monthly_plot_data.empty and 'value' in gdp_plot_data.columns and 'value' in monthly_plot_data.columns:
             plot_variable_vs_target(
                 transformed_monthly_data=monthly_plot_data, # Expects 'date', 'variable', 'value'
                 target_data=gdp_plot_data,                 # Expects 'date', 'value'
                 variable_name='industrial_production',
                 target_name='GDP Growth',
                 start_date="2022-10-01" # Using dates from synthetic data for a focused plot
             )
             print("Plot generation called (actual display depends on environment and if matplotlib is configured for non-GUI).")
        else:
            print("Skipping plot: Data for plotting ('industrial_production' or target) is not adequately prepared or missing 'value' column.")
    except Exception as e:
        print(f"Error generating plot: {e}")
        import traceback
        traceback.print_exc()
        # To avoid GUI pop-ups in non-interactive environments, you might need:
        # import matplotlib
        # matplotlib.use('Agg') # To save plots to file instead of displaying
        # before importing pyplot. Plotting might also be skipped if plt.show() is called.

    print("\n--- Midas Nowcasting Example 1 (Updated) Finished ---")

if __name__ == "__main__":
    main()
