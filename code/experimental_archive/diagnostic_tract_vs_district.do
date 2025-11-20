/*==============================================================================
Project    : School Spending – Diagnostic: Tract vs District Results
File       : diagnostic_tract_vs_district.do
Purpose    : Quantify why tract-level and district-level analyses give different
             results by examining sample composition, measurement, and weights
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-19
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES:
  • Compares district-level sample to tract-assigned district sample
  • Identifies which districts are dropped in tract-based approach
  • Quantifies impact of GRF coverage, multi-district areas, and weighting
  • Produces diagnostic tables and figures

INPUTS:
  - f33_indfin_grf_canon.dta (all districts)
  - grf_tract_canon.dta (tract-district crosswalk)
  - interp_d.dta (county panel)

OUTPUTS:
  - diagnostic_summary.log
  - Sample composition tables
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

log using diagnostic_summary.log, replace text

*** ---------------------------------------------------------------------------
*** 1. District Sample Comparison: ALL vs GRF-Linked
*** ---------------------------------------------------------------------------

di as result "═══════════════════════════════════════════════════════════════"
di as result "DIAGNOSTIC 1: Sample Coverage - Districts in Finance Data vs GRF"
di as result "═══════════════════════════════════════════════════════════════"
di ""

* Load all districts with baseline data
use f33_indfin_grf_canon, clear
gen in_finance = 1
keep LEAID GOVID in_finance
duplicates drop

tempfile all_districts
save `all_districts'

* Load tract-assigned districts
use grf_tract_canon, clear
gen in_grf = 1
keep LEAID in_grf
duplicates drop

* Merge to identify coverage
merge 1:1 LEAID using `all_districts'

* Summary
di as text "Total districts in finance data: " as result _N
di as text "Districts in GRF (tract-linkable): " as result sum(in_grf) if in_grf==1
di as text "Districts NOT in GRF (dropped): " as result sum(_merge==2)
di as text "GRF coverage rate: " as result %5.2f (100*sum(in_grf)/(_N)) "%"
di ""

* Save for later
tempfile coverage
save `coverage'

*** ---------------------------------------------------------------------------
*** 2. Multi-District Assignment: How many districts serve each tract?
*** ---------------------------------------------------------------------------

di as result "═══════════════════════════════════════════════════════════════"
di as result "DIAGNOSTIC 2: Multi-District Areas - How many districts dropped?"
di as result "═══════════════════════════════════════════════════════════════"
di ""

use grf_tract_canon, clear

* Count districts per tract
bys tract70 sdtc: gen n_districts = _N
tab n_districts

* What share of districts are in multi-district tracts?
gen multi_district = (n_districts > 1)
di as text "Tracts served by exactly 1 district: " as result sum(!multi_district)
di as text "Tracts served by 2+ districts: " as result sum(multi_district)
di ""

* After assignment, how many districts get dropped?
* (Assignment rule: keep district with max allocated population)
bys tract70 sdtc (alloc_pop): gen byte keep_in_assignment = (_n == _N)
di as text "Districts BEFORE assignment: " as result _N
di as text "Districts AFTER assignment (one per tract-sdtc): " as result sum(keep_in_assignment)
di as text "Districts DROPPED due to assignment: " as result _N - sum(keep_in_assignment)
di ""

*** ---------------------------------------------------------------------------
*** 3. Sample Characteristics: Dropped vs Kept Districts
*** ---------------------------------------------------------------------------

di as result "═══════════════════════════════════════════════════════════════"
di as result "DIAGNOSTIC 3: Characteristics of Dropped Districts"
di as result "═══════════════════════════════════════════════════════════════"
di ""

* Merge with finance data to get district characteristics
merge m:1 LEAID using f33_indfin_grf_canon
keep if _merge == 3

* Compare dropped vs kept
di as text "--- Population Allocation (proxy for district size) ---"
bys keep_in_assignment: summ alloc_pop, detail

di ""
di as text "--- District Type Distribution ---"
tab sdtc keep_in_assignment, row

*** ---------------------------------------------------------------------------
*** 4. County-Level Aggregation: Enrollment Weighting Impact
*** ---------------------------------------------------------------------------

di as result "═══════════════════════════════════════════════════════════════"
di as result "DIAGNOSTIC 4: County Aggregation - Weighting Impact"
di as result "═══════════════════════════════════════════════════════════════"
di ""

* Load interpolated county panel
use interp_d, clear

* Show county-type distribution
tab county_type

di as text "Counties by type:"
di as text "  Type 1 (fully tracted): Most reliable"
di as text "  Type 2 (fully untracted): OK"
di as text "  Type 3 (≥2 untracted areas): PROBLEMATIC - may be excluded"
di as text "  Type 4 (mixed): Moderate quality"
di ""

*** ---------------------------------------------------------------------------
*** 5. Treatment Group Comparison
*** ---------------------------------------------------------------------------

di as result "═══════════════════════════════════════════════════════════════"
di as result "DIAGNOSTIC 5: Treatment vs Control in Both Samples"
di as result "═══════════════════════════════════════════════════════════════"
di ""

* District-level sample
use district_panel_tagged, clear
keep if year4 == 1990  // Pick a year for snapshot
gen in_district_sample = 1
keep LEAID in_district_sample
duplicates drop

tempfile dist_sample
save `dist_sample'

* Tract-assigned sample
use interp_t, clear
keep if year4 == 1990
keep LEAID
duplicates drop
gen in_tract_sample = 1

* Merge
merge 1:1 LEAID using `dist_sample'

di as text "Districts in district-level sample (1990): " as result sum(in_district_sample)
di as text "Districts in tract-assigned sample (1990): " as result sum(in_tract_sample)
di as text "Districts in BOTH samples: " as result sum(in_district_sample==1 & in_tract_sample==1)
di as text "Districts ONLY in district sample (lost in tract approach): " ///
    as result sum(in_district_sample==1 & in_tract_sample!=1)
di ""

*** ---------------------------------------------------------------------------
*** SUMMARY
*** ---------------------------------------------------------------------------

di as result "═══════════════════════════════════════════════════════════════"
di as result "SUMMARY: Why Results Differ Between Tract and District Levels"
di as result "═══════════════════════════════════════════════════════════════"
di ""
di as text "1. GRF Coverage: Districts not in 1969 GRF are excluded from tract analysis"
di as text "2. Multi-District Assignment: Smaller/overlapping districts dropped"
di as text "3. Spending Assignment: Tract spending is IMPUTED, not measured"
di as text "4. County Filtering: Some county types flagged as problematic"
di as text "5. Weighting: County analysis uses enrollment weights, district doesn't"
di ""
di as text "Recommendation: Run BOTH approaches to assess robustness"
di ""

log close
