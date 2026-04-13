* Set PROJECT_ROOT to the folder containing Patient_level_*.dta
global root "PROJECT_ROOT"
cd "$root"

use Patient_level_2026_2_27, clear
egen physician_id = group(primary_physician)
drop if num_visits<=2
**************************************************
* Define control variables and dependent variables
**************************************************

* Comorbidity controls
local comorb HTN DM Dyslipidemia Cancer MI Ischemic_Stroke ///
    Peripheral_artery_disease Chronic_obstructive_pulmonary ///
    Hyperthyroidism atrial_fibrillation Heart_failure ///
    Dementia Hemorrhagic_stroke
* Baseline demographic and clinical controls
local basectrl Gender age_baseline distance_to_hospital_km `comorb'
* Dependent variables: four CKD progression measures
local ylist prog30_patient prog50_patient prog30_firstlas prog50_firstlas

**************************************************
* 1. Main regression: sd_visit_interval + num_visits + CKD baseline
**************************************************
est clear
local i = 1
foreach y of local ylist {
    reghdfe `y' `basectrl' num_visits sd_visit_interval i.CKDid_baseline i.physician_id
    est store m`i'
    local ++i
}

esttab m1 m2 m3 m4 using "Main Regression-sd+num_visit.rtf", replace ///
    star(* 0.1 ** 0.05 *** 0.01) ///
    b(%9.3f) t(%7.2f) ///
    stats(N r2 r2_a F, fmt(%12.0fc %9.3f %9.3f %9.2f) labels("N" "R2" "Adj R2" "F")) ///
    order(*.CKDid_baseline sd_visit_interval num_visits) ///
    nonotes addnotes("Notes: The dependent variables measure CKD progression defined by 30% and 50% declines in eGFR (prog30, prog50), constructed using both patient-level follow-up and first-to-last observations. The key independent variables are sd_visit_interval, capturing visit irregularity, and num_visits, capturing visit frequency. All specifications control for baseline CKD stage fixed effects, demographic characteristics, comorbidities, and physician fixed effects. The sample is restricted to patients with more than two visits.") compress nogaps

**************************************************

* 2. Main regression: sd_visit_interval + mean_visit_interval + CKD baseline
**************************************************
est clear
local i = 1
foreach y of local ylist {
    reghdfe `y' `basectrl' mean_visit_interval sd_visit_interval i.CKDid_baseline i.physician_id
    est store m`i'
    local ++i
}

esttab m1 m2 m3 m4 using "Main Regression-sd+mean.rtf", replace ///
    star(* 0.1 ** 0.05 *** 0.01) ///
    b(%9.3f) t(%7.2f) ///
    stats(N r2 r2_a F, fmt(%12.0fc %9.3f %9.3f %9.2f) labels("N" "R2" "Adj R2" "F")) ///
    order(*.CKDid_baseline sd_visit_interval mean_visit_interval) ///
    nonotes addnotes("Notes: The dependent variables measure CKD progression defined by 30% and 50% declines in eGFR. The key independent variables are sd_visit_interval, capturing visit irregularity, and mean_visit_interval, capturing the average spacing between visits. All regressions include baseline CKD stage fixed effects, demographic characteristics, comorbidities, and physician fixed effects. The sample is restricted to patients with more than two visits.") compress nogaps

**************************************************
* 3. Main regression: cv_visit_interval + num_visits + CKD baseline
**************************************************
est clear
local i = 1
foreach y of local ylist {
    reghdfe `y' `basectrl' num_visits cv_visit_interval i.CKDid_baseline i.physician_id
    est store m`i'
    local ++i
}

esttab m1 m2 m3 m4 using "Main Regression-cv+num.rtf", replace ///
    star(* 0.1 ** 0.05 *** 0.01) ///
    b(%9.3f) t(%7.2f) ///
    stats(N r2 r2_a F, fmt(%12.0fc %9.3f %9.3f %9.2f) labels("N" "R2" "Adj R2" "F")) ///
    order(*.CKDid_baseline cv_visit_interval num_visits) ///
    nonotes addnotes("Notes: The dependent variables measure CKD progression defined by 30% and 50% declines in eGFR. The key independent variables are cv_visit_interval, capturing relative variability in visit intervals, and num_visits, capturing visit frequency. All regressions include baseline CKD stage fixed effects, demographic characteristics, comorbidities, and physician fixed effects. The sample is restricted to patients with more than two visits.") compress nogaps

	
	
	
**************************************************
* 4. Main regression: sd_visit_interval + num_visits + baseline eGFR
**************************************************
est clear
local i = 1
foreach y of local ylist {
    reghdfe `y' `basectrl' num_visits sd_visit_interval egfr_baseline i.physician_id
    est store m`i'
    local ++i
}

esttab m1 m2 m3 m4 using "Main Regression-sd+num+egfr.rtf", replace ///
    star(* 0.1 ** 0.05 *** 0.01) ///
    b(%9.3f) t(%7.2f) ///
    stats(N r2 r2_a F, fmt(%12.0fc %9.3f %9.3f %9.2f) labels("N" "R2" "Adj R2" "F")) ///
    order(egfr_baseline sd_visit_interval num_visits) ///
    nonotes addnotes("Notes: The dependent variables measure CKD progression defined by 30% and 50% declines in eGFR. The key independent variables are sd_visit_interval and num_visits. Baseline kidney function is controlled using continuous eGFR (egfr_baseline) instead of CKD stage indicators. All regressions include demographic characteristics, comorbidities, and physician fixed effects. The sample is restricted to patients with more than two visits.") compress nogaps

**************************************************
* 5. Main regression: sd_visit_interval + mean_visit_interval + baseline eGFR
**************************************************
est clear
local i = 1
foreach y of local ylist {
    reghdfe `y' `basectrl' mean_visit_interval sd_visit_interval egfr_baseline i.physician_id
    est store m`i'
    local ++i
}

esttab m1 m2 m3 m4 using "Main Regression-sd+mean+egfr.rtf", replace ///
    star(* 0.1 ** 0.05 *** 0.01) ///
    b(%9.3f) t(%7.2f) ///
    stats(N r2 r2_a F, fmt(%12.0fc %9.3f %9.3f %9.2f) labels("N" "R2" "Adj R2" "F")) ///
    order(egfr_baseline sd_visit_interval mean_visit_interval) ///
    nonotes addnotes("Notes: The dependent variables measure CKD progression defined by 30% and 50% declines in eGFR. The key independent variables are sd_visit_interval and mean_visit_interval. Baseline kidney function is controlled using continuous eGFR (egfr_baseline). All regressions include demographic characteristics, comorbidities, and physician fixed effects. The sample is restricted to patients with more than two visits.") compress nogaps

**************************************************
* 6. Main regression: cv_visit_interval + num_visits + baseline eGFR
**************************************************
est clear
local i = 1
foreach y of local ylist {
    reghdfe `y' `basectrl' num_visits cv_visit_interval egfr_baseline i.physician_id
    est store m`i'
    local ++i
}

esttab m1 m2 m3 m4 using "Main Regression-cv+num+egfr.rtf", replace ///
    star(* 0.1 ** 0.05 *** 0.01) ///
    b(%9.3f) t(%7.2f) ///
    stats(N r2 r2_a F, fmt(%12.0fc %9.3f %9.3f %9.2f) labels("N" "R2" "Adj R2" "F")) ///
    order(egfr_baseline cv_visit_interval num_visits) ///
    nonotes addnotes("Notes: The dependent variables measure CKD progression defined by 30% and 50% declines in eGFR. The key independent variables are cv_visit_interval and num_visits. Baseline kidney function is controlled using continuous eGFR (egfr_baseline). All regressions include demographic characteristics, comorbidities, and physician fixed effects. The sample is restricted to patients with more than two visits.") compress nogaps	
