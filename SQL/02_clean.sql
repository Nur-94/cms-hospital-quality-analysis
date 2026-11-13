--CMS Hospital Quality Analysis
--02_clean.sql  -  Clean raw tables and build the analysis view
---------------------------------------------------------------------
USE CMS_Hospital
GO

/* =====================================================================
   SECTION 1 - clean_general
   ---------------------------------------------------------------------
   QUESTION: What kind of hospital is each one?
             (location, region, type, ownership, star rating)
   WHY     : These are the explanatory variables for RQ1 and RQ3
             e.g. "Are for-profit hospitals penalized more?"
   ===================================================================== */

-- BUILD 1: create clean_general from raw_general
DROP TABLE IF EXISTS clean_general;
SELECT
CAST(LTRIM(RTRIM(Facility_ID)) AS NVARCHAR(10))				AS facility_id, 
Facility_Name												AS facility_name,
City_Town													AS city,
State														AS state,
ZIP_Code													AS zip_code,
County_Parish												AS county,

  -- U.S. Census region (lets us compare regions, RQ1/RQ3)
  CASE
WHEN State IN ('CT','ME','MA','NH','RI','VT','NJ','NY','PA')   THEN 'Northeast'
WHEN State IN ('IL','IN','MI','OH','WI','IA','KS','MN','MO','NE','ND','SD') THEN 'Midwest'
WHEN State IN ('DE','DC','FL','GA','MD','NC','SC','VA','WV','AL','KY','MS','TN','AR','LA','OK','TX') THEN 'South'
WHEN State IN ('AZ','CO','ID','MT','NV','NM','UT','WY','AK','CA','HI','OR','WA') THEN 'West'
ELSE 'Territory'
END															AS census_region,

Hospital_Type												AS  hospital_type,
Hospital_Ownership											AS hospital_ownership,

 -- Simplified ownership groups (original has 10+ detailed categories)
 CASE
 WHEN Hospital_Ownership LIKE 'Voluntary%' THEN 'Nonprofit'
 WHEN Hospital_Ownership IN ('Proprietary','Physician') THEN 'For-profit'
 WHEN Hospital_Ownership LIKE 'Government%' 
 OR Hospital_Ownership LIKE 'Veterans%' 
 OR Hospital_Ownership IN ('Department of Defense','Tribal') THEN 'Government'
        ELSE 'Other'
		END													AS ownership_group,
		
CASE LTRIM(RTRIM(Emergency_Services))
WHEN 'Yes' THEN 1 WHEN 'NO' THEN 0 END						AS emergency_services,

CASE WHEN LTRIM(RTRIM(Meets_criteria_for_birthing_friendly_designation)) = 'Y' 
THEN 1 ELSE 0  END											AS birthing_friendly,

TRY_CAST(Hospital_overall_rating AS INT)					AS overall_star_rating,

-- Measure-group comparisons vs. national average
    TRY_CAST(Count_of_MORT_Measures_Better       AS INT)    AS mort_better,
    TRY_CAST(Count_of_MORT_Measures_No_Different AS INT)    AS mort_no_different,
    TRY_CAST(Count_of_MORT_Measures_Worse        AS INT)    AS mort_worse,
    TRY_CAST(Count_of_Safety_Measures_Better       AS INT)  AS safety_better,
    TRY_CAST(Count_of_Safety_Measures_No_Different AS INT)  AS safety_no_different,
    TRY_CAST(Count_of_Safety_Measures_Worse        AS INT)  AS safety_worse,
    TRY_CAST(Count_of_READM_Measures_Better       AS INT)   AS readm_better,
    TRY_CAST(Count_of_READM_Measures_No_Different AS INT)   AS readm_no_different,
    TRY_CAST(Count_of_READM_Measures_Worse        AS INT)   AS readm_worse
	INTO clean_general
	FROM raw_general
	GO

--Check 1a: Did any hospital disappear? (Expect 5419)
SELECT COUNT(*) AS n_hospital FROM clean_general;

