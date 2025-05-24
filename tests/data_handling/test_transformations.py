# tests/data_handling/test_transformations.py
import unittest
import pandas as pd
import numpy as np
from midas_nowcasting.data_handling.transformations import transformations

class TestTransformations(unittest.TestCase):

    def setUp(self):
        self.dates = pd.to_datetime(['2023-01-01', '2023-02-01', '2023-03-01', '2023-04-01'])
        self.data = pd.DataFrame({
            'date': self.dates,
            'var1': [10, 12, 15, 13],
            'var2': [100, 110, 105, 115.5] # for ldiff
        })

    def test_diff_transform(self):
        trans_dict = {'var1': 'diff'}
        transformed_df = transformations(self.data, trans_dict)
        expected_diff = pd.Series([np.nan, 2.0, 3.0, -2.0])
        pd.testing.assert_series_equal(transformed_df['var1'].reset_index(drop=True), expected_diff.reset_index(drop=True), check_dtype=False)

    def test_ldiff_transform(self):
        trans_dict = {'var2': 'ldiff'}
        transformed_df = transformations(self.data, trans_dict)
        expected_ldiff = np.log(self.data['var2']).diff()
        pd.testing.assert_series_equal(transformed_df['var2'].reset_index(drop=True), expected_ldiff.reset_index(drop=True), check_dtype=False)
        
    def test_log_transform(self):
        trans_dict = {'var1': 'log'}
        transformed_df = transformations(self.data, trans_dict)
        expected_log = np.log(self.data['var1'])
        pd.testing.assert_series_equal(transformed_df['var1'].reset_index(drop=True), expected_log.reset_index(drop=True), check_dtype=False)

    def test_std_transform(self):
        trans_dict = {'var1': 'std'}
        transformed_df = transformations(self.data, trans_dict)
        var1_series = self.data['var1']
        expected_std = (var1_series - var1_series.mean()) / var1_series.std()
        pd.testing.assert_series_equal(transformed_df['var1'].reset_index(drop=True), expected_std.reset_index(drop=True), check_dtype=False)


if __name__ == '__main__':
    unittest.main()
