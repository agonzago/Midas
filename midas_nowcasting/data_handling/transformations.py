# midas_nowcasting/data_handling/transformations.py
import numpy as np
import pandas as pd

def transformations(data: pd.DataFrame, trans_dict: dict) -> pd.DataFrame:
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
            # Optionally, print a warning or raise an error if a variable in trans_dict is not in data
            # print(f"Warning: Variable '{var}' specified in trans_dict not found in data.")
            continue
            
        series = data[var].copy()
        
        if trans == 'ldiff':
            # Ensure series is positive for log transformation
            if (series <= 0).any():
                # Handle non-positive values, e.g., by adding a small constant or skipping
                # print(f"Warning: Variable '{var}' contains non-positive values. Log difference not applied.")
                result[var] = np.nan # Or keep original, or other handling
                continue
            result[var] = np.log(series).diff()
        elif trans == 'diff':
            result[var] = series.diff()
        elif trans == 'dmean':
            result[var] = series - series.mean()
        elif trans == 'log':
            if (series <= 0).any():
                # print(f"Warning: Variable '{var}' contains non-positive values. Log not applied.")
                result[var] = np.nan
                continue
            result[var] = np.log(series)
        elif trans == 'dllog': # Demeaned log
            if (series <= 0).any():
                # print(f"Warning: Variable '{var}' contains non-positive values. Demeaned log not applied.")
                result[var] = np.nan
                continue
            log_series = np.log(series)
            result[var] = log_series - log_series.mean()
        elif trans == 'std': # Standardize
            result[var] = (series - series.mean()) / series.std()
        else:
            raise ValueError(f"Unknown transformation: '{trans}' for variable '{var}'. Supported transformations are 'diff', 'ldiff', 'dmean', 'log', 'dllog', 'std'")
    
    return result
