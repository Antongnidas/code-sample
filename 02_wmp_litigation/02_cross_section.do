clear all
set more off

* Set PROJECT_ROOT to the folder containing case_level_with_pseudo_time_*.dta
global root "PROJECT_ROOT"
cd "$root"

****************************************************
* 0. 读取已经带 pseudo time 的 case-level 数据
****************************************************
use case_level_with_pseudo_time_2026_4_6, clear

****************************************************
* 1. 只保留初级和中级法院；只保留有 pseudo time 的法院
****************************************************
keep if inlist(court_type, "初级", "中级")
drop if missing(pseudo_setup_month)

****************************************************
* 2. 构造处理组标记（重新生成，避免和原变量冲突）
****************************************************
capture drop cs_treat
gen cs_treat = !missing(setup_day)

****************************************************
* 3. 只用审判长
****************************************************
capture drop cs_judge cs_judge_id
gen cs_judge = 审判长

replace cs_judge = trim(cs_judge)
replace cs_judge = subinstr(cs_judge, "　", "", .)
replace cs_judge = subinstr(cs_judge, " ", "", .)
replace cs_judge = trim(cs_judge)

drop if missing(cs_judge)
drop if cs_judge == ""
drop if cs_judge == "无"
drop if cs_judge == "无。"
drop if cs_judge == "-"
drop if cs_judge == "--"

egen cs_judge_id = group(cs_judge)

****************************************************
* 4. 定义 pre / post
*    不设窗口，直接按 pseudo_setup_month 前后划分
****************************************************
capture drop cs_pre_flag cs_post_flag
gen cs_pre_flag  = (month <  pseudo_setup_month)
gen cs_post_flag = (month >= pseudo_setup_month)

keep if cs_pre_flag == 1 | cs_post_flag == 1

****************************************************
* 5. 生成 pre 审判长集合
****************************************************
preserve
    keep if cs_pre_flag == 1
    keep court_id cs_judge_id
    duplicates drop court_id cs_judge_id, force
    gen cs_pre_member = 1
    tempfile cs_pre_set
    save `cs_pre_set'
restore

****************************************************
* 6. 生成 post 审判长集合
****************************************************
preserve
    keep if cs_post_flag == 1
    keep court_id cs_judge_id
    duplicates drop court_id cs_judge_id, force
    gen cs_post_member = 1
    tempfile cs_post_set
    save `cs_post_set'
restore

****************************************************
* 7. 合并 pre / post 集合
****************************************************
use `cs_pre_set', clear
merge 1:1 court_id cs_judge_id using `cs_post_set'

* _merge==1: 只在 pre
* _merge==2: 只在 post
* _merge==3: pre 和 post 都在

capture drop cs_in_pre cs_in_post cs_both cs_new cs_exit
gen cs_in_pre  = .
gen cs_in_post = .
gen cs_both    = .
gen cs_new     = .
gen cs_exit    = .

replace cs_in_pre  = (_merge == 1 | _merge == 3)
replace cs_in_post = (_merge == 2 | _merge == 3)
replace cs_both    = (_merge == 3)
replace cs_new     = (_merge == 2)
replace cs_exit    = (_merge == 1)

drop _merge cs_pre_member cs_post_member

****************************************************
* 8. collapse 成法院层面
****************************************************
collapse ///
    (sum) cs_in_pre cs_in_post cs_both cs_new cs_exit, ///
    by(court_id)

****************************************************
* 9. 构造 judge change 指标
****************************************************
capture drop cs_new_ratio cs_exit_ratio cs_jaccard
gen cs_new_ratio  = cs_new  / cs_in_post if cs_in_post > 0
gen cs_exit_ratio = cs_exit / cs_in_pre  if cs_in_pre  > 0
gen cs_jaccard    = 1 - cs_both / (cs_in_pre + cs_in_post - cs_both) ///
                    if (cs_in_pre + cs_in_post - cs_both) > 0

****************************************************
* 10. merge 法院层面信息
****************************************************
preserve
    use case_level_with_pseudo_time_2026_4_6, clear
    keep court_id court_type setup_day pseudo_setup_month
    keep if inlist(court_type, "初级", "中级")
    drop if missing(pseudo_setup_month)

    capture drop cs_treat cs_intermediate
    gen cs_treat = !missing(setup_day)
    gen cs_intermediate = (court_type == "中级")

    duplicates drop court_id, force

    tempfile cs_courtinfo
    save `cs_courtinfo'
restore

merge 1:1 court_id using `cs_courtinfo', nogen

****************************************************
* 11. 保存法院层面的截面数据
****************************************************
save judge_change_cross_section_2026_4_6, replace

****************************************************
* 12. 描述统计
****************************************************
sum cs_new_ratio cs_exit_ratio cs_jaccard cs_in_pre cs_in_post cs_both cs_new cs_exit
tab court_type
tab cs_treat court_type

****************************************************
* 13. 基准回归：合并样本
****************************************************
reg cs_new_ratio  cs_treat, robust
est store r1

reg cs_exit_ratio cs_treat, robust
est store r2

reg cs_jaccard    cs_treat, robust
est store r3

****************************************************
* 14. 区分初级 / 中级法院
****************************************************
reg cs_new_ratio cs_treat if court_type == "初级", robust
est store r4

reg cs_new_ratio cs_treat if court_type == "中级", robust
est store r5

reg cs_jaccard cs_treat if court_type == "初级", robust
est store r6

reg cs_jaccard cs_treat if court_type == "中级", robust
est store r7

****************************************************
* 15. 交互项：比较初级 vs 中级
****************************************************
reg cs_new_ratio c.cs_treat##c.cs_intermediate, robust
est store r8

reg cs_jaccard c.cs_treat##c.cs_intermediate, robust
est store r9

****************************************************
* 16. 控制 pre 规模
****************************************************
reg cs_new_ratio c.cs_treat##c.cs_intermediate cs_in_pre, robust
est store r10

reg cs_jaccard c.cs_treat##c.cs_intermediate cs_in_pre, robust
est store r11

****************************************************
* 17. 导出结果
****************************************************
capture noisily esttab r1 r2 r3 r4 r5 r6 r7 r8 r9 r10 r11 ///
    using judge_change_cross_section_results_2026_4_6.rtf, ///
    replace b(%9.3f) se(%9.3f) star(* 0.10 ** 0.05 *** 0.01) ///
    stats(N r2, fmt(%9.0g %9.3f)) ///
    mtitles("New ratio" "Exit ratio" "Jaccard" ///
            "New ratio-Primary" "New ratio-Intermediate" ///
            "Jaccard-Primary" "Jaccard-Intermediate" ///
            "New ratio: Interact" "Jaccard: Interact" ///
            "New ratio: Interact+PreSize" "Jaccard: Interact+PreSize")