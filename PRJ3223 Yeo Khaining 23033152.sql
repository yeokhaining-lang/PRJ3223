-- =============================================
-- SOLAR PV INSTALLATION ANALYSIS SQL QUERIES
-- =============================================

-- 1. BASIC DATA EXPLORATION
SELECT 'User Type Data' AS dataset, COUNT(*) AS total_rows, 
       COUNT(DISTINCT year) AS years_covered,
       MIN(year) AS start_year, MAX(year) AS end_year
FROM UserTypeData
UNION ALL
SELECT 'Region Data', COUNT(*), COUNT(DISTINCT year),
       MIN(year), MAX(year)
FROM RegionData;

-- 2. TOTAL CAPACITY GROWTH OVER TIME
SELECT 
    year,
    SUM(inst_cap_mwac) AS total_capacity_mwac,
    LAG(SUM(inst_cap_mwac)) OVER (ORDER BY year) AS prev_year_capacity,
    ROUND((SUM(inst_cap_mwac) - LAG(SUM(inst_cap_mwac)) OVER (ORDER BY year)) / 
          LAG(SUM(inst_cap_mwac)) OVER (ORDER BY year) * 100, 2) AS growth_rate_pct,
    SUM(SUM(inst_cap_mwac)) OVER (ORDER BY year) AS cumulative_capacity
FROM UserTypeData
GROUP BY year
ORDER BY year;

-- 3. USER TYPE ANALYSIS - MARKET SHARE OVER TIME
WITH yearly_totals AS (
    SELECT 
        year,
        SUM(inst_cap_mwac) AS total_capacity
    FROM UserTypeData
    GROUP BY year
)
SELECT 
    u.year,
    u.user_type,
    SUM(u.inst_cap_mwac) AS user_capacity,
    ROUND(SUM(u.inst_cap_mwac) / y.total_capacity * 100, 1) AS market_share_pct,
    RANK() OVER (PARTITION BY u.year ORDER BY SUM(u.inst_cap_mwac) DESC) AS rank
FROM UserTypeData u
JOIN yearly_totals y ON u.year = y.year
GROUP BY u.year, u.user_type, y.total_capacity
ORDER BY u.year, market_share_pct DESC;

-- 4. REGIONAL DISTRIBUTION ANALYSIS
SELECT 
    year,
    ura_planning_region,
    SUM(num_solar_pv_inst) AS total_installations,
    ROUND(SUM(inst_cap_kwac)/1000, 2) AS total_capacity_mw,
    ROUND(SUM(inst_cap_kwac) / SUM(SUM(inst_cap_kwac)) OVER (PARTITION BY year) * 100, 1) AS regional_share_pct,
    ROUND(AVG(inst_cap_kwac/num_solar_pv_inst), 1) AS avg_installation_size_kw
FROM RegionData
WHERE num_solar_pv_inst > 0
GROUP BY year, ura_planning_region
ORDER BY year, regional_share_pct DESC;

-- 5. RESIDENTIAL VS NON-RESIDENTIAL ANALYSIS
SELECT 
    year,
    residential_status,
    COUNT(*) AS num_records,
    SUM(inst_cap_mwac) AS total_capacity,
    ROUND(SUM(inst_cap_mwac) / SUM(SUM(inst_cap_mwac)) OVER (PARTITION BY year) * 100, 1) AS percentage_of_total
FROM UserTypeData
GROUP BY year, residential_status
ORDER BY year, residential_status;

-- 6. FORECASTING USING LINEAR REGRESSION CALCULATION
WITH time_series AS (
    SELECT 
        year,
        SUM(inst_cap_mwac) AS total_capacity,
        year - 2007 AS time_index
    FROM UserTypeData
    GROUP BY year
),
stats AS (
    SELECT 
        AVG(time_index) AS avg_time,
        AVG(total_capacity) AS avg_capacity,
        COUNT(*) AS n,
        SUM((time_index - AVG(time_index) OVER()) * (total_capacity - AVG(total_capacity) OVER())) AS sum_xy,
        SUM(POWER(time_index - AVG(time_index) OVER(), 2)) AS sum_xx
    FROM time_series
)
SELECT 
    slope,
    intercept,
    ROUND(slope * (2022-2007) + intercept, 1) AS forecast_2022,
    ROUND(slope * (2023-2007) + intercept, 1) AS forecast_2023,
    ROUND(slope * (2024-2007) + intercept, 1) AS forecast_2024
FROM (
    SELECT 
        ROUND(sum_xy / sum_xx, 4) AS slope,
        ROUND(avg_capacity - (sum_xy / sum_xx) * avg_time, 4) AS intercept
    FROM stats
) calc;

