#%%
import pandas as pd
import numpy as np
import re

import pandas as pd
import numpy as np
import re
from statsmodels.tsa.x13 import x13_arima_analysis

def parse_description(desc):
    """
    Parse Haver description to extract:
    - Base description (text before parentheses)
    - Seasonality (SA, NSA, SAAR)
    - Scale and units (e.g., Mil.2018.NewPesos)
    
    Seasonality rules:
    - SAAR and SA are counted as SA
    - NSA is its own category
    - Must match exactly (not finding SA within NSA)
    """
    if pd.isna(desc):
        return {
            'base_description': None,
            'seasonality': None,
            'scale': None,
            'units': None,
            'full_description': None
        }
        
    base_desc = desc
    seasonality = None
    scale = None
    units = None
    
    # Extract content in parentheses
    matches = re.findall(r'\((.*?)\)', desc)
    if matches:
        parentheses_content = matches[-1]  # Take the last parentheses
        components = [x.strip() for x in parentheses_content.split(',')]
        
        # Find seasonality with strict matching
        # First check for exact SAAR or SA
        for component in components:
            # Use word boundaries to ensure exact matches
            if re.search(r'\b(SAAR|SA)\b', component):
                seasonality = 'SA'
                break
            elif re.search(r'\bNSA\b', component):
                seasonality = 'NSA'
                break
        
        # Get scale and units (usually last component)
        if components:
            scale_units = components[-1]
            # Try to separate scale from units
            scale_patterns = ['Mil', 'Bil', 'Thous']
            for pattern in scale_patterns:
                if pattern in scale_units:
                    scale = pattern
                    units = scale_units.replace(pattern, '').strip('.')
                    break
            if not scale:
                units = scale_units
                
        # Base description is everything before the last parentheses
        base_desc = desc.rsplit('(', 1)[0].strip()
    
    return {
        'base_description': base_desc,
        'seasonality': seasonality,
        'scale': scale,
        'units': units,
        'full_description': desc
    }

