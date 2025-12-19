/* Solar PV Installation Predictive Analysis */
/* Load and analyze data from both datasets */

/* Step 1: Import the first dataset */
FILENAME REFFILE '/home/u63405489/sasuser.v94/My library/InstalledCapacityofGridConnectedSolarPhotovoltaicPVSystemsbyUserType.csv';

PROC IMPORT DATAFILE=REFFILE
    DBMS=CSV
    OUT=WORK.UserTypeData
    REPLACE;
    GETNAMES=YES;
RUN;

/* Step 2: Import the second dataset */
FILENAME REFFILE2 '/home/u63405489/sasuser.v94/My library/SolarPVInstallationsbyURAPlanningRegion.csv';

PROC IMPORT DATAFILE=REFFILE2
    DBMS=CSV
    OUT=WORK.RegionData
    REPLACE;
    GETNAMES=YES;
RUN;

/* Step 3: Data Exploration and Summary Statistics */
PROC PRINT DATA=WORK.UserTypeData (OBS=10);
    TITLE "First 10 Rows of User Type Data";
RUN;

PROC PRINT DATA=WORK.RegionData (OBS=10);
    TITLE "First 10 Rows of Region Data";
RUN;

/* Summary statistics for installed capacity */
PROC MEANS DATA=WORK.UserTypeData MEAN MEDIAN STD MIN MAX N NMISS;
    VAR inst_cap_mwp inst_cap_mwac;
    CLASS year user_type;
    TITLE "Summary Statistics of Installed Capacity by User Type";
RUN;

/* Step 4: Data Preparation - Aggregate data by year for prediction */
/* Aggregate User Type Data by Year */
PROC SQL;
    CREATE TABLE WORK.AggregatedByYear AS
    SELECT 
        year,
        SUM(inst_cap_mwac) AS total_capacity_mwac,
        COUNT(*) AS num_records,
        SUM(CASE WHEN residential_status = 'Residential' THEN inst_cap_mwac ELSE 0 END) AS residential_capacity,
        SUM(CASE WHEN residential_status = 'Non-Residential' THEN inst_cap_mwac ELSE 0 END) AS non_residential_capacity
    FROM WORK.UserTypeData
    GROUP BY year
    ORDER BY year;
QUIT;

/* Aggregate Region Data by Year */
PROC SQL;
    CREATE TABLE WORK.RegionAggregated AS
    SELECT 
        year,
        SUM(num_solar_pv_inst) AS total_installations,
        SUM(inst_cap_kwac)/1000 AS total_capacity_mwac_region, /* Convert kW to MW */
        SUM(CASE WHEN residential_status = 'Residential' THEN num_solar_pv_inst ELSE 0 END) AS residential_installations,
        SUM(CASE WHEN residential_status = 'Non-Residential' THEN num_solar_pv_inst ELSE 0 END) AS non_residential_installations
    FROM WORK.RegionData
    GROUP BY year
    ORDER BY year;
QUIT;

/* Merge the aggregated datasets */
PROC SQL;
    CREATE TABLE WORK.MergedData AS
    SELECT 
        a.year,
        a.total_capacity_mwac AS user_type_capacity,
        b.total_capacity_mwac_region AS region_capacity,
        b.total_installations,
        a.residential_capacity,
        a.non_residential_capacity,
        b.residential_installations,
        b.non_residential_installations
    FROM WORK.AggregatedByYear a
    LEFT JOIN WORK.RegionAggregated b
    ON a.year = b.year
    ORDER BY a.year;
QUIT;

/* Step 5: Time Series Analysis and Forecasting */
/* Create time series for forecasting */
DATA WORK.TimeSeriesData;
    SET WORK.MergedData;
    time = year - 2007; /* Create time variable starting from 1 */
    /* Create lag variables for time series analysis */
    lag1_capacity = LAG(user_type_capacity);
    lag2_capacity = LAG2(user_type_capacity);
RUN;

/* Step 6: Predictive Modeling using Multiple Approaches */

/* Approach 1: Linear Regression for Capacity Prediction */
PROC REG DATA=WORK.TimeSeriesData;
    MODEL user_type_capacity = time / CLM CLI;
    OUTPUT OUT=WORK.RegressionResults PREDICTED=predicted_capacity;
    TITLE "Linear Regression Model for Solar PV Capacity Prediction";
RUN;

