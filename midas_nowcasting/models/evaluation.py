# midas_nowcasting/models/evaluation.py
import pandas as pd
import numpy as np
from dataclasses import dataclass
from typing import Dict, List, Optional
from sklearn.linear_model import Ridge # Added as per instructions, used in ForecastCombiner

@dataclass
class ForecastHistory:
    """Store forecast history for each indicator"""
    indicator: str
    forecasts: List[float]
    actuals: List[float]
    dates: List[pd.Timestamp]
    
    def calculate_rmse(self, window: Optional[int] = None) -> float:
        """Calculate RMSE with optional rolling window"""
        if len(self.forecasts) == 0:
            return np.inf
            
        errors = np.array(self.forecasts) - np.array(self.actuals)
        if window:
            errors = errors[-window:]
        return np.sqrt(np.mean(errors ** 2))
    
    def calculate_mae(self, window: Optional[int] = None) -> float:
        """Calculate MAE with optional rolling window"""
        if len(self.forecasts) == 0:
            return np.inf
            
        errors = np.abs(np.array(self.forecasts) - np.array(self.actuals))
        if window:
            errors = errors[-window:]
        return np.mean(errors)
    
    def calculate_directional_accuracy(self, window: Optional[int] = None) -> float:
        """Calculate directional accuracy"""
        if len(self.forecasts) < 2:
            return 0.5 # Return 0.5 if not enough data points to calculate direction
            
        f_direction = np.diff(self.forecasts)
        a_direction = np.diff(self.actuals)
        
        # Handle cases where diff results in zero length array
        if len(f_direction) == 0 or len(a_direction) == 0:
            return 0.5

        correct_dir = (f_direction * a_direction) > 0
        
        if window:
            # Ensure window does not exceed available data points for correct_dir
            actual_window = min(window, len(correct_dir))
            if actual_window > 0:
                 correct_dir = correct_dir[-actual_window:]
            else: # Not enough data for window
                return 0.5 
        
        if len(correct_dir) == 0: # If after windowing, no data left
            return 0.5

        return np.mean(correct_dir)

