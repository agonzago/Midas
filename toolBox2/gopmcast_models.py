from sklearn.base import BaseEstimator
from typing import Dict, List
import numpy as np
import pandas as pd
from sklearn.metrics import mean_squared_error, mean_absolute_error, r2_score
from sklearn.model_selection import train_test_split    
class NowcastModel:
    """
    Handles model training, prediction, and forecast combinations.
    
    Args:
        models (Dict[str, BaseEstimator]): Dictionary of models (e.g., {"UMIDAS": LinearRegression()}).
    """
    def __init__(self, models: Dict[str, BaseEstimator]):
        self.models = models
        self.trained_models = {}

    def train(self, X: np.ndarray, y: pd.Series) -> None:
        """Train all models on the prepared data."""
        for name, model in self.models.items():
            model.fit(X, y)
            self.trained_models[name] = model

    def train(self, X: np.ndarray, y: pd.Series, test_size: float = 0.2) -> None:
        """Train models and evaluate on a holdout set."""
        X_train, X_test, y_train, y_test = train_test_split(
            X, y, test_size=test_size, shuffle=False
        )
        
        for name, model in self.models.items():
            model.fit(X_train, y_train)
            preds = model.predict(X_test)
            
            # Store metrics
            self.metrics[name] = {
                "RMSE": np.sqrt(mean_squared_error(y_test, preds)),
                "MAE": mean_absolute_error(y_test, preds),
                "R²": r2_score(y_test, preds)
            }
            self.trained_models[name] = model

    def summary_table(self) -> pd.DataFrame:
        """Generate a performance summary table."""
        df = pd.DataFrame(self.metrics).T
        df["Latest_Nowcast"] = [self.trained_models[name].predict(X_nowcast)[0] 
                               for name in df.index]
        return df.sort_values("RMSE")
    def predict(self, X: np.ndarray) -> Dict[str, float]:
        """Generate predictions from all trained models."""
        return {name: model.predict(X) for name, model in self.trained_models.items()}

    def combine_forecasts(self, predictions: Dict[str, float], 
                          weights: Dict[str, float] = None) -> float:
        """
        Combine forecasts using specified weights (default: equal weights).
        
        Example:
            weights = {"UMIDAS": 0.6, "AR": 0.4}
        """
        if weights is None:
            weights = {name: 1/len(predictions) for name in predictions.keys()}
        combined = sum(pred * weights[name] for name, pred in predictions.items())
        return combined
    
    def plot_variable_vs_gdp(
        self, 
        var_name: str, 
        start_date: str = "2010-01-01", 
        end_date: str = "2023-12-31"
    ) -> None:
        """
        Plot transformed monthly variable (demeaned) vs quarterly GDP growth.
        
        Args:
            var_name: Variable to plot (e.g., 'industrial_production')
            start_date: Start date for the plot
            end_date: End date for the plot
        """
        # Get transformed monthly data
        var_data = self.processed_monthly_data[
            (self.processed_monthly_data['variable'] == var_name) &
            (self.processed_monthly_data['date'] >= start_date) &
            (self.processed_monthly_data['date'] <= end_date)
        ].set_index('date')['value']
        
        # Get GDP data
        gdp = self.gdp_data[
            (self.gdp_data['date'] >= start_date) &
            (self.gdp_data['date'] <= end_date)
        ].set_index('date')['gdp_growth']
        
        # Create plot
        fig, ax = plt.subplots(figsize=(12, 6))
        
        # Plot monthly variable (demeaned)
        ax.plot(var_data.index, var_data, 'b-', lw=1.5, 
                label=f"{var_name} (demeaned)")
        
        # Plot quarterly GDP (red dots)
        ax.scatter(gdp.index, gdp, color='red', s=70, 
                   label='GDP Growth', zorder=5)
        
        # Style
        ax.axhline(0, color='k', linestyle='--', alpha=0.5)
        ax.set_title(f"{var_name} vs. GDP Growth", fontsize=14)
        ax.set_xlabel("Date", fontsize=12)
        ax.set_ylabel("Standardized Units", fontsize=12)
        ax.legend()
        plt.grid(True, alpha=0.3)
        plt.show()