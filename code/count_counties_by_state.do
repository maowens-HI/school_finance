/*==============================================================================
Project    : School Spending – Count Counties by State
File       : count_counties_by_state.do
Purpose    : Generate count of counties per state for sample restriction analysis
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-12-16
───────────────────────────────────────────────────────────────────────────────
WHAT THIS FILE DOES:
  • Loads county panel data
  • Counts unique counties per state
  • Shows which states would be affected by "≥10 counties" restriction
  • Identifies treatment status by state

INPUTS:
  - jjp_interp.dta (or county_exp_final.dta)

OUTPUTS:
  - Console output showing county counts by state
  - state_county_counts.dta (optional saved output)
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Load county panel data
*** ---------------------------------------------------------------------------

* Try loading the processed data first
capture use jjp_interp, clear

* If that doesn't exist, build from source files
if _rc != 0 {
    use county_clean, clear
    merge 1:m county using county_exp_final
    keep if _merge == 3
    drop _merge
}

*** ---------------------------------------------------------------------------
*** Extract state FIPS from county identifier
*** ---------------------------------------------------------------------------

* County should be 5-digit: SSCCC (state FIPS + county FIPS)
gen state_fips = substr(county, 1, 2) if strlen(county) == 5
destring state_fips, replace

* Alternative if county_id exists as string
capture confirm variable county_id
if _rc == 0 {
    replace state_fips = real(substr(county_id, 1, 2)) if strlen(county_id) == 5 & missing(state_fips)
}

*** ---------------------------------------------------------------------------
*** Identify treatment status by state
*** ---------------------------------------------------------------------------

* Create treatment indicator if not exists
capture confirm variable reform_year
if _rc == 0 {
    bysort state_fips: egen state_ever_treated = max(reform_year < .)
    label define treat_lbl 0 "Never Treated" 1 "Ever Treated"
    label values state_ever_treated treat_lbl
}
else {
    gen state_ever_treated = .
}

*** ---------------------------------------------------------------------------
*** Count unique counties per state (TOTAL in dataset)
*** ---------------------------------------------------------------------------

preserve

* Collapse to unique county-state combinations
collapse (max) state_ever_treated, by(state_fips county)

* Count counties per state
collapse (count) n_counties = county (max) state_ever_treated, by(state_fips)

* Sort by number of counties (descending)
gsort -n_counties

* Display results
list, separator(0)

* Summary statistics
summarize n_counties, detail

* Show states with < 10 counties
di _newline "States with FEWER than 10 counties:"
list state_fips n_counties state_ever_treated if n_counties < 10, separator(0)

* Show count by treatment status
di _newline "Summary by treatment status:"
tabstat n_counties, by(state_ever_treated) statistics(count mean median min max)

* Optional: save results
save state_county_counts, replace

restore

*** ---------------------------------------------------------------------------
*** Count BALANCED counties per state (if balance criteria exist)
*** ---------------------------------------------------------------------------

* Check if we have balanced panel indicator
capture confirm variable balanced
if _rc == 0 {
    di _newline(2) "===== BALANCED PANEL COUNTY COUNTS ====="

    preserve

    * Keep only balanced counties
    keep if balanced == 1

    * Collapse to unique county-state combinations
    collapse (max) state_ever_treated, by(state_fips county)

    * Count balanced counties per state
    collapse (count) n_balanced_counties = county (max) state_ever_treated, by(state_fips)

    * Sort by number of balanced counties (descending)
    gsort -n_balanced_counties

    * Display results
    list, separator(0)

    * Show states with < 10 balanced counties
    di _newline "States with FEWER than 10 balanced counties:"
    list state_fips n_balanced_counties state_ever_treated if n_balanced_counties < 10, separator(0)

    * Merge with total counts
    merge 1:1 state_fips using state_county_counts
    drop _merge

    * Show comparison
    di _newline "Comparison: Total vs Balanced Counties by State:"
    list state_fips n_counties n_balanced_counties state_ever_treated, separator(0)

    restore
}
else {
    di _newline "Note: No 'balanced' variable found. Only showing total county counts."
    di "Run balance.do or 06_A_county_balanced_figure1.do first to get balanced panel counts."
}

*** ---------------------------------------------------------------------------
*** Alternative: Count from event-time window (-5 to +17)
*** ---------------------------------------------------------------------------

capture confirm variable relative_year
if _rc == 0 {
    di _newline(2) "===== COUNTIES WITH COMPLETE EVENT WINDOW (-5 to +17) ====="

    preserve

    * Create indicator for complete event window
    gen in_window = inrange(relative_year, -5, 17) | missing(relative_year)

    * Check if county has all years in window
    bysort county state_fips: egen has_all_leads = min(relative_year >= -5 & relative_year <= -1) if !missing(relative_year)
    bysort county state_fips: egen has_all_lags = min(relative_year >= 0 & relative_year <= 17) if !missing(relative_year)

    gen complete_window = (has_all_leads == 1 & has_all_lags == 1)

    * Collapse to unique counties
    collapse (max) complete_window state_ever_treated, by(state_fips county)

    * Count counties with complete window per state
    collapse (sum) n_complete_window = complete_window (max) state_ever_treated, by(state_fips)

    gsort -n_complete_window

    list, separator(0)

    di _newline "States with FEWER than 10 counties with complete event window:"
    list state_fips n_complete_window state_ever_treated if n_complete_window < 10, separator(0)

    restore
}

di _newline(2) "===== DONE ====="
