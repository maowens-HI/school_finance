**# Bookmark #1
/*==============================================================================
Project    : School Spending - Build analysis_panel_bal Dataset
File       : 06_build_analysis_panel_bal.do
Purpose    : Construct final analysis dataset (analysis_panel_bal) from county panel by
             applying balanced panel restrictions and state-level quality filters.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2026-01-05
-------------------------------------------------------------------------------

 
WHAT THIS FILE DOES:
  - Step 1: Load county panel and merge quality flags
  - Step 2: Apply baseline data quality filter (good_county_1972)
  - Step 3: Create rolling mean spending variables
  - Step 4: Apply balanced panel restriction (event window -5 to +17)
  - Step 5: Apply state-level filter (drop states with <10 balanced counties)
  - Step 6: Save analysis_panel_bal.dta

 

INPUTS:
  - county_panel.dta    (from 05_create_county_panel.do)
  - county_qual_flags.dta        (from 04_tag_county_quality.do)

 
OUTPUTS:
  - analysis_panel_unrestricted.dta    (Full county panel before balance restriction)
  - analysis_panel_bal.dta           (Balanced panel with state filter applied)

 
==============================================================================*/

 

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

 
clear all
set more off
cd "$SchoolSpending/data"

 

*** ---------------------------------------------------------------------------
*** Section 1: Load County Panel and Merge Quality Flags
*** ---------------------------------------------------------------------------

 
use county_panel, clear

 
merge m:1 county using county_qual_flags
keep if _merge == 3 | _merge == 1
replace good_county_1972 = 0 if missing(good_county_1972)
drop _merge
 
count
*** ---------------------------------------------------------------------------
*** Section 3: Create Key Analysis Variables
*** ---------------------------------------------------------------------------

 

rename county county_id
gen never_treated = treatment == 0
bysort county_id: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4 - 1

 

* Winsorize spending at 1st and 99th percentiles
rename county_exp exp
winsor2 exp, replace c(1 99) by(year_unified)

 

* Create log spending
gen lexp = log(exp)

 

* Create 13-year rolling mean
rangestat (mean) exp, interval(year_unified -12 0) by(county_id)
rename exp_mean exp_ma
gen lexp_ma = log(exp_ma)

 

* Create STRICT 13-year rolling mean (only if full 13-year window available)
rangestat (mean) exp_ma_strict = exp (count) n_obs = exp, ///
interval(year_unified -12 0) by(county_id)
replace exp_ma_strict = . if n_obs < 13
gen lexp_ma_strict = log(exp_ma_strict)

 

* Create relative year

gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

 

*** ---------------------------------------------------------------------------

*** Section 4: Create Lead and Lag Indicators

*** ---------------------------------------------------------------------------

 

forvalues k = 1/17 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)

}

 

forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)

}

 

* Bin endpoints

replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year)
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)

 

*** ---------------------------------------------------------------------------
*** Section 4: Create Baseline Spending Quartiles (1971)
*** ---------------------------------------------------------------------------

tempfile main_data
save `main_data', replace

* pre_q: Good counties only
preserve
keep if year_unified == 1971 & good_county_1972 == 1
keep if !missing(exp, state_fips, county_id)

bysort state_fips: egen pre_q = xtile(exp), n(4)
keep state_fips county_id pre_q

tempfile q_good
save `q_good', replace
restore

* pre_q_all: All counties
preserve
keep if year_unified == 1971
keep if !missing(exp, state_fips, county_id)

bysort state_fips: egen pre_q_all = xtile(exp), n(4)
keep state_fips county_id pre_q_all

tempfile q_all
save `q_all', replace
restore

* Merge both back
use `main_data', clear
merge m:1 state_fips county_id using `q_good', nogen
merge m:1 state_fips county_id using `q_all', nogen


 

*** ---------------------------------------------------------------------------
*** Section 5: Create Income Quartiles
*** ---------------------------------------------------------------------------