--Check 1b: Did 'Not Available' ratings become NULL without losing rows?
--           ('Not Available' count in raw should equal NULL count in clean)
SELECT Hospital_overall_rating, COUNT(*) AS n
FROM raw_general 
GROUP BY Hospital_overall_rating 
ORDER BY Hospital_overall_rating;

SELECT overall_star_rating, COUNT(*) AS n
FROM clean_general
GROUP BY overall_star_rating
ORDER BY overall_star_rating;

-- CHECK 1c: Did every ownership type land in the right group? (nothing important in 'Other')
SELECT ownership_group, hospital_ownership, COUNT(*) AS n 
FROM clean_general
GROUP BY ownership_group, hospital_ownership
ORDER BY ownership_group, n DESC;

-- CHECK 1d: How many hospitals are in each region?
SELECT census_region, COUNT(*) AS n
FROM clean_general
GROUP BY census_region
ORDER BY n DESC;

/* =====================================================================
   SECTION 2 - clean_hrrp
   ---------------------------------------------------------------------
   QUESTION: For each hospital AND each condition, were readmissions
             higher or lower than expected?
   WHY     : RQ1 - "Which condition has the most hospitals doing worse
             than expected?"  Kept in LONG format (6 rows per hospital)
             because comparing conditions is easiest that way.
   KEY TERM: Excess Readmission Ratio (ERR) = predicted / expected rate.
             ERR > 1 means more readmissions than expected.
   ===================================================================== */

-- BUILD 2: create clean_hrrp from raw_hrrp
DROP TABLE IF EXISTS clean_hrrp

SELECT
CAST(LTRIM(RTRIM(Facility_ID)) AS NVARCHAR(10))					AS facility_id,
Measure_Name													AS measure_name,
-- 'READM-30-AMI-HRRP' -> 'AMI'
REPLACE(REPLACE(Measure_Name, 'READM-30-', ' '), '-HRRP', ' ')	AS condition,
TRY_CAST(Number_of_Discharges    AS INT)						AS discharges,
TRY_CAST(Excess_Readmission_Ratio  AS DECIMAL(8,4))				AS excess_readmission_ratio,
TRY_CAST(Predicted_Readmission_Rate AS DECIMAL(8,4))			AS predicted_rate,
TRY_CAST(Expected_Readmission_Rate  AS DECIMAL(8,4))			AS expected_rate,
TRY_CAST(Number_of_Readmissions     AS INT)						AS readmissions,
TRY_CONVERT(DATE, Start_Date, 101)								AS start_date,   -- 101 = MM/DD/YYYY
TRY_CONVERT(DATE, End_Date, 101)								AS end_date,
Footnote														AS footnote
INTO clean_hrrp
FROM raw_hrrp;
GO

-- CHECK 2a: Any rows lost? (expect 18330)
SELECT COUNT(*) AS n_rows FROM clean_hrrp;

-- CHECK 2b: Were the 6 condition names created correctly?
--           (expect AMI, CABG, COPD, HF, HIP-KNEE, PN)
SELECT condition, COUNT(*) AS n_rows,
COUNT(excess_readmission_ratio) AS n_with_err
FROM clean_hrrp
GROUP BY condition
ORDER BY condition;

-- CHECK 2c: Did the dates convert? (should show one real date range, not NULL)
SELECT start_date, end_date, COUNT(*) AS n
FROM clean_hrrp
GROUP BY start_date, end_date; 


/* =====================================================================
   SECTION 3 - clean_hrrp_summary
   ---------------------------------------------------------------------
   QUESTION: Overall, how does EACH HOSPITAL do on readmissions?
   WHY     : Other tables have 1 row per hospital, so HRRP must be
             summarised (6 rows -> 1 row) before joining.
             avg_err is the readmission measure for RQ2.
   NOTE    : any_condition_above_expected is a PROXY for HRRP penalty
             risk (CMS's real formula also uses peer grouping).
   ===================================================================== */

