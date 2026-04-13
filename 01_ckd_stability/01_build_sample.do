**************************************************
* do1: Stability tables + regression-ready datasets
* 基于已经保存好的 regready spell-level 数据
*
* 修订版：
* 年后匹配逻辑改为：
*   1年 -> 在 [0.5, 1.5] 年内找最接近 1 年的 visit
*   2年 -> 在 [1.5, 2.5] 年内找最接近 2 年的 visit
*   3年 -> 在 [2.5, 3.5] 年内找最接近 3 年的 visit
**************************************************

clear all
set more off

* Set PROJECT_ROOT to the folder containing the regready spell-level .dta files
global root "PROJECT_ROOT"
cd "$root"

**************************************************
* 参数设置：只改这里
**************************************************
local window_year_list   "2 2.5 3 3.5 4"
local visit_cut_list     "4 5 6 7 8 9 10"
local horizon_year_list  "1 2 3"
local horizon_visit_list "1 2 3 4 5"

**************************************************
* 0. 读取 valid regready spell-level 数据
**************************************************
use "ckd_stage_spell_level_valid_relaxed_regready.dta", clear

keep if !missing(patient_id, stage_spell, stage_order, ///
                 window_start, window_last_visit, window_end, ///
                 baseline_visit_dt, baseline_visit_seq, egfr_end, ///
                 spell_duration_days, n_visits_in_spell)

sort patient_id window_start window_end

tempfile base_spell
save `base_spell', replace

**************************************************
* 1. 记录总 patient 数（用于后面算占比）
**************************************************
preserve
keep patient_id
duplicates drop
count
local N_patients = r(N)
restore

di "======================================"
di "Total unique patients in valid spell data = `N_patients'"
di "======================================"

**************************************************
* 2. 时间window：总体patient数量
**************************************************
tempname post_time_overall
postfile `post_time_overall' ///
    double(window_year window_days n_patients pct_patients) ///
    using "stability_overall_by_time_window.dta", replace

foreach wy of local window_year_list {

    local this_days = round(`wy' * 365)

    use `base_spell', clear
    gen stable_time = (spell_duration_days >= `this_days')

    bys patient_id: egen patient_stable = max(stable_time)
    bys patient_id: keep if _n == 1

    quietly count if patient_stable == 1
    local n = r(N)
    local pct = 100 * `n' / `N_patients'

    post `post_time_overall' (`wy') (`this_days') (`n') (`pct')
}

postclose `post_time_overall'

use "stability_overall_by_time_window.dta", clear
sort window_days
order window_year window_days n_patients pct_patients
export delimited using "stability_overall_by_time_window.csv", replace

**************************************************
* 3. 时间window：按stage分组patient数量
* 口径：对每个patient-stage，只要存在一个spell满足阈值，就记1
**************************************************
tempname post_time_stage
postfile `post_time_stage' ///
    str6 stage_spell double(stage_order window_year window_days n_patients pct_patients) ///
    using "stability_by_stage_by_time_window.dta", replace