* Clean median family income upfront
replace median_family_income = subinstr(median_family_income, ",", "", .)
destring median_family_income, gen(med_fam_inc) force
drop median_family_income

* inc_q: Good counties only
preserve
keep if good_county_1972 == 1
keep state_fips county_id med_fam_inc
duplicates drop
keep if !missing(med_fam_inc, state_fips, county_id)

bysort state_fips: egen inc_q = xtile(med_fam_inc), n(4)
keep state_fips county_id inc_q

tempfile inc_good
save `inc_good', replace
restore

* inc_q_all: All counties
preserve
keep state_fips county_id med_fam_inc
duplicates drop
keep if !missing(med_fam_inc, state_fips, county_id)

bysort state_fips: egen inc_q_all = xtile(med_fam_inc), n(4)
keep state_fips county_id inc_q_all

tempfile inc_all
save `inc_all', replace
restore

* Merge both back
merge m:1 state_fips county_id using `inc_good', nogen
merge m:1 state_fips county_id using `inc_all', nogen

* Get med_fam_inc values for final dataset
preserve
keep state_fips county_id med_fam_inc
duplicates drop

tempfile inc_vals
save `inc_vals', replace
restore

merge m:1 state_fips county_id using `inc_vals', nogen


*** ---------------------------------------------------------------------------
*** Section 7: Save Full Interpolated Panel (Pre-Balance)
*** ---------------------------------------------------------------------------

 

save analysis_panel_unrestricted, replace

*SPREADSHEET - Count of counties by state
use analysis_panel_unrestricted, clear

preserve
    * Keep one row per county
    keep state_fips county_id
    duplicates drop
    
    * Count counties per state
    bysort state_fips: gen n_counties = _N
    
    * Keep one row per state for clean display
    bysort state_fips: keep if _n == 1
    keep state_fips n_counties
    
    * Display results
    sort state_fips
    list state_fips n_counties, noobs
restore
 

*** ---------------------------------------------------------------------------
*** Section 8: Apply Balanced Panel Restriction
*** ---------------------------------------------------------------------------

 

preserve
keep if inrange(relative_year, -5, 17)

 
bys county_id: egen min_rel = min(relative_year)
bys county_id: egen max_rel = max(relative_year)
bys county_id: gen n_rel = _N

 

bys county_id: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys county_id: replace n_nonmiss = n_nonmiss[_N]

 

keep if min_rel == -5 & max_rel == 17 & n_rel == 23 & n_nonmiss == 23

 
keep county_id
duplicates drop
gen balanced = 1

 

tempfile balanced_counties
save `balanced_counties', replace
restore

 

merge m:1 county_id using `balanced_counties', nogen
replace balanced = 0 if missing(balanced)

/*
levelsof state_fips, local(states)
foreach s of local states {
    preserve
    keep if state_fips == "`s'"
    
    gen byte miss_exp = missing(exp)
    collapse (count) n_counties=miss_exp (sum) n_missing=miss_exp, by(year_unified)
    gen pct_missing = 100 * n_missing / n_counties
    
        display _n "============================================="
    display "STATE `s'"
    display "============================================="
    list year_unified n_counties n_missing pct_missing if n_missing > 0, noobs clean
    
    restore
}



levelsof state_fips, local(states)
foreach s of local states {
  preserve
  keep if year_unified == 1971
  keep if state_fips == "`s'"
  display "STATE `s'"
  tab balanced
  restore


}

levelsof state_fips, local(states)
foreach s of local states {
  preserve
  keep if year_unified == 1971
  keep if state_fips == "`s'"
  display "STATE `s'"
  tab reform_year,m
  restore


}
*/


  tab balanced if year_unified == 1971
  


keep if balanced == 1 | never_treated2 == 1

save jjp_sheet_bal,replace
*SPREADSHEET - Count of counties by state
use jjp_sheet_bal, clear