-- 7. COMPOUND ANNUAL GROWTH RATE (CAGR) CALCULATION
WITH first_last AS (
    SELECT 
        MIN(year) AS first_year,
        MAX(year) AS last_year,
        MAX(year) - MIN(year) AS years_diff
    FROM UserTypeData
),
capacities AS (
    SELECT 
        year,
        SUM(inst_cap_mwac) AS total_capacity
    FROM UserTypeData
    GROUP BY year
),
first_capacity AS (
    SELECT total_capacity AS first_cap
    FROM capacities c, first_last f
    WHERE c.year = f.first_year
),
last_capacity AS (
    SELECT total_capacity AS last_cap
    FROM capacities c, first_last f
    WHERE c.year = f.last_year
)
SELECT 
    f.first_year,
    l.last_year,
    fc.first_cap,
    lc.last_cap,
    ROUND(POWER(lc.last_cap / fc.first_cap, 1.0/f.years_diff) - 1, 4) * 100 AS cagr_pct
FROM first_last f, first_capacity fc, last_capacity lc;

-- 8. TOP PERFORMING YEARS BY GROWTH
WITH yearly_growth AS (
    SELECT 
        year,
        SUM(inst_cap_mwac) AS total_capacity,
        LAG(SUM(inst_cap_mwac)) OVER (ORDER BY year) AS prev_capacity,
        ROUND((SUM(inst_cap_mwac) - LAG(SUM(inst_cap_mwac)) OVER (ORDER BY year)) / 
              LAG(SUM(inst_cap_mwac)) OVER (ORDER BY year) * 100, 1) AS growth_pct
    FROM UserTypeData
    GROUP BY year
)
SELECT 
    year,
    total_capacity,
    growth_pct,
    CASE 
        WHEN growth_pct > 100 THEN 'Explosive Growth'
        WHEN growth_pct > 50 THEN 'High Growth'
        WHEN growth_pct > 20 THEN 'Moderate Growth'
        WHEN growth_pct > 0 THEN 'Slow Growth'
        ELSE 'Stagnant/Decline'
    END AS growth_category
FROM yearly_growth
WHERE growth_pct IS NOT NULL
ORDER BY growth_pct DESC
LIMIT 5;

-- 9. AVERAGE INSTALLATION SIZE TREND
SELECT 
    year,
    ura_planning_region,
    residential_status,
    SUM(inst_cap_kwac) AS total_capacity_kw,
    SUM(num_solar_pv_inst) AS total_installations,
    ROUND(SUM(inst_cap_kwac) / NULLIF(SUM(num_solar_pv_inst), 0), 1) AS avg_install_size_kw,
    ROUND(AVG(total_inst_cap_percent), 1) AS avg_percent_of_total
FROM RegionData
WHERE num_solar_pv_inst > 0
GROUP BY year, ura_planning_region, residential_status
ORDER BY year, ura_planning_region;

-- 10. CORRELATION BETWEEN INSTALLATIONS AND CAPACITY
WITH correlation_data AS (
    SELECT 
        u.year,
        SUM(u.inst_cap_mwac) AS total_capacity,
        SUM(r.num_solar_pv_inst) AS total_installations
    FROM UserTypeData u
    JOIN (
        SELECT year, SUM(num_solar_pv_inst) AS num_solar_pv_inst
        FROM RegionData
        GROUP BY year
    ) r ON u.year = r.year
    GROUP BY u.year
)
SELECT 
    ROUND(
        (COUNT(*) * SUM(total_capacity * total_installations) - 
         SUM(total_capacity) * SUM(total_installations)) /
        SQRT(
            (COUNT(*) * SUM(total_capacity * total_capacity) - 
             POWER(SUM(total_capacity), 2)) *
            (COUNT(*) * SUM(total_installations * total_installations) - 
             POWER(SUM(total_installations), 2))
        ), 3
    ) AS correlation_coefficient
FROM correlation_data;

-- 11. SEASONAL/PATTERN ANALYSIS (QUARTERLY IF DATA AVAILABLE)
-- Note: Since we only have yearly data, this shows year-over-year patterns
SELECT 
    year,
    SUM(inst_cap_mwac) AS annual_capacity,
    ROUND(SUM(inst_cap_mwac) / AVG(SUM(inst_cap_mwac)) OVER () * 100, 1) AS percent_of_avg
FROM UserTypeData
GROUP BY year
ORDER BY year;

-- 12. PREDICTIVE QUERY WITH CONFIDENCE INTERVALS
WITH regression AS (
    SELECT 
        year,
        year - 2007 AS x,
        SUM(inst_cap_mwac) AS y,
        AVG(year - 2007) OVER() AS avg_x,
        AVG(SUM(inst_cap_mwac)) OVER() AS avg_y
    FROM UserTypeData
    GROUP BY year
),
coefficients AS (
    SELECT 
        SUM((x - avg_x) * (y - avg_y)) / SUM(POWER(x - avg_x, 2)) AS slope,
        AVG(avg_y - (SUM((x - avg_x) * (y - avg_y)) / SUM(POWER(x - avg_x, 2))) * avg_x) AS intercept
    FROM regression
),
forecast_years AS (
    SELECT 2022 AS year UNION SELECT 2023 UNION SELECT 2024
)
SELECT 
    f.year,
    ROUND(c.slope * (f.year - 2007) + c.intercept, 1) AS predicted_capacity,
    ROUND(c.slope * (f.year - 2007) + c.intercept * 0.9, 1) AS lower_bound,
    ROUND(c.slope * (f.year - 2007) + c.intercept * 1.1, 1) AS upper_bound