-- BUILD 3 create clean_hrrp_summary from clean_hrrp
DROP TABLE IF EXISTS clean_hrrp_summary;

SELECT
facility_id,
COUNT(excess_readmission_ratio)												AS n_conditions_reported,
-- Hospitals with NO reported ERR get NULL (unknown), not 0 (good)
    CASE WHEN COUNT(excess_readmission_ratio) = 0 THEN NULL
         ELSE SUM(CASE WHEN excess_readmission_ratio > 1 THEN 1 ELSE 0 END)
    END                                                                 AS n_conditions_above_expected,
	CASE WHEN COUNT(excess_readmission_ratio) = 0 THEN NULL
         WHEN SUM(CASE WHEN excess_readmission_ratio > 1 THEN 1 ELSE 0 END) > 0 THEN 1
         ELSE 0
    END                                                                 AS any_condition_above_expected,
CAST(AVG(excess_readmission_ratio) AS DECIMAL(8,4))							AS avg_err,
    MAX(excess_readmission_ratio)											AS max_err,
	-- Pivot: one column per condition
	MAX(CASE WHEN condition ='AMI'		 THEN excess_readmission_ratio END) AS err_ami,
	MAX(CASE WHEN condition = 'HF'       THEN excess_readmission_ratio END) AS err_hf,
    MAX(CASE WHEN condition = 'PN'       THEN excess_readmission_ratio END) AS err_pn,
    MAX(CASE WHEN condition = 'COPD'     THEN excess_readmission_ratio END) AS err_copd,
    MAX(CASE WHEN condition = 'CABG'     THEN excess_readmission_ratio END) AS err_cabg,
    MAX(CASE WHEN condition = 'HIP-KNEE' THEN excess_readmission_ratio END) AS err_hip_knee,
	SUM(discharges)															AS total_hrrp_discharges
	INTO clean_hrrp_summary
	FROM clean_hrrp
	GROUP BY facility_id;
	GO


-- CHECK 3a: One row per hospital? (expect 3055)

   SELECT COUNT(*) n_hospitals FROM clean_hrrp_summary;

	-- CHECK 3b: How many hospitals are above expected on 0,1,2...6 conditions?
	SELECT n_conditions_above_expected, COUNT(*) AS n_hospitals
	FROM clean_hrrp_summary
	GROUP BY n_conditions_above_expected
	ORDER BY n_conditions_above_expected;

	-- CHECK 3c: Hospitals with no ERR at all (too few patients to report)
	SELECT COUNT(*) AS hospitals_without_err
	FROM clean_hrrp_summary
	WHERE avg_err IS NULL;

	-- CHECK 3d (first finding, RQ1): % of hospitals above expected, per condition
	SELECT condition,
       COUNT(excess_readmission_ratio)                               AS hospitals_with_err,
       SUM(CASE WHEN excess_readmission_ratio > 1 THEN 1 ELSE 0 END) AS above_expected,
       CAST(100.0 * SUM(CASE WHEN excess_readmission_ratio > 1 THEN 1 ELSE 0 END)
            / COUNT(excess_readmission_ratio) AS DECIMAL(5,1))       AS pct_above_expected,
       CAST(AVG(excess_readmission_ratio) AS DECIMAL(6,4))           AS avg_err
FROM clean_hrrp
GROUP BY condition
ORDER BY pct_above_expected DESC;


/* =====================================================================
   SECTION 4 - clean_hac
   ---------------------------------------------------------------------
   QUESTION: How safe is each hospital, and did Medicare cut its payment?
   WHY     : hac_payment_reduction (1/0) is the OUTCOME we predict in RQ3.
             Infection scores answer RQ1 "which infection drives penalties?"
   KEY TERMS: SIR = Standardized Infection Ratio (>1 = more infections
              than predicted). W_Z = Winsorized z-score CMS uses to build
              the Total HAC Score. Higher Total HAC Score = worse.
   ===================================================================== */

-- BUILD 4: create clean_hac from clean_hac
DROP TABLE IF EXISTS clean_hac;

