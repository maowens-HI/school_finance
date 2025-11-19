/* The purpose of this file is to run the figure 1 event-studies we have been 
running except on the district level instead of the county level. This was
inspired by our 11/18/25 meting where we considered the Urban Institutes point
that county level results may be less progressive than district level results.
*/


* I am taking the tract level data from do file 05 just before we collapse to counties.
* This data has been processed for primary/secondary schools 
* This data needs tags for good and bad tracts though...

clear
set more off
cd "$SchoolSpending\data"
use "district_panel_tagged.dta", clear
gen state_fips = substr(LEAID,1,2)
save district,replace
*==============================================================*
* IV) Merge reform treatment data (Jackson et al 2016)
*==============================================================*

*--------------------------------------------------------------*
* A) Load and clean JJP reform table
*--------------------------------------------------------------*

* 1)--------------------------------- Import reform mapping from Excel
/*******************************************************************************
Use JJP reform table instead of Hanushek logic
*******************************************************************************/

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
sort state_name reform_year 
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
merge 1:m state_fips using district
replace treatment = 0 if missing(treatment)
keep if _merge ==3
drop _merge
drop long_name sumlev region division state division_name region_name 
keep state_name state_fips reform_year year4 LEAID county pp_exp_real school_age_pop treatment tract70

save "$SchoolSpending/data/district_treat", replace
*/
**************************************************************************
*   PREP: INTERPOLATED COUNTY PANEL + BASELINE QUARTILES + STRICT ROLLING
*   Purpose: Build clean county-year panel with interpolated exp vars,
*            baseline quartiles, and rolling mean (13-year strict)
**************************************************************************/

*--- 0. Setup -----------------------------------------------------------------
clear all
set more off
cd "$SchoolSpending\data"
use county_clean, clear
merge 1:m county using district_treat
drop _merge
replace good_county = 0 if missing(good_county)
rename county county_id
gen never_treated = treatment == 0
bysort county_id: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4-1
winsor2 pp_exp_real, replace c(1 99) by(year_unified)



/**************************************************************************
   STRICT 13-YEAR ROLLING MEAN
**************************************************************************/
***log versions
*log current
rename pp_exp_real exp

gen lexp = log(exp)

**log moving average
rangestat (mean) exp, interval(year_unified -12 -0) by(tract70)
rename exp_mean exp_ma
gen lexp_ma = log(exp_ma)

**log moving average STRICT
rangestat (mean) exp_ma_strict = exp (count) n_obs = exp, ///
    interval(year_unified -12 0) by(tract70)

* keep only obs with full 13-year window
replace exp_ma_strict = . if n_obs < 13 & year4 < 1979
gen lexp_ma_strict = log(exp_ma_strict)

*--- 3. Relative year ---------------------------------------------------------

gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

* Convert string LEAID → numeric
encode tract70, gen(tract70_num)

*drop if missing(exp)
save district_temp, replace



/**************************************************************************
*   BASELINE QUARTILES (1969–1971) + AVERAGE BASELINE
**************************************************************************/



local years 1966 1969 1970 1971
preserve
foreach y of local years {

    use district_temp, clear
    keep if year_unified == `y'
    keep if !missing(exp, state_fips, tract70)

    count
    if r(N)==0 {
        di as error "No observations for year `y' — skipping."
        continue
    }

    bysort state_fips: egen pre_q`y' = xtile(exp), n(4)
    keep state_fips tract70 pre_q`y'

    tempfile q`y'
    save `q`y'', replace


}
restore
* Merge quartiles back
foreach y of local years {
    merge m:1 state_fips tract70 using `q`y'', nogen
}

* Average baseline 1969–1971
local number 66 69 70 71
foreach n of local number {
    gen base_`n' = .
    replace base_`n' = exp if year_unified == 19`n'
    bys tract70: egen base_`n'_max = max(base_`n')
    drop base_`n'
    rename base_`n'_max base_`n'
}
egen base_exp = rowmean( base_66 base_69 base_70 base_71) 
bys state_fips: egen pre_q_66_71 = xtile(base_exp), n(4)

egen base_exp2 = rowmean( base_66 base_69 base_70) 
bys state_fips: egen pre_q_66_70 = xtile(base_exp2), n(4)

egen base_exp3 = rowmean( base_69 base_70 base_71) 
bys state_fips: egen pre_q_69_71 = xtile(base_exp3), n(4)


local year 1966 1969 1970 1971
foreach y of local year{
	forvalues q = 1/4{
		di "`q' `y'"
	summ exp if pre_q`y' == `q'
}
}

/**************************************************************************
   LEADS AND LAGS
**************************************************************************/

forvalues k = 1/17 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}
forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}

replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year) // bins
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year) //  bins




/**************************************************************************
   SAVE CLEAN INTERPOLATED DATASET
**************************************************************************/

rename good_county_1967 good_66
rename good_county_1970 good_69
rename good_county_1971 good_70
rename good_county_1972 good_71
rename good_county_6771 good_66_70
rename good_county good_66_71
rename good_county_7072 good_69_71

drop if missing(LEAID)

save jjp_district, replace


/*******************************************************************************
On 11/12/25 Matt requested that I amke a balanced panel based on event time 
(relative_year) Below is that fix
*******************************************************************************/

preserve
keep if inrange(relative_year, -5, 17) // Only check within the event window

* Find counties with complete windows
bys tract70: egen min_rel = min(relative_year)
bys tract70: egen max_rel = max(relative_year)
bys tract70: gen n_rel = _N

* Keep only if they have the full window
keep if min_rel == -5 & max_rel == 17 & n_rel == 23

* NEW: count nonmissing lexp_ma_strict in the window
bys tract70: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys tract70: replace n_nonmiss = n_nonmiss[_N]