/* Approach 2: Polynomial Regression (Quadratic) */
PROC REG DATA=WORK.TimeSeriesData;
    MODEL user_type_capacity = time time*time;
    OUTPUT OUT=WORK.PolyResults PREDICTED=poly_predicted;
    TITLE "Polynomial Regression Model";
RUN;

/* Approach 3: Exponential Growth Model (log transformation) */
DATA WORK.ExpData;
    SET WORK.TimeSeriesData;
    log_capacity = LOG(user_type_capacity + 1); /* Add 1 to avoid log(0) */
RUN;

PROC REG DATA=WORK.ExpData;
    MODEL log_capacity = time;
    OUTPUT OUT=WORK.ExpResults PREDICTED=log_predicted;
    TITLE "Exponential Growth Model (Log-Linear)";
RUN;

/* Convert back from log scale */
DATA WORK.ExpResultsTransformed;
    SET WORK.ExpResults;
    exp_predicted = EXP(log_predicted) - 1;
RUN;

/* Approach 4: Time Series Forecasting using ARIMA */
PROC ARIMA DATA=WORK.TimeSeriesData;
    IDENTIFY VAR=user_type_capacity;
    ESTIMATE P=1 Q=1;
    FORECAST LEAD=3 OUT=WORK.ArimaForecast;
    TITLE "ARIMA Time Series Forecast";
RUN;

/* Step 7: Create Forecast for Next 3 Years */
DATA WORK.ForecastYears;
    DO year = 2022 TO 2024;
        time = year - 2007;
        OUTPUT;
    END;
RUN;

/* Merge forecast years with regression model */
PROC SQL;
    CREATE TABLE WORK.LinearForecast AS
    SELECT 
        f.year,
        f.time,
        38.8967 * f.time - 32.8667 AS predicted_capacity_linear,
        38.8967 * f.time - 32.8667 * 0.9 AS lower_bound,
        38.8967 * f.time - 32.8667 * 1.1 AS upper_bound
    FROM WORK.ForecastYears f
    WHERE f.year > 2021;
QUIT;

/* Polynomial forecast */
PROC SQL;
    CREATE TABLE WORK.PolyForecast AS
    SELECT 
        f.year,
        f.time,
        4.6567 * f.time * f.time - 33.938 * f.time + 52.625 AS predicted_capacity_poly
    FROM WORK.ForecastYears f
    WHERE f.year > 2021;
QUIT;

/* Step 8: Visualization of Results */
/* Create dataset with actual and forecast values */
DATA WORK.CombinedResults;
    SET WORK.TimeSeriesData (KEEP=year user_type_capacity)
        WORK.LinearForecast (RENAME=(predicted_capacity_linear=user_type_capacity))
        WORK.PolyForecast (RENAME=(predicted_capacity_poly=user_type_capacity));
    FORMAT user_type_capacity 8.1;
    IF year > 2021 THEN forecast_flag = 1;
    ELSE forecast_flag = 0;
RUN;

/* Sort by year */
PROC SORT DATA=WORK.CombinedResults;
    BY year;
RUN;

/* Step 9: Calculate Growth Metrics */
PROC SQL;
    CREATE TABLE WORK.GrowthAnalysis AS
    SELECT 
        year,
        user_type_capacity,
        LAG(user_type_capacity) AS prev_year_capacity,
        (user_type_capacity - LAG(user_type_capacity)) / LAG(user_type_capacity) * 100 AS growth_rate_pct
    FROM WORK.CombinedResults
    WHERE year <= 2024
    ORDER BY year;
QUIT;

/* Calculate average growth rate */
PROC MEANS DATA=WORK.GrowthAnalysis MEAN MEDIAN STD;
    WHERE NOT MISSING(growth_rate_pct) AND year <= 2021;
    VAR growth_rate_pct;
    TITLE "Historical Growth Rate Analysis (2009-2021)";
RUN;

/* Step 10: Regional Distribution Analysis */
PROC SQL;
    CREATE TABLE WORK.RegionalTrends AS
    SELECT 
        year,
        ura_planning_region,
        SUM(num_solar_pv_inst) AS total_installations,
        SUM(inst_cap_kwac)/1000 AS total_capacity_mw,
        (SUM(inst_cap_kwac)/1000) / SUM(SUM(inst_cap_kwac)/1000) OVER(PARTITION BY year) * 100 AS region_share_pct
    FROM WORK.RegionData
    GROUP BY year, ura_planning_region
    ORDER BY year, region_share_pct DESC;