SELECT
CAST(LTRIM(RTRIM(Facility_ID)) AS NVARCHAR(10))			AS facility_id,
Fiscal_Year												AS fiscal_year,
TRY_CAST(PSI_90_Composite_Value AS DECIMAL(10,4))       AS psi90_value,
TRY_CAST(PSI_90_W_Z_Score       AS DECIMAL(10,4))       AS psi90_wz,
TRY_CAST(CLABSI_SIR             AS DECIMAL(10,4))       AS clabsi_sir,
TRY_CAST(CLABSI_W_Z_Score       AS DECIMAL(10,4))       AS clabsi_wz,
TRY_CAST(CAUTI_SIR              AS DECIMAL(10,4))       AS cauti_sir,
TRY_CAST(CAUTI_W_Z_Score        AS DECIMAL(10,4))       AS cauti_wz,
TRY_CAST(SSI_SIR                AS DECIMAL(10,4))       AS ssi_sir,
TRY_CAST(SSI_W_Z_Score          AS DECIMAL(10,4))       AS ssi_wz,
TRY_CAST(CDI_SIR                AS DECIMAL(10,4))       AS cdi_sir,
TRY_CAST(CDI_W_Z_Score          AS DECIMAL(10,4))       AS cdi_wz,
TRY_CAST(MRSA_SIR               AS DECIMAL(10,4))       AS mrsa_sir,
TRY_CAST(MRSA_W_Z_Score         AS DECIMAL(10,4))       AS mrsa_wz,
TRY_CAST(Total_HAC_Score        AS DECIMAL(10,4))       AS total_hac_score,
CASE LTRIM(RTRIM(Payment_Reduction))
WHEN 'Yes' THEN 1 WHEN 'No' THEN 0 END					AS hac_payment_reduction,
TRY_CONVERT(DATE, PSI_90_Start_Date, 101)				AS psi90_start_date,
TRY_CONVERT(DATE, PSI_90_End_Date, 101)					AS psi90_end_date,
TRY_CONVERT(DATE, HAI_Measures_Start_Date, 101)			AS hai_start_date,
TRY_CONVERT(DATE, HAI_Measures_END_Date, 101)			AS hai_end_date
INTO clean_hac
FROM raw_hac;
GO

-- CHECK 4a: Did Yes/No convert to 1/0? Compare raw and clean.
SELECT Payment_Reduction, COUNT(*) AS n FROM raw_hac GROUP BY Payment_Reduction;
SELECT hac_payment_reduction, COUNT(*) AS n FROM clean_hac GROUP BY hac_payment_reduction;

-- CHECK 4b: Does the penalty rate make sense? (CMS penalizes ~25%)
SELECT 
CAST(100.0 * SUM(hac_payment_reduction) / COUNT(hac_payment_reduction) AS DECIMAL(5,1)) AS pet_penalized
FROM clean_hac;

-- CHECK 4c: How much infection data is missing? (small hospitals often lack it)
SELECT 
SUM(CASE WHEN clabsi_sir IS NULL THEN 1 ELSE 0 END) AS null_clabsi,
SUM(CASE WHEN cauti_sir IS NULL THEN 1 ELSE 0 END) AS null_cauti,
SUM(CASE WHEN ssi_sir    IS NULL THEN 1 ELSE 0 END) AS null_ssi,
SUM(CASE WHEN cdi_sir    IS NULL THEN 1 ELSE 0 END) AS null_cdi,
SUM(CASE WHEN mrsa_sir   IS NULL THEN 1 ELSE 0 END) AS null_mrsa,
SUM(CASE WHEN total_hac_score IS NULL THEN 1 ELSE 0 END) AS null_total_hac
FROM clean_hac;

SELECT r.Total_HAC_Score, r.Total_HAC_Score_Footnote, r.Payment_Reduction, COUNT(*) AS n
FROM raw_hac r
WHERE TRY_CAST(r.Total_HAC_Score AS DECIMAL(10,4)) IS NULL
GROUP BY r.Total_HAC_Score, r.Total_HAC_Score_Footnote, r.Payment_Reduction;


