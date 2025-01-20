import pandas as pd
import numpy as np
from datetime import datetime, timedelta
from pymidas.midas import Umidas
import warnings
warnings.filterwarnings('ignore')

import pandas as pd
import numpy as np
from scipy import stats
from dataclasses import dataclass
from typing import Dict, List, Optional

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
            return 0.5
            
        f_direction = np.diff(self.forecasts)
        a_direction = np.diff(self.actuals)
        correct_dir = (f_direction * a_direction) > 0
        
        if window:
            correct_dir = correct_dir[-window:]
        return np.mean(correct_dir)

class ForecastCombiner:
    def __init__(self, forecast_history: Dict[str, ForecastHistory]):
        self.history = forecast_history
        
    def combine_bic(self, forecasts_df: pd.DataFrame) -> pd.Series:
        """Traditional BIC-based weights"""
        weights = 1 / forecasts_df['bic']
        return weights / weights.sum()
    
    def combine_rmse(self, forecasts_df: pd.DataFrame, window: Optional[int] = None) -> pd.Series:
        """RMSE-based weights with optional rolling window"""
        rmse_values = pd.Series({
            ind: self.history[ind].calculate_rmse(window)
            for ind in forecasts_df['indicator']
        })
        weights = 1 / rmse_values
        return weights / weights.sum()
    
    def combine_performance_rank(self, forecasts_df: pd.DataFrame) -> pd.Series:
        """Combine multiple performance metrics using rank-based weights"""
        indicators = forecasts_df['indicator']
        
        # Calculate multiple performance metrics
        rmse_rank = pd.Series({
            ind: self.history[ind].calculate_rmse()
            for ind in indicators
        }).rank()
        
        mae_rank = pd.Series({
            ind: self.history[ind].calculate_mae()
            for ind in indicators
        }).rank()
        
        dir_acc_rank = pd.Series({
            ind: -self.history[ind].calculate_directional_accuracy()  # Negative so lower rank is better
            for ind in indicators
        }).rank()
        
        # Combine ranks
        combined_rank = rmse_rank + mae_rank + dir_acc_rank
        weights = 1 / combined_rank
        return weights / weights.sum()
    
    def combine_adaptive(self, forecasts_df: pd.DataFrame, window: int = 4) -> pd.Series:
        """Adaptive weights based on recent performance"""
        indicators = forecasts_df['indicator']
        recent_rmse = pd.Series({
            ind: self.history[ind].calculate_rmse(window)
            for ind in indicators
        })
        
        recent_dir_acc = pd.Series({
            ind: self.history[ind].calculate_directional_accuracy(window)
            for ind in indicators
        })
        
        # Combine metrics with time-varying weights
        rmse_weight = 0.7  # Base weight for RMSE
        dir_weight = 0.3   # Base weight for directional accuracy
        
        # Adjust weights based on volatility
        if len(self.history[indicators[0]].actuals) >= window:
            volatility = np.std(self.history[indicators[0]].actuals[-window:])
            # In high volatility periods, increase weight on directional accuracy
            if volatility > np.median(self.history[indicators[0]].actuals):
                rmse_weight = 0.5
                dir_weight = 0.5
        
        combined_score = (rmse_weight / recent_rmse) + (dir_weight * recent_dir_acc)
        return combined_score / combined_score.sum()
    
    def combine_thick_modeling(self, forecasts_df: pd.DataFrame, n_models: int = 5) -> pd.Series:
        """Thick modeling approach - average of top N models"""
        indicators = forecasts_df['indicator']
        rmse_values = pd.Series({
            ind: self.history[ind].calculate_rmse()
            for ind in indicators
        })
        
        # Select top N models
        top_n = rmse_values.nsmallest(n_models).index
        weights = pd.Series(0, index=indicators)
        weights[top_n] = 1/n_models
        return weights
    
    def combine_regression_based(self, forecasts_df: pd.DataFrame, window: int = 8) -> pd.Series:
        """Regression-based combination weights"""
        indicators = forecasts_df['indicator']
        
        # Get historical forecasts and actuals for regression
        X = []  # Historical forecasts
        y = []  # Actual values
        
        for ind in indicators:
            hist = self.history[ind]
            if len(hist.forecasts) < window:
                # Not enough history, use equal weights
                return pd.Series(1/len(indicators), index=indicators)
            X.append(hist.forecasts[-window:])
            y = hist.actuals[-window:]
            
        X = np.array(X).T  # Transform to (n_samples, n_features)
        
        try:
            # Ridge regression to avoid perfect multicollinearity
            from sklearn.linear_model import Ridge
            model = Ridge(alpha=1.0)
            model.fit(X, y)
            weights = model.coef_
            # Ensure weights are positive and sum to 1
            weights = np.maximum(weights, 0)
            return pd.Series(weights / weights.sum(), index=indicators)
        except:
            # Fallback to equal weights if regression fails
            return pd.Series(1/len(indicators), index=indicators)

