# midas_nowcasting/reporting/tables.py
import pandas as pd

def generate_model_summary_table(
    model_metrics: dict, 
    latest_nowcasts: dict
) -> pd.DataFrame:
    """
    Generates a performance summary table for models.

    Args:
        model_metrics (dict): A dictionary where keys are model names and 
                              values are dicts of metrics (e.g., {"RMSE": 0.5, "MAE": 0.4}).
                              Example: {"UMIDAS": {"RMSE": 0.5, "MAE": 0.4, "R²": 0.6}}
        latest_nowcasts (dict): A dictionary where keys are model names and 
                                values are their latest nowcast values.
                                Example: {"UMIDAS": 1.23}
    Returns:
        pd.DataFrame: A DataFrame summarizing model performance and latest nowcasts.
    """
    if not model_metrics:
        return pd.DataFrame(columns=["RMSE", "MAE", "R²", "Latest_Nowcast"])

    df = pd.DataFrame.from_dict(model_metrics, orient='index')
    
    # Ensure standard columns are present, even if some models don't have all metrics
    for col in ["RMSE", "MAE", "R²"]:
        if col not in df.columns:
            df[col] = pd.NA
            
    nowcast_series = pd.Series(latest_nowcasts, name="Latest_Nowcast")
    df = df.join(nowcast_series)
    
    return df.sort_values(by="RMSE")
