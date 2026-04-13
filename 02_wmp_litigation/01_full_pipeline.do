* Set PROJECT_ROOT to the folder containing the raw data files (policy.dta, etc.)
global root "PROJECT_ROOT"
cd "$root"
 
use policy, clear

* 年份转数值 & 取样
destring year, gen(year_num)
keep if inrange(year_num, 2004, 2020)
egen city_num=group(city province),missing
* —— 指标标准化（人均）——
replace fin_loan     = fin_loan     / Total_Population
replace fin_deposit  = fin_deposit  / Total_Population  
replace deposit      = deposit      / Total_Population
replace Retail_Sales = Retail_Sales / Total_Population
gen     emp_rate     = Employed_People / Total_Population
save policy_new,replace
use policy_new,clear

xtset city_num  year_num
 
* —— 含上一期（L1）的回归 —— 
reghdfe fin_court ///
    gdp                      L.gdp ///  
    deposit                      L.deposit ///
	indus_1                      L.indus_1 ///
    indus_2                      L.indus_2 ///
    gdp_growth                   L.gdp_growth ///
    lnpGDP                       L.lnpGDP ///
    emp_rate                     L.emp_rate ///
	Primary_Industry_Share       L.Primary_Industry_Share ///
    Secondary_Industry_Share     L.Secondary_Industry_Share, ///
    absorb(city year_num) vce(cluster city)
keep if e(sample)
summarize fin_court if e(sample)
local mean_fin_court = r(mean)
estadd scalar y_mean = `mean_fin_court'
estadd local year_FE "Yes"
estadd local city_FE "Yes"
est store OLS_fin_court
use policy_new,clear
 
keep if inrange(year_num, 2004, 2020)
xtset city_num year_num
foreach v in deposit indus_2 indus_1 gdp_growth lnpGDP emp_rate Primary_Industry_Share Secondary_Industry_Share gdp {
    gen L1_`v' = L.`v'
}


bys city_num (year_num): gen event = fin_court==1 & L.fin_court==0

stset year_num, failure(event) id(city_num) origin(time 2003)

stcox  ///
	gdp                      L1_gdp  ///
    deposit                  L1_deposit ///
    indus_2                  L1_indus_2 ///
	indus_1                  L1_indus_1 ///
    gdp_growth               L1_gdp_growth ///
    lnpGDP                   L1_lnpGDP ///
    emp_rate                 L1_emp_rate ///
	Primary_Industry_Share   L1_Primary_Industry_Share ///
    Secondary_Industry_Share L1_Secondary_Industry_Share, ///
    vce(cluster city_num) strata(year_num) hr
keep if e(sample)
summarize fin_court if e(sample)
local mean_fin_court = r(mean)
estadd scalar y_mean = `mean_fin_court'
estadd local year_FE "Yes"
estadd local city_FE "Yes"
 
est store COX_fin_court

use policy_new, clear
keep if inrange(year_num, 2004, 2020)

* 面板声明
xtset city_num year_num

*------------------------------------------------------------
* 1. 标准化变量 & 生成滞后
*------------------------------------------------------------
local X deposit indus_2 indus_1 gdp_growth lnpGDP emp_rate ///
        Primary_Industry_Share Secondary_Industry_Share gdp

* 对所有解释变量做全样本 z-score（均值 0，方差 1）
foreach v of local X {
    egen z_`v' = std(`v')              // z_ 前缀 = 标准化后水平
    gen  z_L1_`v' = L.z_`v'            // z_L1_ 前缀 = 标准化后水平的 1 期滞后
}

*------------------------------------------------------------
* 2. 生成事件变量、构造生存数据集
*------------------------------------------------------------
bys city_num (year_num): gen event = fin_court == 1 & L.fin_court == 0

stset year_num, failure(event) id(city_num) origin(time 2003)

*------------------------------------------------------------
* 3. 离散时间 Cox 回归（用标准化后的解释量）
*------------------------------------------------------------
stcox  ///
    z_gdp                      z_L1_gdp  ///
    z_deposit                  z_L1_deposit ///
    z_indus_2                  z_L1_indus_2 ///
    z_indus_1                  z_L1_indus_1 ///
    z_gdp_growth               z_L1_gdp_growth ///
    z_lnpGDP                   z_L1_lnpGDP ///
    z_emp_rate                 z_L1_emp_rate ///
    z_Primary_Industry_Share   z_L1_Primary_Industry_Share ///
    z_Secondary_Industry_Share z_L1_Secondary_Industry_Share, ///
    vce(cluster city_num) strata(year_num) hr   // hr=报告 hazard ratio；删掉就给系数