def update_forecast_history(history: Dict[str, ForecastHistory],
                          new_forecasts: pd.DataFrame,
                          actual_gdp: float,
                          forecast_date: pd.Timestamp) -> Dict[str, ForecastHistory]:
    """Update forecast history with new forecasts and actual GDP"""
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

# Example usage:
"""
# Initialize forecast history
forecast_history = {}

# After each GDP release, update history
forecast_history = update_forecast_history(
    history=forecast_history,
    new_forecasts=previous_quarter_forecasts,
    actual_gdp=actual_gdp_value,
    forecast_date=forecast_date
)

# Create combiner
combiner = ForecastCombiner(forecast_history)

# Get weights using different strategies
weights_bic = combiner.combine_bic(current_forecasts)
weights_rmse = combiner.combine_rmse(current_forecasts, window=4)
weights_rank = combiner.combine_performance_rank(current_forecasts)
weights_adaptive = combiner.combine_adaptive(current_forecasts)
weights_thick = combiner.combine_thick_modeling(current_forecasts)
weights_regression = combiner.combine_regression_based(current_forecasts)

# Calculate combined forecasts
final_forecast = {
    'bic': (current_forecasts['forecast'] * weights_bic).sum(),
    'rmse': (current_forecasts['forecast'] * weights_rmse).sum(),
    'rank': (current_forecasts['forecast'] * weights_rank).sum(),
    'adaptive': (current_forecasts['forecast'] * weights_adaptive).sum(),
    'thick': (current_forecasts['forecast'] * weights_thick).sum(),
    'regression': (current_forecasts['forecast'] * weights_regression).sum()
}
"""

class GDPData:
    def __init__(self, historical_gdp, last_forecast=None):
        """
        Initialize GDP data handler
        
        Parameters:
        historical_gdp: pandas Series with historical GDP data
        last_forecast: float, the forecast made for previous quarter (if current quarter GDP not yet released)
        """
        self.historical_gdp = historical_gdp
        self.last_forecast = last_forecast
        
    def get_gdp_series(self, reference_date):
        """
        Get GDP series including provisional value for previous quarter if needed
        """
        gdp_series = self.historical_gdp.copy()
        
        # If we're before GDP release (typically before end of first month)
        # and we have a forecast for previous quarter, use it
        if reference_date.month % 3 == 1 and reference_date.day < 25:  # Assuming GDP releases around 25th
            if self.last_forecast is not None:
                gdp_series.iloc[-1] = self.last_forecast
                
        return gdp_series

class DataCalendar:
    def __init__(self):
        # Define release schedules for Mexican indicators
        self.mex_releases = {
            'business_confidence': {'week': 1, 'day': 3},
            'business_trend': {'week': 1, 'day': 3},
            'manufacturing_orders': {'week': 1, 'day': 3},
            'consumer_confidence': {'week': 1, 'day': 6},
            'vehicle_sales': {'week': 1, 'day': 6},
            'industrial_activity': {'week': 2, 'day': 11},
            'manufacturing_survey': {'week': 3, 'day': 16},
            'services_survey': {'week': 3, 'day': 21},
            'commercial_survey': {'week': 3, 'day': 21},
            'construction_survey': {'week': 4, 'day': 24},
            'private_consumption': {'week': 1, 'day': 15},
            'fixed_capital': {'week': 1, 'day': 15},
            'trade_balance_prelim': {'week': 4, 'day': 27},
            'employment_monthly': {'week': 4, 'day': 28},
        }
        
        # Define release schedules for US indicators
        self.us_releases = {
            'ism_manufacturing': {'week': 1, 'day': 1},
            'nonfarm_payrolls': {'week': 1, 'day': 5},  # First Friday
            'retail_sales': {'week': 2, 'day': 15},
            'industrial_production': {'week': 2, 'day': 16},
            'consumer_confidence': {'week': 4, 'day': -1},  # Last Tuesday
        }

    def get_available_indicators(self, reference_date):
        """Determine which indicators should be available given the reference date"""
        available = []
        
        # Calculate week of month
        first_day = reference_date.replace(day=1)
        week_of_month = (reference_date.day-1) // 7 + 1
        
        # Check Mexican indicators
        for indicator, schedule in self.mex_releases.items():
            if (week_of_month > schedule['week'] or 
                (week_of_month == schedule['week'] and reference_date.day >= schedule['day'])):
                available.append(indicator)
        
        # Check US indicators
        for indicator, schedule in self.us_releases.items():
            if (week_of_month > schedule['week'] or 
                (week_of_month == schedule['week'] and reference_date.day >= schedule['day'])):
                available.append(f"us_{indicator}")
                
        return available

