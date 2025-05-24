# tests/utils/test_dates.py
import unittest
from datetime import datetime
from midas_nowcasting.utils.dates import determine_target_quarter

class TestDateUtils(unittest.TestCase):

    def test_determine_target_quarter(self):
        # Test cases: (input_date, expected_quarter, expected_year, expected_month_in_quarter)
        test_cases = [
            (datetime(2023, 1, 15), 1, 2023, 0),
            (datetime(2023, 3, 31), 1, 2023, 2),
            (datetime(2023, 4, 1), 2, 2023, 0),
            (datetime(2023, 6, 20), 2, 2023, 2),
            (datetime(2023, 7, 10), 3, 2023, 0),
            (datetime(2023, 9, 1), 3, 2023, 2),
            (datetime(2023, 10, 5), 4, 2023, 0),
            (datetime(2023, 12, 31), 4, 2023, 2),
        ]
        for ref_date, exp_q, exp_y, exp_m_in_q in test_cases:
            q, y, m_in_q = determine_target_quarter(ref_date)
            self.assertEqual(q, exp_q, f"Quarter mismatch for {ref_date}")
            self.assertEqual(y, exp_y, f"Year mismatch for {ref_date}")
            self.assertEqual(m_in_q, exp_m_in_q, f"Month in quarter mismatch for {ref_date}")

if __name__ == '__main__':
    unittest.main()
