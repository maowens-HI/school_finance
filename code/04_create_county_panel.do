/*==============================================================================
Project    : School Spending – District Interpolation and County Aggregation
File       : 04_create_county_panel.do
Purpose    : V2 VERSION - Interpolate district spending, expand to tracts,
             adjust for inflation, import enrollment, collapse to counties,
             and merge reform treatment data.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-01-21
───────────────────────────────────────────────────────────────────────────────

V2 EFFICIENCY IMPROVEMENTS OVER ORIGINAL (05_create_county_panel.do):
  1. Reuses tract crosswalk from 02_build_tract_panel_v2.do (no re-assignment)
  2. Inflation adjustment done ONCE efficiently (was scattered/repeated)
  3. Tempfiles replace unnecessary intermediate saves
  4. Loops replace copy-pasted label and cleanup blocks
  5. Type 3/4 county logic combined (was near-identical separate blocks)
  6. Streamlined preserve/restore chains
  7. Cleaner median income merge

WHAT THIS FILE DOES (Summary):
  • Step 1: Interpolate district-level spending for gaps ≤ 3 years
  • Step 2: Expand to tract level using crosswalk from step 02
  • Step 3: Adjust for inflation (CPI-U by state fiscal year)
  • Step 4: Import school enrollment data (weighting variable)
  • Step 5: Collapse tracts to counties (enrollment-weighted averages)
  • Step 6: Merge reform treatment data (Jackson et al 2016)
  • Step 7: Merge median family income

INPUTS:
  - dist_panel.dta     (from 01_build_district_panel_v2.do)
  - xwalk_tract_dist.dta          (from 02_build_tract_panel_v2.do)
  - grf_id_tractlevel.dta        (tract metadata with no_tract flag)
  - fiscal_year.csv              (state fiscal year definitions)
  - FRED CPI-U                   (downloaded via API)
  - enroll_age_tract.csv         (NHGIS tract enrollment)
  - enroll_age_county.csv        (NHGIS county enrollment)
  - tabula-tabled2.xlsx          (JJP reform years)
  - state_fips_master.csv        (state FIPS crosswalk)
  - county2.csv                  (median family income)

OUTPUTS:
  - dist_panel_interp.dta                 # Interpolated district panel (intermediate)
  - county_panel.dta         ★ PRIMARY ANALYSIS FILE ★
      └─> County-year panel with:
          • county, state_fips, year4
          • county_exp (enrollment-weighted pp_exp in 2000 dollars)
          • school_age_pop (weighting variable)
          • reform_year, reform type flags
          • median_family_income

DEPENDENCIES:
  • Requires: global SchoolSpending path set
  • Requires: Steps 01-03 of v2 pipeline completed
  • Requires: FRED API key (set fredkey)
  • Stata packages: fred, ipolate (built-in)
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*==============================================================*
* I) Interpolate district panel (gaps ≤ 3 years)
*==============================================================*

use "dist_panel.dta", clear

* Convert LEAID to numeric for time-series operations
encode LEAID, gen(LEAID_num)

* Detect gaps in time series
bysort LEAID (year4): gen gap_next = year4[_n+1] - year4
gen byte too_far = (gap_next > 3 & !missing(gap_next))

* Create full panel structure
tsset LEAID_num year4
tsfill, full

* Fill stable identifiers for gap-filled rows
foreach var in GOVID LEAID good_govid_baseline {
    bys LEAID_num: egen __fill = mode(`var'), maxmode
    replace `var' = __fill if missing(`var')
    drop __fill
}

* Propagate too_far flag across gaps (run 3x for max gap size)
forvalues i = 1/3 {
    bys LEAID_num (year4): replace too_far = too_far[_n-1] if missing(too_far)
}

* Interpolate spending and enrollment (linear, gaps ≤ 3 years only)
bys LEAID_num: ipolate pp_exp year4 if too_far == 0, gen(pp_exp_interp)
bys LEAID_num: ipolate enrollment year4 if too_far == 0, gen(enroll_interp)

* Replace with interpolated values (keep originals where available)
replace pp_exp_interp = pp_exp if !missing(pp_exp)
replace enroll_interp = enrollment if !missing(enrollment)

* Clean up
drop pp_exp gap_next too_far enrollment
rename pp_exp_interp pp_exp
rename enroll_interp enrollment

* Save interpolated district panel
keep LEAID GOVID year4 pp_exp LEAID_num enrollment
save "dist_panel_interp.dta", replace


*==============================================================*
* II) Expand to tract level using existing crosswalk
*==============================================================*

* Load tract crosswalk (already built in step 02 - no need to redo assignment)
use "xwalk_tract_dist.dta", clear

* Drop vocational districts
drop if sdtc == 4

* Pick highest-population LEAID per tract-sdtc (same logic as step 02)
gen byte has_alloc = !missing(alloc_pop)
gsort tract70 sdtc -has_alloc -alloc_pop LEAID
by tract70 sdtc: keep if _n == 1
drop if missing(tract70) | missing(sdtc)
isid tract70 sdtc
drop has_alloc

tempfile xwalk
save `xwalk', replace

* Load interpolated districts and expand to tract-year
use "dist_panel_interp.dta", clear
joinby LEAID using `xwalk', unmatched(none)

tempfile tract_expanded
save `tract_expanded', replace

* Prepare tract metadata (no_tract flag, county) - must collapse to tract level first
use "grf_id_tractlevel.dta", clear
keep no_tract tract70 county_code
duplicates drop  // Make it unique on tract70
rename county_code county_fips

tempfile tract_meta
save `tract_meta', replace

* Merge tract metadata
use `tract_expanded', clear
merge m:1 tract70 using `tract_meta', keep(match master) nogen

tempfile tract_panel
save `tract_panel', replace


*==============================================================*
* III) Adjust for inflation (CPI-U by state fiscal year)
*==============================================================*

* Set FRED key (suppress repeated prompts)
set fredkey 87d3478358d0f3e781d2657d1aefd1ff, permanently

* Download monthly CPI-U
import fred CPIAUCNS, daterange(1964-01-01 2022-12-31) clear
gen m = mofd(daten)
format m %tm
rename CPIAUCNS cpi_u
keep m cpi_u

tempfile cpi_monthly
save `cpi_monthly', replace

* Load state fiscal year definitions
import delimited "$SchoolSpending/data/fiscal_year.csv", varnames(1) clear
tostring state_fips, replace format("%02.0f")
keep state_fips fy_start_month
duplicates drop

tempfile fy_tbl
save `fy_tbl', replace

* Cross CPI months with states, assign fiscal year
use `cpi_monthly', clear
cross using `fy_tbl'

gen cal_y = year(dofm(m))
gen cal_m = month(dofm(m))
gen year4 = cal_y + (cal_m >= fy_start_month)

keep if inrange(year4, 1967, 2022)

* Collapse to fiscal-year average CPI
collapse (mean) cpi_fy = cpi_u (count) nmonths = cpi_u, by(state_fips year4)
assert nmonths == 12
drop nmonths

* Build 2000-dollar deflators
bys state_fips: egen base2000 = max(cond(year4 == 2000, cpi_fy, .))
gen inflator_2000 = base2000 / cpi_fy
drop base2000

tempfile deflators
save `deflators', replace

* Merge deflators to tract panel
use `tract_panel', clear

* Ensure state_fips is str2
capture confirm string variable state_fips
if _rc {
    tostring state_fips, gen(state_fips_str) format("%02.0f")
    drop state_fips
    rename state_fips_str state_fips
}

merge m:1 state_fips year4 using `deflators', keep(match master) nogen

* Deflate to 2000 dollars
gen pp_exp_real = pp_exp * inflator_2000
label var pp_exp_real "Per-pupil expenditure in 2000 dollars"
drop inflator_2000 cpi_fy

* Classify counties by tracted/untracted status
bys county_fips year4 tract70: egen byte any_untr = max(no_tract == 1)
bys county_fips year4 tract70: gen byte tag_tr = (_n == 1)
gen byte nt_tag = tag_tr & any_untr
bys county_fips year4: egen n_nontr_uniq = total(nt_tag)
drop any_untr tag_tr nt_tag

bys county_fips year4 tract70: egen byte any_tr = max(no_tract == 0)
bys county_fips year4 tract70: gen byte tag_tr2 = (_n == 1)
gen byte tr_tag = tag_tr2 & any_tr
bys county_fips year4: egen n_tr_uniq = total(tr_tag)
drop any_tr tag_tr2 tr_tag

* 4-type county classification
gen byte county_type = .
replace county_type = 1 if n_nontr_uniq == 0 & n_tr_uniq > 0   // fully tracted
replace county_type = 2 if n_nontr_uniq == 1 & n_tr_uniq == 0  // fully untracted
replace county_type = 4 if n_nontr_uniq == 1 & n_tr_uniq > 0   // mixed
replace county_type = 3 if n_nontr_uniq >= 2                    // multi-untracted

label define ctype 1 "All tracted" 2 "Single untracted" 3 "Multi-untracted" 4 "Mixed", replace
label values county_type ctype

tempfile tract_real
save `tract_real', replace


*==============================================================*
* IV) Import school-age population (enrollment weights)
*==============================================================*

*--------------------------------------------------------------
* A) Tract-level enrollment from NHGIS
*--------------------------------------------------------------

import delimited "$SchoolSpending/data/enroll_age_tract.csv", clear

* School-age population (ages 5-17, enrolled + not enrolled)
gen school_age_pop = c04003 + c04004 + c04005 + c04006 + ///
                     c04007 + c04008 + c04009 + c04010
label var school_age_pop "School-age population (5-17 years)"

* Build tract70 identifier
gen str2 state_str = string(statea, "%02.0f")
gen str3 county_str = string(countya, "%03.0f")

gen digits = floor(log10(tracta)) + 1 if tracta > 0
replace digits = 1 if tracta == 0 | missing(tracta)

gen str6 tract_str = ""
replace tract_str = string(tracta * 100, "%06.0f") if digits <= 4
replace tract_str = string(tracta, "%06.0f") if inlist(digits, 5, 6)

gen str11 tract70 = state_str + county_str + tract_str
label var tract70 "11-digit Census Tract FIPS"

collapse (mean) school_age_pop, by(tract70)

tempfile tract_enroll
save `tract_enroll', replace

*--------------------------------------------------------------
* B) County-level enrollment from NHGIS
*--------------------------------------------------------------

import delimited "$SchoolSpending/data/enroll_age_county.csv", clear

gen school_age_pop = c04003 + c04004 + c04005 + c04006 + ///
                     c04007 + c04008 + c04009 + c04010

gen str5 county_code = string(statea, "%02.0f") + string(countya, "%03.0f")

* Save county names for later
preserve
    keep county_code county
    rename county county_name
    rename county_code county_fips
    duplicates drop county_fips, force
    tempfile cnames
    save `cnames', replace
restore

keep county_code school_age_pop
rename county_code county_fips
rename school_age_pop county_school_age_pop

tempfile county_enroll
save `county_enroll', replace

*--------------------------------------------------------------
* C) Merge enrollment into tract panel
*--------------------------------------------------------------

use `tract_real', clear

* Merge tract-level enrollment
merge m:1 tract70 using `tract_enroll', keep(match master) nogen

* Split into tracted vs untracted
preserve
    keep if no_tract == 0
    tempfile tracted
    save `tracted', replace
restore

keep if no_tract == 1

* For untracted areas, merge county-level enrollment
merge m:1 county_fips using `county_enroll', keep(match master) nogen
replace school_age_pop = county_school_age_pop if missing(school_age_pop)
drop county_school_age_pop

* Recombine
append using `tracted'

tempfile with_enroll
save `with_enroll', replace


*==============================================================*
* V) Handle untracted populations and collapse to counties
*==============================================================*

use `with_enroll', clear

*--------------------------------------------------------------
* A) Handle Type 3 & 4 counties (untracted areas)
*--------------------------------------------------------------

* Type 4: 1 untracted + some tracted
* Type 3: ≥2 untracted areas
* Logic: Assign residual population (county total - tracted sum) to untracted

preserve
    keep if inlist(county_type, 3, 4)

    * County total from untracted row
    gen county_pop = school_age_pop if no_tract == 1
    bys county_fips year4: egen county_total = max(county_pop)

    * Sum of tracted areas
    bys county_fips year4: egen tract_sum = total(cond(no_tract == 0, school_age_pop, .))

    * Residual goes to untracted (floor at 0 to prevent negative weights)
    gen residual_pop = max(0, county_total - tract_sum)
    replace school_age_pop = residual_pop if no_tract == 1

    * For Type 3 (multiple untracted): average spending, keep one row
    if _N > 0 {
        bys county_fips year4: egen untr_pp_avg = mean(cond(no_tract == 1, pp_exp_real, .))
        bys county_fips year4 (tract70): gen keep_flag = (no_tract == 1 & _n == 1)
        replace keep_flag = 1 if no_tract == 0
        keep if keep_flag == 1 | county_type == 4
        replace pp_exp_real = untr_pp_avg if no_tract == 1 & county_type == 3
    }

    tempfile type34
    save `type34', replace
restore

* Drop Type 3 & 4 from main, append fixed versions
drop if inlist(county_type, 3, 4)
append using `type34'

*--------------------------------------------------------------
* B) Collapse tracts to county level
*--------------------------------------------------------------

* Drop observations with invalid weights or missing spending
drop if missing(school_age_pop) | school_age_pop <= 0
drop if missing(pp_exp_real)

* First get total school_age_pop by county-year
preserve
    collapse (sum) school_age_pop, by(county_fips year4)
    tempfile totpop
    save `totpop', replace
restore

* Weighted mean of spending by county-year
collapse (mean) pp_exp_real [w = school_age_pop], by(county_fips year4)

* Merge back total population
merge 1:1 county_fips year4 using `totpop', nogen

rename pp_exp_real county_exp
gen state_fips = substr(county_fips, 1, 2)

tempfile county_panel
save `county_panel', replace


*==============================================================*
* VI) Merge reform treatment data (Jackson et al 2016)
*==============================================================*

import excel using "$SchoolSpending/data/tabula-tabled2.xlsx", firstrow clear

rename CaseNameLegislationwithout case_name
rename Constitutionalityoffinancesys const
rename TypeofReform reform_type
rename FundingFormulaafterReform form_post
rename FundingFormulabeforeReform form_pre
rename Year reform_year
rename State state_name

* Fill down state names
local N = _N
forvalues i = 2/`N' {
    if missing(state_name[`i']) {
        replace state_name = state_name[`i'-1] in `i'
    }
}

* Clean state names
replace state_name = itrim(lower(strtrim(state_name)))
replace state_name = subinstr(state_name, char(10), " ", .)
replace state_name = subinstr(state_name, char(13), " ", .)
replace state_name = itrim(strtrim(state_name))
replace state_name = "massachusetts" if state_name == "massachuset ts"

* Keep first overturned reform per state
drop if missing(case_name)
keep if const == "Overturned"
sort state_name reform_year
bysort state_name: keep if _n == 1

* Reform type indicator (Equity vs Adequacy)
gen reform_eq = regexm(reform_type, "Equity")
label define reform_lbl 0 "Adequacy" 1 "Equity"
label values reform_eq reform_lbl
label variable reform_eq "School finance reform type"

* Parse funding formula changes (pre/post reform)
gen mfp_pre = "MFP" if regexm(form_pre, "MFP")
gen ep_pre  = "EP"  if regexm(form_pre, "EP")
gen le_pre  = "LE"  if regexm(form_pre, "LE")
gen sl_pre  = "SL"  if regexm(form_pre, "SL")

gen mfp_post = "MFP" if regexm(form_post, "MFP")
gen ep_post  = "EP"  if regexm(form_post, "EP")
gen le_post  = "LE"  if regexm(form_post, "LE")
gen sl_post  = "SL"  if regexm(form_post, "SL")

* Generate flags for NEW formula types introduced by reform
gen mfp_flag = (mfp_post != "" & mfp_pre == "")
gen ep_flag  = (ep_post  != "" & ep_pre  == "")
gen le_flag  = (le_post  != "" & le_pre  == "")
gen sl_flag  = (sl_post  != "" & sl_pre  == "")

* Encode into single numeric variable
gen formula_new = .
replace formula_new = 1 if mfp_flag
replace formula_new = 2 if ep_flag
replace formula_new = 3 if le_flag
replace formula_new = 4 if sl_flag
label define formula_lbl 1 "MFP" 2 "EP" 3 "LE" 4 "SL"
label values formula_new formula_lbl

* Create individual reform type indicators
gen reform_mfp = (mfp_flag == 1)
gen reform_ep  = (ep_flag == 1)
gen reform_le  = (le_flag == 1)
gen reform_sl  = (sl_flag == 1)

label variable reform_mfp "MFP Reform"
label variable reform_ep "EP Reform"
label variable reform_le "LE Reform"
label variable reform_sl "SL Reform"

gen treatment = 1
keep state_name reform_year reform_eq reform_mfp reform_ep reform_le reform_sl treatment

tempfile reforms
save `reforms', replace

* Merge with state FIPS
import delimited using "$SchoolSpending/data/state_fips_master.csv", clear
replace state_name = itrim(lower(strtrim(state_name)))
merge 1:m state_name using `reforms', nogen
tostring fips, gen(state_fips) format(%02.0f)
keep state_fips reform_year reform_eq reform_mfp reform_ep reform_le reform_sl treatment

* Merge into county panel
merge 1:m state_fips using `county_panel', keep(match using) nogen
replace treatment = 0 if missing(treatment)

tempfile with_reform
save `with_reform', replace


*==============================================================*
* VII) Merge median family income
*==============================================================*

import delimited using "$SchoolSpending/data/county2.csv", varnames(1) clear

rename v2 median_family_income
drop if missing(county)

* Clean county name and extract state abbrev
gen county_name = regexr(county, "(County|Census|Parish|Borough|city|City).*", "")
gen state_abbr = ""
replace state_abbr = regexs(1) if regexm(county, " ([A-Za-z]+)$")

tempfile income_raw
save `income_raw', replace

* Merge with state FIPS
import delimited using "$SchoolSpending/data/state_fips_master.csv", clear
merge 1:m state_abbr using `income_raw', keep(match) nogen

gen state_fips = string(fips, "%02.0f")

* Clean up duplicates and special cases
drop if regexm(county, "(?i)\bcensus\b")
drop if regexm(county, "(?i)\bcity\b") & !inlist(county, "Carson City, NV", "St. Louis city, MO")
replace county_name = "carson city" if county == "Carson City, NV"
replace county_name = "st. louis city" if county == "St. Louis city, MO"

* Standardize county name
replace county_name = substr(county_name, 1, 25)
replace county_name = lower(trim(county_name))

* County name fixes
replace county_name = subinstr(county_name, "debaca", "de baca", .)
replace county_name = subinstr(county_name, "de kalb", "dekalb", .)
replace county_name = subinstr(county_name, "laplata", "la plata", .)
replace county_name = subinstr(county_name, "la porte", "laporte", .)
replace county_name = subinstr(county_name, "mc kean", "mckean", .)
replace county_name = subinstr(county_name, "o'brien", "o brien", .)
replace county_name = subinstr(county_name, ".", "", .)

keep county_name state_fips median_family_income
duplicates drop county_name state_fips, force

tempfile income
save `income', replace

* Merge county names into panel
use `with_reform', clear
merge m:1 county_fips using `cnames', keep(match master) nogen
replace county_name = lower(county_name)
gen county_name_clean = regexr(county_name, "(County|Census|Parish|Borough|city|City).*", "")
replace county_name_clean = trim(county_name_clean)
drop county_name
rename county_name_clean county_name

* Merge income
merge m:1 county_name state_fips using `income', keep(match master) nogen


*==============================================================*
* VIII) Final cleanup and save
*==============================================================*

order county_fips state_fips year4 county_exp school_age_pop ///
      reform_year reform_eq reform_mfp reform_ep reform_le reform_sl ///
      treatment median_family_income



di as result "✓ County panel complete: county_panel.dta"
di as result "  Observations: " _N
preserve
    bysort county_fips: keep if _n == 1
    di as result "  Unique counties: " _N
restore
preserve
    bysort state_fips: keep if _n == 1
    di as result "  States: " _N
restore

	  rename county_fips county
save "county_panel.dta", replace