class ForecastCombiner:
    def __init__(self, forecast_history: Dict[str, ForecastHistory]):
        self.history = forecast_history
        
    def combine_bic(self, forecasts_df: pd.DataFrame) -> pd.Series:
        """Traditional BIC-based weights"""
        if 'bic' not in forecasts_df.columns or forecasts_df['bic'].empty:
            # Fallback if BIC is missing or empty
            num_models = len(forecasts_df['indicator'])
            return pd.Series([1/num_models] * num_models, index=forecasts_df.index)
        
        # Replace inf BIC values (e.g., from models that couldn't be estimated) with a large number
        bic_values = forecasts_df['bic'].replace([np.inf, -np.inf], np.nan).fillna(np.nanmax(forecasts_df['bic'].replace([np.inf, -np.inf], np.nan)) + 100)
        # If all BICs were inf or nan, use equal weights
        if bic_values.isnull().all():
            num_models = len(forecasts_df['indicator'])
            return pd.Series([1/num_models] * num_models, index=forecasts_df.index)

        weights = 1 / bic_values 
        if weights.sum() == 0: # Avoid division by zero if all weights are zero
             num_models = len(forecasts_df['indicator'])
             return pd.Series([1/num_models] * num_models, index=forecasts_df.index)
        return weights / weights.sum()
    
    def combine_rmse(self, forecasts_df: pd.DataFrame, window: Optional[int] = None) -> pd.Series:
        """RMSE-based weights with optional rolling window"""
        indicators = forecasts_df.get('indicator', pd.Series(dtype=str))
        if indicators.empty:
             return pd.Series(dtype=float)

        rmse_values = pd.Series({
            ind: self.history[ind].calculate_rmse(window)
            for ind in indicators if ind in self.history
        })
        if rmse_values.empty: # Fallback if no valid RMSEs
            num_models = len(indicators)
            return pd.Series([1/num_models] * num_models, index=indicators.index)

        weights = 1 / rmse_values.replace([np.inf, -np.inf], np.nan).fillna(np.nanmax(rmse_values.replace([np.inf, -np.inf], np.nan)) + 100)
        if weights.sum() == 0:
             num_models = len(indicators)
             return pd.Series([1/num_models] * num_models, index=indicators.index)
        return weights / weights.sum()
    
    def combine_performance_rank(self, forecasts_df: pd.DataFrame) -> pd.Series:
        """Combine multiple performance metrics using rank-based weights"""
        indicators = forecasts_df.get('indicator', pd.Series(dtype=str))
        if indicators.empty:
            return pd.Series(dtype=float)

        # Calculate multiple performance metrics
        rmse_rank = pd.Series({
            ind: self.history[ind].calculate_rmse()
            for ind in indicators if ind in self.history
        }).rank()
        
        mae_rank = pd.Series({
            ind: self.history[ind].calculate_mae()
            for ind in indicators if ind in self.history
        }).rank()
        
        dir_acc_rank = pd.Series({ # Negative so lower rank is better
            ind: -self.history[ind].calculate_directional_accuracy()  
            for ind in indicators if ind in self.history
        }).rank()

        if rmse_rank.empty and mae_rank.empty and dir_acc_rank.empty:
            num_models = len(indicators)
            return pd.Series([1/num_models] * num_models, index=indicators.index)
        
        # Combine ranks (handle potential NaNs if some metrics couldn't be calculated)
        combined_rank = rmse_rank.fillna(0) + mae_rank.fillna(0) + dir_acc_rank.fillna(0)
        weights = 1 / combined_rank.replace(0, np.nan) # Avoid division by zero for ranks of 0
        
        # If all weights are NaN or sum to 0, use equal weights
        if weights.isnull().all() or weights.sum() == 0:
            num_models = len(indicators)
            return pd.Series([1/num_models] * num_models, index=indicators.index)
            
        return weights / weights.sum()
    
    def combine_adaptive(self, forecasts_df: pd.DataFrame, window: int = 4) -> pd.Series:
        """Adaptive weights based on recent performance"""
        indicators = forecasts_df.get('indicator', pd.Series(dtype=str))
        if indicators.empty or not any(ind in self.history for ind in indicators):
            num_models = len(indicators) if not indicators.empty else 1
            return pd.Series([1/num_models] * num_models, index=indicators.index if not indicators.empty else [0])


        recent_rmse = pd.Series({
            ind: self.history[ind].calculate_rmse(window)
            for ind in indicators if ind in self.history
        })
        
        recent_dir_acc = pd.Series({
            ind: self.history[ind].calculate_directional_accuracy(window)
            for ind in indicators if ind in self.history
        })

        # Replace inf with large numbers for division
        recent_rmse_safe = recent_rmse.replace([np.inf, -np.inf], np.nan).fillna(np.nanmax(recent_rmse.replace([np.inf, -np.inf], np.nan)) + 100)
        
        # Default weights
        rmse_weight = 0.7
        dir_weight = 0.3
        
        # Adjust weights based on volatility (if any indicator has enough history)
        first_valid_indicator = next((ind for ind in indicators if ind in self.history and len(self.history[ind].actuals) >= window), None)
        if first_valid_indicator:
            actuals_for_volatility = self.history[first_valid_indicator].actuals
            if len(actuals_for_volatility) >= window: # Ensure there's enough data
                volatility = np.std(actuals_for_volatility[-window:])
                median_actuals = np.median(actuals_for_volatility)
                if median_actuals != 0 and volatility > median_actuals : # Avoid division by zero or issues with all zero actuals
                    rmse_weight = 0.5
                    dir_weight = 0.5
        
        combined_score = (rmse_weight / recent_rmse_safe) + (dir_weight * recent_dir_acc)
        
        if combined_score.sum() == 0 or combined_score.isnull().all():
            num_models = len(indicators)
            return pd.Series([1/num_models] * num_models, index=indicators.index)
            
        return combined_score / combined_score.sum()
    
    def combine_thick_modeling(self, forecasts_df: pd.DataFrame, n_models: int = 5) -> pd.Series:
        """Thick modeling approach - average of top N models"""
        indicators = forecasts_df.get('indicator', pd.Series(dtype=str))
        if indicators.empty:
            return pd.Series(dtype=float)

        rmse_values = pd.Series({
            ind: self.history[ind].calculate_rmse()
            for ind in indicators if ind in self.history
        })
        
        if rmse_values.empty: # Fallback
            num_models = len(indicators)
            return pd.Series([1/num_models] * num_models, index=indicators.index)

        # Select top N models
        top_n_indices = rmse_values.nsmallest(n_models).index
        weights = pd.Series(0.0, index=indicators) # Ensure float type
        if not top_n_indices.empty:
            weights[top_n_indices] = 1.0/len(top_n_indices) # Ensure float division
        else: # If no models selected (e.g. all RMSEs were inf/NaN)
            num_models = len(indicators)
            return pd.Series([1/num_models] * num_models, index=indicators.index)
        return weights
    
    def combine_regression_based(self, forecasts_df: pd.DataFrame, window: int = 8) -> pd.Series:
        """Regression-based combination weights"""
        indicators = forecasts_df.get('indicator', pd.Series(dtype=str))
        num_indicators = len(indicators)
        fallback_weights = pd.Series([1/num_indicators if num_indicators > 0 else 1.0] * num_indicators, index=indicators)

        if indicators.empty:
            return fallback_weights

        X_list = []  # Historical forecasts
        y_list = []  # Actual values
        
        valid_indicators_for_regression = []
        for ind in indicators:
            if ind in self.history:
                hist = self.history[ind]
                if len(hist.forecasts) >= window and len(hist.actuals) >= window:
                    X_list.append(hist.forecasts[-window:])
                    if not y_list: # Only populate y_list once
                         y_list = hist.actuals[-window:]
                    valid_indicators_for_regression.append(ind)
            
        if not X_list or len(X_list) != len(valid_indicators_for_regression) or not y_list:
            return fallback_weights # Fallback if not enough data or consistent history
            
        X = np.array(X_list).T  # Transform to (n_samples, n_features)
        y = np.array(y_list)

        if X.shape[0] != y.shape[0] or X.shape[1] == 0: # Check if X is valid
            return fallback_weights

        try:
            model = Ridge(alpha=1.0, fit_intercept=False) # No intercept as forecasts should be unbiased
            model.fit(X, y)
            raw_weights = model.coef_
            # Ensure weights are positive and sum to 1
            positive_weights = np.maximum(raw_weights, 0)
            weight_sum = positive_weights.sum()
            
            final_weights_values = positive_weights / weight_sum if weight_sum > 0 else [1/len(positive_weights)] * len(positive_weights)
            
            # Assign weights to corresponding indicators, others get 0
            final_weights = pd.Series(0.0, index=indicators)
            final_weights[valid_indicators_for_regression] = final_weights_values
            
            # If sum is still 0 (e.g. all valid indicators had 0 weight), redistribute
            if final_weights.sum() == 0:
                return fallback_weights

            return final_weights / final_weights.sum() # Normalize again to be sure

        except Exception:
            return fallback_weights


def update_forecast_history(history: Dict[str, ForecastHistory],
                          new_forecasts: pd.DataFrame, # Expects columns 'indicator', 'forecast'
                          actual_gdp: float,
                          forecast_date: pd.Timestamp) -> Dict[str, ForecastHistory]:
    """Update forecast history with new forecasts and actual GDP"""
    if 'indicator' not in new_forecasts.columns or 'forecast' not in new_forecasts.columns:
        # Or raise an error, depending on desired strictness
        print("Warning: new_forecasts DataFrame must contain 'indicator' and 'forecast' columns.")
        return history

    for _, row in new_forecasts.iterrows():
        indicator = row['indicator']
        if indicator not in history:
            history[indicator] = ForecastHistory(
                indicator=indicator,
                forecasts=[],
                actuals=[],
                dates=[]
            )
        
        history[indicator].forecasts.append(row['forecast'])
        history[indicator].actuals.append(actual_gdp)
        history[indicator].dates.append(forecast_date)
    
    return history
