/*==============================================================================
Project    : School Spending - Build jjp_final Dataset
File       : 06_build_jjp_final.do
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

*** ===========================================================================
*** TOGGLE SWITCHES - Set to 1 to apply filter, 0 to skip
*** ===========================================================================

local REQUIRE_GOOD_BASELINE = 1    // Require good_county_1972 == 1
local REQUIRE_BALANCE       = 1    // Require complete event window (-5 to +17)
local REQUIRE_STATE_MIN     = 1    // Require states have >= N counties
local STATE_MIN_COUNTIES    = 10   // Minimum counties per state

*** ---------------------------------------------------------------------------
*** Section 1: Load County Panel and Merge Quality Flags
*** ---------------------------------------------------------------------------

use county_exp_final, clear

merge m:1 county using county_clean
keep if _merge == 3 | _merge == 1
replace good_county_1972 = 0 if missing(good_county_1972)
drop _merge

*** ---------------------------------------------------------------------------
*** Section 2: Flag Baseline Quality
*** ---------------------------------------------------------------------------

gen good_baseline = (good_county_1972 == 1)

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
*** Section 7: Flag Balanced Counties
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

*** ---------------------------------------------------------------------------
*** Section 8: Flag Valid States (>= N Counties)
*** ---------------------------------------------------------------------------

preserve
keep state_fips county_id
duplicates drop

bysort state_fips: gen n_counties_in_state = _N
keep state_fips n_counties_in_state
duplicates drop

tempfile state_counts
save `state_counts', replace
restore

merge m:1 state_fips using `state_counts', nogen
gen valid_state = (n_counties_in_state >= `STATE_MIN_COUNTIES')

*** ---------------------------------------------------------------------------
*** Section 9: Save Full Dataset with All Flags
*** ---------------------------------------------------------------------------

save jjp_interp_final, replace

*** ---------------------------------------------------------------------------
*** Section 10: Apply Filters Based on Toggle Switches
*** ---------------------------------------------------------------------------

gen keep_obs = 1

* Apply baseline quality filter
if `REQUIRE_GOOD_BASELINE' {
    replace keep_obs = 0 if good_baseline != 1
}

* Apply balance filter (treated must be balanced, never-treated always kept)
if `REQUIRE_BALANCE' {
    replace keep_obs = 0 if balanced != 1 & never_treated2 != 1
}

* Apply state minimum filter
if `REQUIRE_STATE_MIN' {
    replace keep_obs = 0 if valid_state != 1
}

keep if keep_obs == 1
drop keep_obs

*** ---------------------------------------------------------------------------
*** Section 11: Quality of Life Cleanup
*** ---------------------------------------------------------------------------

*--- Create combined reform type indicator
cap egen reform_types = group(reform_eq reform_mfp reform_ep reform_le reform_sl)

*--- Rename for convenience
rename pre_q1971 pre_q

*--- Clean median family income (numeric version)
cap drop med_fam_inc
gen med_fam_inc = regexr(median_family_income, "[^0-9]", "")
destring med_fam_inc, replace

*--- Drop unnecessary variables
cap drop year4 good_county_* never_treated n_obs balanced median_family_income ///
         county_name dup_tag keep_obs good_baseline valid_state n_counties_in_state

*--- Rename for clarity
rename never_treated2 never_treated

*--- Order variables logically
order county_id state_fips year_unified relative_year ///
      exp lexp lexp_ma lexp_ma_strict ///
      pre_q inc_q med_fam_inc ///
      school_age_pop ///
      treatment never_treated reform_year reform_types ///
      reform_eq reform_mfp reform_ep reform_le reform_sl ///
      lead_* lag_*

*--- Label key variables
label var county_id "5-digit FIPS (state + county)"
label var year_unified "School year (year4 - 1)"
label var relative_year "Years since reform"
label var lexp_ma_strict "Log PPE, 13-yr strict rolling mean"
label var pre_q "Baseline spending quartile (1971, within-state)"
label var inc_q "Income quartile (1970 Census, within-state)"
label var med_fam_inc "Median family income (1970 Census)"
label var school_age_pop "School-age population (weight)"
label var never_treated "Never-treated state (control group)"
cap label var reform_types "Reform type grouping"

*** ---------------------------------------------------------------------------
*** Section 12: Save Final Dataset
*** ---------------------------------------------------------------------------

save jjp_final, replace
