# midas_nowcasting/reporting/charts.py
import pandas as pd
import matplotlib.pyplot as plt

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
    var_series = transformed_monthly_data[
        transformed_monthly_data['variable'] == variable_name
    ].copy()
    var_series['date'] = pd.to_datetime(var_series['date'])
    var_series = var_series.set_index('date')['value']

    # Filter target data
    target_series = target_data.copy()
    target_series['date'] = pd.to_datetime(target_series['date'])
    target_series = target_series.set_index('date')['value'] # Assuming 'value' column for target

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
    ax.set_ylabel("Value", fontsize=12) # Y-axis label might need to be more generic or passed as arg
    ax.legend()
    plt.grid(True, alpha=0.3)
    plt.show()
