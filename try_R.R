rm(list = ls())
setwd("/Volumes/TOSHIBA EXT/main_work/Work/Projects/Midas")
load("mex_M.Rdata")
save(mex_m, file = "mex_M.Rdata")
write.csv(mex_m, file = "mex_M.csv")

load("mex_Q.Rdata")
write.csv(mex_q, file = "mex_Q.csv")
