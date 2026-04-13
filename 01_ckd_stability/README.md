# 01 — CKD visit-regularity and disease progression

**Role:** Research Assistant at HKUST (2026), working with hospital EMR data on Hong Kong chronic-kidney-disease (CKD) patients under supervision of the PI.

**Research question:** Does the *regularity* of a patient's follow-up visits (measured by the standard deviation / coefficient of variation of inter-visit intervals) predict CKD progression, holding baseline severity constant?

## Files

- `01_build_sample.do` — Sample construction from spell-level regready data. For each patient and each stage transition, finds the closest visit to the target horizon (1/2/3 years) inside a half-year-wide window, computes stability metrics, and outputs regression-ready datasets for four CKD stages (G2 / G3a / G3b / G4).
- `02_regression.do` — Main regression tables. Patient-level OLS of progression outcomes (30% / 50% eGFR decline indicators) on regularity metrics (SD / CV of intervals, number of visits, mean interval) with comorbidity controls and physician fixed effects. Produces six `esttab` RTF outputs matching the paper's Table 2.

## Data

Not included. Raw data comes from a Hong Kong hospital EMR system under DUA; cannot be redistributed.

## How to run

```stata
* Edit PROJECT_ROOT at the top of each do-file
global root "/path/to/your/data"
do 01_build_sample.do
do 02_regression.do
```