* Keep only if they have the full window AND full nonmissingness
keep if min_rel == -5 & max_rel == 17 & n_rel == 23 & n_nonmiss == 23

keep tract70
duplicates drop
gen balance = 1
tempfile balance
save `balance'
restore

use `balance',clear
merge 1:m tract70 using jjp_district
* Mark unbalanced counties
replace balance = 0 if missing(balance)
**************


* Create balanced-only dataset for analysis
keep if balance ==1 | never_treated2 ==1 // keep balanced counties & never treateds



drop pre_q* base_*

/**************************************************************************
*   BASELINE QUARTILES (1969–1971) + AVERAGE BASELINE
**************************************************************************/



local years 1966 1969 1970 1971
preserve
foreach y of local years {

    use district_temp, clear
    keep if year_unified == `y'
    keep if !missing(exp, state_fips, tract70)

    count
    if r(N)==0 {
        di as error "No observations for year `y' — skipping."
        continue
    }

    bysort state_fips: egen pre_q`y' = xtile(exp), n(4)
    keep state_fips tract70 pre_q`y'

    tempfile q`y'
    save `q`y'', replace


}
restore
* Merge quartiles back
foreach y of local years {
    merge m:1 state_fips tract70 using `q`y'', nogen
}

* Average baseline 1969–1971
local number 66 69 70 71
foreach n of local number {
    gen base_`n' = .
    replace base_`n' = exp if year_unified == 19`n'
    bys tract70: egen base_`n'_max = max(base_`n')
    drop base_`n'
    rename base_`n'_max base_`n'
}
egen base_exp = rowmean( base_66 base_69 base_70 base_71) 
bys state_fips: egen pre_q_66_71 = xtile(base_exp), n(4)

egen base_exp2 = rowmean( base_66 base_69 base_70) 
bys state_fips: egen pre_q_66_70 = xtile(base_exp2), n(4)

egen base_exp3 = rowmean( base_69 base_70 base_71) 
bys state_fips: egen pre_q_69_71 = xtile(base_exp3), n(4)




save jjp_district_balance,replace
*/
/*********************************
* Split by quartiles of baseline spending
**********************************/
local var lexp lexp_ma lexp_ma_strict

local years   pre_q1966  pre_q1969 pre_q1970  pre_q1971 pre_q_66_70 pre_q_66_71 pre_q_69_71
local good good_66 good_69 good_70 good_71 good_66_70 good_66_71 good_69_71
local n: word count `years'

forvalues i = 1/`n' {
	  local y : word `i' of `years'
      local g : word `i' of `good'
    foreach v of local var {
        forvalues q = 1/4 {

            use jjp_district_balance, clear
					drop if `g' != 1
					count
display "Remaining obs in this iteration: " r(N)

            areg `v' ///
                i.lag_* i.lead_* ///
                i.year_unified  [w= school_age_pop] if  `y'==`q' & (never_treated==1 | reform_year<2000), ///
                absorb(LEAID) vce(cluster LEAID)
            *log close

            tempfile results
            postfile handle str15 term float rel_year b se using `results', replace

            forvalues k = 5(-1)1 {
                lincom 1.lead_`k'
                if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
            }

            post handle ("base0") (0) (0) (0)

            forvalues k = 1/17 {
                lincom 1.lag_`k'
                if !_rc post handle ("lag`k'") (`k') (r(estimate)) (r(se))
            }

            postclose handle

            use `results', clear
            sort rel_year

            gen ci_lo = b - 1.645*se
            gen ci_hi = b + 1.645*se

            twoway ///
                (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
                (line b rel_year, lcolor("42 66 94") lwidth(medium)), ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xline(0, lpattern(dash) lcolor(gs10)) ///
                ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
                title("`v' | Quartile `q' | `y' ", size(medlarge) color("35 45 60")) ///
                graphregion(color(white)) ///
                legend(off) ///
                scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_19_25\reg_`v'_`q'_`y'.png", replace

*graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_18_25\balance\reg_`v'_`q'_`y'.png", replace
        }
	}
    
}



*--------------------------------------*
* Regression: exclude top quartile (q == 4)
*--------------------------------------*
**********************************/
local var lexp lexp_ma lexp_ma_strict

local years   pre_q1966  pre_q1969 pre_q1970  pre_q1971 pre_q_66_70 pre_q_66_71 pre_q_69_71
local good good_66 good_69 good_70 good_71 good_66_70 good_66_71 good_69_71

local n: word count `years'

forvalues i = 1/`n' {
	  local y : word `i' of `years'
      local g : word `i' of `good'
    foreach v of local var {
	use jjp_district_balance, clear
	drop if `g' != 1
areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified [w= school_age_pop]   if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(LEAID) vce(cluster LEAID)

*--------------------------------------*
* Extract coefficients
*--------------------------------------*
tempfile results
postfile handle str15 term float rel_year b se using `results', replace

forvalues k = 5(-1)1 {
    lincom 1.lead_`k'
    if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle ("base0") (0) (0) (0)

forvalues k = 1/17 {
    lincom 1.lag_`k'
    if !_rc post handle ("lag`k'") (`k') (r(estimate)) (r(se))
}

postclose handle

*--------------------------------------*
* Plot event study
*--------------------------------------*
use `results', clear
sort rel_year

gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se


            twoway ///
                (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
                (line b rel_year, lcolor("42 66 94") lwidth(medium)), ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xline(0, lpattern(dash) lcolor(gs10)) ///
                ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
                title("`v' | Quartile 1-3 | `y'", size(medlarge) color("35 45 60")) ///
                graphregion(color(white)) ///
                legend(off) ///
                scheme(s2mono)
				
graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_19_25\btm_`v'_`y'.png", replace
*graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_18_25\balance\btm_`v'_`y'.png", replace	
}
}