/* =====================================================================
   SECTION 5 - clean_tps
   ---------------------------------------------------------------------
   QUESTION: What is each hospital's overall value-based performance?
   WHY     : RQ1 - "Do higher star-rated hospitals score better?" and
             "Which domain is weakest for low performers?"
   KEY TERM: Total Performance Score (TPS, 0-100) = weighted sum of
             4 domains: clinical outcomes, engagement, safety, efficiency.
   ===================================================================== */

-- BUILD 5 create clean_tps from clean_tps
DROP TABLE IF EXISTS clean_tps;

SELECT
CAST(LTRIM(RTRIM(Facility_ID)) AS NVARCHAR(10))							  AS facility_id,
Fiscal_Year																  AS fiscal_year,
TRY_CAST(Unweighted_Normalized_Clinical_Outcomes_Domain_Score			  AS DECIMAL(10,4)) AS clinical_outcomes_score,
TRY_CAST(Unweighted_Person_And_Community_Engagement_Domain_Score          AS DECIMAL(10,4)) AS engagement_score,
TRY_CAST(Unweighted_Normalized_Safety_Domain_Score                        AS DECIMAL(10,4)) AS safety_score,
TRY_CAST(Unweighted_Normalized_Efficiency_And_Cost_Reduction_Domain_Score AS DECIMAL(10,4)) AS efficiency_score,
TRY_CAST(Weighted_Normalized_Clinical_Outcomes_Domain_Score               AS DECIMAL(10,4)) AS clinical_outcomes_weighted,
TRY_CAST(Weighted_Person_And_Community_Engagement_Domain_Score            AS DECIMAL(10,4)) AS engagement_weighted,
TRY_CAST(Weighted_Safety_Domain_Score                                     AS DECIMAL(10,4)) AS safety_weighted,
TRY_CAST(Weighted_Efficiency_And_Cost_Reduction_Domain_Score              AS DECIMAL(10,4)) AS efficiency_weighted,
TRY_CAST(Total_Performance_Score                                          AS DECIMAL(10,4)) AS total_performance_score
INTO clean_tps
FROM raw_tps;
GO

-- CHECK 5a: Rows and the range of TPS (should be between 0 and 100)
SELECT COUNT(*) AS n_hospitals,
MIN(total_performance_score) AS min_tps,
AVG(total_performance_score) AS avg_tps,
MAX(total_performance_score) AS max_tps
FROM clean_tps;

-- CHECK 5b: Do the 4 weighted domains add up to TPS? (difference should be ~0)
SELECT TOP 10 facility_id, total_performance_score,
       clinical_outcomes_weighted + engagement_weighted
     + safety_weighted + efficiency_weighted AS sum_of_domains
FROM clean_tps
WHERE total_performance_score IS NOT NULL;

  SELECT COUNT(*) AS n_zero_tps FROM clean_tps WHERE total_performance_score = 0;


  /* =====================================================================
   SECTION 6 - clean_hcahps
   ---------------------------------------------------------------------
   QUESTION: What do patients say about each hospital?
   WHY     : RQ2 - "Do hospitals that explain discharge and care
             transitions well have fewer readmissions?"
   DROPPED : Floor / Achievement Threshold / Benchmark columns are
             national constants (same for every hospital), so they
             cannot explain differences between hospitals.
   ===================================================================== */

-- BUILD 6 create clean_hcahps from clean_hcahps
DROP TABLE IF EXISTS clean_hcahps;

SELECT
CAST(LTRIM(RTRIM(Facility_ID)) AS NVARCHAR(10))												AS facility_id,
Fiscal_Year																					AS  fiscal_year,