*------------------------------------------------------------
* 4. 追加表底信息（与原脚本一致）
*------------------------------------------------------------
keep if e(sample)
summarize fin_court if e(sample)
local mean_fin_court = r(mean)

estadd scalar y_mean = `mean_fin_court'
estadd local year_FE "Yes"
estadd local city_FE "Yes"
est store COX_z
esttab OLS_fin_court   COX_fin_court  COX_z using "8-6-Cox-04-20.rtf", replace ///
      title("2004-2020") ///
      star(* 0.10 ** 0.05 *** 0.01)                      ///
      b(%9.3f) t(%7.3f)                                 ///
      stats(N r2_p ll chi2 r2 y_mean,                               ///
            labels("N" "R^2 / pseudo" "Log-Likelihood" "R2" "mean"))  compress nogaps  
 
 
use policy_new,clear
keep if inrange(year_num, 2004, 2020)
 
sort city year_num
encode city, gen(city_id)
xtset city_id year_num

*--------------------------------------------------------------
* 2. 生成滞后 1 期变量
*--------------------------------------------------------------
foreach var in fin_court ///
               deposit indus_2 indus_1 gdp_growth lnpGDP emp_rate ///
               Primary_Industry_Share Secondary_Industry_Share gdp {
    bysort city_id (year_num): gen L_`var' = L.`var'
}

* 初始观测
by city_id (year_num): gen fin_court0 = fin_court[1]

*--------------------------------------------------------------
* 3. 计算协变量全期均值（CRE 所需）
*--------------------------------------------------------------
local xvars deposit indus_2 indus_1 gdp_growth lnpGDP emp_rate ///
            Primary_Industry_Share Secondary_Industry_Share gdp

foreach v of local xvars {
    by city_id: egen m_`v' = mean(`v')
}

*--------------------------------------------------------------
* 4. CRE-动态 logit 回归
*--------------------------------------------------------------
xtlogit fin_court ///
        /* 状态依赖 */               L_fin_court ///
        /* 滞后协变量 */             L_deposit L_indus_2 L_indus_1 ///
                                     L_gdp_growth L_lnpGDP L_emp_rate ///
                                     L_Primary_Industry_Share L_Secondary_Industry_Share L_gdp ///
        /* 初始状态 */               fin_court0 ///
        /* 组内均值 */               m_deposit m_indus_2 m_indus_1 ///
                                     m_gdp_growth m_lnpGDP m_emp_rate ///
                                     m_Primary_Industry_Share m_Secondary_Industry_Share m_gdp ///
        , re vce(cluster city_id)

est store dy_logit
keep if e(sample)
summarize fin_court if e(sample)
local mean_fin_court = r(mean)
estadd scalar y_mean = `mean_fin_court'

*--------------------------------------------------------------
* 5. 输出结果
*--------------------------------------------------------------
esttab dy_logit using "动态logit-cox.rtf", replace ///
      title("Policy") ///
      star(* 0.10 ** 0.05 *** 0.01) ///
      b(%9.3f) t(%7.3f) ///
      stats(N r2_p ll chi2 y_mean, ///
            labels("N" "pseudo R²" "Log-Likelihood" "Mean(fin_court)")) ///
      compress nogaps nobaselevels noomitted nodepvars ///
      collabels(none) mlabels(none)
************************************************************
use reg_bank_month,clear
destring year, gen(year_num)
replace city ="金华" if city=="义乌"
drop gdp
drop gdp_growth
merge n:1 city province year_num using policy_new,force
drop if _merge==2
drop _merge
egen Underlying_Asset=group(underlying_asset)
save reg_8_6,replace 
use reg_8_6,clear
reghdfe WMP_r fin_court    wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth lnpGDP    indus_2  , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize WMP_r if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store OLS_fin
 
use reg_8_6,clear
reghdfe WMP_r court_count wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth lnpGDP    indus_2   , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize WMP_r if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store OLS_count
use reg_8_6,clear
reghdfe WMP_r fin_court court_count wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth  lnpGDP    indus_2  , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize WMP_r if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store OLS_both

esttab OLS_fin  OLS_count OLS_both using "8-6-Baseline-增加policy-control.rtf", replace ///
    title("Baseline ") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N bank_year_FE city_FE month_FE r2 F y_mean, labels("N" "Bank-Year_FE" "City_FE" "Month FE" "R2" "F" "Y_mean")) order(fin_court   court_count wmp_count bank_count HHI gdp_growth SHIBOR Rrr    SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement Trust Structure Loan Equities Bonds Money_market_products Commodities_foreign_exchange Other_underlying_assets) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the city level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:All single city WMP .\line Sample period: From 2004 to 2021.\line Control variables: Yes.") ///
			compress nogaps nobaselevels noomitted nodepvars  ///
			collabels(none) mlabels(none)	
***********************Principal_protection
use reg_8_6,clear
gen timestamp = clock("2018-04-27 00:00:00", "YMD hms")
keep if issue_date<= timestamp
replace Principal_coverage=Principal_coverage/100
replace principal_coverage=principal_coverage/100
save Principal_protection__8_6,replace

use Principal_protection__8_6,clear
gen P=.
replace P=1 if Principal_coverage >0
replace P=0 if Principal_coverage ==0
reghdfe Principal_coverage fin_court court_count wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity  Min_investment_requirement  Trust Structure    gdp gdp_growth lnpGDP    indus_2 , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize Principal_coverage if e(sample)
local mean_Principal_protection = r(mean)
estadd scalar y_mean = `mean_Principal_protection'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store OLS 
use Principal_protection__8_6,clear
egen Underlying_Asset_num=group(Underlying_Asset)
gen P=.
replace P=1 if Principal_coverage >0
replace P=0 if Principal_coverage ==0
local contvars   court_count wmp_count bank_count HHI SHIBOR Rrr ///
               SHSCI_growth SZSCI_growth Term_to_maturity ///
               Min_investment_requirement gdp gdp_growth lnpGDP indus_2

