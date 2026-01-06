/*==============================================================================
Project    : School Spending – State Panel Characteristics Documentation
File       : 08_state_panel_characteristics.do
Purpose    : Generate comprehensive spreadsheet documenting all U.S. states with
             treatment status, timing, reform types, balanced panel status,
             missing data patterns, and exclusion reasons for DiD analysis.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2026-01-06
-------------------------------------------------------------------------------

WHAT THIS FILE DOES:
  - Step 1: Load county panel data and reform treatment information
  - Step 2: Create state-level summary of treatment status and timing
  - Step 3: Document reform types (equity, adequacy, formula changes)
  - Step 4: Compute balanced panel status and identify missing years
  - Step 5: Generate exclusion reason classifications
  - Step 6: Validate data completeness (50 states + DC)
  - Step 7: Export results to Excel with formatted columns

WHY THIS MATTERS:
  Creates a master reference document for understanding which states are included
  in the difference-in-differences analysis, why certain states are excluded,
  and the treatment timing that drives identification.

INPUTS:
  - jjp_final.dta           (from 06_build_jjp_final.do - main analysis file)
  - jjp_interp_final.dta    (from 06_build_jjp_final.do - pre-balance file)
  - state_fips_master.csv   (FIPS code crosswalk)
  - tabula-tabled2.xlsx     (JJP reform data)

OUTPUTS:
  - state_panel_characteristics.xlsx
  - state_panel_characteristics.dta

==============================================================================*/



*** ===========================================================================
*** SECTION 1: SETUP AND LOAD DATA
*** ===========================================================================

clear all
set more off
cd "$SchoolSpending/data"



*** ---------------------------------------------------------------------------
*** 1.1: Create State-Level Master List (All 50 States + DC)
*** ---------------------------------------------------------------------------

* Load state FIPS crosswalk to ensure we have all states
import delimited using "$SchoolSpending/data/state_fips_master.csv", clear

* Keep only necessary variables
keep fips state_name state_abbr

* Rename for consistency
rename fips state_fips_num

* Standardize state names
replace state_name = proper(strtrim(state_name))
replace state_abbr = upper(strtrim(state_abbr))

* Keep only 50 states + DC (drop territories)
* FIPS codes: 01-56 are states/DC, but exclude 03 (unused), 07 (unused), 14 (unused), 43 (unused), 52 (unused)
* Territories to exclude: 60 (AS), 66 (GU), 69 (MP), 72 (PR), 78 (VI)
keep if state_fips_num <= 56
drop if inlist(state_fips_num, 0, 3, 7, 14, 43, 52)

* Create string FIPS after filtering (more efficient)
gen str2 state_fips = string(state_fips_num, "%02.0f")
drop state_fips_num

* Sort and verify count
sort state_fips
count
local state_count = r(N)
di "Number of states in master list: `state_count'"

* Save master state list
tempfile state_master
save `state_master', replace



*** ===========================================================================
*** SECTION 2: LOAD REFORM TREATMENT DATA
*** ===========================================================================

*** ---------------------------------------------------------------------------
*** 2.1: Import JJP Reform Data from Excel
*** ---------------------------------------------------------------------------

* Load reform data directly from source
import excel using "$SchoolSpending/data/tabula-tabled2.xlsx", firstrow clear

* Rename variables for consistency
rename CaseNameLegislationwithout case_name
rename Constitutionalityoffinancesys const
rename TypeofReform reform_type_raw
rename FundingFormulaafterReform form_post
rename FundingFormulabeforeReform form_pre
rename Year reform_year
rename State state_name_raw

* Fill down state names (JJP data has merged cells)
local N = _N
forvalues i = 2/`N' {
    if missing(state_name_raw[`i']) {
        replace state_name_raw = state_name_raw[`i'-1] in `i'
    }
}

* Clean state names
replace state_name_raw = itrim(lower(strtrim(state_name_raw)))
replace state_name_raw = subinstr(state_name_raw, char(10), " ", .)
replace state_name_raw = subinstr(state_name_raw, char(13), " ", .)
replace state_name_raw = itrim(strtrim(state_name_raw))
replace state_name_raw = "massachusetts" if state_name_raw == "massachuset ts"

* Keep only court-ordered reforms (overturned)
drop if missing(case_name)
keep if const == "Overturned"

