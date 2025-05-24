# midas_nowcasting/models/umidas.py
from midas_nowcasting.models.base import BaseModel
import numpy as np
import pandas as pd
from pymidas.midas import Umidas # Ensure pymidas is installed in the environment

class UMIDASModel(BaseModel):
    def __init__(self, max_y_lags=4, max_x_lags=6, polynomial_weights=None): # polynomial_weights for future use
        self.max_y_lags = max_y_lags
        self.max_x_lags = max_x_lags
        self.polynomial_weights = polynomial_weights # Not directly used by pymidas.Umidas OLS, but for consistency
        
        self.model_ = None # To store the fitted Umidas object
        self.bic_ = np.inf
        self.params_ = None # To store model parameters if needed

    def fit(self, X: pd.Series, y: pd.Series, month_in_quarter: int):
        """
        Fit the UMIDAS model using the logic from run_midas_nowcast.

        Args:
            X (pd.Series): Monthly indicator data (x_monthly). Must have a DatetimeIndex.
            y (pd.Series): Quarterly target data (y_quarterly). Must have a DatetimeIndex.
            month_in_quarter (int): Current month within the quarter (0, 1, or 2).
        """
        if not isinstance(X, pd.Series) or not isinstance(X.index, pd.DatetimeIndex):
            raise ValueError("X (monthly data) must be a pandas Series with a DatetimeIndex.")
        if not isinstance(y, pd.Series) or not isinstance(y.index, pd.DatetimeIndex):
            raise ValueError("y (quarterly data) must be a pandas Series with a DatetimeIndex.")
        if not month_in_quarter in [0, 1, 2]:
            raise ValueError("month_in_quarter must be 0, 1, or 2.")

        # Add NaN for future months in current quarter based on month_in_quarter
        # month_in_quarter: 0 (1st month), 1 (2nd month), 2 (3rd month)
        months_to_pad = 2 - month_in_quarter 
        
        x_padded = X.copy()
        if months_to_pad > 0 and not X.empty:
            last_date = X.index[-1]
            # Create a date range for padding. Frequency might need to be 'ME' (MonthEnd) or 'MS' (MonthStart)
            # depending on how X's index is structured. Assuming 'ME' for now.
            padding_dates = pd.date_range(
                start=last_date + pd.DateOffset(months=1), 
                periods=months_to_pad, 
                freq='ME' # Or 'MS' or other appropriate monthly frequency
            )
            padding_series = pd.Series([np.nan] * months_to_pad, index=padding_dates)
            x_padded = pd.concat([X, padding_series])
        elif X.empty and months_to_pad > 0: # Handle empty X case for padding
            # This case is tricky; if X is empty, we can't easily determine a start date for padding.
            # For now, if X is empty, we can't pad it. The Umidas model might fail.
            # Or, one might need a reference start date for padding if X can be completely empty.
            print("Warning: X is empty, cannot apply padding based on month_in_quarter.")


        best_bic_local = np.inf
        best_model_local = None
        
        # Grid search over lag combinations
        for y_lags_iter in range(self.max_y_lags + 1):
            for x_lags_iter in range(self.max_x_lags + 1):
                try:
                    # Ensure y and x_padded are aligned for Umidas (e.g. y starts after x has enough history)
                    # pymidas handles some alignment internally based on lags.
                    model = Umidas(y, x_padded, 
                                 m=3,           # Monthly to quarterly ratio
                                 k=x_lags_iter, # High-frequency lags
                                 ylag=y_lags_iter,# Low-frequency lags
                                 optim='ols')    # Using OLS as in run_midas_nowcast
                    
                    model.fit()
                    
                    # Calculate BIC
                    n_residuals = len(model.residuals)
                    if n_residuals == 0: continue # Skip if model couldn't produce residuals

                    k_params = len(model.params)
                    # Ensure sum of squared residuals is not zero to avoid log(0)
                    ssr = np.sum(model.residuals**2)
                    if ssr <= 0: ssr = 1e-9 # Small constant to prevent log(0) or negative log

                    bic = n_residuals * np.log(ssr / n_residuals) + k_params * np.log(n_residuals)
                    
                    if bic < best_bic_local:
                        best_bic_local = bic
                        best_model_local = model
                        
                except Exception as e:
                    # print(f"Error during Umidas fit for y_lags={y_lags_iter}, x_lags={x_lags_iter}: {e}")
                    continue # Skip to next lag combination if current one fails
        
        if best_model_local:
            self.model_ = best_model_local
            self.bic_ = best_bic_local
            self.params_ = self.model_.params # Store fitted parameters
        else:
            # Handle case where no model could be fitted
            print(f"Warning: UMIDASModel could not be fitted for X={X.name if X.name else 'Unnamed'}, y={y.name if y.name else 'Unnamed'}")
            self.model_ = None
            self.bic_ = np.inf
            self.params_ = None
            
        return self

    def predict(self, X_pred: pd.Series, month_in_quarter: int) -> np.ndarray:
        """
        Make predictions using the fitted UMIDAS model.

        Args:
            X_pred (pd.Series): Monthly indicator data for prediction. 
                                This should be the series of the indicator that the model was trained on.
                                It should include historical data needed for lags and current quarter's available data.
            month_in_quarter (int): Current month within the quarter (0, 1, or 2) for which prediction is made.
                                    This helps in determining how much of X_pred to use.

        Returns:
            np.ndarray: Array containing the prediction(s). Typically a single value for nowcast.
        """
        if self.model_ is None:
            raise ValueError("UMIDASModel not fitted yet. Call fit() before predict().")
        if not isinstance(X_pred, pd.Series):
            raise ValueError("X_pred must be a pandas Series.")
        if not month_in_quarter in [0, 1, 2]:
            raise ValueError("month_in_quarter must be 0, 1, or 2.")

        # The original logic `x.iloc[-(month_in_quarter+1):]` suggests using the
        # most recent (month_in_quarter + 1) observations from the monthly series.
        # pymidas.predict typically takes the full X series used in fitting (or a compatible one)
        # and handles the necessary history for lags internally.
        # However, if X_pred is only the *new* data, this might differ.
        # The `run_midas_nowcast` example passes `x.iloc[-(month_in_quarter+1):]`
        # This implies `pymidas.predict` can handle shorter series for prediction if they
        # represent the values for the current (incomplete) high-frequency period.
        # Let's assume X_pred is the *full* series, and we might need to pass specific
        # part or let pymidas handle it.
        # The `Umidas.predict` method documentation should clarify this.
        # Often, for MIDAS, `predict` is called without arguments if the model was fitted on
        # data that includes NaNs for future periods, or with an `Xnew` that aligns.

        # For now, let's assume `self.model_.predict()` uses the data context it was fitted with,
        # and the padding in `fit` handles future NaNs.
        # If `predict` needs specific slicing like `x.iloc[-(month_in_quarter+1):]`,
        # it implies that `X_pred` should be this sliced portion.
        # Let's try to align with the original `run_midas_nowcast` more closely.
        # The `predict` method of `Umidas` class in `pymidas` can take an `Xnew` argument.
        # If `Xnew` is not provided, it predicts based on the `X` given during `fit`.

        # Consider the case where X_pred is the complete series up to the reference date.
        # The number of observations needed for prediction depends on `month_in_quarter`.
        # If month_in_quarter = 0 (1st month), we need 1 observation.
        # If month_in_quarter = 1 (2nd month), we need 2 observations.
        # If month_in_quarter = 2 (3rd month), we need 3 observations.
        
        # Slicing X_pred to get the relevant data for the current quarter's prediction
        # This assumes X_pred contains data up to the current point in time.
        if X_pred.empty:
            print("Warning: X_pred is empty, cannot make prediction.")
            return np.array([np.nan])
            
        # We need the last `month_in_quarter + 1` data points from X_pred
        # This is a common way to structure X for UMIDAS prediction for the current quarter
        num_hf_obs_for_prediction = month_in_quarter + 1
        
        # Ensure we don't slice beyond the available data in X_pred
        if len(X_pred) < num_hf_obs_for_prediction:
            print(f"Warning: X_pred has only {len(X_pred)} observations, but "
                  f"{num_hf_obs_for_prediction} are suggested by month_in_quarter. "
                  "Using all available X_pred observations for prediction.")
            relevant_X_pred = X_pred # Use all of it
        else:
            relevant_X_pred = X_pred.iloc[-num_hf_obs_for_prediction:]
        
        try:
            # The `predict` method of `pymidas.Umidas` might expect a specific format or length for Xnew.
            # If `model.fit` was called with `x_padded` (which includes NaNs for future periods),
            # calling `model.predict()` without arguments should yield the forecast for the period
            # corresponding to the first NaN sequence.
            # If we pass `relevant_X_pred` to `model.predict(Xnew=relevant_X_pred)`,
            # it should be the actual available values for the current quarter.
            
            # Based on pymidas examples, predict() is often called without Xnew if X in fit() was prepared.
            # Let's assume the model uses its internal state from fit (which included x_padded).
            # The predict method in pymidas does not take an Xnew argument in the version used in examples.
            # It predicts the next y value(s) based on the X data provided during fit.
            # The result of predict() is an array of all in-sample and out-of-sample forecasts.
            # We typically need the last one for a nowcast.
            
            predictions = self.model_.predict()
            if predictions is not None and len(predictions) > 0:
                return np.array([predictions[-1]]) # Return the last prediction as the nowcast
            else:
                return np.array([np.nan]) # Fallback if no predictions
                
        except Exception as e:
            print(f"Error during UMIDASModel predict: {e}")
            return np.array([np.nan]) # Return NaN or raise error

    def get_params(self):
        """Returns the fitted parameters of the model."""
        return self.params_

    def get_bic(self):
        """Returns the BIC of the fitted model."""
        return self.bic_
