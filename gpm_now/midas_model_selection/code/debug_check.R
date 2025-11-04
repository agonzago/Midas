library(data.table); library(lubridate)
monthly <- fread("/home/andres/work/Midas/gpm_now/retriever/brazil/output/transformed_data/monthly.csv"); monthly[, date:=as.Date(date)]
quarterly <- fread("/home/andres/work/Midas/gpm_now/retriever/brazil/output/transformed_data/quarterly.csv"); quarterly[, date:=as.Date(date)]; quarterly[, quarter:=paste0(year(date),'Q',quarter(date))]
vi <- readRDS("/home/andres/work/Midas/gpm_now/midas_model_selection/data/vintages/pseudo_vintages_2022Q2.rds")
print(class(vi)); print(length(vi)); print(head(names(vi)))
frs <- sort(as.Date(names(vi)))
var <- "DA_IC_Br"
# last month on first Friday
elem <- vi[[as.character(frs[1])]]
print(class(elem)); print(elem)
vinfo <- elem$availability
print(class(vinfo))
print(head(vinfo))
lm <- vinfo[vinfo[["variable"]]==var, "last_month"][1][[1]]
print(list(firstFriday=frs[1], last_month=lm))
K <- 6
x <- data.table(date=monthly$date, val=monthly[[var]])
x <- x[date<=lm]
print(tail(x,8))
vals <- tail(x$val, K)
print(vals)