foreach v of local contvars {
    egen z_`v' = std(`v')          // (x-mean)/sd
}

* 重新跑模型（注意把原变量名换成 z_ 前缀）
logit P  fin_court z_court_count z_wmp_count z_bank_count z_HHI  z_SHIBOR  z_Rrr   z_SHSCI_growth z_SZSCI_growth z_Term_to_maturity  z_Min_investment_requirement   Trust  Structure z_gdp z_gdp_growth  z_lnpGDP  z_indus_2 i.Underlying_Asset  i.month_num  i.city_num, ///
      vce(cluster city_num) difficult iterate(800)

summarize Principal_coverage if e(sample)
local mean_Principal_protection = r(mean)
estadd scalar y_mean = `mean_Principal_protection'
estadd local bank_year_FE "No"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
quietly margins, dydx(fin_court)

* r(b) 存放了刚算好的 AME，抓出来保存成标量
matrix M = r(b)
scalar ame_fin = M[1,1]

* 把 AME 写进当前估计结果 (e())，这样 esttab 能调用
estadd scalar AME_finTrib = ame_fin
est store a2
 
esttab OLS a2 using "8-4-P .rtf", replace ///
    title("Principal_coverage") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
     stats(N bank_year_FE city_FE month_FE r2 r2_p  y_mean AME_finTrib, labels("N" "Bank-Year_FE" "City_FE" "Month FE" "R2" "Pseudo-R2"  "Y_mean" "Margin effects of Fin_tribunal")) keep (fin_court court_count wmp_count bank_count HHI  SHIBOR  Rrr   SHSCI_growth SZSCI_growth Term_to_maturity  Min_investment_requirement  Trust Structure gdp gdp_growth  lnpGDP  indus_2 z_court_count z_wmp_count z_bank_count z_HHI  z_SHIBOR  z_Rrr   z_SHSCI_growth z_SZSCI_growth z_Term_to_maturity  z_Min_investment_requirement   Trust  Structure z_gdp z_gdp_growth  z_lnpGDP  z_indus_2  )order(fin_court   court_count wmp_count bank_count HHI gdp_growth SHIBOR Rrr    SHSCI_growth SZSCI_growth Term_to_maturity   Min_investment_requirement Trust Structure Loan Equities Bonds Money_market_products Commodities_foreign_exchange Other_underlying_assets) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the city level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:All single city WMP .\line Sample period: From 2004 to 2021.\line Control variables: Yes.") ///
			compress nogaps
			
			
***************Target Investor
use reg_8_6 ,clear	
gen pbank = .
gen org = .
replace org = 4 if strpos(发行对象, "机构") > 0
gen hnw = .
replace pbank= 3 if strpos(发行对象, "私人银行客户") > 0 

replace hnw = 3 if strpos(发行对象, "高净值客户") > 0 
gen vip = . 
replace vip = 2 if strpos(发行对象, "VIP") > 0 
gen per = .
replace per = 1 if strpos(发行对象, "个人") > 0 
gen target_investors_top = max(pbank, hnw, org, per, vip)
gen target_investors_bot = . 

replace target_investors_bot = per if per>0 
replace target_investors_bot = org if (target_investors_bot==. | (org<target_investors_bot & org>0))
replace target_investors_bot = hnw if (target_investors_bot==. | (hnw<target_investors_bot & hnw>0)) 
replace target_investors_bot = pbank if (target_investors_bot==. | (pbank<target_investors_bot & pbank>0)) 
replace target_investors_bot = vip if (target_investors_bot==. | (vip<target_investors_bot & vip>0)) 
 
drop pbank hnw org per vip
replace target_investors_bot=1 if strpos(发行对象, "全部")
replace target_investors_top=5 if strpos(发行对象, "全部")
gen target_diff=target_investors_top-target_investors_bot
save target_8_6,replace 

use  target_8_6,clear
drop if target_investors_bot ==4
drop if target_investors_top ==4
reghdfe target_investors_bot  fin_court court_count wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth  lnpGDP    indus_2 , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize target_investors_bot if e(sample)
local mean_target_investors_bot = r(mean)
estadd scalar y_mean = `mean_target_investors_bot'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store bot

