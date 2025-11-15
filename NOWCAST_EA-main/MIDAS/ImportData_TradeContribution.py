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
Targetcodes = ['ptxneth'] # nonresidential investment Haver code
Quarterlyname = 'TradeCont' # Readable name for plot
Reg_codes = ['bpbmm', 'bgsb', 'tmxah', 'tmmcah']  # Haver codes  
Reg_names = ['Nom. goods balance', 'Nom. goods and serv.', 'Real exports', 'Real imports'] # Nice names for table , 'Markit Manu PMI'
#'M. PCE',
begindate = '1992-01-01' # Start of data download

# Download quarterly target data and calculate qoq growth
Target_dat = hv.data(Targetcodes ,  HVdb, frequency='Q', startdate=begindate)

#Target_dat[Targetcodes] = Target_dat[Targetcodes].pct_change(p)*100

# Download monthly forecasting data and calculate m/m growth for those that need to be transformed
Monthly_dat = hv.data(Reg_codes ,  HVdb, frequency='M', startdate=begindate)

#########################################################
# Supplmental data for scaling trade balance with nominal GDP and appending advance estimate if available
# Get advance estimate for goods trade 
Advestimate = hv.data('tabca' , HVdb, frequency='M', startdate=begindate)
Monthly_dat = pd. merge(Monthly_dat, Advestimate, left_index=True, right_index=True, how='outer') 
Monthly_dat['bpbmm'] = Monthly_dat['bpbmm'].fillna(Monthly_dat['tabca'])


QGDP = hv.data(['gdp', 'gdph'] ,  HVdb, frequency='Q', startdate=begindate)
QGDP['Quarter'] = QGDP.index.quarter
QGDP['Year'] = QGDP.index.year

Monthly_dat['Quarter'] = Monthly_dat.index.quarter
Monthly_dat['Year'] = Monthly_dat.index.year

Monthly_dat = pd.merge(Monthly_dat, QGDP, on=['Year', 'Quarter'], how='left')
Monthly_dat['gdp'] =  Monthly_dat['gdp'].fillna(method="ffill")
Monthly_dat['gdph'] =  Monthly_dat['gdph'].fillna(method="ffill")
Monthly_dat[['bpbmm', 'bgsb']] = Monthly_dat[['bpbmm', 'bgsb']].div(Monthly_dat.gdp, axis=0)
Monthly_dat[['tmxah', 'tmmcah']] = Monthly_dat[['tmxah', 'tmmcah']].div(Monthly_dat.gdph, axis=0)

Monthly_dat = Monthly_dat.drop(['Quarter', 'Year', 'gdp','gdph', 'tabca'], axis=1)

CombinedModel = ['Real exports', 'Real imports']

# Monthly_dat2 = hv.data('s111mmm' ,  'MKTPMI', frequency='M', startdate=begindate)
# Monthly_dat = pd.concat([Monthly_dat, Monthly_dat2], axis=1)
#Monthly_dat[['tmxah', 'bmbcsx']] = Monthly_dat[['tmxah', 'bmbcsx']].pct_change(fill_method=None)*100
#'cbhm', 
# Remove first NA period after calculating percentage changes
Target_dat = Target_dat[1:] # Get rid of first Q
Delay = [0,0,0,0]
Monthly_dat = DelaySeries(Monthly_dat, Delay)

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
TestFcastHav = ForecastCombine(GDP=Target_dat.values, monthlyseries=MonthlyListHav, skip=30, ARt = 5, maxlag = 10, ARinclude = 0, weighttype = "mse", names = Reg_names, MultiModel = CombinedModel) 
TestFcastHav.Optimize() # Find optimal forecasting lags and out of sample RMSE for each explanatory variable - calculate combined forecast.
TestFcastHav.PlotBest(date_list, Quarterlyname) # Plot out of sample optimal forecast in months 1-3
TestFcastHav.PrintNiceOutput(date_list) # Print table of optimal nowcast, individual nowcast, and RMSEs.
#        
    