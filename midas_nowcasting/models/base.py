# midas_nowcasting/models/base.py
from sklearn.base import BaseEstimator

class BaseModel(BaseEstimator):
    def fit(self, X, y=None):
        raise NotImplementedError("Subclasses should implement this method.")

    def predict(self, X):
        raise NotImplementedError("Subclasses should implement this method.")