def determine_target_quarter(reference_date):
    """
    Determine which quarter we're forecasting
    
    Parameters:
    reference_date: datetime object
    
    Returns:
    target_quarter: int (1-4)
    target_year: int
    current_month_in_quarter: int (0-2, where 0 is first month)
    """
    month = reference_date.month
    current_quarter = (month - 1) // 3 + 1
    current_month_in_quarter = (month - 1) % 3
    
    # We're always forecasting the current quarter
    target_quarter = current_quarter
    target_year = reference_date.year
    
    return target_quarter, target_year, current_month_in_quarter

def run_midas_nowcast(y_quarterly, x_monthly, month_in_quarter, max_y_lags=4, max_x_lags=6):
    """Run MIDAS nowcast for a single indicator"""
    # Add NaN for future months in current quarter
    months_ahead = 2 - month_in_quarter
    if months_ahead > 0:
        x_padded = pd.concat([x_monthly, 
                            pd.Series([np.nan] * months_ahead, 
                                    index=pd.date_range(x_monthly.index[-1] + pd.DateOffset(months=1), 
                                                      periods=months_ahead, 
                                                      freq='M'))])
    else:
        x_padded = x_monthly.copy()

    best_bic = np.inf
    best_model = None
    
    # Grid search over lag combinations
    for y_lags in range(max_y_lags + 1):
        for x_lags in range(max_x_lags + 1):
            try:
                model = Umidas(y_quarterly, x_padded, 
                             m=3,           # Monthly to quarterly ratio
                             k=x_lags,      # High-frequency lags
                             ylag=y_lags,   # Low-frequency lags
                             optim='ols')
                
                model.fit()
                
                # Calculate BIC
                n = len(model.residuals)
                k = len(model.params)
                bic = n * np.log(np.sum(model.residuals**2)/n) + k * np.log(n)
                
                if bic < best_bic:
                    best_bic = bic
                    best_model = model
                    
            except Exception as e:
                continue
                
    return best_model, {'bic': best_bic}

def run_weekly_nowcast(gdp_data, x_monthly_dict, reference_date):
    """
    Run nowcast for current quarter based on weekly data availability
    
    Parameters:
    gdp_data: GDPData object containing historical and provisional GDP
    x_monthly_dict: dictionary of monthly indicators
    reference_date: datetime object representing the current date
    """
    # Get GDP series (including provisional value if needed)
    y_quarterly = gdp_data.get_gdp_series(reference_date)
    
    # Initialize calendar
    calendar = DataCalendar()
    
    # Get available indicators
    available_indicators = calendar.get_available_indicators(reference_date)
    
    # Determine target quarter and current month in quarter
    target_quarter, target_year, month_in_quarter = determine_target_quarter(reference_date)
    
    results = []
    
    # Process available indicators
    for indicator in available_indicators:
        if indicator in x_monthly_dict:
            x = x_monthly_dict[indicator]
            model, params = run_midas_nowcast(y_quarterly, x, month_in_quarter)
            
            if model is not None:
                # Use available months for current quarter
                forecast = model.predict(x.iloc[-(month_in_quarter+1):])
                results.append({
                    'indicator': indicator,
                    'forecast': forecast[-1],
                    'bic': params['bic']
                })
    
    # Calculate weighted forecast
    if results:
        results_df = pd.DataFrame(results)
        weights = 1/results_df['bic']
        weights = weights/weights.sum()
        weighted_forecast = (results_df['forecast'] * weights).sum()
        
        return weighted_forecast, results_df.assign(weight=weights)
    else:
        return None, None

