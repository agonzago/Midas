# midas_nowcasting/reporting/charts.py
import pandas as pd
import matplotlib.pyplot as plt
import numpy as np # Added for general plotting utilities, though not directly in new functions

def plot_variable_vs_target(
    transformed_monthly_data: pd.DataFrame,
    target_data: pd.DataFrame,
    variable_name: str,
    target_name: str = 'Target',
    start_date: str = None,
    end_date: str = None
) -> None:
    """
    Plots a transformed monthly variable against a quarterly/annual target variable.

    Args:
        transformed_monthly_data (pd.DataFrame): DataFrame with monthly data. 
                                                 Expected columns: 'date', 'variable', 'value'.
        target_data (pd.DataFrame): DataFrame with target variable data.
                                    Expected columns: 'date', 'value'.
        variable_name (str): The name of the monthly variable to plot from transformed_monthly_data.
        target_name (str): The name of the target variable for labeling.
        start_date (str, optional): Start date for the plot (YYYY-MM-DD).
        end_date (str, optional): End date for the plot (YYYY-MM-DD).
    """
    
    # Filter monthly variable data
    var_series_df = transformed_monthly_data[
        transformed_monthly_data['variable'] == variable_name
    ].copy()
    var_series_df['date'] = pd.to_datetime(var_series_df['date'])
    var_series = var_series_df.set_index('date')['value']

    # Filter target data
    target_series_df = target_data.copy()
    target_series_df['date'] = pd.to_datetime(target_series_df['date'])
    target_series = target_series_df.set_index('date')['value']

    if start_date:
        var_series = var_series[var_series.index >= pd.to_datetime(start_date)]
        target_series = target_series[target_series.index >= pd.to_datetime(start_date)]
    if end_date:
        var_series = var_series[var_series.index <= pd.to_datetime(end_date)]
        target_series = target_series[target_series.index <= pd.to_datetime(end_date)]

    fig, ax = plt.subplots(figsize=(12, 6))
    
    ax.plot(var_series.index, var_series, 'b-', lw=1.5, 
            label=f"{variable_name} (transformed)")
    
    ax.scatter(target_series.index, target_series, color='red', s=70, 
               label=f"{target_name}", zorder=5)
    
    ax.axhline(0, color='k', linestyle='--', alpha=0.5)
    ax.set_title(f"{variable_name} vs. {target_name}", fontsize=14)
    ax.set_xlabel("Date", fontsize=12)
    ax.set_ylabel("Value", fontsize=12) 
    ax.legend()
    plt.grid(True, alpha=0.3)
    plt.show()


# --- Functions from umidas_mexico.py ---

def plot_combined_series(monthly_data: pd.DataFrame, quarterly_data: pd.DataFrame, variables: dict):
    """
    Plot monthly and quarterly series together, normalized around quarterly mean.
    
    Parameters:
    -----------
    monthly_data : pd.DataFrame
        Monthly data with datetime index.
    quarterly_data : pd.DataFrame
        Quarterly data with datetime index.
    variables : dict
        Dictionary with two keys: 'monthly' and 'quarterly', containing the names
        of variables to plot from each dataset.
        e.g., {'monthly': 'EAI', 'quarterly': 'GDP'}
    
    Returns:
    --------
    fig, ax : matplotlib figure and axis objects
    """
    # Create figure and axis
    fig, ax = plt.subplots(figsize=(12, 6))
    
    # Get the series
    monthly_variable_name = variables.get('monthly')
    quarterly_variable_name = variables.get('quarterly')

    if not monthly_variable_name or monthly_variable_name not in monthly_data.columns:
        print(f"Monthly variable '{monthly_variable_name}' not found in monthly_data.")
        return None, None
    if not quarterly_variable_name or quarterly_variable_name not in quarterly_data.columns:
        print(f"Quarterly variable '{quarterly_variable_name}' not found in quarterly_data.")
        return None, None
        
    monthly_series = monthly_data[monthly_variable_name]
    quarterly_series = quarterly_data[quarterly_variable_name]
    
    # Calculate quarterly mean for normalization
    q_mean = quarterly_series.mean()
    q_std = quarterly_series.std()
    m_std = monthly_series.std()

    if q_std == 0 or m_std == 0: # Avoid division by zero if standard deviation is zero
        monthly_scale = 1.0
    else:
        monthly_scale = q_std / m_std
        
    monthly_adjusted = (monthly_series - monthly_series.mean()) * monthly_scale + q_mean
    
    # Plot both series
    ax.plot(monthly_data.index, monthly_adjusted,
            color='blue', linewidth=1, 
            label=f'{monthly_variable_name} (Monthly, Adjusted)')
    
    ax.scatter(quarterly_data.index, quarterly_series,
               color='red', s=30, 
               label=f'{quarterly_variable_name} (Quarterly)')
    
    # Customize the plot
    ax.set_title(f'{monthly_variable_name} (Monthly) vs {quarterly_variable_name} (Quarterly)')
    ax.grid(True, linestyle='--', alpha=0.7)
    ax.legend(loc='upper left')
    
    # Rotate x-axis labels for better readability
    plt.xticks(rotation=45)
    
    # Adjust layout to prevent label cutoff
    plt.tight_layout()
    
    return fig, ax

