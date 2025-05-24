import pandas as pd
from datetime import datetime, timedelta

def generate_release_calendar(config_variable_info: dict, 
                              target_year: int, 
                              quarters: list = ['Q1', 'Q2', 'Q3', 'Q4']) -> pd.DataFrame:
    """
    Generates a release calendar DataFrame based on variable configuration.

    Args:
        config_variable_info (dict): A dictionary where keys are variable names and values are dicts
                                     containing their metadata, including a 'release_schedule' dict
                                     with 'week_of_quarter' and 'day_of_month'.
                                     Example: 
                                     {
                                         "industrial_production": {
                                             "release_schedule": {"week_of_quarter": 2, "day_of_month": 11}
                                         }, ...
                                     }
        target_year (int): The year for which to generate the calendar.
        quarters (list): List of quarter strings (e.g., ['Q1', 'Q2', 'Q3', 'Q4']) for which to generate dates.

    Returns:
        pd.DataFrame: A DataFrame with columns ['variable', 'quarter', 'release_date'].
    """
    
    quarter_start_dates = {
        'Q1': datetime(target_year, 1, 1),
        'Q2': datetime(target_year, 4, 1),
        'Q3': datetime(target_year, 7, 1),
        'Q4': datetime(target_year, 10, 1)
    }

    release_calendar_entries = []

    for variable_name, info in config_variable_info.items():
        if 'release_schedule' in info and isinstance(info['release_schedule'], dict):
            week_of_quarter = info['release_schedule'].get('week_of_quarter')
            day_of_month = info['release_schedule'].get('day_of_month') # This was day_of_month in original

            if week_of_quarter is None or day_of_month is None:
                # print(f"Warning: Missing 'week_of_quarter' or 'day_of_month' for {variable_name}. Skipping.")
                continue

            for quarter_str in quarters:
                if quarter_str not in quarter_start_dates:
                    # print(f"Warning: Quarter {quarter_str} not recognized. Skipping for {variable_name}.")
                    continue
                
                quarter_start_date = quarter_start_dates[quarter_str]
                
                # Calculate the first day of the target month for that quarter.
                # The original logic seems to imply day_of_month is relative to the start of the quarter's first month.
                # Example: Q1 starts Jan 1. week_of_quarter 2, day_of_month 11 means Jan 11th if week starts on day 1.
                # This interpretation is a bit ambiguous. Let's assume day_of_month refers to day within the
                # first month of the quarter for simplicity, and week_of_quarter is which week of that month.
                # A more robust way: day_of_month should be day_of_week if week_of_quarter is used,
                # or day_of_month is absolute day in the month.

                # Simpler interpretation: day_of_month is the actual day in the first month of the quarter.
                # week_of_quarter is which week (1-4/5) of that month.
                # The original function's `start_date + timedelta(days=week_offset + day_of_month - 1)`
                # implies day_of_month is an absolute day. And week_of_quarter determines the month.
                # If week_of_quarter = 1, it's month 1 of quarter. If week_of_quarter = 5, it's month 2 etc.
                # This is not standard.

                # Let's assume 'day_of_month' is the target day, and 'week_of_quarter' refers to
                # which month of the quarter (1st, 2nd, 3rd), and then which week within that month.
                # This is still not clear from the original.

                # Re-interpreting based on original: `start_date` is quarter start.
                # `week_offset = (week_of_quarter - 1) * 7`
                # `release_date = start_date + timedelta(days=week_offset + day_of_month - 1)`
                # This means `day_of_month` is a day *within that specific week*.
                # E.g. Q1 (Jan 1), week_of_quarter=2, day_of_month=11.
                # week_offset = (2-1)*7 = 7 days from Jan 1, so Jan 8th.
                # release_date = Jan 8th + 11 days - 1 day = Jan 18th. (This seems more plausible)
                # So, day_of_month is more like "day_in_target_week_of_quarter_start".

                # Let's stick to the original calculation logic for now, assuming it was intended.
                # The week_of_quarter is from the start of the quarter.
                # The day_of_month is the day within that week (1=Mon, ..., 7=Sun if week starts Mon)
                # Or, day_of_month is just a number of days to add. The original is ambiguous.
                # The original `day_of_month - 1` suggests `day_of_month` is 1-indexed.
                
                # Let's assume schedule means: Xth day of Yth week of the Zth month of the quarter
                # The original `generate_release_calendar` is simpler:
                # It calculates an offset from the start of the quarter.
                # `week_of_quarter` is the Nth week from the start of the quarter.
                # `day_of_month` is the Nth day from the start of that week.

                # Let's assume the parameters mean:
                # week_of_quarter: The Nth week *of the quarter*.
                # day_of_month: The Nth day *of that week*. (e.g. 1 for Monday, 2 for Tuesday etc. if week starts on Mon)
                # This requires knowing the day of the week for quarter_start_date.

                # Given the original code: `start_date + timedelta(days=week_offset + day_of_month - 1)`
                # It appears `day_of_month` is simply an additional day offset within that week.
                # Example: week_of_quarter = 2, day_of_month = 3
                # week_offset = 7 days. release_date = start_date + 7 days + 3 days - 1 day = start_date + 9 days.
                # This is simple addition of days.

                try:
                    week_offset_days = (int(week_of_quarter) - 1) * 7
                    day_offset = int(day_of_month) -1 # Adjust if day_of_month is 1-indexed
                    
                    release_date = quarter_start_date + timedelta(days=week_offset_days + day_offset)
                    
                    # Ensure the release date is within the target quarter, or handle as needed.
                    # This logic might push dates into the next quarter if week_of_quarter is large.
                    # For now, following the literal calculation.

                    release_calendar_entries.append({
                        'variable': variable_name,
                        'quarter': quarter_str, # Storing Q1, Q2 etc.
                        'release_date': release_date
                    })
                except (ValueError, TypeError) as e:
                    # print(f"Warning: Invalid 'week_of_quarter' or 'day_of_month' for {variable_name}: {e}. Skipping.")
                    continue
        else:
            # print(f"Warning: 'release_schedule' not found or not a dict for {variable_name}. Skipping.")
            continue
            
    return pd.DataFrame(release_calendar_entries)