def create_nowcast_report(gdp_data, x_monthly_dict, reference_date):
    """Create a complete nowcast report"""
    # Run nowcast
    forecast, details = run_weekly_nowcast(gdp_data, x_monthly_dict, reference_date)
    
    if forecast is None:
        return {
            'status': 'No indicators available',
            'reference_date': reference_date,
            'forecast': None,
            'details': None
        }
    
    # Get target quarter info
    target_quarter, target_year, month_in_quarter = determine_target_quarter(reference_date)
    
    # Calculate quarter progress
    quarter_progress = ((month_in_quarter + 1) / 3) * 100
    
    # Get available indicators
    calendar = DataCalendar()
    available = calendar.get_available_indicators(reference_date)
    
    return {
        'status': 'success',
        'reference_date': reference_date,
        'target_quarter': target_quarter,
        'target_year': target_year,
        'forecast': forecast,
        'quarter_progress': quarter_progress,
        'available_indicators': available,
        'details': details
    }

# Example usage:
"""
# Initialize with historical GDP and last quarter's forecast
gdp_data = GDPData(
    historical_gdp=pd.Series(...),  # Historical GDP data
    last_forecast=2.5  # Last quarter's forecast (if needed)
)

# Monthly indicator data
x_monthly_dict = {
    'business_confidence': pd.Series(...),
    'industrial_activity': pd.Series(...),
    # ... other indicators
}

# Run nowcast for current date
reference_date = datetime.now()
report = create_nowcast_report(gdp_data, x_monthly_dict, reference_date)

# Print results
if report['status'] == 'success':
    print(f"GDP Nowcast for Q{report['target_quarter']} {report['target_year']}: {report['forecast']:.2f}%")
    print(f"Quarter Progress: {report['quarter_progress']:.1f}%")
    print("\nContributing Indicators:")
    print(report['details'])
else:
    print("No indicators available for nowcast")
"""
#%%
import pandas as pd
import os
import matplotlib.pyplot as plt
import numpy as np

# Get the directory of the current script
current_dir = os.path.dirname(os.path.abspath(__file__))

# Set the working directory to the script's directory
os.chdir(current_dir)

# Verify the working directory
print("Current Working Directory:", os.getcwd())

mex_M = pd.read_csv("mex_M.csv", index_col=0, parse_dates=True)
mex_Q = pd.read_csv("mex_Q.csv", index_col=0, parse_dates=True)

monthly_indicators = mex_M.columns[0:11]

def transformations(data, trans_dict):
    """
    Apply transformations to specified variables in a DataFrame
    
    Parameters:
    -----------
    data : pd.DataFrame
        Input DataFrame with time index
    trans_dict : dict
        Dictionary mapping variables to transformation types
        e.g. {'GDP': 'ldiff', 'Inflation': 'diff'}
        Supported transforms: 'diff', 'ldiff' (log+diff), 'dmean', 'log', 'dllog', 'std'
    
    Returns:
    --------
    pd.DataFrame
        DataFrame with transformed variables
    """
    # Start with a copy of the original data
    result = data.copy()
    
    # Only transform the variables specified in trans_dict
    for var, trans in trans_dict.items():
        if var not in data.columns:
            continue
            
        series = data[var].copy()
        
        if trans == 'ldiff':
            result[var] = np.log(series).diff()
        elif trans == 'diff':
            result[var] = series.diff()
        elif trans == 'dmean':
            result[var] = series - series.mean()
        elif trans == 'log':
            result[var] = np.log(series)
        elif trans == 'dllog':
            result[var] = np.log(series) - np.mean(np.log(series))
        elif trans == 'std':
            result[var] = (series - series.mean())/series.std()
        else:
            raise ValueError(f"Unknown transformation: available transformations are 'diff', 'ldiff', 'dmean', 'log', 'dllog', 'std'")
    
    return result