use  target_8_6,clear
drop if target_investors_bot ==4
drop if target_investors_top ==4
reghdfe target_investors_top  fin_court court_count wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth   lnpGDP    indus_2 , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize target_investors_top if e(sample)
local mean_target_investors_bot = r(mean)
estadd scalar y_mean = `mean_target_investors_bot'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store top
esttab  top bot using "8-6 target .rtf", replace ///
    title("target_investors ") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N bank_year_FE city_FE month_FE r2 F y_mean, labels("N" "Bank-Year_FE" "City_FE" "Month FE"  "R2" "F" "Y_mean")) order(fin_court   court_count wmp_count bank_count HHI gdp_growth SHIBOR Rrr    SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement Trust Structure  ) ///
    nonotes ///
			addnotes("Notes: The standard errors are clustered at the city level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source: All single city WMP .\line Sample period: From 2004 to 2021") ///
			compress nogaps  
			
			
**************Realized Return
use reg_8_6,clear
drop WMP_r
destring 实际年化收益率_银行理财大全, generate(WMP_r) force
reghdfe WMP_r fin_court    wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth  lnpGDP    indus_2 , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize WMP_r if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store OLS_fin
 
use reg_8_6,clear
drop WMP_r
destring 实际年化收益率_银行理财大全, generate(WMP_r) force
reghdfe WMP_r court_count wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth  lnpGDP    indus_2 , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize WMP_r if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store OLS_count
use reg_8_6,clear
drop WMP_r
destring 实际年化收益率_银行理财大全, generate(WMP_r) force
reghdfe WMP_r fin_court court_count wmp_count bank_count HHI  SHIBOR  Rrr  gdp_growth   SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure    gdp gdp_growth  lnpGDP    indus_2 , absorb(bank_year month_num city underlying_asset) vce (cluster city)
keep if e(sample)
summarize WMP_r if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local bank_year_FE "Yes"
estadd local city_FE "Yes"
estadd local month_FE "Yes"
est store OLS_both

esttab OLS_fin  OLS_count OLS_both using "8-6-Realized Retrun.rtf", replace ///
        title("Realized Retrun") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N bank_year_FE city_FE month_FE r2 F y_mean, labels("N" "Bank-Year_FE" "City_FE" "Month FE" "R2" "F" "Y_mean")) order(fin_court   court_count wmp_count bank_count HHI gdp_growth SHIBOR Rrr    SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement Trust Structure ) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the city level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:All single city WMP .\line Sample period: From 2004 to 2021.\line Control variables: Yes.") ///
			compress nogaps nobaselevels noomitted nodepvars  ///
			collabels(none) mlabels(none)	
			
			
**********Lawsuit
use lawsuit_all ,clear
drop if high
gen year_num=year
drop if missing(city)
clonevar city_raw = city   
replace city = ustrregexra(city, "市$", "")   if ustrregexm(city, "市$")
merge n:1 city year_num using policy_new,force
keep if year >=2004& year <=2020
egen prefecture_month = group(province city prefecture time_begin), missing
egen prefecture_year = group(province city prefecture year), missing
egen prefec = group(province city prefecture), missing
reghdfe  month_diff_tr  fin_tribunal gdp gdp_growth  lnpGDP    indus_2 , absorb( prefec time_begin type ) vce (cluster prefec)
keep if e(sample)
summarize month_diff_tr  if e(sample)
local mean_month_diff_tr  = r(mean)
estadd scalar y_mean =`mean_month_diff_tr'
estadd local Type_FE "Yes"
estadd local Prefecutre_Year_FE "No"
estadd local Prefecutre_FE "Yes"
estadd local Month_FE "Yes"
est store lawsuit_2016_py


