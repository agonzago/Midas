rm(list=ls())

library("readxl")
library("lubridate")
library("dplyr")
library("tidyverse")
library("reticulate")
library("zoo")
library("lubridate")
library(tseries)
library("midasr")
library(knitr)
install.packages(c('readx', 'dplyr', 'tidyverse', 'reticulate', 'zoo', 'lubridate', 'tseries', 'midasr', 'knitr'))
  
reticulate::use_python("//ecnswn06p/apps/python/python312", required=TRUE)
imf_datatools <- reticulate::import("imf_datatools")

setwd('E:/data/gpm/SANDBOXES/andres/Mexico/MEX_MIDAS/')
#Quaterly Data
quarterly_codes <- c("S273NGPC")
var_names_q <-  c("GDP")

database <-"EMERGELA" 
havercodes_q <- paste(quarterly_codes, "@", rep(database, length(quarterly_codes)), sep="")
dquarter_c <-imf_datatools$get_haver_data(havercodes_q, eop = TRUE)
colnames(dquarter_c) <- var_names_q
dquarter_c$Date <- as.Date(rownames(dquarter_c), format = "%Y-%m-%d")

#Data Transform
dquarter_c <- dquarter_c %>%
    mutate(across(where(is.numeric), 
                  list(      
                    #DL = ~ c(NA, 100*diff(log(.)))   #QoQ log growth  
                    DL = ~ 100 * ((.) / lag(.) - 1) # QoQ Growth rate
                    ), 
                  .names = "{.fn}_{.col}"
    ))

#Monthly Data
monthly_codes <- c("S273VMA",	"S273VMNA"	,"S273VPCC",	"N273VCP"	,"S273VPMI",	"N273OMV",	"S273DW",	"N273IXV",
                 	"S273ELUR",	"C273TXUQ",	"S273TMD",	"S273TXD",	"H273IUQ", "H273SA",	"C273ST",	"S273TRS",	"N273IZUS")
 
var_names_m <-  c("BUS_CLIM_MFG",	"BUS_CLIM_NONMFG",	"CONSUMER_CONF","PRODUCER_CONF","PMI_MANU"	,"AUTO_PROD"	,"IP",	"AUTO_EXPORT",	"UNEMP",	"PETRO_EXP",	"IMP",	"EXP",	"PETRO_PROD",	
                  "AUTO_SALES",	"TRUCK_SALES",	"RETAIL_SALES",	"TRADE_BAL"	)

#"S273NGPC", "GDP"
database <-"EMERGELA" 
havercodes_m <- paste(monthly_codes, "@", rep(database, length(monthly_codes)), sep="")
dmonthly_c <-imf_datatools$get_haver_data(havercodes_m, eop=TRUE)
colnames(dmonthly_c) <- var_names_m
dmonthly_c$Date <- as.Date(rownames(dmonthly_c), format = "%Y-%m-%d")

database <-"USECON" 
monthly_codes <-c("CSENT",	"CCIN",	"NAPMC",	"NRS",	"IP",	"CUT",	"HST",	"NWSH11",	"MV000MC",	"MV000MT")
var_names_m <-  c("CONS_SENTI_US",	"CONS_CONF_US"	,"PMI_COMP_US",	"RETAIL_SALES_US",	"IP_US"	,"CAP_UTILI_US",	"HOUSING_STARTS_US",	"AUTO_SALES_US",	"CAR_IMP_US",	"TRUCK_IMP_US"	)
havercodes_m <- paste(monthly_codes, "@", rep(database, length(monthly_codes)), sep="")
dmonthly_us <-imf_datatools$get_haver_data(havercodes_m, eop = TRUE)
colnames(dmonthly_us) <- var_names_m
dmonthly_us$Date <- as.Date(rownames(dmonthly_us), format = "%Y-%m-%d")

#Monthly Data
data_m <- merge(dmonthly_c, dmonthly_us, by = "Date")
#Data Transform
save(data_m, file = "data_m.RData")
save(data_q_c, file = "data_q.RData")

data_m <- data_m %>%
    mutate(across(where(is.numeric), 
                  list(                    
                    #DL = ~ c(NaN, 100*diff(log(.)))   #QoQ log growth    
                    DL = ~ 100 * ((.) / lag(.) - 1) # QoQ Growth rate
                  ), 
                  .names = "{.fn}_{.col}"
    ))


