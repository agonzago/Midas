# --- Start of gpmcast_config.py ---
from dataclasses import dataclass
import pandas as pd
import json

@dataclass
class NowcastConfig:
    """
    Configuration for the nowcasting system.
    
    Attributes:
        variable_info (dict): Metadata for variables (unit, SA, transformations).
        release_calendar (pd.DataFrame): Release dates for each variable/month.
        raw_monthly_path (str): Path to raw monthly data.
        raw_gdp_path (str): Path to quarterly GDP data.
    """
    variable_info: dict
    release_calendar: pd.DataFrame
    raw_monthly_path: str
    raw_gdp_path: str

    @classmethod
    def from_json(cls, config_path: str):
        """Load configuration from a JSON file."""
        with open(config_path, 'r') as f:
            config = json.load(f)
        return cls(
            variable_info=config["variable_info"],
            release_calendar=pd.DataFrame(config["release_calendar"]),
            raw_monthly_path=config["raw_monthly_path"],
            raw_gdp_path=config["raw_gdp_path"]
        )
# --- End of gpmcast_config.py ---

# --- Start of gopmcast_models.py ---
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
# --- End of gopmcast_models.py ---

# --- Start of gpmcast_data_handling.py ---
import pandas as pd
from datetime import datetime, timedelta
from sklearn.experimental import enable_iterative_imputer
from sklearn.impute import IterativeImputer

class NowcastData:
    """
    Handles data loading, transformations, and real-time alignment.
    
    Args:
        config (NowcastConfig): Configuration object.
    """
    def __init__(self, config: NowcastConfig):
        self.config = config
        self.monthly_data = self._load_monthly_data()
        self.gdp_data = self._load_gdp_data()
        self.imputer = IterativeImputer()

    def _load_monthly_data(self) -> pd.DataFrame:
        """Load and preprocess raw monthly data."""
        df = pd.read_csv(self.config.raw_monthly_path, parse_dates=['date'])
        # Add transformations here if needed (e.g., date alignment)
        return df

    def _load_gdp_data(self) -> pd.DataFrame:
        """Load quarterly GDP data."""
        return pd.read_csv(self.config.raw_gdp_path, parse_dates=['date'])

    def _apply_transformations(self, df: pd.DataFrame) -> pd.DataFrame:
        """Apply variable-specific transformations (SA, growth rates, etc.)."""
        processed = []
        for var, info in self.config.variable_info.items():
            subset = df[df['variable'] == var].copy()
            # Seasonal adjustment
            if info['sa']:
                subset['value'] = self._seasonal_adjust(subset['value'])
            # Nominal to real conversion
            if 'convert_to_real' in info['transformation']:
                subset['value'] = self._convert_to_real(subset)
            # Other transformations (growth rates, standardization)
            subset = self._apply_custom_transforms(subset, info['transformation'])
            processed.append(subset)
        return pd.concat(processed)

    def get_real_time_features(self, nowcast_date: datetime) -> pd.DataFrame:
        """
        Get features available as of `nowcast_date` using the release calendar.
        
        Returns:
            DataFrame with features aligned to quarters (with NaNs for missing data).
        """
        # Logic to check release calendar and filter available data
        # (Implementation similar to earlier get_available_data() function)
        # ...
        return processed_features

    def prepare_training_data(self) -> tuple[pd.DataFrame, pd.Series]:
        """Generate training dataset with real-time vintages."""
        # Logic to simulate historical nowcast runs
        # ...
        X_imputed = self.imputer.fit_transform(X)
        return X_imputed, y
# --- End of gpmcast_data_handling.py ---

# --- Start of gpmcast_models.py ---
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
# --- End of gpmcast_models.py ---

# --- Start of generate_data.py ---
import pandas as pd
import numpy as np

# Generate monthly data (2010-01 to 2013-12)
dates = pd.date_range("2010-01-01", "2013-12-31", freq="MS")
variables = ["industrial_production", "retail_sales_nominal", "ipc"]

monthly_data = []
for date in dates:
    for var in variables:
        value = np.random.normal(loc=100, scale=5)  # Synthetic data
        monthly_data.append({"date": date, "variable": var, "value": value})

monthly_df = pd.DataFrame(monthly_data)

# Generate quarterly GDP growth (mocked relationship)
quarters = monthly_df["date"].dt.to_period("Q").unique()
gdp = []
for q in quarters:
    # GDP depends on industrial_production + retail_sales (mock relationship)
    ip = monthly_df[
        (monthly_df["variable"] == "industrial_production") & 
        (monthly_df["date"].dt.to_period("Q") == q)
    ]["value"].mean()
    
    rs = monthly_df[
        (monthly_df["variable"] == "retail_sales_nominal") & 
        (monthly_df["date"].dt.to_period("Q") == q)
    ]["value"].mean()
    
    gdp_growth = 0.5 * (ip - 100) + 0.3 * (rs - 100) + np.random.normal(0, 0.5)
    gdp.append({"date": q.end_time, "gdp_growth": gdp_growth})

gdp_df = pd.DataFrame(gdp)

# Save to CSV
monthly_df.to_csv("synthetic_monthly.csv", index=False)
gdp_df.to_csv("synthetic_gdp.csv", index=False)
# --- End of generate_data.py ---

# --- Start of test_gpmcast.py ---
from datetime import datetime
import json
import pandas as pd
from sklearn.linear_model import LinearRegression
from config import NowcastConfig
from data_handler import NowcastData
from model import NowcastModel

# Load config
config = NowcastConfig.from_json("config.json")

# Initialize data handler
data = NowcastData(config)

# Check processed data
print("Processed monthly data sample:")
print(data.monthly_data.head())

# Check GDP data
print("\nGDP data sample:")
print(data.gdp_data.head())

# Prepare training data
X_train, y_train = data.prepare_training_data()
print(f"\nTraining data shape: {X_train.shape}")

# Train simple model
model = NowcastModel({"UMIDAS": LinearRegression()})
model.train(X_train, y_train)

# Generate summary
print("\nModel Performance Summary:")
print(model.summary_table())

# Plot variables vs GDP
data.plot_variable_vs_gdp("industrial_production", start_date="2010-01-01")
# --- End of test_gpmcast.py ---