use lawsuit_all ,clear
drop if high
keep if mid
gen year_num=year
drop if missing(city)
clonevar city_raw = city   
replace city = ustrregexra(city, "市$", "")   if ustrregexm(city, "市$")
merge n:1 city year_num using policy_new,force
keep if year >=2004& year <=2020
egen prefecture_year = group(province city   year), missing
 egen prefec = group(province city prefecture), missing
reghdfe  month_diff_tr  fin_tribunal gdp gdp_growth  lnpGDP    indus_2 , absorb( prefec  time_begin type ) vce (cluster prefec)
keep if e(sample)
summarize month_diff_tr  if e(sample)
local mean_month_diff_tr  = r(mean)
estadd scalar y_mean =`mean_month_diff_tr'
estadd local Type_FE "Yes"
estadd local Prefecutre_Year_FE "No"
estadd local Prefecutre_FE "Yes"
estadd local Month_FE "Yes"

est store lawsuit_2016_mid_2


esttab      lawsuit_2016_py   lawsuit_2016_mid_*  using "8-6-04-20诉讼回归.rtf", replace ///
    title("2014-2020 ") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N      Prefecutre_FE Month_FE Type_FE r2   y_mean, labels("N"   "Prefecutre_FE"  "Month_FE" "Case_Type_FE""R2"  "Mean DV")) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the prefecture level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:Lawsuit case   .\line ")	///
    compress nogaps noomitted   ///
    collabels(none) 
	
****************胜诉
use  判决_new,clear
gen year_num=year
drop _merge
clonevar city_raw = city   
replace city = ustrregexra(city, "市$", "")   if ustrregexm(city, "市$")
merge n:1 city   year_num using policy_new,force
drop if _merge==2
keep if year >=2004& year <=2020
egen prefec= group(province city prefecture),missing
egen time_be=group(time_begin),missing
reghdfe  fin_vs_person_win  fin_tribunal  gdp gdp_growth  lnpGDP    indus_2 , absorb(prefec type time_begin) vce (cluster prefec)
keep if e(sample)
summarize  fin_vs_person_win if e(sample)
local mean_month_diff_tr  = r(mean)
estadd scalar y_mean =`mean_month_diff_tr'
estadd local Type_FE "Yes"
estadd local Prefecutre_FE "Yes"
estadd local Month_FE "Yes"
est store fin_vs_person_win
 
use  判决_new,clear
gen year_num=year
drop _merge
clonevar city_raw = city   
replace city = ustrregexra(city, "市$", "")   if ustrregexm(city, "市$")
merge n:1 city   year_num using policy_new,force
keep if year >=2004& year <=2020
egen prefec= group(province city prefecture),missing
egen time_be=group(time_begin),missing
reghdfe  fin_vs_company_win  fin_tribunal  gdp gdp_growth  lnpGDP    indus_2 , absorb(prefec type time_begin) vce (cluster prefec)
keep if e(sample)
summarize  fin_vs_company_win if e(sample)
local mean_month_diff_tr  = r(mean)
estadd scalar y_mean =`mean_month_diff_tr'
estadd local Type_FE "Yes"
estadd local Prefecutre_FE "Yes"
estadd local Month_FE "Yes"
est store fin_vs_company_win
use  判决_new,clear
gen year_num=year
drop _merge
clonevar city_raw = city   
replace city = ustrregexra(city, "市$", "")   if ustrregexm(city, "市$")
merge n:1 city   year_num using policy_new,force
keep if year >=2004& year <=2020
egen prefec= group(province city prefecture),missing
egen prefec_year= group(province city prefecture year),missing
egen time_be=group(time_begin),missing
reghdfe  fin_vs_no_fin_win  fin_tribunal  gdp gdp_growth lnpGDP    indus_2 , absorb(prefec  type time_begin) vce (cluster prefec)
keep if e(sample)
summarize  fin_vs_no_fin_win if e(sample)
local mean_month_diff_tr  = r(mean)
estadd scalar y_mean =`mean_month_diff_tr'
estadd local Type_FE "Yes"
estadd local Prefecutre_FE "Yes"
estadd local Month_FE "Yes"
est store fin_vs_no_fin_win
 


