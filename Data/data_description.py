#%%
import pandas as pd
import numpy as np
import re

import pandas as pd
import numpy as np
import re
from statsmodels.tsa.x13 import x13_arima_analysis
from workalendar.america import Mexico
import statsmodels.api as sm
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
        for component in components:
            if re.search(r'\b(SAAR|SA)\b', component):
                seasonality = 'SA'
                break
            elif re.search(r'\bNSA\b', component):
                seasonality = 'NSA'
                break
        
        # Get scale and units from all components
        for component in components:
            scale_patterns = ['Mil', 'Bil', 'Thous']
            for pattern in scale_patterns:
                if pattern in component:
                    scale = pattern
                    units = component.replace(pattern, '').strip('.')
                    break
            if scale:  # If scale found, stop searching
                break
        
        # If no scale found, use last component as units
        if not scale and not units:
            units = components[-1]
                
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
        self.variable_ids = self.df.iloc[0, 2:].dropna().tolist()
        
        # Check for duplicate names
        base_names = [vid.split('@')[0] for vid in self.variable_ids]
        duplicates = [name for name in set(base_names) if base_names.count(name) > 1]
        if duplicates:
            print("\nWarning - Duplicate series found:")
            for dup in duplicates:
                dupe_series = [vid for vid in self.variable_ids if vid.split('@')[0] == dup]
                print(f"{dup}:")
                for ds in dupe_series:
                    desc = self.df.iloc[1, self.df.columns.get_loc(ds)]
                    print(f"  - {ds}: {desc}")
        
        # Extract metadata
        self.metadata = {}
        for idx in range(1, 14):
            row = self.df.iloc[idx]
            key = str(row.iloc[0]).strip('.')
            values = row.iloc[2:len(self.variable_ids) + 2].tolist()
            self.metadata[key] = values
        
        # Process data portion
        data_df = self.df.iloc[14:].copy()
        data_df = data_df.iloc[:, :len(self.variable_ids) + 2]
        data_df.columns = ['date', 'excel_last'] + self.variable_ids
        
        # Clean and convert dates
        data_df['date'] = data_df['date'].astype(str).str.replace(' *M', '')
        data_df['date'] = pd.to_datetime(data_df['date'], format='%Y%m')
        self.data = data_df.dropna(subset=['date'])
        
        # Build series info with parsed descriptions
        series_data = []
        for idx, var_id in enumerate(self.variable_ids):
            desc = self.metadata['DESC'][idx]
            parsed = parse_description(desc)
            
            series_data.append({
                'series_id': var_id,
                'name': var_id.split('@')[0] if '@' in var_id else var_id,
                'description': parsed['base_description'],
                'full_description': parsed['full_description'],
                'frequency': self.metadata['FRQ'][idx],
                'data_type': self.metadata['DATA_TYPE'][idx],
                'source': self.metadata['SOURCE'][idx],
                'seasonality': parsed['seasonality'],
                'units': parsed['units'],
                'scale': parsed['scale'],
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
            
        # Get matching columns including date
        result = self.data[['date'] + matching_series].copy()
        
        # Remove database part from column names
        result.columns = ['date'] + [s.split('@')[0] for s in matching_series]
        
        # Set date as index
        result = result.set_index('date', drop=True)
        
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

    def x13_adjust(self, data, freq='M'):
        """Perform X-13 seasonal adjustment with robust outlier handling"""
        results = {}
        
        for column in data.columns:
            if column not in ['date', 'excel_last']:
                series = data[column].dropna()
                if len(series) > 0:
                    valid_data = data.loc[series.index[0]:series.index[-1], [column]]
                    td_adjusted = self.adjust_trading_days(valid_data, freq)
                    
                    try:
                        # First attempt with stricter outlier criteria
                        x13_result = x13_arima_analysis(
                            td_adjusted[column].astype(float),
                            freq=freq,
                            trading=True,
                            #outlier_critical=4.0,  # Stricter outlier detection
                            #outlier_types=['AO', 'LS'],  # Limit outlier types
                            print_stdout=False
                        )
                        
                        results[column.split('@')[0]] = pd.Series(
                            x13_result.seasadj,
                            index=x13_result.seasadj.index,
                            dtype=float
                        )
                        
                    except Exception as e:
                        try:
                            # Second attempt with even stricter settings
                            x13_result = x13_arima_analysis(
                                td_adjusted[column].astype(float),
                                freq=freq,
                                trading=True,
                                #outlier_critical=5.0,
                                #outlier_types=['AO'],
                                print_stdout=False
                            )
                            
                            results[column.split('@')[0]] = pd.Series(
                                x13_result.seasadj,
                                index=x13_result.seasadj.index,
                                dtype=float
                            )
                            
                        except Exception as e2:
                            print(f"X-13 adjustment failed for {column} with both attempts")
                            # Keep original series if adjustment fails
                            results[column.split('@')[0]] = td_adjusted[column].astype(float)
        
        return pd.DataFrame(results)

    def get_mexican_business_days(self,date):
        """Get number of business days in month according to Mexican calendar"""
        cal = Mexico()
        start_date = date.replace(day=1)
        end_date = date + pd.offsets.MonthEnd(0)
        return len([d for d in pd.date_range(start_date, end_date) 
                if cal.is_working_day(d)])

    def adjust_trading_days(self, data, freq='M'):
        """Adjust for trading day effects using Mexican calendar"""
        adjusted_data = pd.DataFrame(index=data.index)
        
        for column in data.columns:
            series = data[column].dropna().astype(float)
            if len(series) > 0:
                # Get business days
                trading_days = pd.Series(
                    [self.get_mexican_business_days(date) for date in series.index],
                    index=series.index,
                    dtype=float
                )
                
                # Prepare regression inputs
                X = np.column_stack([
                    np.ones(len(trading_days), dtype=float), 
                    trading_days.values.astype(float)
                ])
                y = series.values.astype(float)
                
                # Simple regression using matrix multiplication
                XtX = X.T @ X
                Xty = X.T @ y
                beta = np.linalg.solve(XtX.astype(float), Xty.astype(float))
                
                # Calculate and remove trading day effect
                td_effect = beta[1] * (trading_days - trading_days.mean())
                adjusted_data[column] = series - td_effect
        
        return adjusted_data

    def create_sa_database(self):
        """Create database of seasonally adjusted series"""
        # Get NSA series
        nsa_series = self.series_info[self.series_info['seasonality'] == 'NSA']['series_id'].tolist()
        
        # Get existing SA series
        sa_series = self.series_info[self.series_info['seasonality'] == 'SA']['series_id'].tolist()
        
        all_sa_data = []
        
        # Process NSA series
        if nsa_series:
            for series_id in nsa_series:
                series_data = self.data[['date', series_id]].set_index('date')
                adjusted = self.x13_adjust(series_data)
                
                # Extract SA series and rename to match original series ID
                sa_cols = [col for col in adjusted.columns if col.endswith('_sa')]
                if sa_cols:
                    sa_series_data = adjusted[sa_cols]
                    # Remove _sa suffix and database suffix for column name
                    sa_series_data.columns = [col.replace('_sa', '').split('@')[0] for col in sa_cols]
                    all_sa_data.append(sa_series_data)
        
        # Add existing SA series
        if sa_series:
            existing_sa = self.data[['date'] + sa_series].set_index('date')
            # Remove database suffix from column names
            existing_sa.columns = [col.split('@')[0] for col in existing_sa.columns]
            all_sa_data.append(existing_sa)
        
        # Combine all series
        sa_data = pd.concat(all_sa_data, axis=1)
        
        return sa_data, self.series_info[self.series_info['seasonality'].isin(['SA', 'NSA'])]
    
# Example usage:
import os
# Get directory containing the script
script_dir = os.path.dirname(os.path.abspath(__file__))

# Change working directory to script location 
os.chdir(script_dir)
haver = HaverData('Statistics Mexico Haver.xlsx')

# # Get Monthly series (note the capital M)
data, metadata = haver.get_series(frequency='Monthly')

# # Get Quarterly series (note the capital Q)
# data, metadata = haver.get_series(frequency='Quarterly')

# Get Monthly INDEX series
sa_data ,sa_metadata = haver.create_sa_database()


# Example usage:
# print("Frequencies:", haver.get_unique_frequencies())
# print("Data Types:", haver.get_unique_data_types())
# print("Seasonalities:", haver.get_unique_seasonalities())
# print("Scales:", haver.get_unique_scales())
# %%

 
# %%
