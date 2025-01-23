_adjust(self, data, freq='M'):
        """
        Perform X-13-ARIMA-SEATS seasonal adjustment across all columns.
        
        Parameters:
        -----------
        data : pandas.DataFrame
            DataFrame with datetime index and columns to adjust
        freq : str
            Frequency of data ('M' for monthly, 'Q' for quarterly)
            
        Returns:
        --------
        pandas.DataFrame
            DataFrame with original and adjusted series
        """
        # Create output DataFrame with same index as input
        output = pd.DataFrame(index=data.index)
        
        # Process each column
        for column in data.columns:
            # Create series with only non-missing values
            series_clean = data[column].dropna()
            
            if len(series_clean) > 0:
                try:
                    # Run X-13 ARIMA SEATS
                    results = x13_arima_analysis(
                        series_clean,
                        freq=freq,
                        trading=True,
                        outlier=True,
                        forecast_years=1
                    )
                    
                    # Add original and adjusted series to output
                    output[f'{column}_original'] = data[column]
                    output[f'{column}_sa'] = results.seasadj
                    
                except Exception as e:
                    print(f"X-13 adjustment failed for {column}: {str(e)}")
                    output[f'{column}_original'] = data[column]
                    output[f'{column}_sa'] = np.nan
            else:
                output[f'{column}_original'] = data[column]
                output[f'{column}_sa'] = np.nan
        
        return output