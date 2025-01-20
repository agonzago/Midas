rm(list=ls())

# Packages for nowcasting 
if (!require("midasr")) {install.packages("midasr"); library("midasr")}

# Packages for data retrive 
if (!require("readxl")) {install.packages("readxl"); library("readxl")}
if (!require("lubridate")) {install.packages("lubridate"); library("lubridate")}
if (!require("dplyr")) {install.packages("dplyr"); library("dplyr")}
if (!require("tidyverse")) {install.packages("tidyverse"); library("tidyverse")}
if (!require("reticulate")) {install.packages("reticulate"); library("reticulate")}
if (!require("zoo")) {install.packages("zoo"); library("zoo")}
if (!require("lubridate")) {install.packages("lubridate"); library("lubridate")}

# Load midas package
if (!require("midasr")) {install.packages("midasr"); library("midasr")}


use_python("C:/ProgramData/anaconda3", required=TRUE)
imf_datatools <- reticulate::import("imf_datatools")


RetriveTransformDAta <-function(monthly_codes, var_names_m, quarterly_codes, var_names_q)
{
  database <-"EMERGELA" 
  havercodes_m <- paste(monthly_codes, "@", rep(database, length(quarterly_codes)), sep="")
  havercodes_q <- paste(quarterly_codes, "@", rep(database, length(quarterly_codes)), sep="")
  #Monthly (Load data and changing names)
  mex_m <-imf_datatools$get_haver_data(havercodes_m)
  colnames(mex_m) <- var_names_m
  
  # Transformations for monthly indicators
  ##Create quarterly averages and growth rate 
  mex_m$Quarter <- as.yearqtr(row.names(mex_m), format="%Y-%m-%d")
  mex_q_from_m <- mex_m %>%group_by(Quarter) %>% summarise_all("sum",  na.rm=FALSE)
  
  
  # Quarterly 
  mex_q <-imf_datatools$get_haver_data(havercodes_q)
  colnames(mex_q) <- var_names_q
  
  
  ## Merge to quarterly data set
  mex_q$Quarter <- as.yearqtr(row.names(mex_q), format="%Y-%m-%d")
  mex_q <- merge(mex_q, mex_q_from_m, by = "Quarter")
  mex_q$YEAR = format(mex_q$Quarter, "%Y")
  
  rm(mex_q_from_m)
  
  #Create some transformations for quarterly data
  mex_q <- mex_q %>%
    mutate(across(where(is.numeric), 
                  list(
                    L = ~ log(.),
                    DL = ~ c(NA, 400*diff(log(.))),   #QoQ log growth 
                    DA = ~ 400*((.)/lag(.)-1),        #QoQ Growth rate annualized 
                    D = ~ 100*((.)/lag(.)-1),         #QoQ Growth rate
                    D4= ~ 100*((.)/(lag(.,4)-1)) ##YOY
                  ), 
                  .names = "{.fn}_{.col}"
    ))
  
  row.names(mex_q)<- as.Date(mex_q$Quarter , format="%Y-%m-%d")
  
  #Create some transformations for quarterly data
  mex_m <- mex_m %>%
    mutate(across(where(is.numeric), 
                  list(
                    DA = ~ 1200*((.)/lag(.)-1),       #QoQ Growth rate annualized 
                    D = ~ 100*( (.)/lag(.)-1 ),         #QoQ Growth rate
                    D4= ~ 100*((.)/lag(.,12)-1)     #YOY
                  ), 
                  .names = "{.fn}_{.col}"
    ))
  mex_m <- mex_m %>%  select(-Quarter) 
  

  # Compute transformations for monthly data 
  
  return(list(monthly = mex_m, 
              quarterly=mex_q))
  
}


#Quaterly Data
quarterly_codes <- c("S273NGPC", "S273NCC", "S273NCPC","S273NCGC","S273NFC", "S273NFPC", "S273NFGC")
var_names_q <-  c("GDP", "CONT",  "CONPR", "CONPU","INVT","INVPR", "INVPU")


#Monthly Data
monthly_codes <- c("S273GVI", "S273GVFI", "S273VMA", "S273VMNA", "S273TRS", "S273TR1", "S273TRN", "S273RST", "S273TR6", "S273RSH", "S273TR8" )
var_names_m <-  c("EAI", "GVFI", "PMI_M", "PMI_NM", "RETSALES", "RETGRO", "RETSUP", "RETTEXT", "RETPERF", "RETFURN", "RETCAR")

mex_data <- RetriveTransformDAta( monthly_codes, var_names_m, quarterly_codes, var_names_q)

mex_m<-mex_data$monthly
mex_q<-mex_data$quarterly

setwd("G:/My Drive/Work/Monitoring_toolkit/Mexico")
load("mex_M.Rdata")
load("mex_Q.Rdata")
## Done with data preparation 

# Create a time series object ts()
mex_q$Quarter <- as.Date(mex_q$Quarter)
start_year <- year(min(mex_q$Quarter))
start_quarter <- quarter(min(mex_q$Quarter))  
# Convert data frame to ts object
mex_q_ts <- ts(mex_q, start = c(start_year, start_quarter), frequency = 4)

mex_m$Month <- as.Date(row.names(mex_m))
start_year <- year(min(mex_m$Month))
start_month <- month(min(mex_m$Month))  
mex_m_ts <- ts(mex_m, start = c(start_year, start_month), frequency = 12)

start_es_q <- c(2000,1) #First quarter 
end_es_q <- c(2023,1) # Last quarter
mex_q_est <- window(mex_q_ts, start = start_es_q, end = end_es_q) #Sample for quarterly data

start_es_m <- c(2000,1) #First month  
end_es_m <- c(2023,3) # Last month 
mex_m_est <- window(mex_m_ts, start = start_es_m, end = end_es_m)

#Select some variables 
D_GDP <- mex_q_est[, "D_GDP"]
D_GDP_le <- stats::lag(D_GDP, -1)
D_EAI <-mex_m_est[, "D_EAI"]
D_GVFI <-mex_m$D_GVFI

# Midas forecast horizon 1 (Using one lag GDP and one lag high frequency data)
eq_u_h1 <- midas_u(D_GDP ~  mls(D_GDP, 2,1) + mls(D_EAI, k = 4:6, m = 3) )  #Using one quarter lag D_EAI
#eq_u_h1 <- midas_u(D_GDP ~  mls(D_GDP, 1,1) + mls(D_EAI, k = 4:9, m = 3) )  #Using two quarter lag D_EAI
eq_u_h2 <- midas_u(D_GDP_le ~  mls(D_GDP_le, 2,1) + mls(D_EAI, k = 4:6, m = 3) )  #Using second quarter lag D_EAI

# Forecast horizon h= 1
xn <- c( window(mex_m_ts[, "D_EAI"], start=c(2023,4), end=c(2023,4)), NA, NA) #, 0.1441910)
fh1 <- forecast(eq_u_h1, newdata=list( D_EAI=c(xn), D_GDP =c(NA)), method = "static")
fh1 <- forecast(eq_u_h1, newdata=list( D_EAI=c(xn), D_GDP =c(NA)), method = "static")
#fh1b <- forecast(eq_u_h1b, newdata=list( D_EAI=c(xn), D_GDP =c(NA)), method = "dynamic")

# Forecast horizon h= 2
fh2 <- forecast(eq_u_h2, newdata=list( D_EAI=c(xn), D_GDP =c(NA)), method = "dynamic")

c(fh1$mean, fh2$mean)
