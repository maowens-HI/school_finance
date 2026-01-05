/*==============================================================================
Project    : School Spending - Build jjp_final Dataset
File       : 08_build_jjp_final.do
Purpose    : Construct final analysis dataset (jjp_final) from county panel by
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
  - Step 6: Save jjp_final.dta

INPUTS:
  - county_exp_final.dta    (from 05_create_county_panel.do)
  - county_clean.dta        (from 04_tag_county_quality.do)

OUTPUTS:
  - jjp_interp_final.dta    (Full county panel before balance restriction)
  - jjp_final.dta           (Balanced panel with state filter applied)

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

use county_exp_final, clear

merge m:1 county using county_clean
keep if _merge == 3 | _merge == 1
replace good_county_1972 = 0 if missing(good_county_1972)
drop _merge

*** ---------------------------------------------------------------------------
*** Section 2: Apply Baseline Quality Filter
*** ---------------------------------------------------------------------------

drop if good_county_1972 != 1

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
*** Section 5: Create Baseline Spending Quartiles (1971)
*** ---------------------------------------------------------------------------

tempfile main_data
save `main_data', replace

keep if year_unified == 1971
keep if !missing(exp, state_fips, county_id)

sort state_fips county_id
bysort state_fips: astile pre_q1971 = exp, n(4)
keep state_fips county_id pre_q1971

tempfile q1971
save `q1971', replace

use `main_data', clear
merge m:1 state_fips county_id using `q1971', nogen

*** ---------------------------------------------------------------------------
*** Section 6: Create Income Quartiles
*** ---------------------------------------------------------------------------

preserve
keep state_fips county_id median_family_income
gen med_fam_inc = regexr(median_family_income, "[^0-9]", "")
destring med_fam_inc, replace
drop median_family_income
duplicates drop
keep if !missing(med_fam_inc, state_fips, county_id)

sort state_fips county_id
bysort state_fips: astile inc_q = med_fam_inc, n(4)
keep state_fips county_id inc_q

tempfile inc_q
save `inc_q', replace
restore

merge m:1 state_fips county_id using `inc_q', nogen

*** ---------------------------------------------------------------------------
*** Section 7: Save Full Interpolated Panel (Pre-Balance)
*** ---------------------------------------------------------------------------

save jjp_interp_final, replace

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

keep if balanced == 1 | never_treated2 == 1

*** ---------------------------------------------------------------------------
*** Section 9: Apply State-Level Filter (>= 10 Counties)
*** ---------------------------------------------------------------------------

preserve
keep if year_unified == 1971 | (never_treated2 == 1 & year_unified == 1980)
keep state_fips county_id balanced never_treated2
duplicates drop

bysort state_fips: gen n_counties_in_state = _N
keep if n_counties_in_state >= 10
keep state_fips
duplicates drop

tempfile valid_states
save `valid_states', replace
restore

merge m:1 state_fips using `valid_states'
keep if _merge == 3
drop _merge

*** ---------------------------------------------------------------------------
*** Section 10: Save Final Dataset
*** ---------------------------------------------------------------------------

save jjp_final, replace