* Keep first reform per state (initial treatment date)
sort state_name_raw reform_year
bysort state_name_raw: keep if _n == 1

* Create reform type indicators
gen byte reform_equity = regexm(reform_type_raw, "Equity")
gen byte reform_adequacy = 1 - reform_equity

* Create formula change indicators
gen byte reform_mfp = (regexm(form_post, "MFP") & !regexm(form_pre, "MFP"))
gen byte reform_ep  = (regexm(form_post, "EP")  & !regexm(form_pre, "EP"))
gen byte reform_le  = (regexm(form_post, "LE")  & !regexm(form_pre, "LE"))
gen byte reform_sl  = (regexm(form_post, "SL")  & !regexm(form_pre, "SL"))

* Create combined reform type string
gen reform_types_str = ""
replace reform_types_str = reform_types_str + "equity " if reform_equity == 1
replace reform_types_str = reform_types_str + "adequacy " if reform_adequacy == 1
replace reform_types_str = reform_types_str + "MFP " if reform_mfp == 1
replace reform_types_str = reform_types_str + "EP " if reform_ep == 1
replace reform_types_str = reform_types_str + "LE " if reform_le == 1
replace reform_types_str = reform_types_str + "SL " if reform_sl == 1
replace reform_types_str = strtrim(reform_types_str)

* Mark as treated
gen byte treated = 1

* Standardize state name for merge
rename state_name_raw state_name
replace state_name = proper(state_name)

* Keep relevant variables
keep state_name reform_year treated reform_equity reform_adequacy ///
     reform_mfp reform_ep reform_le reform_sl reform_types_str case_name

* Merge with state FIPS codes
tempfile reform_data
save `reform_data', replace

import delimited using "$SchoolSpending/data/state_fips_master.csv", clear
keep fips state_name
gen str2 state_fips = string(fips, "%02.0f")
drop fips
replace state_name = proper(strtrim(state_name))

merge 1:1 state_name using `reform_data', nogen

* Fill in missing values for untreated states
replace treated = 0 if missing(treated)
replace reform_equity = 0 if missing(reform_equity)
replace reform_adequacy = 0 if missing(reform_adequacy)
replace reform_mfp = 0 if missing(reform_mfp)
replace reform_ep = 0 if missing(reform_ep)
replace reform_le = 0 if missing(reform_le)
replace reform_sl = 0 if missing(reform_sl)
replace reform_types_str = "never treated (control)" if treated == 0

* Save reform characteristics
tempfile state_treatment
save `state_treatment', replace



*** ===========================================================================
*** SECTION 3: COMPUTE PANEL BALANCE AND MISSING DATA
*** ===========================================================================

*** ---------------------------------------------------------------------------
*** 3.1: Load Analysis Dataset and Compute State-Level Statistics
*** ---------------------------------------------------------------------------

* Try to load the final analysis file first, fall back to interp file
capture use "$SchoolSpending/data/jjp_final.dta", clear
if _rc != 0 {
    di as text "jjp_final.dta not found, trying jjp_interp_final.dta..."
    capture use "$SchoolSpending/data/jjp_interp_final.dta", clear
    if _rc != 0 {
        di as text "jjp_interp_final.dta not found, trying county_exp_final.dta..."
        use "$SchoolSpending/data/county_exp_final.dta", clear
    }
}

* Ensure we have state_fips as string
capture confirm string variable state_fips
if _rc {
    tostring state_fips, gen(state_fips_str) format(%02.0f)
    drop state_fips
    rename state_fips_str state_fips
}

* Get year variable name (could be year, year_unified, or year4)
capture confirm variable year
if _rc {
    capture confirm variable year_unified
    if _rc {
        gen year = year4 - 1
    }
    else {
        rename year_unified year
    }
}

*** ---------------------------------------------------------------------------
*** 3.2: Count Counties and Years by State
*** ---------------------------------------------------------------------------

* Count unique counties per state
preserve
keep state_fips county_id
duplicates drop
bysort state_fips: gen n_counties_total = _N
keep state_fips n_counties_total
duplicates drop
tempfile county_counts
save `county_counts', replace
restore

