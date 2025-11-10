library(midasr)
source("R/midas_models.R")

# Create simple test data
set.seed(123)
y_q <- ts(rnorm(40, mean = 2, sd = 0.5), start = c(2010, 1), frequency = 4)
x_m <- ts(rnorm(120, mean = 100, sd = 10), start = c(2010, 1), frequency = 12)

# Fit model using fit_midas_unrestricted
cat("======= Using fit_midas_unrestricted =======\n")
model1 <- fit_midas_unrestricted(
  y_q = y_q,
  x_m = x_m,
  y_lag = 2,
  x_lag = 4,
  month_of_quarter = 2
)

cat("\nmodel1$fit formula:\n")
print(formula(model1$fit))
cat("\nmodel1$fit formula environment:\n")
print(ls(environment(formula(model1$fit))))

# Fit directly with midas_u
cat("\n\n======= Using midas_u directly =======\n")
model2 <- midas_u(y_q ~ mls(y_q, 1:2, 1) + mls(x_m, 2:6, 3))

cat("\nmodel2 formula:\n")
print(formula(model2))
cat("\nmodel2 formula environment:\n")
print(ls(environment(formula(model2))))

# Try forecast with model2
cat("\n\n======= Testing forecast with model2 (direct) =======\n")
y_ext <- c(y_q, NA)
x_ext <- c(x_m, rep(NA, 3))
newdata <- list(y_q = y_ext, x_m = x_ext)

tryCatch({
  fc <- forecast::forecast(model2, newdata = newdata, method = "static")
  cat("SUCCESS! Point forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})

# Try forecast with model1
cat("\n\n======= Testing forecast with model1 (from fit_midas_unrestricted) =======\n")
tryCatch({
  fc <- forecast::forecast(model1$fit, newdata = newdata, method = "static")
  cat("SUCCESS! Point forecast:", tail(fc$mean, 1), "\n")
}, error = function(e) {
  cat("FAILED:", e$message, "\n")
})