def plot_combined_series(monthly_data, quarterly_data, variables):
    """
    Plot monthly and quarterly series together, normalized around quarterly mean
    
    Parameters:
    -----------
    monthly_data : pd.DataFrame
        Monthly data with datetime index
    quarterly_data : pd.DataFrame
        Quarterly data with datetime index
    variables : dict
        Dictionary with two keys: 'monthly' and 'quarterly', containing the names
        of variables to plot from each dataset
        e.g., {'monthly': 'EAI', 'quarterly': 'GDP'}
    
    Returns:
    --------
    fig, ax : matplotlib figure and axis objects
    """
    # Create figure and axis
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Get the series
    monthly_series = monthly_data[variables['monthly']]
    quarterly_series = quarterly_data[variables['quarterly']]
    
    # Calculate quarterly mean for normalization
    q_mean = quarterly_series.mean()
    
    # Normalize monthly series around quarterly mean
    monthly_scale = quarterly_series.std() / monthly_series.std()
    monthly_adjusted = (monthly_series - monthly_series.mean()) * monthly_scale + q_mean
    
    # Plot both series
    ax.plot(monthly_data.index, monthly_adjusted,
            color='blue', linewidth=1, 
            label=f'{variables["monthly"]} (Monthly)')
    
    ax.scatter(quarterly_data.index, quarterly_series,
               color='red', s=30, 
               label=f'{variables["quarterly"]} (Quarterly)')
    
    # Customize the plot
    ax.set_title(f'{variables["monthly"]} (Monthly) vs {variables["quarterly"]} (Quarterly)')
    ax.grid(True, linestyle='--', alpha=0.7)
    ax.legend(loc='upper left')
    
    # Rotate x-axis labels for better readability
    plt.xticks(rotation=45)
    
    # Adjust layout to prevent label cutoff
    plt.tight_layout()
    
    return fig, ax

def create_comparison_report(monthly_data, quarterly_data, monthly_vars, quarterly_var):
    """
    Create a multi-panel figure comparing multiple monthly variables with a quarterly variable
    
    Parameters:
    -----------
    monthly_data : pd.DataFrame
        Monthly data with datetime index
    quarterly_data : pd.DataFrame
        Quarterly data with datetime index
    monthly_vars : list
        List of monthly variables to compare
    quarterly_var : str
        Name of quarterly variable to compare against
    """
    # Set up the subplot grid
    n_plots = len(monthly_vars)
    fig = plt.figure(figsize=(15, 4*n_plots))
    
    # Create each subplot
    for i, monthly_var in enumerate(monthly_vars, 1):
        ax = fig.add_subplot(n_plots, 1, i)
        
        # Get the series
        monthly_series = monthly_data[monthly_var]
        quarterly_series = quarterly_data[quarterly_var]
        
        # Calculate quarterly mean for normalization
        q_mean = quarterly_series.mean()
        
        # Normalize monthly series around quarterly mean
        monthly_scale = quarterly_series.std() / monthly_series.std()
        monthly_adjusted = (monthly_series - monthly_series.mean()) * monthly_scale + q_mean
        
        # Plot both series
        ax.plot(monthly_data.index, monthly_adjusted,
                color='blue', linewidth=1, 
                label=f'{monthly_var} (Monthly)')
        
        ax.scatter(quarterly_data.index, quarterly_series,
                   color='red', s=30, 
                   label=f'{quarterly_var} (Quarterly)')
        
        # Customize the subplot
        ax.set_title(f'{monthly_var} vs {quarterly_var}')
        ax.grid(True, linestyle='--', alpha=0.7)
        ax.legend(loc='upper left')
        plt.setp(ax.get_xticklabels(), rotation=45)
    
    plt.tight_layout()
    return fig


# Define transformations if needed
trans_dict = {
    'GDP': 'ldiff',
    'EAI': 'ldiff', 
    #'GVFI': 'ldiff', 
    'PMI_M' : 'dmean',  
    'PMI_NM': 'dmean',  
    'RETSALES': 'ldiff', 
    'RETGRO': 'ldiff',
    'RETSUP': 'ldiff',
    'RETTEXT': 'ldiff',
    'RETPERF': 'ldiff',
    'RETFURN': 'ldiff',
    'RETCAR': 'ldiff'
}

# First, let's filter both datasets to start from 2008
start_date_q = '2020-01-01'  # This will capture 2008Q1
start_date_m = '2020-01-01'  # This will capture 2008M1

# Filter the transformed data
transformed_m_data = transformations(mex_M, trans_dict)[start_date_m:]
transformed_q_data = transformations(mex_Q, trans_dict)[start_date_q:]

# Create the report
monthly_vars = ['EAI', 'PMI_M', 'PMI_NM', 'RETSALES', 'RETGRO', 'RETSUP', 'RETTEXT', 'RETPERF', 'RETFURN', 'RETCAR']
fig = create_comparison_report(transformed_m_data, transformed_q_data, 
                             monthly_vars, 'GDP')


