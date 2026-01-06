/*==============================================================================
Project    : School Spending - State Treatment Summary
File       : 08_state_treatment_summary.do
Purpose    : Create spreadsheet summarizing treatment status, reform info, and
             balanced panel status for all states in the data.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2026-01-06
-------------------------------------------------------------------------------

INPUTS:
  - jjp_interp_final.dta    (Full county panel before balance restriction)
  - state_fips_master.csv   (State names crosswalk)

OUTPUTS:
  - state_treatment_summary.csv

==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Load Full Panel (Pre-Balance Restriction)
*** ---------------------------------------------------------------------------

use jjp_interp_final, clear

*** ---------------------------------------------------------------------------
*** Section 2: Identify Balanced Counties
*** ---------------------------------------------------------------------------

* A county is "balanced" if it has complete data in event window -5 to +17
preserve
keep if inrange(relative_year, -5, 17)

bys county_id: egen min_rel = min(relative_year)
bys county_id: egen max_rel = max(relative_year)
bys county_id: gen n_rel = _N

bys county_id: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys county_id: replace n_nonmiss = n_nonmiss[_N]

* Balanced = complete window with no missing outcome
gen balanced = (min_rel == -5 & max_rel == 17 & n_rel == 23 & n_nonmiss == 23)

keep county_id state_fips balanced
duplicates drop
tempfile balanced_flags
save `balanced_flags', replace
restore

*** ---------------------------------------------------------------------------
*** Section 3: Merge Balanced Flags Back
*** ---------------------------------------------------------------------------

merge m:1 county_id state_fips using `balanced_flags', nogen
replace balanced = 0 if missing(balanced)

*** ---------------------------------------------------------------------------
*** Section 4: Identify Missing Data Years by State
*** ---------------------------------------------------------------------------

* Find years with missing lexp_ma_strict for each state
preserve
keep state_fips year lexp_ma_strict
gen missing_exp = missing(lexp_ma_strict)

* Collapse to state-year level
collapse (max) missing_exp, by(state_fips year)

* Keep only years with missing data
keep if missing_exp == 1

* Create comma-separated list of missing years per state
sort state_fips year
by state_fips: gen year_str = string(year)
by state_fips: gen missing_years = year_str if _n == 1
by state_fips: replace missing_years = missing_years[_n-1] + ", " + year_str if _n > 1
by state_fips: keep if _n == _N

keep state_fips missing_years
tempfile missing_years
save `missing_years', replace
restore

*** ---------------------------------------------------------------------------
*** Section 5: Collapse to State Level
*** ---------------------------------------------------------------------------

* Get one row per state with treatment info
preserve
keep state_fips treatment reform_year reform_eq reform_mfp reform_ep reform_le reform_sl
duplicates drop

* There should be one unique row per state
bysort state_fips: assert _N == 1

tempfile state_treatment
save `state_treatment', replace
restore

* Count balanced counties per state
preserve
keep state_fips county_id balanced
duplicates drop
gen one = 1  // numeric variable for counting
collapse (sum) n_balanced = balanced (sum) n_counties = one, by(state_fips)
tempfile state_counts
save `state_counts', replace
restore

*** ---------------------------------------------------------------------------
*** Section 6: Build State Summary
*** ---------------------------------------------------------------------------

use `state_treatment', clear

* Merge county counts
merge 1:1 state_fips using `state_counts', nogen

* Merge missing years
merge 1:1 state_fips using `missing_years', nogen

* Create treatment status string
gen treatment_status = "Treated" if treatment == 1
replace treatment_status = "Control" if treatment == 0

* Create reform type string
gen reform_type = ""
replace reform_type = "Equity" if reform_eq == 1 & treatment == 1
replace reform_type = "Adequacy" if reform_eq == 0 & treatment == 1

* Create in_balanced_panel indicator
* State is in balanced panel if it has >=10 balanced counties OR is never-treated
gen in_balanced_panel = "Yes" if n_balanced >= 10
replace in_balanced_panel = "Yes" if treatment == 0  // Control states kept
replace in_balanced_panel = "No" if missing(in_balanced_panel)

* Create notes for why not in balanced panel
gen notes = ""

* Too few counties
replace notes = "Fewer than 10 balanced counties (" + string(n_balanced) + " balanced)" ///
    if in_balanced_panel == "No" & n_balanced < 10 & treatment == 1

* Reform too early (pre-reform window insufficient)
replace notes = notes + "; " if notes != "" & reform_year <= 1972 & treatment == 1
replace notes = notes + "Reform year " + string(reform_year) + " too early (insufficient pre-period)" ///
    if reform_year <= 1972 & treatment == 1 & !regexm(notes, "too early")

* Reform too late (post-reform window extends past data)
* Data ends ~2019, need +17 years, so reform must be <= 2002
replace notes = notes + "; " if notes != "" & reform_year >= 2000 & treatment == 1
replace notes = notes + "Reform year " + string(reform_year) + " too late (post-period extends past data)" ///
    if reform_year >= 2000 & treatment == 1 & !regexm(notes, "too late")

* Clean up notes
replace notes = subinstr(notes, "; ; ", "; ", .)
replace notes = "" if regexm(notes, "^; ")
replace notes = substr(notes, 3, .) if substr(notes, 1, 2) == "; "

*** ---------------------------------------------------------------------------
*** Section 7: Merge State Names
*** ---------------------------------------------------------------------------

* Import state names
preserve
import delimited "$SchoolSpending/data/state_fips_master.csv", clear
tostring fips, gen(state_fips) format(%02.0f)
keep state_fips state_name
duplicates drop
tempfile state_names
save `state_names', replace
restore

merge 1:1 state_fips using `state_names', keep(match master) nogen

* Clean state name
replace state_name = proper(state_name)

*** ---------------------------------------------------------------------------
*** Section 8: Format and Export
*** ---------------------------------------------------------------------------

* Select and order variables
keep state_name state_fips treatment_status reform_year reform_type ///
     in_balanced_panel missing_years notes n_balanced n_counties

order state_name state_fips treatment_status reform_year reform_type ///
      in_balanced_panel missing_years notes

* Sort by state name
sort state_name

* Rename for CSV clarity
rename state_name State
rename state_fips FIPS
rename treatment_status Treatment_Status
rename reform_year Reform_Year
rename reform_type Reform_Type
rename in_balanced_panel In_Balanced_Panel
rename missing_years Missing_Data_Years
rename notes Notes

* Export to CSV
export delimited using "$SchoolSpending/state_treatment_summary.csv", replace

* Display summary
di _n "=== STATE TREATMENT SUMMARY ===" _n
list State FIPS Treatment_Status Reform_Year Reform_Type In_Balanced_Panel, sep(0)

di _n "=== SUMMARY STATISTICS ===" _n
tab Treatment_Status
tab In_Balanced_Panel
tab Treatment_Status In_Balanced_Panel

di _n "Saved to: $SchoolSpending/state_treatment_summary.csv"
