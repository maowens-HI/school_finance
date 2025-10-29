/*-------------------------------------------------------------------------------
File     : 04_cnty
Purpose  : Collapse tracts into a county level spending panel
Inputs   : school enrollment data: school_level_1970.csv
		   county enrollment data: county_level.csv
		   tract spending data: tracts_panel_real
Outputs  : county spending data: county_pp_exp_panel_real
Author   : Myles Owens
Created  : 27 August 2025
Notes    : - merges enrollment data into tract spending panel
		   - collapses tract spending into county level weighted by enrollment
-------------------------------------------------------------------------------*/

*** Housekeeping
clear 
set more off 

*** Set working directory
cd "$SchoolSpending\data"

*** Load tract-level NHGIS school enrollment data
import delimited "$SchoolSpending\data\school_level_1970.csv", clear

*** Create truncated GISJOIN for merging with tract panel
gen gisjoin2 = substr(gisjoin, 2, 14)

*** Merge NHGIS data to tract panel
merge 1:m gisjoin2 using "$SchoolSpending\data\tracts_panel_real"

*** Drop NHGIS-only records and clean merge variable
drop if _merge == 1
drop _merge

*** Generate county code from state FIPS and county code
gen str5 county_code = state_fips + coc70

*** Save intermediate dataset
tempfile grf_tract_enrollment_v1
save `grf_tract_enrollment_v1'

*** Load county-level enrollment file
import delimited ///
    "$SchoolSpending\data\county_level.csv", ///
    clear

*** Construct county code using state and county numeric codes
gen str5 county_code = string(statea, "%02.0f") + string(countya, "%03.0f")

*** Merge county-level enrollment with tract-level dataset
merge 1:m county_code using `grf_tract_enrollment_v1' , update replace 
*** Drop records not found in tract file
drop if _merge ==1
drop _merge

*** Save updated dataset
tempfile grf_tract_enrollment_v2
save `grf_tract_enrollment_v2' , replace

*** Rename NHGIS enrollment variables for clarity
rename c05001 nursery_school
rename c05002 kindergarten
rename c05003 elementary
rename c05004 high_school
rename c05005 college

*** Keep only relevant variables
keep LEAID GOVID year4 pp_exp_real good_tract sdtc state_fips gisjoin2 coc70 tract70 county kindergarten elementary high_school

*** Generate enrollment measures
gen enrollment = kindergarten + elementary + high_school
gen primary_age    = kindergarten + elementary
gen secondary_age  = high_school
gen age_total      = primary_age + secondary_age
gen share_primary   = primary_age   / age_total if age_total > 0
gen share_secondary = secondary_age / age_total if age_total > 0

*** Rename and construct county identifiers
rename county county_name
gen str5 county = state_fips + coc70

*** Pivot from long to wide


*** Drop exact duplicates of tract-year-district observations
duplicates drop gisjoin2 year4 sdtc LEAID tract70, force

*** If multiple LEAIDs remain for same tract-year-type, keep first
by tract70 year4 sdtc (LEAID), sort: keep if _n == 1

*** Reshape dataset wide by district type
keep LEAID gisjoin2 year4 sdtc pp_exp_real enrollment ///
share_primary share_secondary county_name county good_tract
reshape wide LEAID pp_exp_real enrollment share_primary share_secondary county_name county, i(gisjoin2 year4) j(sdtc)

/*────────────────────────────────────────────────────────────────────────────
   ── Assign tract-level per-pupil expenditure (PPE) ─────────────────────────
   Combine primary (sdtc==2) and secondary (sdtc==3) PPE weighted by shares.
   ------------------------------------------------------------------------*/

*** Drop redundant share variables from reshape
drop share_primary3 share_secondary2

*** Initialize tract PPE variable
gen ppe_tract = .

*** Calculate weighted PPE for split-district cases
replace ppe_tract = pp_exp_real2*share_primary2 + ///
                    pp_exp_real3*share_secondary3 ///
                    if !missing(pp_exp_real2) & !missing(pp_exp_real3)

*** Sanity check distribution of tract PPE
summarize ppe_tract, detail

*** Fill missing tract PPE with available single-district values
replace ppe_tract = pp_exp_real1 if missing(ppe_tract) & !missing(pp_exp_real1)
replace ppe_tract = pp_exp_real2 if missing(ppe_tract) & !missing(pp_exp_real2)
replace ppe_tract = pp_exp_real3 if missing(ppe_tract) & !missing(pp_exp_real3)

*** Final rename for tract PPE
rename ppe_tract pp_exp_real

*** Reset working directory
cd "$SchoolSpending\data"

*** Clean enrollment variables
rename enrollment1 enrollment
replace enrollment = enrollment2 if missing(enrollment) 
drop enrollment2
replace enrollment = enrollment3 if missing(enrollment)
drop enrollment3

*** Clean county_name variables from reshape
rename county_name1 county_name
replace county_name = county_name2 if missing(county_name)
drop county_name2
replace county_name = county_name3 if missing(county_name)
drop county_name3

*** Clean county identifiers from reshape
rename county1 county
replace county = county2 if missing(county)
drop county2
replace county = county3 if missing(county)
drop county3

*** Clean LEAID variables
rename LEAID1 LEAID
replace LEAID = LEAID2 + LEAID3 if missing(LEAID)

*** Create county-level lookup for merging back later
preserve
keep county_name county
duplicates drop county county_name, force
save county_lookup,replace
restore

*****************************************************************************
*Collapse into counties
*****************************************************************************

*** Collapse tract data to county-year averages, weighted by enrollment
* preferred: one-liner with analytic weights
* Proper syntax: apply weights inside the mean group only
collapse (sum) enrollment (mean) pp_exp_real (max) good_county = good_tract, by(county year4)


save county_panel_temp, replace


use county_panel_temp,clear
*** Rename collapsed variables for clarity
rename pp_exp_real county_exp   
gen state_fips = substr(county,1,2)
gen year_unified = year4 - 1

*** Save county-year panel temporarily
tempfile mytemp2
save `mytemp2'

*** Merge county names back into collapsed panel
use county_lookup
merge 1:m county using `mytemp2'
keep if _merge==3
drop _merge

*** Clean county names for consistency
replace county_name = lower(county_name)
gen county_name2 = regexr(county_name, "(County|Census|Parish|Borough|city|City).*", "")
drop county_name 
rename county_name2 county_name
replace county_name = trim(county_name)

*** Save final county-level per-pupil expenditure panel
gen interp = 0
save county_pp_exp_panel_real, replace



*****************************************************************************
*non-missing county list
*****************************************************************************
* ==== Counts: before vs after restriction ====

* Count unique counties in baseline years BEFORE filtering
preserve
    keep county
    duplicates drop
    count
    di as text "Unique counties (any year): " as result r(N)
restore

* Keep counties present in all 4 baseline years AND zero problems
preserve
    keep county year4 good_county
    keep if good_county ==1
    keep county good_county
    duplicates drop
    save clean_cty, replace
restore

* Apply the restriction
merge m:1 county using clean_cty, keep(match) nogen

* Count unique counties AFTER filtering (in baseline years)
preserve
    keep county
    duplicates drop
    count
    di as text "Unique counties (any year): " as result r(N)
restore