-- Performance rates (% of patients giving the best answer)
TRY_CAST(REPLACE(Communication_With_Nurses_Performance_Rate,  '%','') AS DECIMAL(8,4))		AS nurse_comm_rate,
TRY_CAST(REPLACE(Communication_With_Doctors_Performance_Rate, '%','') AS DECIMAL(8,4))		AS doctor_comm_rate,
TRY_CAST(REPLACE(Responsiveness_Of_Hospital_Staff_Performance_Rate, '%','') AS DECIMAL(8,4))AS staff_responsiveness_rate,
TRY_CAST(REPLACE(Care_Transition_Performance_Rate, '%','') AS DECIMAL(8,4))					AS care_transition_rate,
TRY_CAST(REPLACE(Communication_About_Medicines_Performance_Rate, '%','') AS DECIMAL(8,4))	AS medicine_comm_rate,
TRY_CAST(REPLACE(Cleanliness_And_Quietness_Of_Hospital_Environment_Performance_Rate, '%','')AS DECIMAL(8,4)) AS clean_quiet_rate,
TRY_CAST(REPLACE(Discharge_Information_Performance_Rate, '%','') AS DECIMAL(8,4))			AS discharge_info_rate,
TRY_CAST(REPLACE(Overall_Rating_Of_Hospital_Performance_Rate, '%','') AS DECIMAL(8,4))		AS overall_rating_rate,

-- Dimension scores (0-10 points CMS gives per topic)
TRY_CAST(Communication_With_Nurses_Dimension_Score  AS DECIMAL(8,4))						AS nurse_comm_score,
TRY_CAST(Communication_With_Doctors_Dimension_Score AS DECIMAL(8,4))						AS doctor_comm_score,
TRY_CAST(Responsiveness_Of_Hospital_Staff_Dimension_Score AS DECIMAL(8,4))					AS staff_responsiveness_score,
TRY_CAST(Care_Transition_Dimension_Score AS DECIMAL(8,4))									AS care_transition_score,
TRY_CAST(Communication_About_Medicines_Dimension_Score AS DECIMAL(8,4))						AS medicine_comm_score,
TRY_CAST(Cleanliness_And_Quietness_Of_Hospital_Environment_Dimension_Score AS DECIMAL(8,4)) AS clean_quiet_score,
TRY_CAST(Discharge_Information_Dimension_Score AS DECIMAL(8,4))								AS discharge_info_score,
TRY_CAST(Overall_Rating_Of_Hospital_Dimension_Score AS DECIMAL(8,4))						AS overall_rating_score,
TRY_CAST(Hcahps_Base_Score        AS DECIMAL(8,4))											AS hcahps_base_score,
TRY_CAST(Hcahps_Consistency_Score AS DECIMAL(8,4))											AS hcahps_consistency_score
INTO clean_hcahps
FROM raw_hcahps;
GO

-- CHECK 6a: Look at raw vs clean for one column - did the % convert?
SELECT TOP 10 r.Discharge_Information_Performance_Rate AS raw_value,
 c.discharge_info_rate  AS clean_value
 FROM raw_hcahps AS r
 JOIN clean_hcahps As c ON LTRIM(RTRIM(r.Facility_ID)) = c.facility_id;

 -- CHECK 6b: Ranges look reasonable? (rates should be 0-100 or 0-1)
 SELECT MIN(discharge_info_rate) AS min_rate, 
        AVG(discharge_info_rate) AS avg_rate,
        MAX(discharge_info_rate) AS max_rate,
        MIN(hcahps_base_score)   AS min_base, 
	    MAX(hcahps_base_score) AS max_base
FROM clean_hcahps;


/* =====================================================================
   SECTION 7 - Primary keys
   ---------------------------------------------------------------------
   QUESTION: Does each hospital appear only ONCE in each table?
   WHY     : If a hospital appeared twice, joins would double it and
             every count and average would be wrong (data quality).
   If a line gives an error, that table has duplicate IDs - tell Claude.
   ===================================================================== */

