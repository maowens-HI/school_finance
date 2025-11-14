*Check for balance in data
use interp_d,clear
gen state_fips = substr(LEAID,1,2)
tempfile dist_panel
save `dist_panel'
*** ============================================
*** Use JJP reform table instead of Hanushek logic
*** ============================================

*** Housekeeping
clear
set more off
cd "$SchoolSpending/data"
*** Load JJP reform mapping (first sheet assumed)
import excel using "$SchoolSpending/data/tabula-tabled2.xlsx", firstrow


rename CaseNameLegislationwithout case_name
rename Constitutionalityoffinancesys const
rename TypeofReform reform_type
rename FundingFormulaafterReform form_post
rename FundingFormulabeforeReform form_pre
rename Year reform_year
rename State state_name



* create a local with the number of rows
local N = _N  

forvalues i = 2/`N' {
    if missing(state_name[`i']) {
        replace state_name = state_name[`i'-1] in `i'
    }
    else {
        replace state_name = state_name[`i'] in `i'
    }
}

replace state_name = itrim(lower(strtrim(state_name)))
* replace line feeds with a space
replace state_name = subinstr(state_name, char(10), " ", .)
replace state_name = subinstr(state_name, char(13), " ", .)
* now clean up any double spaces
replace state_name = itrim(strtrim(state_name))

replace state_name = "massachusetts" if state_name == "massachuset ts"

drop if missing(case_name)
keep if const == "Overturned"
bysort state_name: keep if _n == 1

gen mfp_pre = "MFP" if regexm(form_pre, "MFP")
gen ep_pre  = "EP"  if regexm(form_pre, "EP")
gen le_pre  = "LE"  if regexm(form_pre, "LE")
gen sl_pre  = "SL"  if regexm(form_pre, "SL")

gen mfp_post = "MFP" if regexm(form_post, "MFP")
gen ep_post  = "EP"  if regexm(form_post, "EP")
gen le_post  = "LE"  if regexm(form_post, "LE")
gen sl_post  = "SL"  if regexm(form_post, "SL")

gen reform = 0
replace reform = 1 if regexm(reform_type, "Equity")
drop reform_type
label define reform_lbl 0 "Adequacy" 1 "Equity"
label values reform reform_lbl
label variable reform "School finance reform type"
gen treatment = 1

* Generate flags
gen mfp_flag = (mfp_post != "" & mfp_pre == "")
gen ep_flag  = (ep_post  != "" & ep_pre  == "")
gen le_flag  = (le_post  != "" & le_pre  == "")
gen sl_flag  = (sl_post  != "" & sl_pre  == "")

* Encode into a single numeric variable
gen formula_new = .
replace formula_new = 1 if mfp_flag
replace formula_new = 2 if ep_flag
replace formula_new = 3 if le_flag
replace formula_new = 4 if sl_flag

label define formula_lbl 1 "MFP" 2 "EP" 3 "LE" 4 "SL"
label values formula_new formula_lbl

gen reform_mfp = mfp_flag == 1
gen reform_ep = ep_flag == 1
gen reform_le = le_flag == 1
gen reform_sl = sl_flag == 1
rename reform reform_eq

label variable reform_mfp "MFP Reform"
label variable reform_ep "EP Reform"
label variable reform_le "LE Reform"
label variable reform_sl "SL Reform"


tempfile temp
save `temp'

import delimited using state_fips_master, clear
replace state_name = itrim(lower(strtrim(state_name)))

merge 1:m state_name using `temp'
drop _merge
tostring fips, gen(state_fips) format(%02.0f)

drop fips

*** Save final panel with JJP treatment
merge 1:m state_fips using `dist_panel'
replace treatment = 0 if missing(treatment)
keep if _merge ==3
drop _merge

drop long_name sumlev region division state division_name region_name
keep state_fips reform_year reform_* year4  treatment LEAID 
save "$SchoolSpending/data/f33_indfin_grf_panel", replace



*--- 0. Setup -----------------------------------------------------------------
clear all
set more off
cd "$SchoolSpending\data"
use f33_indfin_grf_panel, clear
gen never_treated = treatment == 0
bysort LEAID: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4-1
*keep if good_county ==1
*take the 99% value and any obs that are above the 99% replace with 99%

*keep if good_county == 1
/**************************************************************************
*   STRICT 13-YEAR ROLLING MEAN
**************************************************************************/


*--- 3. Relative year ---------------------------------------------------------

gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

* Convert string LEAID → numeric
encode LEAID, gen(county_num)


tempfile interp_temp
save `interp_temp',replace




/**************************************************************************
*   BASELINE QUARTILES (1969–1971) + AVERAGE BASELINE
**************************************************************************/







**log close
/**************************************************************************
*   LEADS AND LAGS
**************************************************************************/

forvalues k = 1/17 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}
forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}

replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year)
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)



drop if LEAID == "06037"
/**************************************************************************
*   SAVE CLEAN INTERPOLATED DATASET
**************************************************************************/



*New stuff to delete
keep if inrange(relative_year, -5, 17)
xtset county_num relative_year
xtdescribe

* define event window bounds
local min_rel = -5
local max_rel = 17

* check which counties cover the full window
bys LEAID: egen min_rel_year = min(relative_year)

gen has_full_window = (min_rel_year <= `min_rel')

assert has_full_window


* drop counties missing parts of the event window
keep if has_full_window | never_treated ==1






