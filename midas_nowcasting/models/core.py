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