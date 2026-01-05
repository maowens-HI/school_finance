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
  Phase 2 of jjp_final construction:
  - Step 1: Load county panel (county_exp_final.dta) and merge quality flags
  - Step 2: Apply baseline data quality filter (good_county_1972)
  - Step 3: Create rolling mean spending variables
  - Step 4: Apply balanced panel restriction (event window -5 to +17)
  - Step 5: Apply state-level filter (drop states with <10 balanced counties)
  - Step 6: Save jjp_final.dta

WHY THIS MATTERS:
  This creates the canonical analysis dataset by:
  - Ensuring all counties have complete baseline data (for quartile construction)
  - Requiring complete event windows (for clean event-study identification)
  - Ensuring adequate within-state variation (states need >=10 counties)

  The resulting dataset is used for all Figure 1 replications and downstream analysis.

INPUTS:
  - county_exp_final.dta    (from 05_create_county_panel.do)
  - county_clean.dta        (from 04_tag_county_quality.do)

OUTPUTS:
  - jjp_interp_final.dta    (Full county panel with all variables, before balance)
  - jjp_final.dta           (Balanced panel with state filter applied)
  - jjp_final_diagnostic.log (Sample size at each filtering step)

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

* Start logging for diagnostics
cap log close
log using "jjp_final_diagnostic.log", replace text

di "=============================================="
di "Building jjp_final Dataset"
di "Date: $S_DATE $S_TIME"
di "=============================================="

*** ---------------------------------------------------------------------------
*** Section 1: Load County Panel and Merge Quality Flags
*** ---------------------------------------------------------------------------

di _n "STEP 1: Loading county_exp_final.dta and merging quality flags"
di "--------------------------------------------------------------"

use county_exp_final, clear

* Document initial sample
di "Initial sample:"
count
local n_initial = r(N)
di "  Total county-year observations: `n_initial'"

distinct county
local n_counties_initial = r(ndistinct)
di "  Unique counties: `n_counties_initial'"

distinct state_fips
local n_states_initial = r(ndistinct)
di "  Unique states: `n_states_initial'"

* Merge quality flags from county_clean
merge m:1 county using county_clean
tab _merge
keep if _merge == 3 | _merge == 1  // Keep master even if no quality flag
replace good_county_1972 = 0 if missing(good_county_1972)
drop _merge

*** ---------------------------------------------------------------------------
*** Section 2: Apply Baseline Quality Filter
*** ---------------------------------------------------------------------------

di _n "STEP 2: Applying baseline quality filter (good_county_1972 == 1)"
di "--------------------------------------------------------------"

* Document pre-filter counts
count if good_county_1972 == 1
local n_good = r(N)
count if good_county_1972 != 1
local n_bad = r(N)
di "  Counties with 1972 baseline data: `n_good' obs"
di "  Counties WITHOUT 1972 baseline: `n_bad' obs"

* Apply filter
drop if good_county_1972 != 1

* Document post-filter counts
count
local n_after_quality = r(N)
di "  After quality filter: `n_after_quality' obs"

distinct county
local n_counties_after_quality = r(ndistinct)
di "  Unique counties: `n_counties_after_quality'"

*** ---------------------------------------------------------------------------
*** Section 3: Create Key Analysis Variables
*** ---------------------------------------------------------------------------

di _n "STEP 3: Creating analysis variables"
di "--------------------------------------------------------------"

* Create county ID and treatment indicators
rename county county_id
gen never_treated = treatment == 0
bysort county_id: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4 - 1

* Winsorize spending at 1st and 99th percentiles (within year)
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

di "  Created: exp, lexp, lexp_ma, lexp_ma_strict"

* Create relative year
gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

di "  Created: relative_year (year_unified - reform_year)"

*** ---------------------------------------------------------------------------
*** Section 4: Create Lead and Lag Indicators
*** ---------------------------------------------------------------------------

di _n "STEP 4: Creating event-study indicators"
di "--------------------------------------------------------------"

* Post-reform indicators (lag_1 through lag_17)
forvalues k = 1/17 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}

* Pre-reform indicators (lead_1 through lead_5)
forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}

* Bin endpoints (17+ and -5 and earlier)
replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year)
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)

di "  Created: lead_1 to lead_5, lag_1 to lag_17 (with endpoint binning)"

*** ---------------------------------------------------------------------------
*** Section 5: Create Baseline Spending Quartiles (1971)
*** ---------------------------------------------------------------------------

di _n "STEP 5: Creating baseline spending quartiles"
di "--------------------------------------------------------------"

* Save current data
tempfile main_data
save `main_data', replace

* Create quartiles using 1971 baseline
keep if year_unified == 1971
keep if !missing(exp, state_fips, county_id)

* Within-state quartiles (stable sort for reproducibility)
sort state_fips county_id
bysort state_fips: astile pre_q1971 = exp, n(4)
keep state_fips county_id pre_q1971

tempfile q1971
save `q1971', replace

* Reload and merge
use `main_data', clear
merge m:1 state_fips county_id using `q1971', nogen