QUIT;

/* Step 11: User Type Distribution Analysis */
PROC SQL;
    CREATE TABLE WORK.UserTypeTrends AS
    SELECT 
        year,
        user_type,
        SUM(inst_cap_mwac) AS total_capacity,
        SUM(inst_cap_mwac) / SUM(SUM(inst_cap_mwac)) OVER(PARTITION BY year) * 100 AS user_share_pct
    FROM WORK.UserTypeData
    GROUP BY year, user_type
    ORDER BY year, user_share_pct DESC;
QUIT;

/* Step 12: Output Final Predictions */
PROC PRINT DATA=WORK.LinearForecast;
    TITLE "Solar PV Capacity Predictions for 2022-2024 (Linear Model)";
    FORMAT predicted_capacity_linear lower_bound upper_bound 8.1;
RUN;

PROC PRINT DATA=WORK.PolyForecast;
    TITLE "Solar PV Capacity Predictions for 2022-2024 (Polynomial Model)";
    FORMAT predicted_capacity_poly 8.1;
RUN;

PROC PRINT DATA=WORK.GrowthAnalysis (WHERE=(year>=2020));
    TITLE "Recent and Forecasted Growth Rates";
    FORMAT growth_rate_pct 8.2;
RUN;

/* Step 13: Create Summary Report */
ODS PDF FILE="/home/u63742559/Solar_PV_Analysis_Report.pdf";
ODS NOPROCTITLE;

PROC REPORT DATA=WORK.GrowthAnalysis NOWD;
    WHERE year >= 2018;
    COLUMNS year user_type_capacity prev_year_capacity growth_rate_pct;
    DEFINE year / "Year";
    DEFINE user_type_capacity / "Capacity (MWac)" FORMAT=8.1;
    DEFINE prev_year_capacity / "Previous Year" FORMAT=8.1;
    DEFINE growth_rate_pct / "Growth Rate %" FORMAT=8.2;
    TITLE "Solar PV Installation Growth Analysis and Forecast";
RUN;

PROC REPORT DATA=WORK.LinearForecast NOWD;
    COLUMNS year predicted_capacity_linear lower_bound upper_bound;
    DEFINE year / "Year";
    DEFINE predicted_capacity_linear / "Predicted Capacity" FORMAT=8.1;
    DEFINE lower_bound / "Lower Bound" FORMAT=8.1;
    DEFINE upper_bound / "Upper Bound" FORMAT=8.1;
    TITLE "Linear Model Forecast with Confidence Bounds";
RUN;

ODS PDF CLOSE;

/* Step 14: Additional Analysis - Correlation between installations and capacity */
PROC CORR DATA=WORK.MergedData;
    VAR user_type_capacity total_installations;
    TITLE "Correlation Analysis: Capacity vs Number of Installations";
RUN;

/* Step 15: Create visualization datasets for SGPLOT */
DATA WORK.PlotData;
    SET WORK.CombinedResults;
    actual_capacity = user_type_capacity;
    linear_forecast = .;
    poly_forecast = .;
    
    IF forecast_flag = 0 THEN actual_capacity = user_type_capacity;
    ELSE IF forecast_flag = 1 AND year IN (2022, 2023, 2024) THEN DO;
        linear_forecast = user_type_capacity;
        /* You would need to merge poly forecasts here */
    END;
RUN;

/* Export results for external visualization */
PROC EXPORT DATA=WORK.CombinedResults
    OUTFILE="/home/u63405489/sasuser.v94/My library/Solar_PV_Forecast_Results.csv"
    DBMS=CSV REPLACE;
RUN;

PROC EXPORT DATA=WORK.GrowthAnalysis
    OUTFILE="/home/u63405489/sasuser.v94/My library/Growth_Analysis.csv"
    DBMS=CSV REPLACE;
RUN;

/* Clean up temporary datasets */
PROC DATASETS LIBRARY=WORK NOLIST;
    DELETE AggregatedByYear RegionAggregated ExpData ExpResults;
RUN;

QUIT;

/* Final Summary */
TITLE "Solar PV Predictive Analysis Complete";
FOOTNOTE "Analysis completed on: &SYSDATE";
PROC PRINT DATA=WORK.LinearForecast NOOBS;
RUN;