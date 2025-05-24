# midas_nowcasting/data_handling/data_calendar.py
import pandas as pd # Added as it's generally useful, though not strictly in original DataCalendar snippet
from datetime import datetime, timedelta # As per original umidas_mexico.py

class DataCalendar:
    def __init__(self):
        # Define release schedules for Mexican indicators
        # These are examples and might be overridden by subclasses or configuration
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
            'private_consumption': {'week': 1, 'day': 15}, # Example, might be different in reality
            'fixed_capital': {'week': 1, 'day': 15},      # Example
            'trade_balance_prelim': {'week': 4, 'day': 27},
            'employment_monthly': {'week': 4, 'day': 28},
        }
        
        # Define release schedules for US indicators (example)
        self.us_releases = {
            'ism_manufacturing': {'week': 1, 'day': 1},
            'nonfarm_payrolls': {'week': 1, 'day': 5},  # First Friday
            'retail_sales': {'week': 2, 'day': 15},
            'industrial_production': {'week': 2, 'day': 16},
            'consumer_confidence': {'week': 4, 'day': -1},  # Last Tuesday (example of relative day)
        }

    def get_available_indicators(self, reference_date: datetime) -> list:
        """Determine which indicators should be available given the reference date"""
        available = []
        
        # Ensure reference_date is a datetime object
        if not isinstance(reference_date, datetime):
            # Attempt to parse if it's a string, or raise error
            # For now, assuming it's passed correctly or add specific parsing
            try:
                reference_date = pd.to_datetime(reference_date).to_pydatetime()
            except ValueError:
                raise ValueError("reference_date must be a datetime object or a parseable date string.")

        # Calculate week of month
        first_day_of_month = reference_date.replace(day=1)
        # Week of month: (day - first_day_weekday + 6) // 7 for Monday start
        # A simpler approach for day-based schedules:
        week_of_month = (reference_date.day - 1) // 7 + 1 # Integer division for week number
        
        # Check Mexican indicators
        for indicator, schedule in self.mex_releases.items():
            release_day = schedule.get('day')
            release_week = schedule.get('week')
            
            # Handle day-of-week logic if present (e.g. first Friday) - not in current struct
            # For now, assumes specific day of month or week/day combination

            if release_week is not None and release_day is not None: # Week and day based
                if (week_of_month > release_week or 
                   (week_of_month == release_week and reference_date.day >= release_day)):
                    available.append(indicator)
            elif release_day is not None: # Only day based (implicit current month)
                 if reference_date.day >= release_day:
                    available.append(indicator)

        # Check US indicators (similar logic)
        for indicator, schedule in self.us_releases.items():
            release_day = schedule.get('day')
            release_week = schedule.get('week')
            
            # Handle relative days like 'last Tuesday'
            if release_day == -1 and release_week == 4: # Example: Last Tuesday of the month
                last_day_of_month = (reference_date.replace(month=reference_date.month % 12 + 1, day=1) - timedelta(days=1)).day
                # Find last Tuesday
                actual_release_day = None
                for day_offset in range(7):
                    potential_day = last_day_of_month - day_offset
                    if potential_day < 1: break # Should not happen if month has days
                    # weekday(): Monday is 0 and Sunday is 6. Tuesday is 1.
                    if datetime(reference_date.year, reference_date.month, potential_day).weekday() == 1: # Tuesday
                        actual_release_day = potential_day
                        break
                if actual_release_day and reference_date.day >= actual_release_day:
                    available.append(f"us_{indicator}")
                continue # Skip normal processing for this special case

            if release_week is not None and release_day is not None:
                if (week_of_month > release_week or 
                   (week_of_month == release_week and reference_date.day >= release_day)):
                    available.append(f"us_{indicator}")
            elif release_day is not None:
                 if reference_date.day >= release_day:
                    available.append(f"us_{indicator}")
                
        return available

class MexicoDataCalendar(DataCalendar):
    def __init__(self):
        super().__init__()
        # Update release schedules specifically for available Mexican indicators from umidas_mexico.py context
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
        # US releases can be inherited or cleared if not relevant for this specific calendar
        # self.us_releases = {} # Optionally clear US releases if MexicoDataCalendar is purely Mexican
