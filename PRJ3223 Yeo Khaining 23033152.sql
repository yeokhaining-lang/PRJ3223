-- create hourly aggregates
CREATE TABLE solar_hourly AS
SELECT
  site_id,
  DATE_TRUNC('hour', timestamp) AS ts_hour,
  AVG(power_kw) AS avg_power_kw,
  MAX(power_kw) AS max_power_kw,
  SUM(power_kwh) AS total_kwh,
  AVG(ghi_wm2) AS avg_ghi,
  AVG(air_temp_c) AS avg_temp,
  AVG(cloud_cover_pct) AS avg_cloud
FROM raw_measurements
GROUP BY site_id, DATE_TRUNC('hour', timestamp);

Feature joins and lag features:
-- join with day-ahead forecast and create lag features
CREATE TABLE model_features AS
SELECT
  s.site_id,
  s.ts_hour,
  s.avg_power_kw,
  f.ghi_forecast AS ghi_forecast_24h,
  LAG(s.avg_power_kw, 1) OVER (PARTITION BY s.site_id ORDER BY s.ts_hour) AS lag_1h,
  LAG(s.avg_power_kw, 24) OVER (PARTITION BY s.site_id ORDER BY s.ts_hour) AS lag_24h,
  EXTRACT(HOUR FROM s.ts_hour) AS hour_of_day,
  EXTRACT(DOW FROM s.ts_hour) AS day_of_week
FROM solar_hourly s
LEFT JOIN ghi_forecasts f
  ON s.site_id = f.site_id AND s.ts_hour = f.forecast_ts;

Export model_features as CSV for SAS Studio or connect SAS to the database (ODBC/JDBC).