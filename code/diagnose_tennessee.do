/*==============================================================================
Project    : School Spending - Diagnose Tennessee County Filtering
File       : diagnose_tennessee.do
Purpose    : Trace Tennessee counties through the data pipeline to identify
             where and why they are being filtered out.
Author     : Myles Owens / Claude
Date       : 2026-01-21
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

display _n(3)
display "==============================================================================="
display "TENNESSEE COUNTY DIAGNOSTIC REPORT"
display "Tennessee State FIPS = 47"
display "==============================================================================="
display _n(2)

*===============================================================================
* STAGE 1: Check GRF Coverage - How many TN districts are in the 1969 GRF?
*===============================================================================

display "==============================================================================="
display "STAGE 1: GRF COVERAGE (1969 Geographic Reference File)"
display "==============================================================================="

capture confirm file "grf_id.dta"
if _rc == 0 {
    use "grf_id.dta", clear

    * Extract state FIPS from LEAID (first 2 characters)
    gen state_fips = substr(LEAID, 1, 2)

    * Count TN districts in GRF
    count if state_fips == "47"
    local n_tn_grf = r(N)
    display _n "Tennessee districts in GRF: `n_tn_grf'"

    * Show all states for comparison
    display _n "Districts in GRF by state (top 20):"
    tab state_fips, sort
}
else {
    display "WARNING: grf_id.dta not found"
}

*===============================================================================
* STAGE 2: Check INDFIN Coverage - Does TN have baseline year data?
*===============================================================================

display _n(2)
display "==============================================================================="
display "STAGE 2: INDFIN COVERAGE (Historical spending data 1967-1991)"
display "==============================================================================="

capture confirm file "district_panel_tagged.dta"
if _rc == 0 {
    use "district_panel_tagged.dta", clear

    * Extract state FIPS from LEAID or GOVID
    capture gen state_fips = substr(LEAID, 1, 2)
    if _rc != 0 {
        capture gen state_fips = substr(GOVID, 1, 2)
    }

    * Count TN districts
    preserve
    keep if state_fips == "47"

    display _n "Tennessee districts in district_panel_tagged: " _N

    * Check baseline years (1967, 1970, 1971, 1972)
    display _n "Tennessee observations by baseline year:"
    tab year4 if inlist(year4, 1967, 1970, 1971, 1972), m

    * Check spending availability
    display _n "Tennessee observations with non-missing spending by baseline year:"
    count if year4 == 1967 & !missing(pp_exp)
    display "  1967: " r(N)
    count if year4 == 1970 & !missing(pp_exp)
    display "  1970: " r(N)
    count if year4 == 1971 & !missing(pp_exp)
    display "  1971: " r(N)
    count if year4 == 1972 & !missing(pp_exp)
    display "  1972: " r(N)

    * Check good_govid flags
    display _n "Tennessee good_govid flags (if they exist):"
    capture tab good_govid_baseline if year4 == 1970, m
    capture tab good_govid if year4 == 1970, m

    restore
}
else {
    display "WARNING: district_panel_tagged.dta not found"
}

*===============================================================================
* STAGE 3: Check Tract Panel - How many TN tracts survive?
*===============================================================================

display _n(2)
display "==============================================================================="
display "STAGE 3: TRACT PANEL"
display "==============================================================================="

capture confirm file "tracts_panel_canon.dta"
if _rc == 0 {
    use "tracts_panel_canon.dta", clear

    * Extract state from tract ID (first 2 digits)
    capture gen state_fips = substr(tract70, 1, 2)
    if _rc != 0 {
        capture gen state_fips = substr(gisjoin2, 1, 2)
    }

    preserve
    keep if state_fips == "47"

    * Count TN tracts
    display _n "Tennessee tract-years in tracts_panel_canon: " _N

    * Unique tracts
    keep state_fips tract70
    duplicates drop
    display "Unique Tennessee tracts: " _N
    restore
}
else {
    display "WARNING: tracts_panel_canon.dta not found"
}

*===============================================================================
* STAGE 4: Check County Quality Flags
*===============================================================================

display _n(2)
display "==============================================================================="
display "STAGE 4: COUNTY QUALITY FLAGS (county_clean.dta)"
display "==============================================================================="

capture confirm file "county_clean.dta"
if _rc == 0 {
    use "county_clean.dta", clear

    * Extract state from county (first 2 digits)
    capture confirm string variable county
    if _rc == 0 {
        gen state_fips = substr(county, 1, 2)
    }
    else {
        tostring county, gen(county_str) format(%05.0f)
        gen state_fips = substr(county_str, 1, 2)
    }

    preserve
    keep if state_fips == "47"

    display _n "Tennessee counties in county_clean: " _N

    * Check quality flags
    display _n "Tennessee good_county_1972 distribution:"
    tab good_county_1972, m

    * List TN counties with their flags
    display _n "Tennessee counties (showing first 20):"
    list county good_county_1972 in 1/20, noobs clean

    restore
}
else {
    display "WARNING: county_clean.dta not found"
}

*===============================================================================
* STAGE 5: Check County Expenditure Panel
*===============================================================================

display _n(2)
display "==============================================================================="
display "STAGE 5: COUNTY EXPENDITURE PANEL (county_exp_final.dta)"
display "==============================================================================="

capture confirm file "county_exp_final.dta"
if _rc == 0 {
    use "county_exp_final.dta", clear

    * Extract state from county
    capture confirm string variable county
    if _rc == 0 {
        gen state_fips = substr(county, 1, 2)
    }
    else {
        tostring county, gen(county_str) format(%05.0f)
        gen state_fips = substr(county_str, 1, 2)
    }

    preserve
    keep if state_fips == "47"

    display _n "Tennessee county-years in county_exp_final: " _N

    * Unique counties
    keep county
    duplicates drop
    display "Unique Tennessee counties: " _N

    restore

    * Check spending coverage in baseline years
    preserve
    keep if state_fips == "47"

    display _n "Tennessee spending availability by year (baseline period):"
    foreach y in 1967 1968 1969 1970 1971 1972 {
        count if year4 == `y' & !missing(county_exp)
        display "  `y': " r(N) " counties with spending data"
    }
    restore
}
else {
    display "WARNING: county_exp_final.dta not found"

    * Try alternate file
    capture confirm file "county_exp_final_alt.dta"
    if _rc == 0 {
        display "Trying county_exp_final_alt.dta instead..."
        use "county_exp_final_alt.dta", clear

        capture confirm string variable county
        if _rc == 0 {
            gen state_fips = substr(county, 1, 2)
        }
        else {
            tostring county, gen(county_str) format(%05.0f)
            gen state_fips = substr(county_str, 1, 2)
        }

        preserve
        keep if state_fips == "47"

        display _n "Tennessee county-years in county_exp_final_alt: " _N

        keep county
        duplicates drop
        display "Unique Tennessee counties: " _N
        restore
    }
}

*===============================================================================
* STAGE 6: Check JJP Interp Final (Pre-Balance)
*===============================================================================

display _n(2)
display "==============================================================================="
display "STAGE 6: JJP INTERP FINAL (Pre-Balance Restriction)"
display "==============================================================================="

capture confirm file "jjp_interp_final.dta"
if _rc == 0 {
    use "jjp_interp_final.dta", clear

    preserve
    keep if state_fips == "47"

    display _n "Tennessee county-years in jjp_interp_final: " _N

    * Unique counties
    keep county_id
    duplicates drop
    display "Unique Tennessee counties: " _N
    restore

    * Check balanced flag distribution for TN
    preserve
    keep if state_fips == "47"

    display _n "Tennessee balanced flag distribution (one obs per county):"
    keep county_id balanced
    duplicates drop
    tab balanced, m

    restore

    * Check good_county_1972 flag
    preserve
    keep if state_fips == "47"

    display _n "Tennessee good_county_1972 distribution (one obs per county):"
    keep county_id good_county_1972
    duplicates drop
    tab good_county_1972, m

    restore
}
else {
    display "WARNING: jjp_interp_final.dta not found"
}

*===============================================================================
* STAGE 7: Check JJP Final (After Balance + State Filter)
*===============================================================================

display _n(2)
display "==============================================================================="
display "STAGE 7: JJP FINAL (After Balance + State Filter)"
display "==============================================================================="

capture confirm file "jjp_final.dta"
if _rc == 0 {
    use "jjp_final.dta", clear

    preserve
    keep if state_fips == "47"

    display _n "Tennessee county-years in jjp_final: " _N

    * Unique counties
    keep county_id
    duplicates drop
    local n_final = _N
    display "Unique Tennessee counties in final dataset: `n_final'"

    restore

    * Check if TN passes state filter
    preserve
    keep if state_fips == "47"

    display _n "Tennessee state filter status:"
    sum valid_st valid_st_gd n_counties_all n_counties_good

    restore

    * Check good counties
    preserve
    keep if state_fips == "47" & good == 1
    keep county_id
    duplicates drop
    display _n "Tennessee GOOD counties in jjp_final: " _N
    restore

    * Check good + valid_st_gd
    preserve
    keep if state_fips == "47" & good == 1 & valid_st_gd == 1
    keep county_id
    duplicates drop
    display _n "Tennessee GOOD counties passing state filter: " _N
    restore
}
else {
    display "WARNING: jjp_final.dta not found"
}

*===============================================================================
* STAGE 8: Comparison with Other States
*===============================================================================

display _n(2)
display "==============================================================================="
display "STAGE 8: COMPARISON WITH OTHER STATES"
display "==============================================================================="

capture confirm file "jjp_final.dta"
if _rc == 0 {
    use "jjp_final.dta", clear

    * Count good counties by state
    preserve
    keep if good == 1
    keep state_fips county_id
    duplicates drop

    bysort state_fips: gen n_good = _N
    keep state_fips n_good
    duplicates drop

    gsort -n_good
    display _n "Good counties by state (states with reforms):"
    list state_fips n_good in 1/20, noobs clean

    restore

    * Check TN's position
    preserve
    keep state_fips county_id good
    keep if good == 1
    duplicates drop

    bysort state_fips: gen n = _N
    keep state_fips n
    duplicates drop

    sum n if state_fips == "47"
    display _n "Tennessee good county count: " r(mean)
    display "Threshold for valid_st_gd: 10"
    restore
}

*===============================================================================
* SUMMARY
*===============================================================================

display _n(3)
display "==============================================================================="
display "SUMMARY: WHERE TENNESSEE COUNTIES ARE LOST"
display "==============================================================================="
display _n
display "Check the counts above at each stage to identify the filtering bottleneck:"
display "  1. GRF Coverage: Are TN districts in the 1969 Geographic Reference File?"
display "  2. INDFIN Data: Does TN have baseline spending data (1967, 1970-1972)?"
display "  3. Quality Flags: How many TN counties have good_county_1972 = 1?"
display "  4. Balance Check: Do TN counties have complete event windows?"
display "  5. State Filter: Does TN have >= 10 good counties to pass valid_st_gd?"
display _n
display "==============================================================================="

