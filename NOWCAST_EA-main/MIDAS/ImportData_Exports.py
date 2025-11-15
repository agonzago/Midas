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
Targetcodes = ['xh'] # nonresidential investment Haver code
Quarterlyname = 'Exports' # Readable name for plot
Reg_codes = ['tmxah','bpxmm', 'taxa', 'bmbcsx', 'nmsdg', 'nmocg']  # Haver codes  
Reg_names = ['Real goods exports' ,'Nom. Goods Exports', 'Adv. Nom. Goods Exports', 'Nom. Services exports',  'Durable goods ord.' , 'Capital goods'] # Nice names for table , 'Markit Manu PMI'
#'M. PCE',
begindate = '1992-01-01' # Start of data download

# Download quarterly target data and calculate qoq growth
Target_dat = hv.data(Targetcodes ,  HVdb, frequency='Q', startdate=begindate)

Target_dat[Targetcodes] = Target_dat[Targetcodes].pct_change()*100

# Download monthly forecasting data and calculate m/m growth for those that need to be transformed
Monthly_dat = hv.data(Reg_codes ,  HVdb, frequency='M', startdate=begindate)
# Monthly_dat2 = hv.data('s111mmm' ,  'MKTPMI', frequency='M', startdate=begindate)
# Monthly_dat = pd.concat([Monthly_dat, Monthly_dat2], axis=1)
Monthly_dat[['tmxah','bpxmm', 'taxa', 'bmbcsx', 'nmsdg', 'nmocg']] = Monthly_dat[['tmxah','bpxmm', 'taxa', 'bmbcsx', 'nmsdg', 'nmocg']].pct_change(fill_method=None)*100
# add advance goods imports to nominal goods imports if available, then delete.
Monthly_dat['bpxmm'] = Monthly_dat['bpxmm'].fillna(Monthly_dat['taxa'])
Monthly_dat = Monthly_dat.drop(['taxa'], axis=1) # remove advance
Reg_names.remove('Adv. Nom. Goods Exports') 
# Remove first NA period after calculating percentage changes
Target_dat = Target_dat[1:] # Get rid of first Q
# Delay series based on their release date
Delay = [1,0,0,0,0]
Monthly_dat = DelaySeries(Monthly_dat, Delay)


# Get a datetime vector starting at new truncated data start (+ nowcast quarter). Used for plotting.
date_list = pd.date_range(pd.to_datetime(Target_dat.index.astype(str))[0], periods=len(Target_dat)+1, freq = 'Q').to_pydatetime().tolist()


####################################################
# View data - uncomment if needed

# # plot all series in a dataframe
# fig = plt.figure(figsize=(10,10))
# for c,num in zip(Monthly_dat.columns, range(1,len(Monthly_dat.columns)+1)):
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
TestFcastHav = ForecastCombine(GDP=Target_dat.values, monthlyseries=MonthlyListHav, skip=40, ARt = 5, maxlag = 10, ARinclude = 0, weighttype = "mse", names = Reg_names) 
TestFcastHav.Optimize() # Find optimal forecasting lags and out of sample RMSE for each explanatory variable - calculate combined forecast.
TestFcastHav.PlotBest(date_list, Quarterlyname) # Plot out of sample optimal forecast in months 1-3
TestFcastHav.PrintNiceOutput(date_list) # Print table of optimal nowcast, individual nowcast, and RMSEs.
#        
    