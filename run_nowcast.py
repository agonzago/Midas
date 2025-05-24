# run_nowcast.py
import pandas as pd
from datetime import datetime

# Import from the new midas_nowcasting structure
from midas_nowcasting.config.gpmcast_config import NowcastConfig
from midas_nowcasting.data_handling.gpmcast_data_handling import NowcastData
from midas_nowcasting.models.core import NowcastModel as NowcastModelManager # Renamed to avoid confusion
from midas_nowcasting.models.ar import ARModel
from midas_nowcasting.models.umidas import UMIDASModel
from midas_nowcasting.reporting.tables import generate_model_summary_table
from midas_nowcasting.reporting.charts import plot_variable_vs_target

def main():
    print("Starting Midas Nowcasting Platform execution...")

    # 1. Load Configuration
    print("\n--- 1. Loading Configuration ---")
    # Note: The NowcastConfig.from_json expects release_calendar to be a DataFrame.
    # The JSON has it as a list of dicts, so direct from_json might need adjustment
    # or the JSON structure for release_calendar needs to match what from_json can parse.
    # For now, let's create config directly for simplicity in this example.
    
    # Create a dummy release calendar DataFrame
    release_calendar_df = pd.DataFrame([
        {'date': pd.to_datetime('2023-01-15'), 'variable': 'industrial_production', 'release_lag_days': 15},
        {'date': pd.to_datetime('2023-01-20'), 'variable': 'retail_sales', 'release_lag_days': 20}
    ])
    
    config = NowcastConfig(
        variable_info={
            "industrial_production": {"seasonal_adjust": False, "growth_rate": True, "transformations": ["level"]},
            "retail_sales": {"seasonal_adjust": False, "growth_rate": True, "transformations": ["level"]}
        },
        release_calendar=release_calendar_df,
        raw_monthly_path="synthetic_monthly.csv",
        raw_gdp_path="synthetic_gdp.csv"
    )
    print("Configuration loaded.")
    print(f"Monthly data path: {config.raw_monthly_path}")
    print(f"GDP data path: {config.raw_gdp_path}")

    # 2. Initialize Data Handling
    print("\n--- 2. Initializing Data Handling ---")
    try:
        data_handler = NowcastData(config)
        print("Data handler initialized.")
    except FileNotFoundError as e:
        print(f"Error initializing data handler: {e}")
        print("Please ensure 'synthetic_monthly.csv' and 'synthetic_gdp.csv' exist in the root directory.")
        return
    except Exception as e:
        print(f"An unexpected error occurred during data handling initialization: {e}")
        return

    # 3. Prepare Training Data
    print("\n--- 3. Preparing Training Data ---")
    nowcast_date = datetime(2023, 1, 1) # Example nowcast date
    print(f"Preparing data for nowcast date: {nowcast_date.strftime('%Y-%m-%d')}")
    try:
        # The prepare_training_data in the current NowcastData uses IterativeImputer,
        # which might fail with the very small dummy dataset.
        # We'll call get_real_time_features which is less complex for this demo.
        # X_train, y_train = data_handler.prepare_training_data(nowcast_date)
        
        # The get_real_time_features method expects 'release_date' in monthly_data to be datetime
        data_handler.monthly_data['release_date'] = pd.to_datetime(data_handler.monthly_data['release_date'])
        
        # The _apply_transformations method expects 'variable' and 'value' columns.
        # And the pivot_table part needs 'gdp_growth' in the aligned data.
        # The dummy data is very minimal, this part might show issues.
        
        features_df = data_handler.get_real_time_features(nowcast_date)
        print("Real-time features (head):")
        print(features_df.head())
        
        # For training, we'd need to select X and y from features_df
        # This is a simplified example, proper X, y splitting is needed for actual model training
        if features_df.empty or 'gdp_growth' not in features_df.columns:
             print("Could not generate features or 'gdp_growth' is missing. Skipping model training/prediction.")
             y_train = pd.Series(dtype=float) # Empty series
             X_train = pd.DataFrame() # Empty dataframe
        else:
            y_train = features_df['gdp_growth']
            # Attempt to intelligently drop known non-feature columns
            cols_to_drop = ['gdp_growth', 'date', 'quarter', 'variable', 'month', 'value', 
                            'industrial_production', 'retail_sales'] 
            # Filter cols_to_drop to only include those present in features_df.columns
            cols_to_drop_existing = [col for col in cols_to_drop if col in features_df.columns]
            X_train = features_df.drop(columns=cols_to_drop_existing)
            
            # Imputation might be needed here for real use cases
            X_train = X_train.fillna(0)


        print(f"X_train shape: {X_train.shape}, y_train shape: {y_train.shape}")

    except Exception as e:
        print(f"Error preparing training data: {e}")
        # import traceback
        # traceback.print_exc()
        print("Skipping further steps due to data preparation error.")
        return

    # 4. Specify Models
    print("\n--- 4. Specifying Models ---")
    # These are using the placeholder models.
    # Actual parameters (lags, variables, etc.) would be set here.
    ar_ip = ARModel(variable_name="industrial_production", lags=1)
    # UMIDAS model expects specific column names like 'industrial_production_1', etc.
    # These would be generated by get_real_time_features if data was richer.
    # For now, using placeholder column names that might not exist in X_train
    umidas_x_vars = [col for col in X_train.columns if 'industrial_production' in col or 'retail_sales' in col]
    if not umidas_x_vars: # if no specific vars found, use all X_train columns as a fallback for demo
        umidas_x_vars = list(X_train.columns)

    umidas_ip_retail = UMIDASModel(
        x_vars=umidas_x_vars, 
        y_var='gdp_growth'
    )
    
    models_to_run = {
        "AR_IP": ar_ip,
        "UMIDAS_IP_Retail": umidas_ip_retail
    }
    print(f"Models specified: {list(models_to_run.keys())}")

    # 5. Train Models (using NowcastModelManager)
    print("\n--- 5. Training Models ---")
    model_manager = NowcastModelManager(models=models_to_run)
    
    if not X_train.empty and not y_train.empty:
        try:
            print("Note: Calling fit directly on placeholder models for demonstration.")
            for name, model_instance in models_to_run.items():
                print(f"Training {name}...")
                if isinstance(model_instance, ARModel):
                     # AR model placeholder expects a series from X_train for 'variable_name'
                     # The synthetic data creates columns like 'industrial_production_10', 'industrial_production_11', etc.
                     # The ARModel expects a single column named 'industrial_production'.
                     # This part needs adjustment for how features are named.
                     # For now, we'll try to find a column that starts with the variable name.
                     potential_cols = [col for col in X_train.columns if col.startswith(model_instance.variable_name)]
                     if potential_cols:
                         # Using the first found column for simplicity
                         model_instance.fit(X_train[[potential_cols[0]]], y_train) 
                     else:
                         print(f"Skipping AR model, column starting with {model_instance.variable_name} not in X_train. X_train columns: {X_train.columns}")
                elif isinstance(model_instance, UMIDASModel):
                    # Ensure all x_vars for UMIDAS are in X_train
                    current_x_vars = [var for var in model_instance.x_vars if var in X_train.columns]
                    if len(current_x_vars) < len(model_instance.x_vars):
                        print(f"Warning: Not all specified x_vars for UMIDAS model are present in X_train. Available: {current_x_vars}")
                    if not current_x_vars:
                        print(f"Skipping UMIDAS model as none of its x_vars are in X_train. X_train columns: {X_train.columns}")
                    else:
                        model_instance.fit(X_train[current_x_vars], y_train)
                else: 
                     model_instance.fit(X_train, y_train)
            
            print("Models training process completed (using placeholders).")
            dummy_metrics = {
                "AR_IP": {"RMSE": 1.0, "MAE": 0.8, "R²": 0.1},
                "UMIDAS_IP_Retail": {"RMSE": 0.8, "MAE": 0.6, "R²": 0.3}
            }
            model_manager.metrics = dummy_metrics 
            model_manager.trained_models = models_to_run 

        except Exception as e:
            print(f"Error training models: {e}")
            # import traceback
            # traceback.print_exc()
    else:
        print("Skipping model training due to empty training data.")


    # 6. Generate Predictions (using placeholder models)
    print("\n--- 6. Generating Predictions ---")
    X_pred = X_train 
    predictions = {}
    if not X_pred.empty and hasattr(model_manager, 'trained_models') and model_manager.trained_models:
        try:
            print("Note: Calling predict directly on placeholder models for demonstration.")
            for name, model_instance in model_manager.trained_models.items():
                if isinstance(model_instance, ARModel):
                     potential_cols = [col for col in X_pred.columns if col.startswith(model_instance.variable_name)]
                     if potential_cols:
                         predictions[name] = model_instance.predict(X_pred[[potential_cols[0]]])
                     else:
                         print(f"Skipping AR model prediction, column starting with {model_instance.variable_name} not in X_pred.")
                         predictions[name] = np.array([0]) 
                elif isinstance(model_instance, UMIDASModel):
                    current_x_vars = [var for var in model_instance.x_vars if var in X_pred.columns]
                    if not current_x_vars:
                        print(f"Skipping UMIDAS prediction as none of its x_vars are in X_pred.")
                        predictions[name] = np.array([0])
                    else:
                        predictions[name] = model_instance.predict(X_pred[current_x_vars])
                else:
                     predictions[name] = model_instance.predict(X_pred)

            print("Predictions (first element per model):")
            for name, pred_array in predictions.items():
                # Ensure pred_array is not None and is iterable
                if pred_array is not None and len(pred_array) > 0:
                     print(f"  {name}: {pred_array[0]}")
                else:
                     print(f"  {name}: N/A (no prediction generated or empty array)")
        except Exception as e:
            print(f"Error generating predictions: {e}")
            # import traceback
            # traceback.print_exc()
    else:
        print("Skipping predictions due to empty data or no trained models.")
        
    # 7. Combine Forecasts
    print("\n--- 7. Combining Forecasts ---")
    if predictions:
        # Filter out models that didn't produce valid predictions (e.g. returned None or empty)
        valid_predictions = {name: pred for name, pred in predictions.items() if pred is not None and len(pred)>0}
        if valid_predictions:
            weights = {name: 1/len(valid_predictions) for name in valid_predictions.keys()}
            # Ensure weights only for models with valid predictions
            combined_forecast = model_manager.combine_forecasts(valid_predictions, weights)
            print(f"Combined forecast: {combined_forecast}")
        else:
            print("Skipping forecast combination as no valid predictions were generated.")
            combined_forecast = "N/A"
    else:
        print("Skipping forecast combination as no predictions dictionary was generated.")
        combined_forecast = "N/A"

    # 8. Produce Reports
    print("\n--- 8. Producing Reports ---")
    if hasattr(model_manager, 'metrics') and model_manager.metrics:
        latest_nowcasts_report = {
            name: p[0] if p is not None and len(p) > 0 else 0 
            for name, p in predictions.items()
        }
        
        summary_df = generate_model_summary_table(model_manager.metrics, latest_nowcasts_report)
        print("\nModel Summary Table:")
        print(summary_df)
    else:
        print("Skipping summary table generation as model metrics are not available.")

    print("\nPlotting example (conceptual):")
    try:
        plot_monthly_df = pd.DataFrame({
            'date': pd.to_datetime(['2022-10-01', '2022-11-01', '2022-12-01']),
            'variable': 'industrial_production', # This should match a variable name expected by plot function
            'value': [0.5, 0.6, 0.55] 
        })
        plot_target_df = pd.DataFrame({
            'date': pd.to_datetime(['2022-09-30', '2022-12-31']),
            'value': [1.0, 1.2] 
        })
        # plot_variable_vs_target( # Call is commented out to prevent GUI popup
        #     transformed_monthly_data=plot_monthly_df, 
        #     target_data=plot_target_df,
        #     variable_name='industrial_production', # This is the variable to plot from plot_monthly_df
        #     target_name='GDP Growth'
        # )
        print("Plot generation would occur here if data was suitably prepared and call uncommented.")
        print("(Skipping actual plot generation for this console-based demo script to avoid GUI pop-ups)")

    except Exception as e:
        print(f"Error generating plot: {e}")
        # import traceback
        # traceback.print_exc()

    print("\nMidas Nowcasting Platform execution finished.")

if __name__ == "__main__":
    # Need to add numpy for UMIDAS and AR model placeholders if they return np.array()
    import numpy as np 
    main()