class HaverData:
    def __init__(self, filename):
        """Initialize with Excel file"""
        self.df = pd.read_excel(filename, sheet_name=1, header=None)
        self._process_data()
    
    def _process_data(self):
        """Process the Haver data structure"""
        # Get variable IDs from first row (starting at column 2)
        self.variable_ids = self.df.iloc[0, 2:].dropna().tolist()
        
        # Extract metadata
        self.metadata = {}
        for idx in range(1, 14):  # Get metadata rows
            row = self.df.iloc[idx]
            key = str(row.iloc[0]).strip('.')
            values = row.iloc[2:len(self.variable_ids) + 2].tolist()  # Only get values for valid variables
            self.metadata[key] = values
            
        # Get data portion (starting from row 14)
        data_df = self.df.iloc[14:].copy()
        # Reset column indexing and only keep relevant columns
        data_df = data_df.iloc[:, :len(self.variable_ids) + 2]
        # Set proper column names
        new_columns = ['date', 'excel_last'] + self.variable_ids
        data_df.columns = new_columns
        
        # Drop rows where date column is NaN
        self.data = data_df.dropna(subset=['date'])
        
        # Create series info DataFrame with all metadata
        series_data = []
        for idx, var_id in enumerate(self.variable_ids):
            desc = self.metadata['DESC'][idx]
            
            # Parse descriptions for seasonality, units, and scale
            seasonality = None
            units = None
            scale = None
            
            # Extract from description parentheses if present
            if desc and '(' in desc:
                parts = desc.split('(')[-1].strip(')')
                for part in parts.split(','):
                    part = part.strip()
                    if part in ['SA', 'NSA', 'SAAR']:
                        seasonality = 'SA' if part in ['SA', 'SAAR'] else 'NSA'
                    elif any(s in part for s in ['Mil', 'Bil', 'Thous']):
                        for s in ['Mil', 'Bil', 'Thous']:
                            if s in part:
                                scale = s
                                units = part.replace(s, '').strip('.')
                                break
                    else:
                        units = part if not units else units
            
            series_data.append({
                'series_id': var_id,
                'name': var_id.split('@')[0] if '@' in var_id else var_id,
                'description': desc,
                'frequency': self.metadata['FRQ'][idx],
                'data_type': self.metadata['DATA_TYPE'][idx],
                'source': self.metadata['SOURCE'][idx],
                'seasonality': seasonality,
                'units': units,
                'scale': scale,
                'mag': self.metadata['MAG'][idx] if 'MAG' in self.metadata else None,
                'grp': self.metadata['GRP'][idx] if 'GRP' in self.metadata else None,
                'grpdesc': self.metadata['GRPDESC'][idx] if 'GRPDESC' in self.metadata else None,
                'agg': self.metadata['AGG'][idx] if 'AGG' in self.metadata else None,
                'dtlm': self.metadata['DTLM'][idx] if 'DTLM' in self.metadata else None,
                'lsource': self.metadata['LSOURCE'][idx] if 'LSOURCE' in self.metadata else None,
                'start_date': self.metadata['T1'][idx] if 'T1' in self.metadata else None,
                'end_date': self.metadata['TN'][idx] if 'TN' in self.metadata else None
            })
            
        self.series_info = pd.DataFrame(series_data)

    def get_series(self, frequency=None, data_type=None, source=None, seasonality=None, 
                units=None, scale=None):
        """Get series matching specified criteria"""
        mask = pd.Series([True] * len(self.series_info))
        
        if frequency:
            mask &= self.series_info['frequency'] == frequency
        if data_type:
            mask &= self.series_info['data_type'] == data_type
        if source:
            mask &= self.series_info['source'] == source
        if seasonality:
            mask &= self.series_info['seasonality'] == seasonality    
        if units:
            mask &= self.series_info['units'] == units    
        if scale:
            mask &= self.series_info['scale'] == scale
        
        matching_series = self.series_info[mask]['series_id'].tolist()
        
        if not matching_series:
            return pd.DataFrame(), self.series_info[mask]
        
        # Create DataFrame with date and matched series
        columns_to_select = ['date'] + matching_series
        result = self.data[columns_to_select].copy()
        
        # Rename columns to remove database part
        rename_dict = {series: series.split('@')[0] for series in matching_series}
        result = result.rename(columns=rename_dict)
        
        # Convert date column to datetime
        # Assuming date format is YYYYMM
        result['date'] = pd.to_datetime(result['date'].astype(str).str.pad(6, fillchar='0'), format='%Y%m') + pd.offsets.MonthBegin(0)
        
        # Set date as index
        result = result.set_index('date')
        
        return result, self.series_info[mask]

    def get_unique_frequencies(self):
        """Get list of unique frequencies"""
        return sorted(self.series_info['frequency'].unique().tolist())
    
    def get_unique_data_types(self):
        """Get list of unique data types"""
        return sorted(self.series_info['data_type'].unique().tolist())
    
    def get_unique_sources(self):
        """Get list of unique sources"""
        return sorted(self.series_info['source'].unique().tolist())
    
    def get_unique_seasonalities(self):
        """Get list of unique seasonality adjustments"""
        return sorted([x for x in self.series_info['seasonality'].unique().tolist() if pd.notna(x)])
    
    def get_unique_scales(self):
        """Get list of unique scales"""
        return sorted([x for x in self.series_info['scale'].unique().tolist() if pd.notna(x)])

    def x13_adjust(self, data, date_column='date', value_column='value', freq='M'):
        """
        Perform X-13-ARIMA-SEATS seasonal adjustment while preserving missing values
        in the original date range.
        
        Parameters:
        -----------
        data : pandas.DataFrame
            DataFrame with date and value columns
        date_column : str
            Name of date column
        value_column : str
            Name of value column
        freq : str
            Frequency of data ('M' for monthly, 'Q' for quarterly)
            
        Returns:
        --------
        pandas.DataFrame
            DataFrame with original dates (including missing) and adjusted series
        """
        
        # Create copy of data
        df = data.copy()
        
        # Store original date range including missing values
        full_date_range = pd.DataFrame({date_column: df[date_column]})
        
        # Remove missing values for X-13
        df_clean = df.dropna(subset=[value_column])
        
        # Only proceed with X-13 if we have data
        if len(df_clean) > 0:
            # Set date as index
            df_clean.set_index(date_column, inplace=True)
            
            try:
                # Run X-13 ARIMA SEATS on non-missing data
                results = x13_arima_analysis(
                    df_clean[value_column],
                    freq=freq,
                    trading=True,  # Trading day adjustment
                    outlier=True,  # Outlier detection
                    forecast_years=1  # Generate 1 year of forecasts
                )
                
                # Get seasonally adjusted series
                adjusted = results.seasadj
                
                # Create output dataframe for non-missing period
                output_clean = pd.DataFrame({
                    'original': df_clean[value_column],
                    'seasonally_adjusted': adjusted
                })
                
                # Reset index to get date back as column
                output_clean.reset_index(inplace=True)
                
                # Merge with full date range to restore missing dates
                output = pd.merge(full_date_range, output_clean, 
                                on=date_column, 
                                how='left')
                
            except Exception as e:
                print(f"X-13 adjustment failed: {str(e)}")
                # Return original data with NaN for adjusted column
                output = pd.DataFrame({
                    date_column: full_date_range[date_column],
                    'original': df[value_column],
                    'seasonally_adjusted': np.nan
                })
        else:
            # If no valid data, return original with NaN for adjusted
            output = pd.DataFrame({
                date_column: full_date_range[date_column],
                'original': df[value_column],
                'seasonally_adjusted': np.nan
            })
        
        return output

    
# Example usage:
import os
# Get directory containing the script
script_dir = os.path.dirname(os.path.abspath(__file__))

# Change working directory to script location 
os.chdir(script_dir)
haver = HaverData('Statistics Mexico Haver.xlsx')

# Get Monthly series (note the capital M)
data, metadata = haver.get_series(frequency='Monthly')

# Get Quarterly series (note the capital Q)
data, metadata = haver.get_series(frequency='Quarterly')

# Get Monthly INDEX series
data, metadata = haver.get_series(frequency='Monthly', seasonality = 'NSA', data_type='INDEX')

adjusted = haver.x13_adjust(data)

# Example usage:
print("Frequencies:", haver.get_unique_frequencies())
print("Data Types:", haver.get_unique_data_types())
print("Seasonalities:", haver.get_unique_seasonalities())
print("Scales:", haver.get_unique_scales())
# %%
