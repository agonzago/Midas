#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
@author: Gene Kindberg-Hanlon
"""

import pandas as pd
import os
import matplotlib.pyplot as plt
import numpy as np
from sklearn.linear_model import LinearRegression
from MIDAS import *
import datetime as dt
import Haver as hv

dirname = os.path.dirname(__file__)
hv.path('auto') # path for Haver 

####################################################
# Import data
HVdb = 'USECON' # Haver database to be used
Targetcodes = ['vh'] # nonresidential investment Haver code
Quarterlyname = 'Inventories' # Readable name for plot
Reg_codes = ['nti','nmi', 'nri', 'nwih']  # Haver codes last is goods cpi ex energy  'ntr', 'nmri', 'nrr', 'nwrh',
Reg_names = ['Tot inv.', 'Manufact inv.', 'Retail inv.', 'Wholesale inv.'] # Nice names for table 'Tot ratio i/s', 'Manu ratio i/s', 'Retail ratio i/s', 'Wholesale ratio i/s'
#'M. PCE',
begindate = '1992-01-01' # Start of data download

# Download quarterly target data and calculate qoq growth
Target_dat = hv.data(Targetcodes ,  HVdb, frequency='Q', startdate=begindate)

# Target_dat[Targetcodes] = Target_dat[Targetcodes].pct_change()*100

# Download monthly forecasting data and calculate m/m growth for those that need to be transformed
Monthly_dat = hv.data(Reg_codes ,  HVdb, frequency='M', startdate=begindate)
Monthly_dat2 = hv.data(['rmfg'] ,  'ppir', frequency='M', startdate=begindate)
Monthly_dat = pd.concat((Monthly_dat, Monthly_dat2), axis=1)
Reg_codes = ['nti','nmi', 'nri', 'nwih', 'rmfg']  # Haver codes last is goods cpi ex energy  'ntr', 'nmri', 'nrr', 'nwrh',
Reg_names = ['Tot inv.', 'Manufact inv.', 'Retail inv.', 'Wholesale inv.', 'manufacturing PPI']

# # Rebase CPI to 2012
Monthly_dat['rmfg'] = 100*Monthly_dat['rmfg']/np.mean(Monthly_dat.loc['2012-01':'2012-12', 'rmfg'])

# Make all nominal inventories real inventories indexed to 2012 as in NIPA

for ii in ['nti','nmi', 'nri', 'nwih']:
    Monthly_dat[ii] = 100*Monthly_dat[ii].div(Monthly_dat['rmfg'])
# Drop CPI
Monthly_dat = Monthly_dat.drop(columns=['rmfg'])
Reg_names = ['Tot inv.', 'Manufact inv.', 'Retail inv.', 'Wholesale inv.']

Monthly_dat[['nti','nmi', 'nri', 'nwih']] = Monthly_dat[['nti','nmi', 'nri', 'nwih']].diff()
#'cbhm', 
# Remove first NA period after calculating percentage changes
Target_dat = Target_dat[1:] # Get rid of first Q
Delay = [1,1,1,1]
Monthly_dat = DelaySeries(Monthly_dat, Delay)

CombinedModel = ['Tot inv.', 'Retail inv.']
# Get a datetime vector starting at new truncated data start (+ nowcast quarter). Used for plotting.
date_list = pd.date_range(pd.to_datetime(Target_dat.index.astype(str))[0], periods=len(Target_dat)+1, freq = 'Q').to_pydatetime().tolist()


####################################################
# View data - uncomment if needed

# Plot target series
# fig, (ax1) = plt.subplots(1, 1)
# Target_dat[Targetcodes].plot(figsize=(20,10), linewidth=5, fontsize=20, ax=ax1)
# plt.xlabel('Year', fontsize=20)

# # plot all series in a dataframe
# fig = plt.figure(figsize=(10,10))
# for c,num in zip(Monthly_dat.columns, range(1,len(Monthly_dat.columns))):
#     ax = fig.add_subplot(3,3,num)
#     #ax.plot(Monthly_dat[c].index, Monthly_dat[c].values)
#     Monthly_dat[c].plot(ax = ax)
#     ax.set_title(c)
# #
# plt.tight_layout()
# plt.show()


####################### Test forecast combinations and come up with optimal forecast

# Function takes a list of variables - make using pandas data from Haver
MonthlyListHav = []
for ii in Monthly_dat.columns:
    MonthlyListHav.append(Monthly_dat[ii][0:].values.reshape(-1,1))

# Initiate MIDAS function with required data and arguments
TestFcastHav = ForecastCombine(GDP=Target_dat.values, monthlyseries=MonthlyListHav, skip=40, ARt = 5, maxlag = 8, ARinclude = 0, weighttype = 'mse', names = Reg_names, MultiModel = CombinedModel) 
TestFcastHav.Optimize() # Find optimal forecasting lags and out of sample RMSE for each explanatory variable - calculate combined forecast.
TestFcastHav.PlotBest(date_list, Quarterlyname) # Plot out of sample optimal forecast in months 1-3
TestFcastHav.PrintNiceOutput(date_list) # Print table of optimal nowcast, individual nowcast, and RMSEs.
#        
    