## Done with data preparation 
## Convert data frame to ts object
  start_year <- year(min(data_m$Date))
  start_month <- month(min(data_m$Date))
  data_m_ts <- ts(data_m, start = c(start_year, start_month), frequency = 12)
  
  start_year <- year(min(dquarter_c$Date))
  start_quarter <- quarter(min(dquarter_c$Date))  
  dquarter_c_ts <- ts(dquarter_c, start = c(start_year, start_quarter), frequency = 4)
 
# Set selection sample
  start_es_q <- c(2005, 2) # Second quarter
  end_es_q <- c(2024,2) 
  q_est <- window(dquarter_c_ts, start = start_es_q, end = end_es_q) # Sample for quarterly data
 
  start_es_m <- c(2005, 4) # First month of the second quarter 
  end_es_m <- c( end(q_est)[1], end(q_est)[2]*3) # Last month of the last quarter
  m_est <- window(data_m_ts, start = start_es_m, end = end_es_m)
#This next function is still under construction (not really working)
Compute_MSE_selected_model <- function(y, x, month_of_quarter, out_best_model) {   

   #Nowcast with u-midas
 indic <- c( "DL_BUS_CLIM_MFG",  "DL_BUS_CLIM_NONMFG",
  "DL_CONSUMER_CONF",     "DL_PRODUCER_CONF",     "DL_OPI_SURVEY",
 "DL_AUTO_PROD",         "DL_IP",                "DL_AUTO_EXPORT",
 "DL_UNEMP",             "DL_PETRO_EXP",         "DL_IMP",
 "DL_EXP",               "DL_PETRO_PROD",        "DL_AUTO_SALES",
 "DL_TRUCK_SALES",       "DL_RETAIL_SALES",      "DL_TRADE_BAL",
 "DL_CONS_SENTI_US",     "DL_CONS_CONF_US",      "DL_PMI_COMP_US",
 "DL_RETAIL_SALES_US",   "DL_IP_US",             "DL_CAP_UTILI_US",
 "DL_HOUSING_STARTS_US", "DL_AUTO_SALES_US",     "DL_CAR_IMP_US",
 "DL_TRUCK_IMP_US")
   

    T <- length(y)
    xm_lag <- out_best_model$xm_lag
    y_lag <- out_best_model$y_lag
    insample = 1:(T - 3)
    outsample = (T-2):(T-2)
    #datasplit <- split_data(fullsample, insample, outsample)
    datasplit <- split_data(list(y=y, x=x), insample, outsample)
    ytmp <- datasplit$indata$y
    xtmp <- datasplit$indata$x
    
    fit <- midas_u(ytmp ~ mls(ytmp, 1:y_lag, 1) + mls(xtmp, month_of_quarter:(month_of_quarter+xm_lag), 3)) 
    # Assumnes that the forecast is done the last month in the quarter fmls (change this)
    fore<- forecast(fit, list(y=ytmp[(T - 3)], xtmp=datasplit$outdata$x), method='static')
    o <- datasplit$outdata$y
    fore_err <- ( o - fore$mean )
    print(fore_err)
}

Select_model_BIC <- function(max_Ylag, max_Xm_lag, month_of_quarter, y, x) {
  # Model selection using BIC (this is useful for midas_u)
  # Generates a Y and X matrices to select the model keeping sample size constant
  # Adjusted to select the model for each month in a quarter 
  # month_of_quarter =0 (Assumes that data is available until last month of quarter) 
  #                  =1 (Assumes that data is available until the second month of the quarter)       
  #                  =2 (Assumes that data is available until the fist month quarter) 

  ## Fits initially models without lags of the Y variable
  fit <- midas_u(y ~ mls(x, month_of_quarter:(month_of_quarter+max_Xm_lag), 3))
  xmat <- model.matrix(fit)
  ymat <- fit$model$y
  min_bic <- 10e6
  
  jy_ast <- 0 # No lags in Y
  for (xj in 1:max_Xm_lag+1) {
      temp <- lm(ymat ~ xmat[, 2:(1 + xj)])  
      tbic <- BIC(temp)
      if (tbic < min_bic) {
        min_bic <- tbic        
        xj_ast <- xj        
      }
    }

#Models with lags in Y
  fit <- midas_u(y ~ mls(y, 1:max_Ylag, 1) + mls(x, month_of_quarter:(month_of_quarter+max_Xm_lag), 3))
  xmat <- model.matrix(fit)
  ymat <- fit$model$y
 
  for (jy in 1:max_Ylag) {
    for (xj in 1:max_Xm_lag+1) {
      temp <- lm(ymat ~ xmat[, 1:(jy + 1)] + xmat[, (max_Ylag + 2):(max_Ylag + 1 + xj)])  
      tbic <- BIC(temp)
      if (tbic < min_bic) {
        min_bic <- tbic        
        xj_ast <- xj
        jy_ast <- jy
      }
    }
  }
  # Map indices to parameter for the midas_u
  return(list(xm_lag=(xj_ast-1), y_lag = jy_ast, bic=min_bic))
}