* Count unique years per state
preserve
keep state_fips year
duplicates drop
bysort state_fips: gen n_years_total = _N
bysort state_fips: egen min_year = min(year)
bysort state_fips: egen max_year = max(year)
keep state_fips n_years_total min_year max_year
duplicates drop
tempfile year_counts
save `year_counts', replace
restore

*** ---------------------------------------------------------------------------
*** 3.3: Identify Missing Years by State
*** ---------------------------------------------------------------------------

* Create complete year grid for each state
preserve

* Get all unique state-year combinations that exist
keep state_fips year
duplicates drop

* Get state list
tempfile existing
save `existing', replace

* Create complete grid
keep state_fips
duplicates drop
tempfile states
save `states', replace

* Generate all years in study period (1967-2019)
clear
set obs 53
gen year = 1966 + _n
keep if year <= 2019

* Cross with states to create complete grid
cross using `states'

* Merge back to find missing
merge 1:1 state_fips year using `existing'

* Flag missing years
gen byte is_missing = (_merge == 1)
drop _merge

* Create list of missing years per state
bysort state_fips: egen n_missing_years = total(is_missing)

* Create string of missing years
sort state_fips year
by state_fips: gen missing_years_str = ""
by state_fips: replace missing_years_str = missing_years_str[_n-1] if _n > 1

* Add year to string if missing
by state_fips: replace missing_years_str = missing_years_str + " " + string(year) if is_missing == 1
by state_fips: replace missing_years_str = missing_years_str[_N]

* Clean up string
replace missing_years_str = strtrim(missing_years_str)

* Collapse to state level
keep state_fips n_missing_years missing_years_str
duplicates drop

tempfile missing_years
save `missing_years', replace
restore

*** ---------------------------------------------------------------------------
*** 3.4: Compute Balanced Panel Status (Event Window -5 to +17)
*** ---------------------------------------------------------------------------

preserve