FROM forecast_years f, coefficients c
ORDER BY f.year;

-- 13. MARKET CONCENTRATION ANALYSIS (HERFINDAHL-HIRSCHMAN INDEX)
WITH market_shares AS (
    SELECT 
        year,
        user_type,
        SUM(inst_cap_mwac) AS user_capacity,
        SUM(SUM(inst_cap_mwac)) OVER (PARTITION BY year) AS total_capacity,
        POWER(SUM(inst_cap_mwac) / SUM(SUM(inst_cap_mwac)) OVER (PARTITION BY year) * 100, 2) AS squared_share
    FROM UserTypeData
    GROUP BY year, user_type
)
SELECT 
    year,
    ROUND(SUM(squared_share), 0) AS hhi_index,
    CASE 
        WHEN SUM(squared_share) < 1500 THEN 'Competitive Market'
        WHEN SUM(squared_share) BETWEEN 1500 AND 2500 THEN 'Moderately Concentrated'
        ELSE 'Highly Concentrated'
    END AS market_concentration
FROM market_shares
GROUP BY year
ORDER BY year;

-- 14. REGIONAL PENETRATION ANALYSIS
WITH regional_population AS (
    -- Assuming hypothetical population data (replace with actual if available)
    SELECT 'Central' AS region, 1.5 AS population_millions UNION ALL
    SELECT 'East', 1.2 UNION ALL
    SELECT 'North-East', 1.0 UNION ALL
    SELECT 'North', 0.8 UNION ALL
    SELECT 'West', 1.5
)
SELECT 
    r.year,
    r.ura_planning_region,
    ROUND(SUM(r.inst_cap_kwac)/1000, 2) AS capacity_mw,
    p.population_millions,
    ROUND(SUM(r.inst_cap_kwac)/1000 / p.population_millions, 2) AS mw_per_million_pop
FROM RegionData r
JOIN regional_population p ON r.ura_planning_region = p.region
WHERE r.year = 2021
GROUP BY r.year, r.ura_planning_region, p.population_millions
ORDER BY mw_per_million_pop DESC;

-- 15. COMPREHENSIVE REPORT VIEW
CREATE OR REPLACE VIEW Solar_PV_Comprehensive_Report AS
SELECT 
    u.year,
    SUM(u.inst_cap_mwac) AS total_capacity_mwac,
    SUM(r.num_solar_pv_inst) AS total_installations,
    SUM(CASE WHEN u.residential_status = 'Residential' THEN u.inst_cap_mwac ELSE 0 END) AS residential_capacity,
    SUM(CASE WHEN u.residential_status = 'Non-Residential' THEN u.inst_cap_mwac ELSE 0 END) AS non_residential_capacity,
    ROUND(AVG(r.inst_cap_kwac / NULLIF(r.num_solar_pv_inst, 0)), 1) AS avg_installation_size_kw,
    COUNT(DISTINCT r.ura_planning_region) AS regions_active
FROM UserTypeData u
LEFT JOIN (
    SELECT 
        year,
        SUM(num_solar_pv_inst) AS num_solar_pv_inst,
        SUM(inst_cap_kwac) AS inst_cap_kwac,
        COUNT(DISTINCT ura_planning_region) AS ura_planning_region
    FROM RegionData
    GROUP BY year
) r ON u.year = r.year
GROUP BY u.year
ORDER BY u.year;

-- Query the comprehensive view
SELECT * FROM Solar_PV_Comprehensive_Report;

-- 16. TREND IDENTIFICATION QUERY
WITH moving_averages AS (
    SELECT 
        year,
        SUM(inst_cap_mwac) AS annual_capacity,
        AVG(SUM(inst_cap_mwac)) OVER (ORDER BY year ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) AS ma_3year,
        AVG(SUM(inst_cap_mwac)) OVER (ORDER BY year ROWS BETWEEN 4 PRECEDING AND CURRENT ROW) AS ma_5year
    FROM UserTypeData
    GROUP BY year
)
SELECT 
    year,
    annual_capacity,
    ROUND(ma_3year, 1) AS moving_avg_3year,
    ROUND(ma_5year, 1) AS moving_avg_5year,
    CASE 
        WHEN annual_capacity > ma_3year * 1.2 THEN 'Above Trend'
        WHEN annual_capacity < ma_3year * 0.8 THEN 'Below Trend'
        ELSE 'On Trend'
    END AS trend_status
FROM moving_averages
ORDER BY year;