esttab fin_vs_person_win  fin_vs_company_win   fin_vs_no_fin_win using "8-6 -04-20胜诉回归.rtf", replace ///
    title("2014-2020 ") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N  Prefecutre_FE Month_FE Type_FE r2   y_mean, labels("N"    "Prefecutre_FE" "Month_FE" "Case_Type_FE""R2"  "Mean DV")) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the prefecture level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:Lawsuit case   .\line ") ///
    compress nogaps ///
    collabels(none) 
	
	

*************event study*************			
use reg_8_6,clear
   generate fin_0 = 0
	replace fin_0 = 1 if issue_date == setup_time_中级
   	forvalues i = 0/23 {
		generate q_minus_`i' = 0
		generate q_plus_`i' = 0
	}
	generate q_plus_24 = 0
	
	forvalues i = -11/24 {
		local suffix = abs(`i')

		if (`i' < 0) {
			if (`i' >= -10) {
				replace q_minus_`suffix' = 1 if timeToEvent_中 == `i'
			}
			else {
				replace q_minus_11=1 if timeToEvent_中 <= -11
			}
		}
		else if (`i' > 0) {
			if (`i' <= 23) {
				replace q_plus_`suffix' = 1 if timeToEvent_中 == `i'
			}
			else {
				replace q_plus_24 = 1 if timeToEvent_中 >= 24
			}
		}
	}
 
	gen untreat=1-fin_中
 
eventstudyinteract WMP_r q_minus_11 q_minus_10 q_minus_9 q_minus_8 q_minus_7 q_minus_6 q_minus_5 q_minus_4 q_minus_3 q_minus_2 q_minus_1 q_plus_0 q_plus_1 q_plus_2 q_plus_3 q_plus_4 q_plus_5 q_plus_6 q_plus_7 q_plus_8 q_plus_9 q_plus_10 q_plus_11 q_plus_12 q_plus_13 q_plus_14 q_plus_15 q_plus_16 q_plus_17 q_plus_18 q_plus_19 q_plus_20 q_plus_21 q_plus_22 q_plus_23 q_plus_24, cohort(setup_time_中级) control_cohort(untreat)  covariates(  court_count wmp_count bank_count HHI gdp_growth SHIBOR  Rrr     SHSCI_growth SZSCI_growth Term_to_maturity Principal_coverage Min_investment_requirement  Trust Structure   gdp gdp_growth lnpGDP    indus_2  ) absorb(bank_year city_num month_num Underlying_Asset) vce(cluster city_num)
keep if e(sample)
estimates store ev_sa
 
 
      
forvalues i = 1/34 {
    local v_`i' = e(V_iw)[`i', `i']
}


matrix input mat3_sa = (`v_1', `v_2', `v_3', `v_4', `v_5', `v_6', `v_7', `v_8', `v_9', `v_10', `v_11', `v_12', `v_13', `v_14', `v_15', `v_16', `v_17', `v_18', `v_19', `v_20', `v_21', `v_22', `v_23',  `v_24', `v_25', `v_26', `v_27', `v_28', `v_29', `v_30', `v_31', `v_32', `v_33', `v_34'   )
mat colnames mat3_sa = q_minus_11 q_minus_10 q_minus_9 q_minus_8 q_minus_7 q_minus_6 q_minus_5 q_minus_4 q_minus_3 q_minus_2 q_minus_1 q_plus_0 q_plus_1 q_plus_2 q_plus_3 q_plus_4 q_plus_5 q_plus_6 q_plus_7 q_plus_8 q_plus_9 q_plus_10 q_plus_11 q_plus_12 q_plus_13 q_plus_14 q_plus_15 q_plus_16 q_plus_17 q_plus_18 q_plus_19 q_plus_20 q_plus_21 q_plus_22  
 

   forvalue i=1(1)34 {
	   local m_`i' = e(b_iw)[1, `i']
   
}

