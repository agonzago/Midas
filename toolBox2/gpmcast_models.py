from sklearn.base import BaseEstimator
from typing import Dict, List
import numpy as np

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