-- CHECK 7 (run first): find duplicates - every number should be 0
SELECT 'general' AS tbl, COUNT(*) - COUNT(DISTINCT facility_id) AS duplicates FROM clean_general    UNION ALL
SELECT 'hrrp_summary',   COUNT(*) - COUNT(DISTINCT facility_id) FROM clean_hrrp_summary				UNION ALL
SELECT 'hac',            COUNT(*) - COUNT(DISTINCT facility_id) FROM clean_hac						UNION ALL
SELECT 'tps',            COUNT(*) - COUNT(DISTINCT facility_id) FROM clean_tps						UNION ALL
SELECT 'hcahps',         COUNT(*) - COUNT(DISTINCT facility_id) FROM clean_hcahps;

-- BUILD 7a: make facility_id NOT NULL in every table
-- (must run in its OWN batch - SQL Server checks the whole batch before
--  running it, so it would still see the column as nullable otherwise)
ALTER TABLE clean_general      ALTER COLUMN facility_id NVARCHAR(10) NOT NULL;
ALTER TABLE clean_hrrp_summary ALTER COLUMN facility_id NVARCHAR(10) NOT NULL;
ALTER TABLE clean_hac          ALTER COLUMN facility_id NVARCHAR(10) NOT NULL;
ALTER TABLE clean_tps          ALTER COLUMN facility_id NVARCHAR(10) NOT NULL;
ALTER TABLE clean_hcahps       ALTER COLUMN facility_id NVARCHAR(10) NOT NULL;
GO

-- BUILD 7b: add the primary keys
ALTER TABLE clean_general      ADD CONSTRAINT pk_clean_general      PRIMARY KEY (facility_id);
ALTER TABLE clean_hrrp_summary ADD CONSTRAINT pk_clean_hrrp_summary PRIMARY KEY (facility_id);
ALTER TABLE clean_hac          ADD CONSTRAINT pk_clean_hac          PRIMARY KEY (facility_id);
ALTER TABLE clean_tps          ADD CONSTRAINT pk_clean_tps          PRIMARY KEY (facility_id);
ALTER TABLE clean_hcahps       ADD CONSTRAINT pk_clean_hcahps       PRIMARY KEY (facility_id);
GO

-- CHECK 7b: list the primary keys (expect 5 rows)
SELECT t.name AS table_name, k.name AS primary_key
FROM sys.key_constraints k
JOIN sys.tables t ON k.parent_object_id = t.object_id
WHERE k.type = 'PK'
ORDER BY t.name;


/* =====================================================================
   SECTION 8 - v_hospital_analysis
   ---------------------------------------------------------------------
   QUESTION: Can I see everything about one hospital in ONE row?
   WHY     : Python regression (RQ3), correlation (RQ2) and Power BI all
             need one row per hospital with all variables side by side.
             Base = all 5,419 hospitals; flags show program participation.
   ===================================================================== */

-- BUILD 8:
CREATE OR ALTER VIEW v_hospital_analysis AS
SELECT
    g.facility_id, g.facility_name, g.city, g.state, g.census_region,
    g.hospital_type, g.hospital_ownership, g.ownership_group,
    g.emergency_services, g.birthing_friendly, g.overall_star_rating,

    -- Program participation flags
    CASE WHEN r.facility_id IS NOT NULL THEN 1 ELSE 0 END AS in_hrrp,
    CASE WHEN h.facility_id IS NOT NULL THEN 1 ELSE 0 END AS in_hac,
    CASE WHEN t.facility_id IS NOT NULL THEN 1 ELSE 0 END AS in_hvbp,

    -- Readmissions (HRRP)  -> RQ1, RQ2
    r.n_conditions_reported, r.n_conditions_above_expected,
    r.any_condition_above_expected, r.avg_err, r.max_err,
    r.err_ami, r.err_hf, r.err_pn, r.err_copd, r.err_cabg, r.err_hip_knee,
    r.total_hrrp_discharges,

    -- Safety (HAC)  -> RQ1, RQ3
    h.psi90_value, h.clabsi_sir, h.cauti_sir, h.ssi_sir, h.cdi_sir, h.mrsa_sir,
    h.total_hac_score, h.hac_payment_reduction,

    -- Value-based purchasing (HVBP)  -> RQ1
    t.clinical_outcomes_score, t.engagement_score, t.safety_score,
    t.efficiency_score, t.total_performance_score,

    -- Patient experience (HCAHPS)  -> RQ2
    e.nurse_comm_rate, e.doctor_comm_rate, e.care_transition_rate,
    e.discharge_info_rate, e.overall_rating_rate,
    e.hcahps_base_score, e.hcahps_consistency_score