import pandas as pd
import numpy as np
from datetime import datetime
import matplotlib.pyplot as plt
from dataclasses import dataclass
from typing import Dict, List, Optional

def load_and_prepare_data():
    """Load and prepare Mexican data for nowcasting"""
    # Read the data
    mex_m = pd.read_csv('mex_M.csv', index_col=0, parse_dates=True)
    mex_q = pd.read_csv('mex_Q.csv', index_col=0, parse_dates=True)
    
    # Select base indicators (before transformations)
    monthly_indicators = [
        'EAI',      # Economic Activity Index
        'PMI_M',    # Manufacturing PMI
        'PMI_NM',   # Non-Manufacturing PMI
        'RETSALES', # Retail Sales
        'RETGRO',   # Retail Groceries
        'RETSUP',   # Retail Supermarkets
        'RETTEXT',  # Retail Textiles
        'RETPERF',  # Retail Personal Care
        'RETFURN',  # Retail Furniture
        'RETCAR'    # Retail Vehicles
    ]
    
    # Create dictionary of monthly indicators
    x_monthly_dict = {
        ind: mex_m[ind] for ind in monthly_indicators
    }
    
    # Get GDP series
    y_quarterly = mex_q['GDP']
    
    return x_monthly_dict, y_quarterly

class MexicoDataCalendar(DataCalendar):
    def __init__(self):
        super().__init__()
        # Update release schedules for available Mexican indicators
        self.mex_releases = {
            'EAI': {'week': 4, 'day': 22},        # IGAE
            'PMI_M': {'week': 1, 'day': 3},       # Manufacturing PMI
            'PMI_NM': {'week': 1, 'day': 3},      # Non-Manufacturing PMI
            'RETSALES': {'week': 3, 'day': 21},   # Retail Sales
            'RETGRO': {'week': 3, 'day': 21},     # Retail Groceries
            'RETSUP': {'week': 3, 'day': 21},     # Retail Supermarkets
            'RETTEXT': {'week': 3, 'day': 21},    # Retail Textiles
            'RETPERF': {'week': 3, 'day': 21},    # Retail Personal Care
            'RETFURN': {'week': 3, 'day': 21},    # Retail Furniture
            'RETCAR': {'week': 3, 'day': 21},     # Retail Vehicles
        }

def run_example_nowcast():
    """Run a complete nowcast example"""
    # Load data
    x_monthly_dict, y_quarterly = load_and_prepare_data()
    
    # Initialize GDP data handler with last quarter's forecast
    gdp_data = GDPData(
        historical_gdp=y_quarterly,
        last_forecast=2.1  # Example forecast from previous quarter
    )
    
    # Initialize forecast history
    forecast_history = {}
    
    # Set reference date
    reference_date = datetime(2025, 1, 15)  # Middle of January 2025
    
    # Create nowcast report
    report = create_nowcast_report(gdp_data, x_monthly_dict, reference_date)
    
    # Initialize forecast combiner with different weighting strategies
    combiner = ForecastCombiner(forecast_history)
    
    if report['status'] == 'success':
        # Get weights using different strategies
        forecasts_df = report['details']
        weights_bic = combiner.combine_bic(forecasts_df)
        weights_thick = combiner.combine_thick_modeling(forecasts_df, n_models=3)
        
        # Calculate combined forecasts
        forecast_bic = (forecasts_df['forecast'] * weights_bic).sum()
        forecast_thick = (forecasts_df['forecast'] * weights_thick).sum()
        
        # Print results
        print(f"\nNowcast Report for {reference_date.strftime('%Y-%m-%d')}")
        print(f"Target: Q{report['target_quarter']} {report['target_year']}")
        print(f"Quarter Progress: {report['quarter_progress']:.1f}%")
        print("\nAvailable Indicators:")
        for ind in report['available_indicators']:
            print(f"- {ind}")
        
        print("\nForecasts:")
        print(f"BIC-weighted: {forecast_bic:.2f}%")
        print(f"Thick Modeling: {forecast_thick:.2f}%")
        
        print("\nIndicator Details:")
        print(forecasts_df[['indicator', 'forecast', 'weight']])
    else:
        print("No indicators available for nowcast")

if __name__ == "__main__":
    run_example_nowcast()