foreach wy of local window_year_list {

    local this_days = round(`wy' * 365)

    use `base_spell', clear
    gen stable_time = (spell_duration_days >= `this_days')

    collapse ///
        (max) stable_time ///
        (first) stage_order = stage_order, ///
        by(patient_id stage_spell)

    collapse ///
        (sum) n_patients = stable_time ///
        (first) stage_order = stage_order, ///
        by(stage_spell)

    gen window_year = `wy'
    gen window_days = `this_days'
    gen pct_patients = 100 * n_patients / `N_patients'

    quietly {
        forvalues i = 1/`=_N' {
            post `post_time_stage' ///
                (stage_spell[`i']) ///
                (stage_order[`i']) ///
                (window_year[`i']) ///
                (window_days[`i']) ///
                (n_patients[`i']) ///
                (pct_patients[`i'])
        }
    }
}

postclose `post_time_stage'

use "stability_by_stage_by_time_window.dta", clear
sort stage_order window_days
order stage_order stage_spell window_year window_days n_patients pct_patients
export delimited using "stability_by_stage_by_time_window.csv", replace

**************************************************
* 4. visit次数阈值：总体patient数量
**************************************************
tempname post_visit_overall
postfile `post_visit_overall' ///
    double(visit_cut n_patients pct_patients) ///
    using "stability_overall_by_visit_cut.dta", replace

foreach vc of local visit_cut_list {

    use `base_spell', clear
    gen stable_visit = (n_visits_in_spell >= `vc')

    bys patient_id: egen patient_stable = max(stable_visit)
    bys patient_id: keep if _n == 1

    quietly count if patient_stable == 1
    local n = r(N)
    local pct = 100 * `n' / `N_patients'

    post `post_visit_overall' (`vc') (`n') (`pct')
}

postclose `post_visit_overall'

use "stability_overall_by_visit_cut.dta", clear
sort visit_cut
order visit_cut n_patients pct_patients
export delimited using "stability_overall_by_visit_cut.csv", replace

**************************************************
* 5. visit次数阈值：按stage分组patient数量
**************************************************
tempname post_visit_stage
postfile `post_visit_stage' ///
    str6 stage_spell double(stage_order visit_cut n_patients pct_patients) ///
    using "stability_by_stage_by_visit_cut.dta", replace

foreach vc of local visit_cut_list {

    use `base_spell', clear
    gen stable_visit = (n_visits_in_spell >= `vc')

    collapse ///
        (max) stable_visit ///
        (first) stage_order = stage_order, ///
        by(patient_id stage_spell)

    collapse ///
        (sum) n_patients = stable_visit ///
        (first) stage_order = stage_order, ///
        by(stage_spell)

    gen visit_cut = `vc'
    gen pct_patients = 100 * n_patients / `N_patients'

    quietly {
        forvalues i = 1/`=_N' {
            post `post_visit_stage' ///
                (stage_spell[`i']) ///
                (stage_order[`i']) ///
                (visit_cut[`i']) ///
                (n_patients[`i']) ///
                (pct_patients[`i'])
        }
    }
}

postclose `post_visit_stage'

use "stability_by_stage_by_visit_cut.dta", clear
sort stage_order visit_cut
order stage_order stage_spell visit_cut n_patients pct_patients
export delimited using "stability_by_stage_by_visit_cut.csv", replace

**************************************************
* 6. 准备 visit-level 数据（future egfr 匹配用）
**************************************************
use "data_2026_2_23.dta", clear

keep patient_id visit_dt eGFR_EPI
drop if missing(patient_id, visit_dt, eGFR_EPI)

capture confirm numeric variable visit_dt
if _rc {
    di as error "visit_dt 不是数值型 Stata 日期，请先转换。"
    exit 198
}

sort patient_id visit_dt
by patient_id visit_dt: keep if _n == 1
by patient_id: gen visit_seq = _n

rename eGFR_EPI egfr

tempfile visitdata
save `visitdata', replace

**************************************************
* 7. 构造 stable_sample_time
**************************************************
local first_time = 1
tempfile stable_time_all

foreach wy of local window_year_list {

    local this_days = round(`wy' * 365)

    use `base_spell', clear
    keep if spell_duration_days >= `this_days'

    * 每个 patient × window_year，只保留最早一个 stable spell
    sort patient_id window_start window_end
    by patient_id: keep if _n == 1

    gen threshold_type  = "time"
    gen threshold_value = `wy'
    gen window_year     = `wy'
    gen window_days     = `this_days'

    keep patient_id stage_spell stage_order ///
         window_start window_last_visit window_end window_length_days ///
         spell_duration_days n_visits_in_spell ///
         baseline_visit_dt baseline_visit_seq egfr_end ///
         threshold_type threshold_value window_year window_days

    if `first_time' == 1 {
        save `stable_time_all', replace
        local first_time = 0
    }
    else {
        append using `stable_time_all'
        save `stable_time_all', replace
    }
}

use `stable_time_all', clear
sort threshold_value patient_id
gen sample_id = _n
isid sample_id
isid patient_id threshold_type threshold_value
save "stable_sample_time.dta", replace

**************************************************
* 8. 构造 stable_sample_visit
**************************************************
local first_visit = 1
tempfile stable_visit_all

foreach vc of local visit_cut_list {

    use `base_spell', clear
    keep if n_visits_in_spell >= `vc'

    * 每个 patient × visit_cut，只保留最早一个 stable spell
    sort patient_id window_start window_end
    by patient_id: keep if _n == 1

    gen threshold_type  = "visit"
    gen threshold_value = `vc'
    gen visit_cut       = `vc'

    keep patient_id stage_spell stage_order ///
         window_start window_last_visit window_end window_length_days ///
         spell_duration_days n_visits_in_spell ///
         baseline_visit_dt baseline_visit_seq egfr_end ///
         threshold_type threshold_value visit_cut

    if `first_visit' == 1 {
        save `stable_visit_all', replace
        local first_visit = 0
    }
    else {
        append using `stable_visit_all'
        save `stable_visit_all', replace
    }
}

use `stable_visit_all', clear
sort threshold_value patient_id
gen sample_id = _n
isid sample_id
isid patient_id threshold_type threshold_value
save "stable_sample_visit.dta", replace
**************************************************
* 9. 基于 stable_sample_time 生成 reg_ready_from_time_window
*    年后匹配：在 [h-0.5, h+0.5] 年内取最接近 h 年的 visit
**************************************************
use "stable_sample_time.dta", clear
tempfile time_master
save `time_master', replace

foreach hy of local horizon_year_list {

    use `time_master', clear

    local hy_clean = subinstr("`hy'", ".", "_", .)

    * 目标点
    gen target_dt_y`hy_clean' = window_end + round(`hy' * 365)

    * 匹配窗口：例如 1年 -> [0.5, 1.5] 年
    local lb_days = round((`hy' - 0.5) * 365)
    local ub_days = round((`hy' + 0.5) * 365)

    gen lower_dt_y`hy_clean' = window_end + `lb_days'
    gen upper_dt_y`hy_clean' = window_end + `ub_days'

    joinby patient_id using `visitdata'

    * 只保留在对应年份窗口内的 visit
    keep if visit_dt >= lower_dt_y`hy_clean' & visit_dt <= upper_dt_y`hy_clean'

    * 在窗口内找最接近目标点的 visit
    gen abs_gap = abs(visit_dt - target_dt_y`hy_clean')
    bysort sample_id (abs_gap visit_dt visit_seq): keep if _n == 1

    rename visit_dt  future_visit_dt_y`hy_clean'
    rename visit_seq future_visit_seq_y`hy_clean'
    rename egfr      egfr_future_y`hy_clean'

    gen gap_days_y`hy_clean'     = future_visit_dt_y`hy_clean' - target_dt_y`hy_clean'
    gen abs_gap_days_y`hy_clean' = abs(gap_days_y`hy_clean')
    gen in_window_y`hy_clean'    = 1
    gen match_ok_y`hy_clean'     = 1

    gen egfr_relchg_y`hy_clean' = ///
        (egfr_future_y`hy_clean' - egfr_end) / egfr_end ///
        if !missing(egfr_future_y`hy_clean', egfr_end) & egfr_end != 0

    keep sample_id ///
         future_visit_dt_y`hy_clean' ///
         future_visit_seq_y`hy_clean' ///
         egfr_future_y`hy_clean' ///
         gap_days_y`hy_clean' ///
         abs_gap_days_y`hy_clean' ///
         in_window_y`hy_clean' ///
         match_ok_y`hy_clean' ///
         egfr_relchg_y`hy_clean'

    tempfile tmpy`hy_clean'
    save `tmpy`hy_clean'', replace

    use `time_master', clear
    merge 1:1 sample_id using `tmpy`hy_clean'', nogen
    save `time_master', replace
}

* 第x次visit后的egfr relative change
foreach hv of local horizon_visit_list {

    use `time_master', clear
    gen target_visit_seq_v`hv' = baseline_visit_seq + `hv'

    joinby patient_id using `visitdata'
    keep if visit_seq == target_visit_seq_v`hv'

    rename visit_dt  future_visit_dt_v`hv'
    rename visit_seq future_visit_seq_v`hv'
    rename egfr      egfr_future_v`hv'

    gen egfr_relchg_v`hv' = ///
        (egfr_future_v`hv' - egfr_end) / egfr_end ///
        if !missing(egfr_future_v`hv', egfr_end) & egfr_end != 0

    keep sample_id ///
         future_visit_dt_v`hv' ///
         future_visit_seq_v`hv' ///
         egfr_future_v`hv' ///
         egfr_relchg_v`hv'

    tempfile tmpv`hv'
    save `tmpv`hv'', replace

    use `time_master', clear
    merge 1:1 sample_id using `tmpv`hv'', nogen
    save `time_master', replace
}

use `time_master', clear
gen followup_available = !missing(egfr_end)

format window_start window_last_visit window_end baseline_visit_dt %td

order sample_id patient_id stage_spell stage_order ///
      threshold_type threshold_value window_year window_days ///
      window_start window_last_visit window_end window_length_days ///
      spell_duration_days n_visits_in_spell ///
      baseline_visit_dt baseline_visit_seq egfr_end ///
      future_visit_dt_y1 gap_days_y1 abs_gap_days_y1 in_window_y1 ///
      future_visit_dt_y2 gap_days_y2 abs_gap_days_y2 in_window_y2 ///
      future_visit_dt_y3 gap_days_y3 abs_gap_days_y3 in_window_y3 ///
      egfr_relchg_y1 egfr_relchg_y2 egfr_relchg_y3 ///
      egfr_relchg_v1 egfr_relchg_v2 egfr_relchg_v3 egfr_relchg_v4 egfr_relchg_v5

sort threshold_value patient_id
save "reg_ready_from_time_window_strictwindow.dta", replace
export delimited using "reg_ready_from_time_window_strictwindow.csv", replace

**************************************************
* 10. 基于 stable_sample_visit 生成 reg_ready_from_visit_cut
*     年后匹配：在 [h-0.5, h+0.5] 年内取最接近 h 年的 visit
**************************************************
use "stable_sample_visit.dta", clear
tempfile visit_master
save `visit_master', replace

* x年后的egfr relative change
foreach hy of local horizon_year_list {

    use `visit_master', clear

    local hy_clean = subinstr("`hy'", ".", "_", .)

    * 目标点
    gen target_dt_y`hy_clean' = window_end + round(`hy' * 365)

    * 匹配窗口：例如 1年 -> [0.5, 1.5] 年
    local lb_days = round((`hy' - 0.5) * 365)
    local ub_days = round((`hy' + 0.5) * 365)

    gen lower_dt_y`hy_clean' = window_end + `lb_days'
    gen upper_dt_y`hy_clean' = window_end + `ub_days'

    joinby patient_id using `visitdata'

    * 只保留在对应年份窗口内的 visit
    keep if visit_dt >= lower_dt_y`hy_clean' & visit_dt <= upper_dt_y`hy_clean'

    * 在窗口内找最接近目标点的 visit
    gen abs_gap = abs(visit_dt - target_dt_y`hy_clean')
    bysort sample_id (abs_gap visit_dt visit_seq): keep if _n == 1

    rename visit_dt  future_visit_dt_y`hy_clean'
    rename visit_seq future_visit_seq_y`hy_clean'
    rename egfr      egfr_future_y`hy_clean'

    gen gap_days_y`hy_clean'     = future_visit_dt_y`hy_clean' - target_dt_y`hy_clean'
    gen abs_gap_days_y`hy_clean' = abs(gap_days_y`hy_clean')

    * 在这个新逻辑下，只要能匹配上，就一定在窗口内
    gen match_ok_y`hy_clean' = 1

    gen egfr_relchg_y`hy_clean' = ///
        (egfr_future_y`hy_clean' - egfr_end) / egfr_end ///
        if !missing(egfr_future_y`hy_clean', egfr_end) & egfr_end != 0

    keep sample_id ///
         future_visit_dt_y`hy_clean' ///
         future_visit_seq_y`hy_clean' ///
         egfr_future_y`hy_clean' ///
         gap_days_y`hy_clean' ///
         abs_gap_days_y`hy_clean' ///
         match_ok_y`hy_clean' ///
         egfr_relchg_y`hy_clean'

    tempfile tmpy2_`hy_clean'
    save `tmpy2_`hy_clean'', replace

    use `visit_master', clear
    merge 1:1 sample_id using `tmpy2_`hy_clean'', nogen
    save `visit_master', replace
}

* 第x次visit后的egfr relative change
foreach hv of local horizon_visit_list {

    use `visit_master', clear
    gen target_visit_seq_v`hv' = baseline_visit_seq + `hv'

    joinby patient_id using `visitdata'
    keep if visit_seq == target_visit_seq_v`hv'

    rename visit_dt  future_visit_dt_v`hv'
    rename visit_seq future_visit_seq_v`hv'
    rename egfr      egfr_future_v`hv'

    gen egfr_relchg_v`hv' = ///
        (egfr_future_v`hv' - egfr_end) / egfr_end ///
        if !missing(egfr_future_v`hv', egfr_end) & egfr_end != 0

    keep sample_id ///
         future_visit_dt_v`hv' ///
         future_visit_seq_v`hv' ///
         egfr_future_v`hv' ///
         egfr_relchg_v`hv'

    tempfile tmpv2_`hv'
    save `tmpv2_`hv'', replace

    use `visit_master', clear
    merge 1:1 sample_id using `tmpv2_`hv'', nogen
    save `visit_master', replace
}

use `visit_master', clear
gen followup_available = !missing(egfr_end)

format window_start window_last_visit window_end baseline_visit_dt %td

order sample_id patient_id stage_spell stage_order ///
      threshold_type threshold_value visit_cut ///
      window_start window_last_visit window_end window_length_days ///
      spell_duration_days n_visits_in_spell ///
      baseline_visit_dt baseline_visit_seq egfr_end ///
      egfr_relchg_y1 egfr_relchg_y2 egfr_relchg_y3 ///
      egfr_relchg_v1 egfr_relchg_v2 egfr_relchg_v3 egfr_relchg_v4 egfr_relchg_v5

sort threshold_value patient_id
save "reg_ready_from_visit_cut.dta", replace
export delimited using "reg_ready_from_visit_cut.csv", replace

**************************************************
* 11. 输出检查
**************************************************
di "======================================"
di "Created files:"
di "1. stability_overall_by_time_window.dta / csv"
di "2. stability_by_stage_by_time_window.dta / csv"
di "3. stability_overall_by_visit_cut.dta / csv"
di "4. stability_by_stage_by_visit_cut.dta / csv"
di "5. stable_sample_time.dta"
di "6. stable_sample_visit.dta"
di "7. reg_ready_from_time_window.dta / csv"
di "8. reg_ready_from_visit_cut.dta / csv"
di "======================================"