matrix input mat1_sa = (`m_1', `m_2', `m_3', `m_4', `m_5', `m_6', `m_7', `m_8', `m_9', `m_10', `m_11', `m_12', `m_13', `m_14', `m_15', `m_16', `m_17', `m_18', `m_19', `m_20', `m_21', `m_22', `m_23',`m_24',  `m_25', `m_26', `m_27', `m_28', `m_29', `m_30', `m_31', `m_32', `m_33', `m_34' )
mat colnames mat1_sa = q_minus_11 q_minus_10 q_minus_9 q_minus_8 q_minus_7 q_minus_6 q_minus_5 q_minus_4 q_minus_3 q_minus_2 q_minus_1 q_plus_0 q_plus_1 q_plus_2 q_plus_3 q_plus_4 q_plus_5 q_plus_6 q_plus_7 q_plus_8 q_plus_9 q_plus_10 q_plus_11 q_plus_12 q_plus_13 q_plus_14 q_plus_15 q_plus_16 q_plus_17 q_plus_18 q_plus_19 q_plus_20 q_plus_21 q_plus_22  
 
* ——— 3. 画图（只用一套系数） ———
set scheme s2mono          // 黑白配色，避免彩色意外
 
event_plot mat1_sa#mat3_sa,                                   ///
    stub_lag( q_plus_#) stub_lead(q_minus_#)  together                   ///
    plottype(connected) ciplottype(connected)                 ///
    lag_opt(lcolor(black) lwidth(medthick) msymbol(o) msize(small) ///
            mlcolor(black) mfcolor(black))                    ///
    lead_opt(lcolor(black) lwidth(medthick) msymbol(o) msize(small) ///
             mlcolor(black) mfcolor(black))                   ///
    lag_ci_opt(lcolor(gs6 gs6) lpattern(shortdash shortdash) ///
               lwidth(vthin vthin) msymbol(none none))        ///
    lead_ci_opt(lcolor(gs6 gs6) lpattern(shortdash shortdash) ///
               lwidth(vthin vthin) msymbol(none none))        ///
    graph_opt(legend(off)                                     ///
              yline(0, lpattern(dash) lwidth(vthin) lcolor(gs8)) ///
              xline(0, lpattern(dash) lwidth(vthin) lcolor(gs8)) ///
              xlabel(-11 "< -10" -8(2)21 22 ">=22") ///
			  ylabel(, nogrid)                                  /// 关闭 y 轴网格
              xtitle("{fontface Times New Roman:Months since the event}")        ///
              graphregion(color(white)) plotregion(margin(5 5 5 5)) ///
              name(Figure3_BHAR, replace) )


graph export "8-7-Figure3_bank_year-connect.emf", as(emf) replace


*************Competition
use reg_8_6,clear
duplicates drop  month city,force	
reghdfe HHI fin_court   court_count   SHIBOR  Rrr     SHSCI_growth SZSCI_growth   gdp gdp_growth lnpGDP    indus_2 , absorb(city month) vce (cluster city)
keep if e(sample)
summarize HHI if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local  year_FE "Control"
estadd local city_FE "Control"
est store OLS_fin
use reg_8_6,clear
 
duplicates drop  month city,force	
reghdfe  wmp_count   fin_court court_count SHIBOR  Rrr     SHSCI_growth SZSCI_growth   gdp gdp_growth lnpGDP    indus_2 , absorb(city month) vce (cluster city)
keep if e(sample)
summarize wmp_count if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local  year_FE "Control"
estadd local city_FE "Control"
est store OLS_count
use reg_8_6 ,clear
 
duplicates drop  month city,force		
reghdfe  bank_count  fin_court   court_count   SHIBOR  Rrr     SHSCI_growth SZSCI_growth   gdp gdp_growth lnpGDP    indus_2 , absorb(city month) vce (cluster city)
keep if e(sample)
summarize bank_count if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local  year_FE "Control"
estadd local city_FE "Control"
est store OLS_both

esttab   OLS_count OLS_both  OLS_fin using "Competition.rtf", replace ///
    title("Baseline_control_All single city WMP") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N  year_FE city_FE r2 F y_mean, labels("N" "Year_FE" "City_FE" "R2" "F" "Y_mean")) order(fin_court   court_count     gdp_growth SHIBOR Rrr    SHSCI_growth SZSCI_growth  ) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the city level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:All single city WMP .\line Sample period: From 2004 to 2021.\line Control variables: Yes.")	 ///
    compress nogaps nobaselevels  
use reg_8_6 ,clear
drop  HHI
merge n:1 city month using HHI_n
drop if _merge!=3
drop _merge
drop  bank_count
merge n:1 city month using bank_count_n
drop if _merge!=3
drop _merge
drop  wmp_count
merge n:1 city month using wmp_count_n
drop if _merge!=3
drop _merge
save reg_8_6_n,replace 	
use  reg_8_6_n,clear
duplicates drop  month city,force	
reghdfe HHI fin_court   court_count   SHIBOR  Rrr     SHSCI_growth SZSCI_growth   gdp gdp_growth lnpGDP    indus_2   , absorb(city month) vce (cluster city)
keep if e(sample)
summarize HHI if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local  year_FE "Control"
estadd local city_FE "Control"
est store OLS_fin
use  reg_8_6_n,clear
 
duplicates drop  month city,force	
reghdfe  wmp_count   fin_court court_count     SHIBOR  Rrr     SHSCI_growth SZSCI_growth     gdp gdp_growth lnpGDP    indus_2 , absorb(city month) vce (cluster city)
keep if e(sample)
summarize wmp_count if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local  year_FE "Control"
estadd local city_FE "Control"
est store OLS_count
use  reg_8_6_n,clear
 
duplicates drop  month city,force		
reghdfe  bank_count  fin_court   court_count        SHIBOR  Rrr     SHSCI_growth SZSCI_growth   gdp gdp_growth lnpGDP    indus_2   , absorb(city month) vce (cluster city)
keep if e(sample)
summarize bank_count if e(sample)
local mean_WMP_r = r(mean)
estadd scalar y_mean = `mean_WMP_r'
estadd local  year_FE "Control"
estadd local city_FE "Control"
est store OLS_both

esttab   OLS_count OLS_both  OLS_fin using "8-7-Competition_n.rtf", replace ///
    title("Baseline_control_All single city WMP") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N  year_FE city_FE r2 F y_mean, labels("N" "Year_FE" "City_FE" "R2" "F" "Y_mean")) order(fin_court   court_count     gdp_growth SHIBOR Rrr    SHSCI_growth SZSCI_growth  ) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the city level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:All single city WMP .\line Sample period: From 2004 to 2021.\line Control variables: Yes.")	 ///
    compress nogaps nobaselevels 
	