FROM clean_general g
LEFT JOIN clean_hrrp_summary r ON g.facility_id = r.facility_id
LEFT JOIN clean_hac          h ON g.facility_id = h.facility_id
LEFT JOIN clean_tps          t ON g.facility_id = t.facility_id
LEFT JOIN clean_hcahps       e ON g.facility_id = e.facility_id;
GO

-- CHECK 8a: Still one row per hospital? (expect 5419 - LEFT JOIN keeps all)
SELECT COUNT(*) AS n_rows FROM v_hospital_analysis;

-- CHECK 8b: How many hospitals are in each combination of programs?
SELECT in_hrrp, in_hac, in_hvbp, COUNT(*) AS n_hospitals
FROM v_hospital_analysis
GROUP BY in_hrrp, in_hac, in_hvbp
ORDER BY n_hospitals DESC;


/* =====================================================================
   SECTION 9 - Final validation
   ---------------------------------------------------------------------
   QUESTION: Is the final dataset ready and trustworthy for analysis?
   WHY     : These numbers go into your README "Data" and "Limitations"
             sections (e.g. "X% of hospitals had no star rating").
   ===================================================================== */

-- 9a. Did any rows disappear across all tables?
--     (expect 5419, 18330, 3055, 3055, 2455, 2455, 5419)
SELECT 'clean_general' AS tbl, COUNT(*) AS n FROM clean_general      UNION ALL
SELECT 'clean_hrrp',           COUNT(*)      FROM clean_hrrp         UNION ALL
SELECT 'clean_hrrp_summary',   COUNT(*)      FROM clean_hrrp_summary UNION ALL
SELECT 'clean_hac',            COUNT(*)      FROM clean_hac          UNION ALL
SELECT 'clean_tps',            COUNT(*)      FROM clean_tps          UNION ALL
SELECT 'clean_hcahps',         COUNT(*)      FROM clean_hcahps       UNION ALL
SELECT 'v_hospital_analysis',  COUNT(*)      FROM v_hospital_analysis;

-- 9b. Among hospitals in HRRP, how much key data is missing? (-> Limitations)
SELECT
    COUNT(*)                                                         AS hrrp_hospitals,
    SUM(CASE WHEN overall_star_rating     IS NULL THEN 1 ELSE 0 END) AS null_star_rating,
    SUM(CASE WHEN avg_err                 IS NULL THEN 1 ELSE 0 END) AS null_avg_err,
    SUM(CASE WHEN total_hac_score         IS NULL THEN 1 ELSE 0 END) AS null_hac_score,
    SUM(CASE WHEN total_performance_score IS NULL THEN 1 ELSE 0 END) AS null_tps,
    SUM(CASE WHEN hcahps_base_score       IS NULL THEN 1 ELSE 0 END) AS null_hcahps
FROM v_hospital_analysis
WHERE in_hrrp = 1;

-- 9c. Which hospital types take part in the programs?
SELECT hospital_type,
       COUNT(*)      AS total_hospitals,
       SUM(in_hrrp)  AS in_hrrp,
       SUM(in_hac)   AS in_hac,
       SUM(in_hvbp)  AS in_hvbp
FROM v_hospital_analysis
GROUP BY hospital_type
ORDER BY total_hospitals DESC;

-- 9d. Final look: the 20 hospitals with the highest average readmission ratio
SELECT TOP 20 facility_name, state, ownership_group, overall_star_rating,
       avg_err, n_conditions_above_expected, hac_payment_reduction
FROM v_hospital_analysis
WHERE in_hrrp = 1
ORDER BY avg_err DESC;












