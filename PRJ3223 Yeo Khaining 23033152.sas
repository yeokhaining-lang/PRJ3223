/* 1. Import CSV exported from SQL (or use LIBNAME for DB connection) */
proc import datafile="/folders/myfolders/model_features.csv"
    out=work.model_features
    dbms=csv
    replace;
    getnames=yes;
run;

/* 2. Sort & create time variables */
proc sort data=work.model_features; by site_id ts_hour; run;

data work.model_features2;
  set work.model_features;
  format ts_hour datetime20.;
  /* Example: create rolling features */
  by site_id;
  retain roll_3h_sum;
  if first.site_id then roll_3h_sum = .;
  /* use PROC EXPAND or DATA step for proper moving stats later */
run;
proc expand data=work.model_features out=work.model_ts method=step;
  by site_id;
  id ts_hour;
  convert avg_power_kw = avg_power_kw_interp / transformout=(observed);
  /* can create moving averages, lags here too */
run;
proc arima data=work.site_data;
  identify var=avg_power_kw(1) nlag=48;
  estimate p=1 q=1 seasonal=(12);
  forecast lead=24 out=work.arima_forecast;
run;

proc hpforest data=work.train;
   target avg_power_kw;
   input lag_1h lag_24h avg_ghi ghi_forecast_24h hour_of_day day_of_week / level=interval;
   ods output FitStatistics=rf_stats;
   save rstore="rf_model.rstore";
run;
/* compute error metrics */
data work.eval;
  set work.forecasts;
  err = forecast - avg_power_kw;
  abs_err = abs(err);
  sq_err = err**2;
  pct_err = abs_err / (avg_power_kw + 0.001);
run;

proc means data=work.eval n mean std sum;
  var err abs_err sq_err pct_err;
Run;