preserve
    * Keep one row per county
    keep state_fips county_id
    duplicates drop
    
    * Count counties per state
    bysort state_fips: gen n_counties = _N
    
    * Keep one row per state for clean display
    bysort state_fips: keep if _n == 1
    keep state_fips n_counties
    
    * Display results
    sort state_fips
    list state_fips n_counties, noobs
restore
 


*** ---------------------------------------------------------------------------
*** Section 9: Flag Valid States
*** ---------------------------------------------------------------------------

* valid_state: >= 10 total counties (good + bad)
preserve
keep state_fips county_id
duplicates drop

bysort state_fips: gen n_counties_all = _N
keep state_fips n_counties_all
duplicates drop

tempfile state_counts_all
save `state_counts_all', replace
restore

merge m:1 state_fips using `state_counts_all', nogen
gen valid_st = (n_counties_all >= 10)

* valid_state_good: >= 10 good counties only
preserve
keep if good_county_1972 == 1
keep state_fips county_id
duplicates drop

bysort state_fips: gen n_counties_good = _N
keep state_fips n_counties_good
duplicates drop

tempfile state_counts_good
save `state_counts_good', replace
restore

merge m:1 state_fips using `state_counts_good', nogen
gen valid_st_gd = (n_counties_good >= 10)
replace valid_st_gd = 0 if missing(valid_st_gd)

*** ---------------------------------------------------------------------------
*** Section 10: Quality of Life 
*** ---------------------------------------------------------------------------

*--- Create combined reform type indicator
egen reform_types = group(reform_eq reform_mfp reform_ep reform_le reform_sl)

*--- Clean median family income (numeric version)
destring med_fam_inc, replace

*--- Drop unnecessary variables
rename good_county_1972 good
drop year4 good_county good_county_* never_treated n_obs balanced  ///
     county_name  ever_treated exp_ma  exp_ma_strict treatment // dup_tag
*--- Rename for clarity
rename never_treated2 never_treated
rename year_unified year


*--- Order variables logically
order county_id state_fips year relative_year good ///
      exp lexp_ma_strict lexp_ma ///
      pre_q inc_q med_fam_inc ///
      school_age_pop ///
      never_treated reform_year reform_types ///
      reform_eq reform_mfp reform_ep reform_le reform_sl ///
      lead_* lag_*

*--- Label key variables
label var county_id "5-digit FIPS (state + county)"
label var year "School year (year4 - 1)"
label var relative_year "Years since reform"
label var lexp_ma_strict "Log PPE, 13-yr strict rolling mean"
label var pre_q "Baseline spending quartile (1971, within-state)"
label var inc_q "Income quartile (1970 Census, within-state)"
label var med_fam_inc "Median family income (1970 Census)"
label var school_age_pop "School-age population (weight)"
label var never_treated "Never-treated state (control group)"
label var reform_types "Reform type grouping"
label values reform_eq .
label var reform_eq "Reform type (0=Adequacy, 1=Equity)"


*** ---------------------------------------------------------------------------
*** Section 11: Save Final Dataset
*** ---------------------------------------------------------------------------

save analysis_panel_bal, replace


* States in valid_st_gd
tab state_fips if valid_st_gd == 1

* States in valid_st_gd AND good
tab state_fips if valid_st_gd == 1 & good == 1


use analysis_panel_bal,clear
keep if good == 1 & valid_st_gd == 1
keep state_fips
duplicates drop
tab state_fips


use analysis_panel_bal_alt, clear

preserve
    * Keep one row per county
	keep if good == 1 & valid_st_gd == 1
    keep state_fips county_id
    duplicates drop
    
    * Count counties per state
    bysort state_fips: gen n_counties = _N
    
    * Keep one row per state for clean display
    bysort state_fips: keep if _n == 1
    keep state_fips n_counties
    
    * Display results
    sort state_fips
    list state_fips n_counties, noobs
restore
 