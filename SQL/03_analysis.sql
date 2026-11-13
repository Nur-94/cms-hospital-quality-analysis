
-- Q1 (RQ1): Do penalty rates and readmissions differ by ownership group?
SELECT ownership_group,
       COUNT(*) AS n_hospitals,
       CAST(AVG(avg_err) AS DECIMAL(6,4)) AS avg_err,
       CAST(100.0 * SUM(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
                  / COUNT(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
            AS DECIMAL(5,1)) AS pct_hac_penalized
FROM v_hospital_analysis
WHERE in_hrrp = 1
GROUP BY ownership_group
ORDER BY pct_hac_penalized DESC;


-- Q2 (RQ1/RQ3): Are larger hospitals penalized more often?
WITH sized AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY total_hrrp_discharges) AS size_quartile
    FROM v_hospital_analysis
    WHERE in_hrrp = 1
      AND total_hrrp_discharges IS NOT NULL
)
SELECT size_quartile,
       COUNT(*) AS n_hospitals,
       CAST(AVG(avg_err) AS DECIMAL(6,4)) AS avg_err,
       CAST(100.0 * SUM(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
                  / COUNT(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
            AS DECIMAL(5,1)) AS pct_hac_penalized,
       MIN(total_hrrp_discharges) AS min_discharges,
       MAX(total_hrrp_discharges) AS max_discharges
FROM sized
GROUP BY size_quartile
ORDER BY size_quartile;



-- Q3 (RQ1/RQ3): How are ownership groups distributed across size quartiles?
WITH sized AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY total_hrrp_discharges) AS size_quartile
    FROM v_hospital_analysis
    WHERE in_hrrp = 1
      AND total_hrrp_discharges IS NOT NULL
)
SELECT ownership_group,
       size_quartile,
       COUNT(*) AS n_hospitals,
       CAST(100.0 * COUNT(*)
            / SUM(COUNT(*)) OVER (PARTITION BY ownership_group)
            AS DECIMAL(5,1)) AS pct_of_group,
       CAST(100.0 * SUM(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
                  / COUNT(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
            AS DECIMAL(5,1)) AS pct_hac_penalized
FROM sized
GROUP BY ownership_group, size_quartile
ORDER BY ownership_group, size_quartile;


-- Q4 (RQ2): Do hospitals with better discharge information have fewer readmissions?
WITH grouped AS (
    SELECT *,
           NTILE(4) OVER (ORDER BY discharge_info_rate) AS discharge_quartile
    FROM v_hospital_analysis
    WHERE in_hrrp = 1
      AND discharge_info_rate IS NOT NULL    
      AND avg_err IS NOT NULL
)
SELECT discharge_quartile,
       COUNT(*) AS n_hospitals,
       CAST(AVG(avg_err) AS DECIMAL(6,4)) AS avg_err,
       CAST(AVG(discharge_info_rate) AS DECIMAL(5,1)) AS avg_discharge_rate
FROM grouped
GROUP BY discharge_quartile
ORDER BY discharge_quartile;


--Q5 (RQ1): Do readmissions, penalties and performance differ by region?
SELECT census_region,
       COUNT(*)   AS n_hospitals,
       CAST(AVG(avg_err) AS DECIMAL(6,4))   AS avg_err,
       CAST(100.0 * SUM(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
                  / COUNT(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
            AS DECIMAL(5,1))  AS pct_hac_penalized,
       CAST(AVG(total_performance_score) AS DECIMAL(5,1)) AS avg_tps
FROM v_hospital_analysis
WHERE in_hrrp = 1
GROUP BY census_region
ORDER BY avg_err DESC;


--Q6 (RQ1): Do CMS star ratings agree with the penalty programs?
SELECT overall_star_rating,
       COUNT(*)  AS n_hospitals,
       CAST(AVG(avg_err) AS DECIMAL(6,4))   AS avg_err,
       CAST(100.0 * SUM(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
                  / COUNT(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
            AS DECIMAL(5,1))  AS pct_hac_penalized,
       CAST(AVG(total_performance_score) AS DECIMAL(5,1)) AS avg_tps
FROM v_hospital_analysis
WHERE in_hrrp = 1
GROUP BY overall_star_rating
ORDER BY overall_star_rating;     


--Q7 (RQ1): Which states have the highest and lowest readmissions?
WITH state_stats AS (
    SELECT state,
           COUNT(avg_err)                     AS n_hospitals,
           CAST(AVG(avg_err) AS DECIMAL(6,4)) AS avg_err,
           CAST(100.0 * SUM(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
                      / COUNT(CASE WHEN total_hac_score IS NOT NULL THEN hac_payment_reduction END)
                AS DECIMAL(5,1))              AS pct_hac_penalized
    FROM v_hospital_analysis
    WHERE in_hrrp = 1
    GROUP BY state
    HAVING COUNT(avg_err) >= 10        -- HAVING filters groups (WHERE filters rows)
)
SELECT RANK() OVER (ORDER BY avg_err DESC) AS readmission_rank,   -- 1 = worst
       state, n_hospitals, avg_err, pct_hac_penalized
FROM state_stats
ORDER BY readmission_rank;


--Q8 (RQ1): Which hospitals have the highest readmissions WITHIN each state?
WITH ranked AS (
    SELECT state, facility_name, city, ownership_group, overall_star_rating,
           avg_err, n_conditions_reported, n_conditions_above_expected,
           hac_payment_reduction,
           ROW_NUMBER() OVER (PARTITION BY state ORDER BY avg_err DESC) AS rank_in_state
    FROM v_hospital_analysis
    WHERE in_hrrp = 1
      AND n_conditions_reported >= 3
)
SELECT *
FROM ranked
WHERE rank_in_state <= 5
  AND state IN ('NY', 'CA', 'TX')
ORDER BY state, rank_in_state;


--Q9 (RQ1/RQ3): How many hospitals are weak on BOTH readmissions and safety?
WITH flags AS (
    SELECT ownership_group,
           CASE WHEN 1.0 * n_conditions_above_expected / n_conditions_reported > 0.5
                THEN 1 ELSE 0 END AS weak_readmissions,
           hac_payment_reduction
    FROM v_hospital_analysis
    WHERE in_hrrp = 1
      AND n_conditions_reported > 0
      AND total_hac_score IS NOT NULL
      AND hac_payment_reduction IS NOT NULL
)
SELECT ownership_group,
       COUNT(*) AS n_hospitals,
       SUM(CASE WHEN weak_readmissions = 1 AND hac_payment_reduction = 1 THEN 1 ELSE 0 END) AS weak_on_both,
       CAST(100.0 * SUM(CASE WHEN weak_readmissions = 1 AND hac_payment_reduction = 1 THEN 1 ELSE 0 END)
            / COUNT(*) AS DECIMAL(5,1)) AS pct_weak_on_both
FROM flags
GROUP BY ownership_group
ORDER BY pct_weak_on_both DESC;



