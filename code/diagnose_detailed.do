/*==============================================================================
Project    : School Spending – Detailed State Dropout Diagnosis
File       : diagnose_detailed.do
Purpose    : Verify exactly why each state drops from the analysis
Author     : Myles Owens / Claude
Date       : 2025-01-26
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*==============================================================================
* PART 1: Understand the crosswalk structure
*==============================================================================

di _n "=== EXAMINING CANON_CROSSWALK.DTA ==="
use "canon_crosswalk.dta", clear
describe
di "Number of observations: " _N
list in 1/10

*==============================================================================
* PART 2: For each state, trace the exact dropout mechanism
*==============================================================================

*--- ARIZONA ---
di _n _n "========================================================================"
di "ARIZONA DETAILED ANALYSIS"
di "========================================================================"

* Step 1: What GOVIDs are in INDFIN for Arizona?
di _n "--- INDFIN: Arizona districts (GOVS state 03) ---"
use "indfin_panel.dta", clear
gen govs_st = substr(GOVID, 1, 2)
keep if govs_st == "03"
keep GOVID
duplicates drop
gen govs_cty = substr(GOVID, 4, 3)
di "Unique districts in INDFIN:"
list GOVID govs_cty in 1/30
di "Unique GOVS counties:"
tab govs_cty

* Step 2: What GOVIDs are in dist_panel for Arizona?
di _n "--- DIST_PANEL: Arizona districts ---"
use "dist_panel.dta", clear
gen govs_st = substr(GOVID, 1, 2)
keep if govs_st == "03"
keep GOVID LEAID
duplicates drop
gen govs_cty = substr(GOVID, 4, 3)
di "Unique districts in dist_panel:"
list GOVID LEAID govs_cty in 1/30
di "Unique GOVS counties:"
tab govs_cty

* Step 3: What LEAIDs in Arizona link to what FIPS counties via tracts?
di _n "--- TRACT_PANEL: Arizona tracts and their LEAIDs ---"
use "tract_panel.dta", clear
gen fips_st = substr(county_code, 1, 2)
keep if fips_st == "04"
keep LEAID county_code tract
duplicates drop
di "Sample of Arizona tracts with LEAIDs:"
list in 1/30
di "Unique FIPS counties:"
tab county_code

* Step 4: Check if Arizona LEAIDs in dist_panel appear in tract_panel
di _n "--- CHECKING LEAID OVERLAP ---"
use "dist_panel.dta", clear
gen govs_st = substr(GOVID, 1, 2)
keep if govs_st == "03"
keep LEAID
duplicates drop
gen in_dist = 1
tempfile az_dist_leaids
save `az_dist_leaids', replace

use "tract_panel.dta", clear
gen fips_st = substr(county_code, 1, 2)
keep if fips_st == "04"
keep LEAID
duplicates drop
gen in_tract = 1
tempfile az_tract_leaids
save `az_tract_leaids', replace

use `az_dist_leaids', clear
merge 1:1 LEAID using `az_tract_leaids'
di "LEAIDs in dist_panel (AZ GOVS) vs tract_panel (AZ FIPS):"
tab _merge
list if _merge != 3

*==============================================================================
* CONNECTICUT
*==============================================================================
di _n _n "========================================================================"
di "CONNECTICUT DETAILED ANALYSIS"
di "========================================================================"

* Check balanced panel failure - need to see lexp_ma_strict coverage
di _n "--- WHY CT FAILS BALANCED PANEL ---"
use "analysis_panel_unrestricted.dta", clear
cap gen fips_st = substr(county_id, 1, 2)
keep if fips_st == "09"

* Check reform year
di "Connecticut reform year:"
tab reform_year if year_unified == 1971

* Check relative_year coverage
di "Relative year distribution for CT:"
tab relative_year

* Check lexp_ma_strict missingness by relative_year
di "lexp_ma_strict missingness by relative_year:"
gen miss_strict = missing(lexp_ma_strict)
tab relative_year miss_strict if inrange(relative_year, -5, 17)

* For each county, count non-missing lexp_ma_strict in event window
preserve
keep if inrange(relative_year, -5, 17)
bys county_id: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys county_id: replace n_nonmiss = n_nonmiss[_N]
keep county_id n_nonmiss
duplicates drop
di "CT counties and their non-missing lexp_ma_strict count (need 23):"
list
restore

*==============================================================================
* OREGON
*==============================================================================
di _n _n "========================================================================"
di "OREGON DETAILED ANALYSIS"
di "========================================================================"

di _n "--- WHY OR FAILS BALANCED PANEL ---"
use "analysis_panel_unrestricted.dta", clear
cap gen fips_st = substr(county_id, 1, 2)
keep if fips_st == "41"

di "Oregon reform year:"
tab reform_year if year_unified == 1971

di "Relative year distribution for OR:"
tab relative_year

gen miss_strict = missing(lexp_ma_strict)
di "lexp_ma_strict missingness by relative_year:"
tab relative_year miss_strict if inrange(relative_year, -5, 17)

preserve
keep if inrange(relative_year, -5, 17)
bys county_id: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys county_id: replace n_nonmiss = n_nonmiss[_N]
keep county_id n_nonmiss
duplicates drop
di "OR counties and their non-missing lexp_ma_strict count (need 23):"
list in 1/30
restore

*==============================================================================
* SOUTH CAROLINA
*==============================================================================
di _n _n "========================================================================"
di "SOUTH CAROLINA DETAILED ANALYSIS"
di "========================================================================"

di _n "--- WHY SC FAILS BALANCED PANEL ---"
use "analysis_panel_unrestricted.dta", clear
cap gen fips_st = substr(county_id, 1, 2)
keep if fips_st == "45"

di "South Carolina reform year:"
tab reform_year if year_unified == 1971

di "Relative year distribution for SC:"
tab relative_year

gen miss_strict = missing(lexp_ma_strict)
di "lexp_ma_strict missingness by relative_year:"
tab relative_year miss_strict if inrange(relative_year, -5, 17)

preserve
keep if inrange(relative_year, -5, 17)
bys county_id: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys county_id: replace n_nonmiss = n_nonmiss[_N]
keep county_id n_nonmiss
duplicates drop
di "SC counties and their non-missing lexp_ma_strict count (need 23):"
list in 1/30
restore

*==============================================================================
* MONTANA - Big drop at INDFIN → dist_panel
*==============================================================================
di _n _n "========================================================================"
di "MONTANA DETAILED ANALYSIS"
di "========================================================================"

di _n "--- WHY 42 MONTANA COUNTIES DROP AT INDFIN → DIST_PANEL ---"

* Get Montana GOVIDs from INDFIN
use "indfin_panel.dta", clear
gen govs_st = substr(GOVID, 1, 2)
keep if govs_st == "27"
keep GOVID
duplicates drop
gen in_indfin = 1
tempfile mt_indfin
save `mt_indfin', replace
di "Montana GOVIDs in INDFIN: " _N

* Get Montana GOVIDs from dist_panel
use "dist_panel.dta", clear
gen govs_st = substr(GOVID, 1, 2)
keep if govs_st == "27"
keep GOVID
duplicates drop
gen in_dist = 1
tempfile mt_dist
save `mt_dist', replace
di "Montana GOVIDs in dist_panel: " _N

* Merge to see which are missing
use `mt_indfin', clear
merge 1:1 GOVID using `mt_dist'
di "Montana GOVIDs: INDFIN vs dist_panel"
tab _merge
di "GOVIDs in INDFIN but NOT in dist_panel:"
list GOVID if _merge == 1

* Check the crosswalk for Montana
di _n "--- CHECKING CROSSWALK FOR MONTANA ---"
use "canon_crosswalk.dta", clear
* Need to understand the structure first
describe
* Check if there's a state identifier
gen govs_st = substr(GOVID, 1, 2) if length(GOVID) >= 2
tab govs_st if govs_st == "27"

*==============================================================================
* VALID_ST_GD CHECK FOR ALL STATES
*==============================================================================
di _n _n "========================================================================"
di "VALID_ST_GD CHECK - WHY STATES FAIL THE 10-COUNTY THRESHOLD"
di "========================================================================"

use "analysis_panel_bal.dta", clear
gen fips_st = substr(county_id, 1, 2)
keep if inlist(fips_st, "04", "09", "23", "25", "30") | ///
        inlist(fips_st, "33", "36", "41", "45", "47", "50")

* Count good counties per state
preserve
keep county_id fips_st good
duplicates drop
di "All counties in analysis_panel_bal by state and good status:"
tab fips_st good

* Now count just good counties
keep if good == 1
bys fips_st: gen n_good = _N
keep fips_st n_good
duplicates drop
di "Count of GOOD counties per state (need >= 10 for valid_st_gd):"
list
restore

*==============================================================================
* CHECK NEVER_TREATED STATUS
*==============================================================================
di _n _n "========================================================================"
di "NEVER_TREATED STATUS BY STATE"
di "========================================================================"

use "analysis_panel_bal.dta", clear
gen fips_st = substr(county_id, 1, 2)
keep if inlist(fips_st, "04", "09", "23", "25", "30") | ///
        inlist(fips_st, "33", "36", "41", "45", "47", "50")

keep county_id fips_st never_treated reform_year
duplicates drop
di "Treatment status by state:"
tab fips_st never_treated

di "Reform years by state:"
tab fips_st reform_year
