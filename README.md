# CMS Hospital Quality Analysis

**Which U.S. hospitals get penalized by Medicare, and why?**

Analysis of FY2026 CMS hospital quality programs — Hospital Readmissions Reduction Program (HRRP), Hospital-Acquired Condition Reduction Program (HAC), and Hospital Value-Based Purchasing (HVBP) — using SQL Server, Python, and Power BI.

*Work in progress*

## Research Questions
1. How do readmissions, safety penalties, and performance scores differ by state, region, and hospital ownership?
2. Do hospitals with better patient experience have fewer excess readmissions?
3. Which hospital characteristics are associated with receiving a HAC payment reduction?

## Data
Source: [CMS Provider Data Catalog](https://data.cms.gov/provider-data/) (downloaded October 2026)

| File | Rows |
|---|---|
| Hospital_General_Information.csv | 5,419 |
| FY_2026_Hospital_Readmissions_Reduction_Program_Hospital.csv | 18,330 |
| FY_2026_HAC_Reduction_Program_Hospital.csv | 3,055 |
| hvbp_tps.csv | 2,455 |
| hvbp_person_and_community_engagement.csv | 2,455 |

Raw files are not included in this repository; download them from the link above.

## Progress
- [x] Data loading and validation (`SQL/01_load_check.sql`)
- [x] Data cleaning and analysis view (`SQL/02_clean.sql`)
- [x] SQL analysis queries
- [ ] Python statistical analysis
- [ ] Power BI dashboard
- [ ] Findings and summary report
