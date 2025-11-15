#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Gene Kindberg-Hanlon
"""

import pandas as pd
import os
import matplotlib.pyplot as plt
import numpy as np
from MIDAS import *
import datetime as dt
import Haver as hv

dirname = os.path.dirname(__file__)
hv.path('auto') # path for Haver 

####################################################
# Import data
HVdb = 'USECON' # Haver database to be used
Targetcodes = ['gh'] # Quarterly variable you want to nowcast
Quarterlyname = 'Gov cons and invest' # Readable name for plot
Reg_codes = ['fto', 'lagovta', 'pcu']  # Haver codes of target variables 
Reg_names = ['net outlays', 'gov payroll' ] # Nice names for table

begindate = '1992-01-01' # Start of data download

# Download quarterly target data and calculate qoq growth
Target_dat = hv.data(Targetcodes ,  HVdb, frequency='Q', startdate=begindate)
Target_dat[Targetcodes] = Target_dat[Targetcodes].pct_change()*100


# Download monthly forecasting data and calculate m/m growth for those that need to be transformed
Monthly_dat = hv.data(Reg_codes ,  HVdb, frequency='M', startdate=begindate)
Monthly_dat['fto'] = 100*Monthly_dat['fto'].div(Monthly_dat['pcu'])
Monthly_dat[['fto', 'lagovta']] = Monthly_dat[['fto', 'lagovta']].pct_change(fill_method=None)*100
Monthly_dat = Monthly_dat.drop(columns=['pcu'])

CombinedModel = ['net outlays', 'gov payroll']

# Remove first NA period after calculating percentage changes
Target_dat = Target_dat[1:] # Get rid of first Q

# Delay = 1 if series is released 1 month late - for example, PMI for Jan is released in Jan, but PCE for December is released late Jan. "1" in first column delays PCE.
# If you don't like this system then just leave all elements of "Delay" as zeros (I.e. you want to see Jan PCE as month one data in Q1 instead of month2)
Delay = [0,0]
Monthly_dat = DelaySeries(Monthly_dat, Delay)


# Get a datetime vector starting at new truncated data start (+ nowcast quarter). Used for plotting and table.
date_list = pd.date_range(pd.to_datetime(Target_dat.index.astype(str))[0], periods=len(Target_dat)+1, freq = 'Q').to_pydatetime().tolist()


####################################################
# View data - uncomment if needed

#Plot target series
# fig, (ax1) = plt.subplots(1, 1)
# Target_dat[Targetcodes].plot(figsize=(20,10), linewidth=5, fontsize=20, ax=ax1)
# plt.xlabel('Year', fontsize=20)

# # plot all series in a dataframe
# fig2 = plt.figure(figsize=(10,10))
# for c,num in zip(Monthly_dat.columns, range(1,len(Monthly_dat.columns))):
#     ax2 = fig2.add_subplot(3,3,num)
#     #ax.plot(Monthly_dat[c].index, Monthly_dat[c].values)
#     Monthly_dat[c].plot(ax = ax2)
#     ax2.set_title(c)
# #
# plt.tight_layout()
# plt.show()


####################### Haver Data

# Nowcast function takes a list of variables - make using pandas dataframe from Haver
MonthlyListHav = []
for ii in Monthly_dat.columns:
    MonthlyListHav.append(Monthly_dat[ii][0:].values.reshape(-1,1))

# Initiate MIDAS function with required data and arguments
#Arguments GDP: Target quarterly nowcast variable, monthlyseries = Series with predictive power over target, skip = how many quarters to skip before assessing out-of-sample RMSE
# ARt = max AR lags if include AR terms. maxlag = max lags of monthly variables to assess., ARinclude = add AR forecast, weighttype = either 'rmse' (root mean squared error)
# of 'mse'. 'mse' will apply smaller weights to less accurate indicators. names = more readable names than Haver codes of indicators.
TestFcastHav = ForecastCombine(GDP=Target_dat.values, monthlyseries=MonthlyListHav, skip=40, ARt = 5, maxlag = 6, ARinclude = 0, weighttype = 'mse', names = Reg_names, MultiModel = CombinedModel) 
TestFcastHav.Optimize() # Find optimal forecasting lags and out of sample RMSE for each explanatory variable - calculate combined forecast.
TestFcastHav.PlotBest(date_list, Quarterlyname) # Plot out of sample optimal forecast in months 1-3
TestFcastHav.PrintNiceOutput(date_list) # Print table of optimal nowcast, individual nowcast, and RMSEs.
#        
    