* Check if relative_year exists, create if not
capture confirm variable relative_year
if _rc {
    * Need to merge reform_year first
    merge m:1 state_fips using `state_treatment', keepusing(reform_year) nogen
    gen relative_year = year - reform_year
    replace relative_year = . if missing(reform_year)
}

* Check if spending variable exists
capture confirm variable lexp_ma_strict
if _rc {
    * Create if we have the raw spending
    capture confirm variable county_exp
    if _rc == 0 {
        gen lexp_ma_strict = log(county_exp)
    }
}

* For treated states: check event window completeness
keep if !missing(relative_year)

* Keep only within event window
keep if inrange(relative_year, -5, 17)

* Count distinct years in window per county
bysort state_fips county_id: egen min_rel = min(relative_year)
bysort state_fips county_id: egen max_rel = max(relative_year)
bysort state_fips county_id: gen n_rel_years = _N

* Check spending data completeness
capture confirm variable lexp_ma_strict
if _rc == 0 {
    bysort state_fips county_id: egen n_nonmiss_spend = total(!missing(lexp_ma_strict))
}
else {
    gen n_nonmiss_spend = n_rel_years
}

* Flag balanced counties
gen byte balanced_county = (min_rel == -5 & max_rel == 17 & n_rel_years == 23 & n_nonmiss_spend >= 20)

* Collapse to state level
collapse (sum) n_balanced_counties = balanced_county ///
         (count) n_treated_counties = county_id, ///
         by(state_fips)

* Remove duplicates from counting
bysort state_fips: keep if _n == 1

gen pct_balanced = (n_balanced_counties / n_treated_counties) * 100

tempfile balance_stats
save `balance_stats', replace
restore

*** ---------------------------------------------------------------------------
*** 3.5: Compute Good County Flags (Baseline Data Quality)
*** ---------------------------------------------------------------------------

preserve

* Check for good county flag
capture confirm variable good_county_1972
if _rc {
    capture confirm variable good
    if _rc == 0 {
        rename good good_county_1972
    }
    else {
        gen good_county_1972 = 1  // Assume all good if flag missing
    }
}

* Count good vs bad counties per state
bysort state_fips county_id: keep if _n == 1
bysort state_fips: egen n_good_counties = total(good_county_1972 == 1)
bysort state_fips: egen n_bad_counties = total(good_county_1972 == 0)

keep state_fips n_good_counties n_bad_counties
duplicates drop

tempfile quality_stats
save `quality_stats', replace
restore



*** ===========================================================================
*** SECTION 4: MERGE ALL STATE-LEVEL INFORMATION
*** ===========================================================================

* Start with state master list
use `state_master', clear

* Merge treatment data
merge 1:1 state_fips using `state_treatment', nogen

* Merge county counts
merge 1:1 state_fips using `county_counts', nogen

* Merge year counts
merge 1:1 state_fips using `year_counts', nogen

* Merge missing year information
merge 1:1 state_fips using `missing_years', nogen

* Merge balance statistics (only for treated states)
merge 1:1 state_fips using `balance_stats', nogen

* Merge quality statistics
merge 1:1 state_fips using `quality_stats', nogen



*** ===========================================================================
*** SECTION 5: CREATE DERIVED VARIABLES AND EXCLUSION REASONS
*** ===========================================================================

*** ---------------------------------------------------------------------------
*** 5.1: Create Panel Status Variables
*** ---------------------------------------------------------------------------

* Determine if state has balanced panel
gen byte has_balanced_panel = 0

* For untreated states: balanced if no missing years
replace has_balanced_panel = 1 if treated == 0 & n_missing_years == 0

* For treated states: balanced if sufficient balanced counties
replace has_balanced_panel = 1 if treated == 1 & n_balanced_counties >= 5

* For states not in data, leave as 0
replace has_balanced_panel = 0 if missing(n_counties_total)

*** ---------------------------------------------------------------------------
*** 5.2: Create Exclusion Reason Classifications
*** ---------------------------------------------------------------------------

gen str200 exclusion_reason = ""

* Category 1: Not in dataset
replace exclusion_reason = "State not in analysis dataset" ///
    if missing(n_counties_total)

* Category 2: Insufficient counties
replace exclusion_reason = "Fewer than 10 counties in state (n=" + string(n_counties_total) + ")" ///
    if !missing(n_counties_total) & n_counties_total < 10 & exclusion_reason == ""

* Category 3: Missing baseline years (1967, 1970-1972)
replace exclusion_reason = "Missing data in baseline years (required for good_county flag)" ///
    if n_good_counties == 0 & exclusion_reason == "" & !missing(n_counties_total)

* Category 4: Early reform (before analysis window)
replace exclusion_reason = "Reform year " + string(reform_year) + " is before 1972 (insufficient pre-period)" ///
    if reform_year < 1972 & treated == 1 & exclusion_reason == ""

* Category 5: Late reform (after 2000)
replace exclusion_reason = "Reform year " + string(reform_year) + " is after 2000 (insufficient post-period)" ///
    if reform_year > 2000 & treated == 1 & exclusion_reason == ""

* Category 6: Missing years in critical window
replace exclusion_reason = "Missing data in years: " + missing_years_str ///
    if n_missing_years > 5 & exclusion_reason == "" & !missing(n_counties_total)

* Category 7: No balanced counties
replace exclusion_reason = "No counties with complete event window (-5 to +17)" ///
    if treated == 1 & n_balanced_counties == 0 & exclusion_reason == "" & !missing(n_counties_total)

* If no exclusion reason and in dataset, mark as included
replace exclusion_reason = "INCLUDED - meets all criteria" ///
    if exclusion_reason == "" & !missing(n_counties_total)

* Create binary inclusion flag
gen byte included_in_analysis = (exclusion_reason == "INCLUDED - meets all criteria")

*** ---------------------------------------------------------------------------
*** 5.3: Label Variables
*** ---------------------------------------------------------------------------

label var state_fips "State FIPS code (2-digit)"
label var state_name "State name"
label var state_abbr "State abbreviation"
label var treated "Treatment status (1=had court-ordered reform)"
label var reform_year "Year of first court-ordered reform"
label var reform_equity "Equity-focused reform"
label var reform_adequacy "Adequacy-focused reform"
label var reform_mfp "Introduced Minimum Foundation Program"
label var reform_ep "Introduced Equalization Program"
label var reform_le "Introduced Local Effort component"
label var reform_sl "Introduced State Lottery funding"
label var reform_types_str "Reform types (text description)"
label var case_name "Court case name"
label var n_counties_total "Total counties in state"
label var n_years_total "Total years with data"
label var min_year "First year with data"
label var max_year "Last year with data"
label var n_missing_years "Number of missing years"
label var missing_years_str "List of missing years"
label var n_balanced_counties "Counties with complete event window"
label var n_treated_counties "Treated counties (for balance calc)"
label var pct_balanced "Percent of counties balanced"
label var n_good_counties "Counties with complete baseline data"
label var n_bad_counties "Counties with incomplete baseline"
label var has_balanced_panel "State has balanced panel (1=yes)"
label var exclusion_reason "Reason for exclusion (if any)"
label var included_in_analysis "Included in final analysis (1=yes)"



*** ===========================================================================
*** SECTION 6: VALIDATION CHECKS
*** ===========================================================================

di _n "=============================================="
di "VALIDATION CHECKS"
di "=============================================="

* Check 1: All 50 states + DC present
count
local n_states = r(N)
if `n_states' == 51 {
    di as text "CHECK 1 PASSED: All 50 states + DC present (N=51)"
}
else {
    di as error "CHECK 1 FAILED: Expected 51 states, found `n_states'"
}