Select_model_BIC_2 <- function(max_Ylag, max_Xm_lag, y, x) {
  # Model selection using BIC (this is useful for midas_u)
  # Generates a Y and X matrices to select the model keeping sample size constant  
  # month_of_quarter =0 (Assumes that data is available until last month of quarter) 
  
  ## Fits initially models without lags of the Y variable
  max_Ylag=4
  max_Xm_lag=6
  month_of_quarter <-0
  fit <- midas_u(y ~ lag(mls(x, month_of_quarter:(month_of_quarter+max_Xm_lag), 3),1))
  xmat <- model.matrix(fit)
  ymat <- fit$model$y

  min_bic <- 10e6  
  jy_ast <- 0 # No lags in Y
  for (xj in 1:max_Xm_lag+1) {
      temp <- lm(ymat ~ xmat[, 2:(1 + xj)])  
      tbic <- BIC(temp)
      if (tbic < min_bic) {
        min_bic <- tbic        
        xj_ast <- xj        
      }
    }

#Models with lags in Y
  fit <- midas_u(y ~ mls(y, 1:max_Ylag, 1) + lag(mls(x, month_of_quarter:(month_of_quarter+max_Xm_lag), 3),1))
  xmat <- model.matrix(fit)
  ymat <- fit$model$y
 
  for (jy in 1:max_Ylag) {
    for (xj in 1:max_Xm_lag+1) {
      temp <- lm(ymat ~ xmat[, 1:(jy + 1)] + xmat[, (max_Ylag + 2):(max_Ylag + 1 + xj)])  
      tbic <- BIC(temp)
      if (tbic < min_bic) {
        min_bic <- tbic        
        xj_ast <- xj
        jy_ast <- jy
      }
    }
  }
  # Map indices to parameter for the midas_u
  return(list(xm_lag=(xj_ast-1), y_lag = jy_ast, bic=min_bic))
}

# Indicator Available month 1 of the quarter without lags
  # indic1 <- c("DL_BUS_CLIM_MFG","DL_BUS_CLIM_NONMFG","DL_PRODUCER_CONF","DL_OPI_SURVEY","DL_AUTO_PROD","DL_AUTO_EXPORT","DL_AUTO_SALES",
  #           "DL_CONS_SENTI_US","DL_CONS_CONF_US","DL_PMI_COMP_US", "DL_PMI_MANU", "DL_CONSUMER_CONF","DL_TRUCK_SALES","DL_RETAIL_SALES_US", "DL_IP_US",
  #           "DL_CAP_UTILI_US")

  indic1 <- c("DL_CAP_UTILI_US","DL_BUS_CLIM_MFG","DL_BUS_CLIM_NONMFG","DL_CONSUMER_CONF",
"DL_PRODUCER_CONF","DL_AUTO_PROD",
"DL_AUTO_EXPORT","DL_AUTO_SALES","DL_TRUCK_SALES",
"DL_PMI_MANU","DL_CONS_SENTI_US","DL_CONS_CONF_US",
"DL_PMI_COMP_US","DL_RETAIL_SALES_US","DL_HOUSING_STARTS_US", "DL_IP_US")

#indic1 <- c("DL_CAP_UTILI_US")

# Indicator Not Available at month of the quarter (3 month lags) 
  # indic2 <- c(	"DL_UNEMP",	"DL_PETRO_EXP",	"DL_IMP",	"DL_EXP",	"DL_PETRO_PROD"	,			
  #           "DL_HOUSING_STARTS_US",	"DL_CAR_IMP_US","DL_TRUCK_IMP_US", "DL_IP", "DL_TRADE_BAL", "DL_AUTO_SALES_US")

   indic2 <- c("DL_IMP","DL_IP","DL_UNEMP","DL_PETRO_EXP",
 "DL_PETRO_PROD","DL_RETAIL_SALES","DL_TRADE_BAL",
 "DL_AUTO_SALES_US", "DL_CAR_IMP_US","DL_TRUCK_IMP_US", "DL_EXP")
