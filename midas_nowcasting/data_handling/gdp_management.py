# midas_nowcasting/data_handling/gdp_management.py
import pandas as pd
from datetime import datetime # Added for type hinting and explicit date operations

class GDPData:
    def __init__(self, historical_gdp: pd.Series, last_forecast: Optional[float] = None):
        """
        Initialize GDP data handler
        
        Parameters:
        historical_gdp (pd.Series): pandas Series with historical GDP data (quarterly frequency, DatetimeIndex).
        last_forecast (float, optional): The forecast made for the previous quarter 
                                         (if current quarter GDP not yet released).
        """
        if not isinstance(historical_gdp, pd.Series):
            raise TypeError("historical_gdp must be a pandas Series.")
        if not isinstance(historical_gdp.index, pd.DatetimeIndex):
            raise TypeError("historical_gdp Series must have a DatetimeIndex.")
            
        self.historical_gdp = historical_gdp.sort_index() # Ensure data is sorted
        self.last_forecast = last_forecast
        
    def get_gdp_series(self, reference_date: datetime) -> pd.Series:
        """
        Get GDP series including a provisional value for the previous quarter if needed.
        Assumes GDP for a quarter T is released around the end of the first month of quarter T+1.
        
        Parameters:
        reference_date (datetime): The current date for which the nowcast is being made.
        
        Returns:
        pd.Series: GDP series potentially including a provisional value.
        """
        gdp_series = self.historical_gdp.copy()
        
        if not gdp_series.empty:
            last_historical_quarter_end = gdp_series.index[-1]
            
            # Determine the quarter of the reference_date
            ref_quarter_year = reference_date.year
            ref_quarter_month = (reference_date.month - 1) // 3 * 3 + 1 # First month of ref_date's quarter
            ref_quarter_start = datetime(ref_quarter_year, ref_quarter_month, 1)

            # Determine the previous quarter relative to the reference_date
            prev_quarter_start_month = ref_quarter_month - 3
            prev_quarter_start_year = ref_quarter_year
            if prev_quarter_start_month < 1:
                prev_quarter_start_month += 12
                prev_quarter_start_year -=1
            
            # End of the previous quarter (e.g., if ref_date is Q1 2023, prev_quarter_end is 2022-12-31)
            # This logic needs to be robust for constructing the correct date.
            # A simpler way: if reference_date's quarter is T, previous quarter is T-1.
            # If historical data's last point is for T-1, and we are in the release window for T-1's GDP,
            # but before actual release, we might use a forecast for T-1.
            
            # Let's define "previous quarter" as the quarter ending *before* the start of reference_date's quarter.
            # Example: if reference_date is 2023-01-15 (Q1 2023), previous quarter is Q4 2022.
            # Its data point would be indexed typically at 2022-12-31.
            
            # If the last historical data point is for the quarter *before* the one ending just before reference_date's quarter
            # AND we are in the typical "limbo" period for that previous quarter's GDP release.
            # (e.g., ref_date is Jan 15th for Q1. Last actual GDP is for Q3. We need Q4 GDP.
            # If Q4 GDP is released Jan 25th, and last_forecast is for Q4, use it).

            # A typical assumption: GDP for quarter Q is released around day 25 of the first month of Q+1.
            # If reference_date is in month M of quarter Q_ref:
            #   - If M=1 (first month of Q_ref) and day < 25:
            #     The GDP for Q_ref-1 might not be released yet.
            #     If self.last_forecast is for Q_ref-1, and historical_gdp does not yet contain Q_ref-1, use it.
            
            # Identify the most recent quarter for which official data *should* exist based on typical release cycle
            # If reference_date is 2023-01-15 (Q1): GDP for Q4 2022 might not be out.
            # If historical data ends at Q3 2022, and last_forecast is for Q4 2022, use it.
            
            # Determine the quarter that the reference_date falls into
            current_quarter_of_ref_date = pd.Timestamp(reference_date).to_period('Q')
            
            # Determine the previous quarter
            previous_quarter_period = current_quarter_of_ref_date - 1
            
            # If the last data point in historical_gdp is for the quarter before 'previous_quarter_period'
            # and we have a last_forecast, and it's before the typical release day of previous_quarter's data.
            if (not gdp_series.empty and 
                gdp_series.index.max().to_period('Q') < previous_quarter_period and
                self.last_forecast is not None and
                reference_date.month % 3 == 1 and reference_date.day < 25): # Typical release condition
                
                # Construct the date for the previous quarter's forecast
                # This needs to be the end-of-quarter date for previous_quarter_period
                # Example: if previous_quarter_period is 2022Q4, date should be 2022-12-31
                prev_quarter_end_date = previous_quarter_period.end_time.normalize()

                # Add the forecast for the previous quarter
                # Ensure not to add if already present or if historical data is more recent
                if prev_quarter_end_date not in gdp_series.index:
                    forecast_series = pd.Series([self.last_forecast], index=[prev_quarter_end_date])
                    gdp_series = pd.concat([gdp_series, forecast_series]).sort_index()
                
        return gdp_series

from typing import Optional # Already imported at class level if this was part of class block
                           # Adding here for clarity if this snippet is viewed standalone.
