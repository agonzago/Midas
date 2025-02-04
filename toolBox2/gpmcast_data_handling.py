import pandas as pd
from datetime import datetime
from sklearn.experimental import enable_iterative_imputer
from sklearn.impute import IterativeImputer
import os 
from gpmcast_config import NowcastConfig


class NowcastData:
    """
    Handles data loading, transformations, and real-time alignment.
    Args:
        config (dict): Configuration object specifying transformations and paths.
    """
    def __init__(self, config):
        self.config = config

        # Validate file paths before loading data
        if not os.path.exists(self.config.raw_monthly_path):
            raise FileNotFoundError(f"Monthly data file not found: {self.config.raw_monthly_path}")
        if not os.path.exists(self.config.raw_gdp_path):
            raise FileNotFoundError(f"GDP data file not found: {self.config.raw_gdp_path}")

        # Load data only if paths are valid
        self.monthly_data = self._load_monthly_data()
        self.gdp_data = self._load_gdp_data()
        self.imputer = IterativeImputer()

    def _load_monthly_data(self) -> pd.DataFrame:
        """Load and preprocess raw monthly data."""
        df = pd.read_csv(self.config.raw_monthly_path, parse_dates=['date'])
        return df

    def _load_gdp_data(self) -> pd.DataFrame:
        """Load quarterly GDP data."""
        return pd.read_csv(self.config.raw_gdp_path, parse_dates=['date'])

    def _apply_transformations(self, df: pd.DataFrame) -> pd.DataFrame:
        """Apply variable-specific transformations."""
        processed = []
        for var, info in self.config["variable_info"].items():
            subset = df[df['variable'] == var].copy()

            # Seasonal Adjustment
            if info.get("seasonal_adjust", False):
                subset['value'] = self._seasonal_adjust(subset['value'])

            # Growth Rate
            if info.get("growth_rate", False):
                subset['value'] = subset['value'].pct_change() * 100

            # Standardization
            if info.get("standardize", False):
                subset['value'] = (subset['value'] - subset['value'].mean()) / subset['value'].std()

            processed.append(subset)
        return pd.concat(processed)

    def _seasonal_adjust(self, series: pd.Series) -> pd.Series:
        """Mock seasonal adjustment function."""
        # Replace with actual seasonal adjustment logic (e.g., X-13ARIMA-SEATS)
        return series - series.mean()

    def align_monthly_with_quarterly(self, monthly_df: pd.DataFrame, quarterly_df: pd.DataFrame) -> pd.DataFrame:
        """
        Align monthly data with quarterly GDP growth without aggregation.
        Args:
            monthly_df: DataFrame with monthly data.
            quarterly_df: DataFrame with quarterly GDP growth.
        Returns:
            DataFrame with aligned monthly and quarterly data.
        """
        # Assign each monthly observation to its corresponding quarter
        monthly_df['quarter'] = monthly_df['date'].dt.to_period("Q")
        quarterly_df['quarter'] = quarterly_df['date'].dt.to_period("Q")

        # Merge monthly data with quarterly GDP growth
        aligned_data = pd.merge(
            monthly_df,
            quarterly_df.rename(columns={'date': 'quarter'}),
            on='quarter',
            how='inner'
        )

        return aligned_data

    def get_real_time_features(self, nowcast_date: datetime) -> pd.DataFrame:
        """
        Get features available as of `nowcast_date` using the release calendar.
        Args:
            nowcast_date: The date for which the nowcast is being made.
        Returns:
            DataFrame with UMIDAS-style features.
        """
        # Filter data based on release dates
        available_data = self.monthly_data[
            self.monthly_data['release_date'] <= nowcast_date
        ]

        # Align with quarterly GDP growth
        aligned_data = self.align_monthly_with_quarterly(available_data, self.gdp_data)

        # Apply transformations
        transformed_data = self._apply_transformations(aligned_data)

        # Create UMIDAS features
        umidas_features = (
            transformed_data
            .assign(month=lambda x: x['date'].dt.month)  # Extract month number
            .pivot_table(
                index=['date', 'gdp_growth'],  # Quarterly date and target variable
                columns=['variable', 'month'],  # Variables and months
                values='value'
            )
            .reset_index()
        )

        # Flatten MultiIndex columns
        umidas_features.columns = [
            '_'.join(map(str, col)).strip() if isinstance(col, tuple) else col
            for col in umidas_features.columns.values
        ]

        return umidas_features

    def prepare_training_data(self, nowcast_date: datetime) -> tuple[pd.DataFrame, pd.Series]:
        """
        Generate training dataset with real-time vintages.
        Args:
            nowcast_date: The date for which the nowcast is being made.
        Returns:
            Tuple of (X, y) for training.
        """
        # Get real-time features
        features = self.get_real_time_features(nowcast_date)

        # Split into features and target
        X = features.drop(columns=['gdp_growth'])
        y = features['gdp_growth']

        # Impute missing values
        X_imputed = self.imputer.fit_transform(X)

        return pd.DataFrame(X_imputed, columns=X.columns), y
    


# # --- Start of Simulation Example ---
# from datetime import datetime
# import pandas as pd
# #from gpmcast_data_handling import NowcastData

# # Define configuration in Python (replacing JSON)
# config = {
#     "variable_info": {
#         "industrial_production": {"seasonal_adjust": True, "growth_rate": True},
#         "retail_sales_nominal": {"standardize": True},
#         "ipc": {"seasonal_adjust": False, "growth_rate": True}
#     },
#     "raw_monthly_path": "synthetic_monthly.csv",
#     "raw_gdp_path": "synthetic_gdp.csv"
# }

# # Initialize data handler
# data_handler = NowcastData(config)

# # Specify a nowcast date
# nowcast_date = datetime(2013, 6, 1)

# # Prepare training data
# X_train, y_train = data_handler.prepare_training_data(nowcast_date)

# # Print results
# print("Training Features (X):")
# print(X_train.head())
# print("\nTarget Variable (y):")
# print(y_train.head())
# # --- End of Simulation Example ---