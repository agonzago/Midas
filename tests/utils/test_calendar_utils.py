# tests/utils/test_calendar_utils.py
import unittest
import pandas as pd
from datetime import datetime
from midas_nowcasting.utils.calendar_utils import generate_release_calendar

class TestCalendarUtils(unittest.TestCase):

    def test_generate_release_calendar_simple(self):
        sample_config_variable_info = {
            "indicator_a": {
                "release_schedule": {"week_of_quarter": 2, "day_of_month": 10} 
            },
            "indicator_b": {
                # No release_schedule, should be skipped
            },
            "indicator_c": {
               "release_schedule": {"week_of_quarter": 4, "day_of_month": 20} 
            }
        }
        target_year = 2023
        release_df = generate_release_calendar(sample_config_variable_info, target_year)
        
        self.assertIsInstance(release_df, pd.DataFrame)
        self.assertGreater(len(release_df), 0, "Release calendar DataFrame should not be empty")
        self.assertIn("variable", release_df.columns)
        self.assertIn("quarter", release_df.columns)
        self.assertIn("release_date", release_df.columns)
        
        # Check if expected indicators are present (each appears 4 times for 4 quarters)
        self.assertEqual(len(release_df[release_df['variable'] == 'indicator_a']), 4)
        self.assertEqual(len(release_df[release_df['variable'] == 'indicator_c']), 4)
        self.assertNotIn('indicator_b', release_df['variable'].unique())

        # Check a specific date (e.g., indicator_a, Q1 2023)
        # Q1 starts Jan 1. Week 2, day 10 means Jan 1 (start) + 7 days (for week 2) + (10-1) days = Jan 17
        # However, the original logic was: week_offset = (week_of_quarter - 1) * 7
        # release_date = start_date + timedelta(days=week_offset + day_of_month - 1)
        # Q1 2023, indicator_a: week 2, day 10. Base date for Q1 is 2023-01-01.
        # week_offset = (2-1)*7 = 7 days. release_date = 2023-01-01 + 7 days + (10-1) days = 2023-01-01 + 16 days = 2023-01-17
        q1_a_release = release_df[
            (release_df['variable'] == 'indicator_a') & (release_df['quarter'] == 'Q1')
        ]['release_date'].iloc[0]
        self.assertEqual(q1_a_release, datetime(2023, 1, 17))


if __name__ == '__main__':
    unittest.main()
