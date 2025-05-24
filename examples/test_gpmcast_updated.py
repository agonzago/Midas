# examples/test_gpmcast_updated.py
import pandas as pd
from datetime import datetime

# Imports from the midas_nowcasting structure
from midas_nowcasting.config.gpmcast_config import NowcastConfig
from midas_nowcasting.data_handling.gpmcast_data_handling import NowcastData
from midas_nowcasting.models.core import NowcastModel as NowcastModelManager
from sklearn.linear_model import LinearRegression # Using a simple model for the test
from midas_nowcasting.reporting.tables import generate_model_summary_table
from midas_nowcasting.reporting.charts import plot_variable_vs_target

def main():
    print("--- Starting Midas Nowcasting Test Script (Updated) ---")

    # --- 1. Load Configuration ---
    print("\n--- 1. Loading Configuration ---")
    # Using dummy_config.json and synthetic data files from the project root.
    release_calendar_df = pd.DataFrame([
        {'date': pd.to_datetime('2023-01-15'), 'variable': 'industrial_production', 'release_lag_days': 15},
        {'date': pd.to_datetime('2023-01-20'), 'variable': 'retail_sales', 'release_lag_days': 20}
    ])
    
    try:
        config = NowcastConfig(
            variable_info={
                "industrial_production": {"seasonal_adjust": False, "growth_rate": True, "transformations": ["level"]},
                "retail_sales": {"seasonal_adjust": False, "growth_rate": True, "transformations": ["level"]}
            },
            release_calendar=release_calendar_df,
            raw_monthly_path="synthetic_monthly.csv",
            raw_gdp_path="synthetic_gdp.csv"
        )
        print("Configuration loaded successfully.")
    except Exception as e:
        print(f"Error loading configuration: {e}")
        return

    # --- 2. Initialize Data Handling ---
    print("\n--- 2. Initializing Data Handling ---")
    try:
        data_handler = NowcastData(config)
        data_handler.monthly_data['release_date'] = pd.to_datetime(data_handler.monthly_data['release_date'])
        print("Data handler initialized successfully.")
        print("Processed monthly data sample (from data_handler):")
        print(data_handler.monthly_data.head())
        print("\nGDP data sample (from data_handler):")
        print(data_handler.gdp_data.head())
    except FileNotFoundError as e:
        print(f"Error initializing data handler: {e}")
        return
    except Exception as e:
        print(f"An unexpected error during data handling initialization: {e}")
        return
        
    # --- 3. Prepare Training Data ---
    print("\n--- 3. Preparing Training Data ---")
    nowcast_date = datetime(2023, 1, 1)
    print(f"Preparing data for nowcast date: {nowcast_date.strftime('%Y-%m-%d')}")
    
    try:
        features_df = data_handler.get_real_time_features(nowcast_date)
        
        if features_df.empty or 'gdp_growth' not in features_df.columns:
             print("Could not generate features or 'gdp_growth' (target) is missing. Exiting.")
             return
        
        y_train = features_df['gdp_growth']
        feature_cols = [col for col in features_df.columns if col not in ['gdp_growth', 'date', 'quarter']]
        X_train = features_df[feature_cols].fillna(0)

        print(f"X_train shape: {X_train.shape}, y_train shape: {y_train.shape}")
        if X_train.empty:
            print("X_train is empty. Cannot proceed.")
            return
        print(f"X_train contains {X_train.shape[1]} features.")

    except Exception as e:
        print(f"Error preparing training data: {e}")
        import traceback
        traceback.print_exc()
        return

    # --- 4. Specify and Train a Simple Model ---
    print("\n--- 4. Specifying and Training a Simple Model ---")
    models_to_run = {
        "SimpleLinearRegression": LinearRegression()
    }
    
    nowcaster_manager = NowcastModelManager(models=models_to_run)
    
    try:
        nowcaster_manager.train(X_train.to_numpy(), y_train.to_numpy())
        print("Model training completed by NowcastModelManager.")
        # Basic check:
        if "SimpleLinearRegression" in nowcaster_manager.trained_models:
            print("SimpleLinearRegression model was trained.")
        else:
            print("Error: SimpleLinearRegression model not found in trained_models.")
    except Exception as e:
        print(f"Error training models: {e}")
        import traceback
        traceback.print_exc()
        return

    # --- 5. Generate Summary Table ---
    print("\n--- 5. Generating Summary Table ---")
    if hasattr(nowcaster_manager, 'metrics') and nowcaster_manager.metrics:
        X_pred_sample = X_train.head(1).to_numpy() if not X_train.empty else pd.DataFrame().to_numpy()
        latest_nowcasts_report = {}
        if X_pred_sample.shape[0] > 0:
            predictions_dict = nowcaster_manager.predict(X_pred_sample)
            for name, pred_array in predictions_dict.items():
                latest_nowcasts_report[name] = pred_array[0] if len(pred_array) > 0 else float('nan')

        summary_df = generate_model_summary_table(nowcaster_manager.metrics, latest_nowcasts_report)
        print("\nModel Performance Summary:")
        print(summary_df)
        # Basic check:
        if not summary_df.empty:
            print("Summary table generated.")
        else:
            print("Error: Summary table is empty.")
    else:
        print("Skipping summary table: Metrics not available.")

    # --- 6. Plot Variables vs Target ---
    print("\n--- 6. Plotting Variables vs Target ---")
    try:
        gdp_plot_data = data_handler.gdp_data.copy()
        if 'value' not in gdp_plot_data.columns and 'gdp_growth' in gdp_plot_data.columns:
            gdp_plot_data['value'] = gdp_plot_data['gdp_growth']

        monthly_plot_data = data_handler.monthly_data[
            data_handler.monthly_data['variable'] == 'industrial_production'
        ].copy()

        if not monthly_plot_data.empty and 'value' in gdp_plot_data.columns and 'value' in monthly_plot_data.columns:
             plot_variable_vs_target(
                 transformed_monthly_data=monthly_plot_data,
                 target_data=gdp_plot_data,
                 variable_name='industrial_production',
                 target_name='GDP Growth',
                 start_date="2022-10-01"
             )
             print("Plot generation called.")
        else:
            print("Skipping plot: Data for plotting not adequately prepared.")
    except Exception as e:
        print(f"Error generating plot: {e}")
        import traceback
        traceback.print_exc()

    print("\n--- Midas Nowcasting Test Script (Updated) Finished ---")

if __name__ == "__main__":
    main()