* Check 2: Treatment coding consistency
count if treated == 1 & missing(reform_year)
if r(N) == 0 {
    di as text "CHECK 2 PASSED: All treated states have reform year"
}
else {
    di as error "CHECK 2 FAILED: `r(N)' treated states missing reform year"
}

* Check 3: No missing treatment indicator
count if missing(treated)
if r(N) == 0 {
    di as text "CHECK 3 PASSED: No missing treatment indicators"
}
else {
    di as error "CHECK 3 FAILED: `r(N)' states with missing treatment"
}

* Check 4: Reform year range
sum reform_year if treated == 1, meanonly
di as text "CHECK 4 INFO: Reform years range from " r(min) " to " r(max)

* Check 5: Summary of inclusion/exclusion
di _n "SUMMARY OF STATE INCLUSION:"
tab included_in_analysis

di _n "EXCLUSION REASONS:"
tab exclusion_reason, sort

* Check 6: Count by treatment status
di _n "TREATMENT STATUS:"
tab treated included_in_analysis, row



*** ===========================================================================
*** SECTION 7: ORDER VARIABLES AND SAVE
*** ===========================================================================

* Order variables logically
order state_fips state_abbr state_name ///
      treated reform_year reform_types_str ///
      reform_equity reform_adequacy reform_mfp reform_ep reform_le reform_sl ///
      case_name ///
      included_in_analysis has_balanced_panel exclusion_reason ///
      n_counties_total n_good_counties n_bad_counties ///
      n_balanced_counties pct_balanced ///
      n_years_total min_year max_year n_missing_years missing_years_str

* Sort by state
sort state_abbr

* Save Stata file
save "$SchoolSpending/data/state_panel_characteristics.dta", replace

*** ---------------------------------------------------------------------------
*** 7.1: Export to Excel
*** ---------------------------------------------------------------------------

* Export full dataset
export excel using "$SchoolSpending/data/state_panel_characteristics.xlsx", ///
    firstrow(varlabels) replace sheet("State Characteristics")

di _n "=============================================="
di "OUTPUT FILES SAVED:"
di "  - state_panel_characteristics.dta"
di "  - state_panel_characteristics.xlsx"
di "=============================================="



*** ===========================================================================
*** SECTION 8: CREATE SUMMARY TABLES FOR QUICK REFERENCE
*** ===========================================================================

*** ---------------------------------------------------------------------------
*** 8.1: Treated States Summary
*** ---------------------------------------------------------------------------

preserve
keep if treated == 1
sort reform_year state_abbr

list state_abbr state_name reform_year reform_types_str included_in_analysis, ///
    sep(0) noobs clean

di _n "Total treated states: " _N
restore

*** ---------------------------------------------------------------------------
*** 8.2: Never-Treated (Control) States Summary
*** ---------------------------------------------------------------------------

preserve
keep if treated == 0
sort state_abbr

list state_abbr state_name n_counties_total included_in_analysis, ///
    sep(0) noobs clean

di _n "Total control states: " _N
restore

*** ---------------------------------------------------------------------------
*** 8.3: Excluded States Summary
*** ---------------------------------------------------------------------------

preserve
keep if included_in_analysis == 0
sort state_abbr

di _n "EXCLUDED STATES:"
list state_abbr state_name exclusion_reason, ///
    sep(0) noobs clean

di _n "Total excluded states: " _N
restore

di _n "=============================================="
di "STATE PANEL CHARACTERISTICS COMPLETE"
di "=============================================="
