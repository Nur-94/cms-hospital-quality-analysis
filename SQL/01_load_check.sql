--1. Row counts
SELECT 'general' AS tbl, COUNT(*) AS n FROM raw_general 
SELECT 'hrrp', COUNT(*) FROM raw_hrrp 
SELECT 'hac', COUNT(*) FROM raw_hac 
SELECT 'tbs', COUNT(*) FROM raw_tps 
SELECT 'hcahps', COUNT(*) FROM raw_hcahps

--2. Leading zeros kept? (should return 0)
SELECT COUNT(*) AS bad_ids
FROM raw_general
WHERE LEN([Facility_ID]) <> 6;

--3. Do the files join? (most HRRP hospitals should match)
SELECT COUNT(DISTINCT h.[Facility_ID]) AS hrrp_hospitals,
COUNT(DISTINCT g.[Facility_ID]) AS matched_in_general
FROM raw_hrrp As h
LEFT JOIN raw_general AS g ON h.[Facility_ID] = g.[Facility_ID];