***************诉讼效率
 
use lawsuit_all ,clear
gen year_num=year
drop if high
replace city = ustrregexra(city, "市$", "")   if ustrregexm(city, "市$")
merge n:1 city   year_num using policy_new,force
keep if year >=2004& year <=2020
 egen prefecture_month = group(province city prefecture time_begin), missing
egen prefecture_year = group(province city prefecture year), missing
egen prefec = group(province city prefecture), missing
reghdfe  month_diff_tr  fin_tribunal gdp gdp_growth lnpGDP    indus_2, absorb( prefec time_begin type ) vce (cluster prefec)
keep if e(sample)
summarize month_diff_tr  if e(sample)
local mean_month_diff_tr  = r(mean)
estadd scalar y_mean =`mean_month_diff_tr'
estadd local Type_FE "Yes"
estadd local Prefecutre_Year_FE "No"
estadd local Prefecutre_FE "Yes"
estadd local Month_FE "Yes"
est store lawsuit_2016_py



use lawsuit_all ,clear
gen year_num=year
drop if missing(time_begin)
drop if missing(time_end)
replace city = ustrregexra(city, "市$", "")   if ustrregexm(city, "市$")
merge n:1 city   year_num using policy_new,force
keep if year >=2004& year <=2020
keep if mid
egen prefecture_year = group(province city   year), missing
 egen prefec = group(province city prefecture), missing
reghdfe  month_diff_tr  fin_tribunal gdp gdp_growth lnpGDP    indus_2, absorb( prefec  time_begin type ) vce (cluster prefec)
keep if e(sample)
summarize month_diff_tr  if e(sample)
local mean_month_diff_tr  = r(mean)
estadd scalar y_mean =`mean_month_diff_tr'
estadd local Type_FE "Yes"
estadd local Prefecutre_Year_FE "No"
estadd local Prefecutre_FE "Yes"
estadd local Month_FE "Yes"

est store lawsuit_2016_mid_2


esttab      lawsuit_2016_py   lawsuit_2016_mid_*  using "8-7-诉讼回归.rtf", replace ///
    title(" ") star(* 0.1 ** 0.05 *** 0.01) b(%9.3f) t(%7.2f) ///
    stats(N      Prefecutre_FE Month_FE Type_FE r2   y_mean, labels("N"   "Prefecutre_FE"  "Month_FE" "Case_Type_FE""R2"  "Mean DV")) ///
    nonotes ///
			addnotes("Notes:The standard errors are clustered at the prefecture level; *, ** and *** indicate significance at the 10%, 5% and 1% levels, respectively.\line Estimation method: OLS regression.\line Sample source:Lawsuit case   .\line ")	///
    compress nogaps noomitted   ///
    collabels(none) 