def create_comparison_report(monthly_data: pd.DataFrame, quarterly_data: pd.DataFrame, 
                             monthly_vars: list, quarterly_var: str):
    """
    Create a multi-panel figure comparing multiple monthly variables with a quarterly variable.
    
    Parameters:
    -----------
    monthly_data : pd.DataFrame
        Monthly data with datetime index.
    quarterly_data : pd.DataFrame
        Quarterly data with datetime index.
    monthly_vars : list
        List of monthly variables to compare.
    quarterly_var : str
        Name of quarterly variable to compare against.
    """
    if quarterly_var not in quarterly_data.columns:
        print(f"Quarterly variable '{quarterly_var}' not found in quarterly_data.")
        return None

    # Set up the subplot grid
    n_plots = len(monthly_vars)
    if n_plots == 0:
        print("No monthly variables provided for comparison.")
        return None
        
    fig = plt.figure(figsize=(15, 4 * n_plots))
    
    # Create each subplot
    for i, monthly_var_name in enumerate(monthly_vars, 1):
        ax = fig.add_subplot(n_plots, 1, i)
        
        if monthly_var_name not in monthly_data.columns:
            print(f"Monthly variable '{monthly_var_name}' at index {i-1} not found in monthly_data. Skipping.")
            ax.text(0.5, 0.5, f"Data for '{monthly_var_name}' not found.", ha='center', va='center')
            ax.set_title(f'{monthly_var_name} vs {quarterly_var} (Data Missing)')
            continue

        # Get the series
        monthly_series = monthly_data[monthly_var_name]
        quarterly_series = quarterly_data[quarterly_var]
        
        # Calculate quarterly mean for normalization
        q_mean = quarterly_series.mean()
        q_std = quarterly_series.std()
        m_std = monthly_series.std()

        if q_std == 0 or m_std == 0:
            monthly_scale = 1.0
        else:
            monthly_scale = q_std / m_std
            
        monthly_adjusted = (monthly_series - monthly_series.mean()) * monthly_scale + q_mean
        
        # Plot both series
        ax.plot(monthly_data.index, monthly_adjusted,
                color='blue', linewidth=1, 
                label=f'{monthly_var_name} (Monthly, Adjusted)')
        
        ax.scatter(quarterly_data.index, quarterly_series,
                   color='red', s=30, 
                   label=f'{quarterly_var} (Quarterly)')
        
        # Customize the subplot
        ax.set_title(f'{monthly_var_name} vs {quarterly_var}')
        ax.grid(True, linestyle='--', alpha=0.7)
        ax.legend(loc='upper left')
        plt.setp(ax.get_xticklabels(), rotation=45)
    
    plt.tight_layout()
    return fig