#indic2 <- c("DL_IMP")

  y <- q_est[, "DL_GDP"]
  
  outS<-matrix(NA, length(indic1)+length(indic2), 2)
  s<-1
  # Models for indicators not available the first month of the quarter
  for ( j in indic2){
    
    x <- m_est[, j]      
    out_best_model<-Select_model_BIC_2(max_Ylag=4, max_Xm_lag=6,y=y, x=x)
    
    ylag <- out_best_model$y_lag
    xlag <- out_best_model$xm_lag
    
    if (ylag==0){
        #fit_best <- midas_u(y~lag(mls(x,0:(xlag),3),1))     
        stmp <- paste("fit_best <- midas_u(y~lag(mls(x,0:", xlag, ", 3),1))", sep="")
    }else{     
        #fit_best <- midas_u(y~mls(y,1:ylag,1)+lag(mls(x,0:xlag,3),1))      
        stmp <- paste("fit_best <- midas_u(y~mls(y,1:", ylag,",1)+lag(mls(x,0:", xlag, ", 3),1))", sep="")
    }    
    eval(parse(text=stmp))
    
    xn <- c(window(data_m_ts[, j],  start = c(2024,4) , end = c(2024,6)))  # This is adding the last data in the sample        
    yn <- window(dquarter_c_ts[, "DL_GDP"],  start = c(2024,2) , end = c(2024,2))  # Last obsevered lag of y
    fh3 <- forecast(fit_best, newdata = list(y = c(yn), x = c(xn)), method = "static")  
    
    #Store Forecast for each model together with the BIC 
    out <- c(fh3$mean, BIC(fit_best))
    
    outS[s,]<-out
    rm(out)
    rm(fit_best)
    rm(fh3)
    rm(out_best_model)
    rm(ylag)
    rm(xlag)
    rm(stmp)
    s<-s+1
  }
  month_of_quarter <- 2 # Models for indicator available the first month of the quarter
 for ( j in indic1){
    
    x <- m_est[, j]
    out_best_model<-Select_model_BIC(max_Ylag=4, max_Xm_lag=6,month_of_quarter, y=y, x=x)
    ylag <- out_best_model$y_lag
    xlag <- out_best_model$xm_lag
    
    if (ylag==0){
      fit_best <- midas_u(y~mls(x,month_of_quarter:(month_of_quarter+xlag),3))     
    }else{     
      fit_best <- midas_u(y~mls(y,1:ylag,1)+mls(x,month_of_quarter:(month_of_quarter+xlag),3))            
    }  
      
    xn <- c(window(data_m_ts[, j],  start = c(2024,7) , end = c(2024,7)),NaN, NaN)  # This is adding the last data in the sample        
    yn <- window(dquarter_c_ts[, "DL_GDP"],  start = c(2024,2) , end = c(2024,2))  # Last obsevered lag of y
    fh3 <- forecast(fit_best, newdata = list(y = c(yn), x = c(xn)), method = "static")  

    #Store Forecast for each model together with the BIC 
    out <- c(fh3$mean, BIC(fit_best))    
    
    outS[s,]<-out
    rm(out)
    rm(fit_best)
    rm(fh3)
    rm(out_best_model)
    rm(ylag)
    rm(xlag)
    
    s<-s+1
    
  }
  #Compute the weigthed mean (using BIC) 
  w=1/outS[,2]
  w=w/sum(w)
  outS[,2]<-w
  midFore <- sum(w*outS[,1])
  colnames(outS)<-c("Forecast", "Weight")
  rownames(outS)<-c(indic2, indic1)
  indx <- order(outS[, 2], decreasing=TRUE)
  cat("----------------------------------","\n")
  cat("Midas forecast",midFore , "\n")
#[indx, ]
  kable(outS[indx,], 
      caption = "Midas Forecast ", 
      digits= 3)%>% print()


#library("forecast")
#model <- auto.arima(y, stepwise = FALSE, D = 0, approximation = FALSE,d=0, max.P=0,max.Q=0, max.p=12, max.q=12)
#forecast::forecast(model,h=1)

for_vars <- grep("^DL_", colnames(data_m_ts), value = TRUE)
tail(data_m_ts[, for_vars], 5)