di "  Created: pre_q1971 (within-state baseline spending quartile)"

*** ---------------------------------------------------------------------------
*** Section 6: Create Income Quartiles
*** ---------------------------------------------------------------------------

* Clean median family income and create quartiles
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

di "  Created: inc_q (within-state income quartile)"

*** ---------------------------------------------------------------------------
*** Section 7: Save Full Interpolated Panel (Pre-Balance)
*** ---------------------------------------------------------------------------

di _n "STEP 6: Saving pre-balance dataset"
di "--------------------------------------------------------------"

save jjp_interp_final, replace

count
di "  jjp_interp_final.dta saved with `r(N)' observations"

*** ---------------------------------------------------------------------------
*** Section 8: Apply Balanced Panel Restriction
*** ---------------------------------------------------------------------------

di _n "STEP 7: Applying balanced panel restriction (event window -5 to +17)"
di "--------------------------------------------------------------"

* Identify counties with complete event windows
preserve
keep if inrange(relative_year, -5, 17)  // Only check within the event window

* Find counties with complete windows
bys county_id: egen min_rel = min(relative_year)
bys county_id: egen max_rel = max(relative_year)
bys county_id: gen n_rel = _N

* Count nonmissing lexp_ma_strict in the window
bys county_id: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys county_id: replace n_nonmiss = n_nonmiss[_N]

* Keep only counties with full window AND no missing spending
* Must have: min_rel == -5, max_rel == 17, exactly 23 obs, all 23 non-missing
keep if min_rel == -5 & max_rel == 17 & n_rel == 23 & n_nonmiss == 23

keep county_id
duplicates drop
gen balanced = 1

* Document balanced county count
count
local n_balanced_counties = r(N)
di "  Counties meeting balance criteria: `n_balanced_counties'"

tempfile balanced_counties
save `balanced_counties', replace
restore

* Merge balance flag back
merge m:1 county_id using `balanced_counties', nogen
replace balanced = 0 if missing(balanced)

* Keep balanced counties + never-treated states (as control group)
di "  Keeping balanced counties and never-treated states..."
keep if balanced == 1 | never_treated2 == 1

count
local n_after_balance = r(N)
di "  After balance restriction: `n_after_balance' observations"

distinct county_id
local n_counties_after_balance = r(ndistinct)
di "  Unique counties: `n_counties_after_balance'"

*** ---------------------------------------------------------------------------
*** Section 9: Apply State-Level Filter (>= 10 Counties)
*** ---------------------------------------------------------------------------

di _n "STEP 8: Applying state-level filter (>= 10 counties per state)"
di "--------------------------------------------------------------"

* Count balanced counties per state (at a point in time to avoid year duplication)
preserve
keep if year_unified == 1971 | (never_treated2 == 1 & year_unified == 1980)
keep state_fips county_id balanced never_treated2
duplicates drop

* Count counties per state
bysort state_fips: gen n_counties_in_state = _N

* List states that will be dropped
di "  States with < 10 counties (will be dropped):"
tab state_fips if n_counties_in_state < 10

* Keep only states with >= 10 counties
keep if n_counties_in_state >= 10
keep state_fips
duplicates drop

tempfile valid_states
save `valid_states', replace
restore

* Merge to keep only valid states
merge m:1 state_fips using `valid_states'
tab _merge

* Document states dropped
di "  States dropped (< 10 counties):"
tab state_fips if _merge == 1, m
local n_states_dropped = r(r)

keep if _merge == 3
drop _merge

*** ---------------------------------------------------------------------------
*** Section 10: Final Quality Checks and Save
*** ---------------------------------------------------------------------------

di _n "STEP 9: Final quality checks and save"
di "--------------------------------------------------------------"

* Document final sample
count
local n_final = r(N)
di "  Final observation count: `n_final'"

distinct county_id
local n_counties_final = r(ndistinct)
di "  Final unique counties: `n_counties_final'"

distinct state_fips
local n_states_final = r(ndistinct)
di "  Final unique states: `n_states_final'"

* Summary statistics
di _n "  Summary of key variables:"
sum exp lexp_ma_strict school_age_pop if year_unified == 1971

* Treatment/control breakdown
di _n "  Treatment status (at baseline 1971):"
tab treatment if year_unified == 1971

* Save final dataset
save jjp_final, replace
di _n "  jjp_final.dta saved successfully!"

*** ---------------------------------------------------------------------------
*** Section 11: Create Summary Report
*** ---------------------------------------------------------------------------

di _n "=============================================="
di "SUMMARY: jjp_final Construction"
di "=============================================="
di "Starting sample:              `n_initial' obs, `n_counties_initial' counties, `n_states_initial' states"
di "After quality filter:         `n_after_quality' obs, `n_counties_after_quality' counties"
di "After balance restriction:    `n_after_balance' obs, `n_counties_after_balance' counties"
di "After state filter (>=10):    `n_final' obs, `n_counties_final' counties, `n_states_final' states"
di "=============================================="

log close

di _n "Diagnostic log saved to: jjp_final_diagnostic.log"
di "jjp_final.dta construction complete!"
