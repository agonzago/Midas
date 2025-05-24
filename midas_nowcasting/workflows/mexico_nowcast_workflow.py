# midas_nowcasting/workflows/mexico_nowcast_workflow.py
import pandas as pd
import numpy as np
from datetime import datetime # Assuming datetime might be used, from original context

# Imports for the new midas_nowcasting structure
from midas_nowcasting.data_handling.data_calendar import DataCalendar # Or MexicoDataCalendar if used
# It seems DataCalendar is used directly in the original run_weekly_nowcast
from midas_nowcasting.utils.dates import determine_target_quarter
from midas_nowcasting.models.umidas import UMIDASModel
# GDPData might also be needed if gdp_data objects are passed around and used here.
# from midas_nowcasting.data_handling.gdp_management import GDPData


# Extracted from umidas_mexico.py
# Original run_midas_nowcast is now part of UMIDASModel.fit method.
# This run_weekly_nowcast will need significant refactoring.

def run_weekly_nowcast(gdp_data, x_monthly_dict: dict, reference_date: datetime, 
                       max_y_lags: int = 4, max_x_lags: int = 6): # Added lag params
    """
    Run nowcast for current quarter based on weekly data availability.
    Refactored to use UMIDASModel class.
    
    Parameters:
    gdp_data: GDPData object (from midas_nowcasting.data_handling.gdp_management)
    x_monthly_dict: dictionary of monthly pandas Series indicators.
    reference_date: datetime object representing the current date.
    max_y_lags: Max lags for AR component in UMIDAS.
    max_x_lags: Max lags for monthly indicators in UMIDAS.
    """
    # Get GDP series (including provisional value if needed)
    y_quarterly = gdp_data.get_gdp_series(reference_date) # Assumes gdp_data is an instance of GDPData
    
    # Initialize calendar - assuming generic DataCalendar, or could be MexicoDataCalendar
    # If MexicoDataCalendar is always used, the import should be specific.
    # For now, keeping it as DataCalendar as per the prompt's initial thought.
    calendar = DataCalendar() 
    
    # Get available indicators
    available_indicators = calendar.get_available_indicators(reference_date)
    
    # Determine target quarter and current month in quarter
    _target_quarter, _target_year, month_in_quarter = determine_target_quarter(reference_date)
    
    results = []
    
    # Process available indicators
    for indicator_name in available_indicators:
        if indicator_name in x_monthly_dict:
            x_monthly_series = x_monthly_dict[indicator_name]
            
            # Instantiate UMIDASModel
            umidas_model = UMIDASModel(max_y_lags=max_y_lags, max_x_lags=max_x_lags)
            
            # Fit the model
            # The fit method of UMIDASModel now contains the logic of run_midas_nowcast
            try:
                umidas_model.fit(X=x_monthly_series, y=y_quarterly, month_in_quarter=month_in_quarter)
            except Exception as e:
                print(f"Error fitting UMIDASModel for indicator {indicator_name}: {e}")
                # Optionally, log this error and continue
                continue # Skip this indicator if fitting fails

            if umidas_model.model_ is not None: # Check if model was successfully fitted
                # Predict using the model
                # The predict method of UMIDASModel needs X_pred and month_in_quarter
                # X_pred should be the same x_monthly_series used for fitting,
                # as predict internally handles the necessary slicing or uses the fitted context.
                # The original run_midas_nowcast used `model.predict(x.iloc[-(month_in_quarter+1):])`
                # The refactored UMIDASModel.predict handles this with its X_pred and month_in_quarter args.
                # We pass the full series X_monthly_series to predict.
                forecast_values = umidas_model.predict(X_pred=x_monthly_series, month_in_quarter=month_in_quarter)
                
                current_forecast = np.nan # Default if prediction array is empty or all NaNs
                if forecast_values is not None and len(forecast_values) > 0:
                    # Assuming the last value is the one-step-ahead nowcast we need
                    current_forecast = forecast_values[-1] 

                if not np.isnan(current_forecast):
                    results.append({
                        'indicator': indicator_name,
                        'forecast': current_forecast,
                        'bic': umidas_model.get_bic() # Retrieve BIC from the model instance
                    })
                else:
                    print(f"Warning: Forecast for {indicator_name} is NaN.")
            else:
                print(f"Warning: UMIDASModel fitting failed for indicator {indicator_name}, BIC might be inf.")
                # Optionally append with NaN forecast and inf BIC if needed for robust combination
                results.append({
                    'indicator': indicator_name,
                    'forecast': np.nan, # Or some other placeholder for failed model
                    'bic': np.inf 
                })

    weighted_forecast = np.nan # Default
    details_df = pd.DataFrame()

    if results:
        results_df = pd.DataFrame(results)
        
        # Handle potential NaNs or Infs in BIC before calculating weights
        results_df['bic'] = results_df['bic'].replace([np.inf, -np.inf], np.nan)
        max_bic = np.nanmax(results_df['bic']) if not results_df['bic'].isnull().all() else 1
        # Fill NaN BICs with a value larger than any other BIC to give them low/zero weight
        results_df['bic'] = results_df['bic'].fillna(max_bic + 100) 

        if not results_df['bic'].isnull().all() and not (results_df['bic'] == 0).all():
            # Calculate weights (inverse BIC, normalized)
            # Avoid division by zero if all BICs are effectively infinite (replaced by large numbers)
            # or if any BIC is zero (which shouldn't happen with proper calculation but good to guard)
            inverse_bic = 1 / results_df['bic']
            sum_inverse_bic = inverse_bic.sum()

            if sum_inverse_bic != 0 and not np.isinf(sum_inverse_bic):
                weights = inverse_bic / sum_inverse_bic
            else: # Fallback to equal weights if sum_inverse_bic is 0 or inf
                print("Warning: Could not calculate BIC weights reliably. Falling back to equal weights.")
                weights = pd.Series(np.ones(len(results_df)) / len(results_df), index=results_df.index)
        else: # Fallback to equal weights if all BICs are null or all zero
            print("Warning: All BIC values are problematic. Falling back to equal weights.")
            weights = pd.Series(np.ones(len(results_df)) / len(results_df), index=results_df.index)

        results_df['weight'] = weights
        
        # Calculate weighted forecast, ensuring 'forecast' column has no NaNs for weighted sum
        # Or handle NaNs as per desired strategy (e.g., exclude, treat as zero if weight is also zero)
        valid_forecasts_for_weighting = results_df.dropna(subset=['forecast'])
        if not valid_forecasts_for_weighting.empty:
            weighted_forecast = (valid_forecasts_for_weighting['forecast'] * valid_forecasts_for_weighting['weight']).sum()
        else:
            print("Warning: No valid forecasts to combine.")
            weighted_forecast = np.nan # Or another suitable value

        details_df = results_df
        
    return weighted_forecast, details_df


