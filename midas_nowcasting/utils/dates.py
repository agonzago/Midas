# midas_nowcasting/utils/dates.py
from datetime import datetime
import pandas as pd # Added to support pd.to_datetime

def determine_target_quarter(reference_date: datetime):
    """
    Determine which quarter we're forecasting based on a reference date.
    
    Parameters:
    reference_date (datetime): The date for which the nowcast is being made.
    
    Returns:
    tuple: (target_quarter, target_year, current_month_in_quarter)
           target_quarter (int): The quarter being forecasted (1-4).
           target_year (int): The year of the target quarter.
           current_month_in_quarter (int): The month number within the current quarter 
                                           (0 for first month, 1 for second, 2 for third).
    """
    if not isinstance(reference_date, datetime):
        # Attempt to parse if it's a string, or raise error
        try:
            reference_date = pd.to_datetime(reference_date).to_pydatetime() 
        except ValueError:
            raise ValueError("reference_date must be a datetime object or a parseable date string.")
        # Removed NameError check as pd is now imported.


    month = reference_date.month
    current_quarter = (month - 1) // 3 + 1
    current_month_in_quarter = (month - 1) % 3
    
    # Assumption: We are always forecasting the quarter that the reference_date falls into.
    target_quarter = current_quarter
    target_year = reference_date.year
    
    return target_quarter, target_year, current_month_in_quarter