def create_nowcast_report(gdp_data, x_monthly_dict: dict, reference_date: datetime):
    """
    Create a complete nowcast report. (Adapted from umidas_mexico.py)
    
    Parameters:
    gdp_data: GDPData object
    x_monthly_dict: dictionary of monthly indicators
    reference_date: datetime object
    """
    # Run nowcast using the refactored run_weekly_nowcast
    forecast, details = run_weekly_nowcast(gdp_data, x_monthly_dict, reference_date)
    
    if forecast is None or np.isnan(forecast): # Check if forecast is None or NaN
        return {
            'status': 'No valid forecast generated or no indicators available',
            'reference_date': reference_date,
            'forecast': None,
            'details': None,
            'target_quarter': None,
            'target_year': None,
            'quarter_progress': None,
            'available_indicators': None
        }
    
    # Get target quarter info
    target_quarter, target_year, month_in_quarter = determine_target_quarter(reference_date)
    
    # Calculate quarter progress
    quarter_progress = ((month_in_quarter + 1) / 3.0) * 100 # Ensure float division
    
    # Get available indicators (can also be retrieved from details if run_weekly_nowcast provides it)
    # For consistency, let's use DataCalendar again or ensure 'details' contains this.
    # The current 'details' DataFrame from run_weekly_nowcast has 'indicator' column.
    available_indicators_from_run = list(details['indicator'].unique()) if details is not None and not details.empty else []

    # If DataCalendar was specific (e.g. MexicoDataCalendar), use it for official list.
    calendar = DataCalendar() # Or the specific calendar used in run_weekly_nowcast
    official_available_indicators = calendar.get_available_indicators(reference_date)

    return {
        'status': 'success',
        'reference_date': reference_date.strftime('%Y-%m-%d'), # Store as string for easier serialization
        'target_quarter': target_quarter,
        'target_year': target_year,
        'forecast': forecast,
        'quarter_progress': f"{quarter_progress:.1f}%", # Store as formatted string
        'available_indicators': official_available_indicators, # List of indicators from calendar
        'contributing_indicators_details': details.to_dict(orient='records') if details is not None else [] # Details of indicators that contributed
    }
