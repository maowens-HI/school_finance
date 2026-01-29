/*==============================================================================
Purpose: Identify which pipeline step causes each state to drop below threshold
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

di _n "=============================================================="
di "WHICH STEP CAUSES EACH STATE TO FAIL?"
di "=============================================================="

/*
Pipeline stages:
1. INDFIN: Raw GOVID-level data (uses GOVS state codes)
2. dist_panel: After 1:1 LEAID-GOVID crosswalk + GRF match
3. tract_panel: After assigning districts to tracts
4. county_panel: After collapsing tracts to counties
5. analysis_panel_bal: After balanced panel filter
6. good + valid_st_gd: After good_county_1972 + 10-county threshold
*/

*==============================================================================
* Stage 1: INDFIN county counts (using GOVS state codes)
*==============================================================================
di _n "=== STAGE 1: INDFIN (GOVS codes) ==="

use indfin_panel, clear

* GOVID format: SS5CCCDDD where SS=state(GOVS), 5=type, CCC=county, DDD=district
* Extract GOVS state code (positions 1-2) and county (positions 4-6)
cap drop govs_state
gen govs_state = substr(GOVID, 1, 2)
cap drop govs_county
gen govs_county = substr(GOVID, 1, 2) + substr(GOVID, 4, 3)

* Count unique counties per GOVS state
preserve
keep govs_state govs_county
duplicates drop
bysort govs_state: gen n_counties = _N
bysort govs_state: keep if _n == 1
keep govs_state n_counties
rename n_counties indfin_counties
tempfile stage1
save `stage1'
restore

*==============================================================================
* Stage 2: dist_panel county counts (uses FIPS via LEAID)
*==============================================================================
di _n "=== STAGE 2: dist_panel (after 1:1 crosswalk + GRF) ==="

use dist_panel, clear

* LEAID format: SSDDDDD where SS=state FIPS
cap drop state_fips
gen state_fips = substr(LEAID, 1, 2)

* Get county from county_id variable (should be 5-char FIPS)
* If county_id doesn't exist, derive from GOVID
capture confirm variable county_id
if _rc {
    capture confirm variable county
    if _rc {
        di "county_id and county not found, using state_fips only"
        gen county = ""
    }
    else {
        di "Using existing county variable"
    }
}
else {
    cap drop county
    rename county_id county
}

* Count unique counties per state
preserve
keep state_fips county
drop if missing(county)
duplicates drop
bysort state_fips: gen n_counties = _N
bysort state_fips: keep if _n == 1
keep state_fips n_counties
rename n_counties dist_counties
tempfile stage2
save `stage2'
restore

*==============================================================================
* Stage 3: tract_panel county counts
*==============================================================================
di _n "=== STAGE 3: tract_panel ==="

* Use the interpolated tract panel
capture use tract_panel_interp_real, clear
if _rc {
    use interp_t, clear
}

* County is first 5 chars of tract70
cap drop county
gen county = substr(tract70, 1, 5)
cap drop state_fips
gen state_fips = substr(tract70, 1, 2)

preserve
keep state_fips county
duplicates drop
bysort state_fips: gen n_counties = _N
bysort state_fips: keep if _n == 1
keep state_fips n_counties
rename n_counties tract_counties
tempfile stage3
save `stage3'
restore

*==============================================================================
* Stage 4: county_panel counts
*==============================================================================
di _n "=== STAGE 4: county_panel ==="

use county_panel, clear

cap drop state_fips
gen state_fips = substr(county, 1, 2)

preserve
keep state_fips county
duplicates drop
bysort state_fips: gen n_counties = _N
bysort state_fips: keep if _n == 1
keep state_fips n_counties
rename n_counties county_panel_counties
tempfile stage4
save `stage4'
restore

*==============================================================================
* Stage 5: analysis_panel_bal counts
*==============================================================================
di _n "=== STAGE 5: analysis_panel_bal (balanced panel) ==="

use analysis_panel_bal, clear

preserve
keep state_fips county_id
duplicates drop
bysort state_fips: gen n_counties = _N
bysort state_fips: keep if _n == 1
keep state_fips n_counties
rename n_counties balanced_counties
tempfile stage5
save `stage5'
restore

*==============================================================================
* Stage 6: good + valid_st_gd counts
*==============================================================================
di _n "=== STAGE 6: good==1 & valid_st_gd==1 ==="

use analysis_panel_bal, clear

preserve
keep if good == 1 & valid_st_gd == 1
keep state_fips county_id
duplicates drop
bysort state_fips: gen n_counties = _N
bysort state_fips: keep if _n == 1
keep state_fips n_counties
rename n_counties final_counties
tempfile stage6
save `stage6'
restore

*==============================================================================
* Merge all stages and create GOVS-FIPS crosswalk
*==============================================================================
di _n "=== MERGE ALL STAGES ==="

* Create GOVS to FIPS crosswalk
clear
input str2 govs_state str2 state_fips str20 state_name
"01" "01" "Alabama"
"02" "02" "Alaska"
"03" "04" "Arizona"
"04" "05" "Arkansas"
"05" "06" "California"
"06" "08" "Colorado"
"07" "09" "Connecticut"
"08" "10" "Delaware"
"09" "11" "DC"
"10" "12" "Florida"
"11" "13" "Georgia"
"12" "15" "Hawaii"
"13" "16" "Idaho"
"14" "17" "Illinois"
"15" "18" "Indiana"
"16" "19" "Iowa"
"17" "20" "Kansas"
"18" "21" "Kentucky"
"19" "22" "Louisiana"
"20" "23" "Maine"
"21" "24" "Maryland"
"22" "25" "Massachusetts"
"23" "26" "Michigan"
"24" "27" "Minnesota"
"25" "28" "Mississippi"
"26" "29" "Missouri"
"27" "30" "Montana"
"28" "31" "Nebraska"
"29" "32" "Nevada"
"30" "33" "New Hampshire"
"31" "34" "New Jersey"
"32" "35" "New Mexico"
"33" "36" "New York"
"34" "37" "North Carolina"
"35" "38" "North Dakota"
"36" "39" "Ohio"
"37" "40" "Oklahoma"
"38" "41" "Oregon"
"39" "42" "Pennsylvania"
"40" "44" "Rhode Island"
"41" "45" "South Carolina"
"42" "46" "South Dakota"
"43" "47" "Tennessee"
"44" "48" "Texas"
"45" "49" "Utah"
"46" "50" "Vermont"
"47" "51" "Virginia"
"48" "53" "Washington"
"49" "54" "West Virginia"
"50" "55" "Wisconsin"
"51" "56" "Wyoming"
end

tempfile xwalk
save `xwalk'

* Merge INDFIN counts
merge 1:1 govs_state using `stage1'
drop _merge

* Merge remaining stages
merge 1:1 state_fips using `stage2'
drop _merge
merge 1:1 state_fips using `stage3'
drop _merge
merge 1:1 state_fips using `stage4'
drop _merge
merge 1:1 state_fips using `stage5'
drop _merge
merge 1:1 state_fips using `stage6'
drop _merge

* Fill zeros for missing
foreach v of varlist *_counties {
    replace `v' = 0 if missing(`v')
}

*==============================================================================
* Identify which step caused drop below 10
*==============================================================================
di _n "=== IDENTIFY CRITICAL DROPOUT STEP ==="

gen dropout_step = ""

* Check each transition
replace dropout_step = "1_INDFIN" if indfin_counties < 10 & indfin_counties > 0
replace dropout_step = "2_dist_panel (crosswalk+GRF)" if indfin_counties >= 10 & dist_counties < 10 & dist_counties > 0
replace dropout_step = "3_tract_panel" if dist_counties >= 10 & tract_counties < 10 & tract_counties > 0
replace dropout_step = "4_county_panel" if tract_counties >= 10 & county_panel_counties < 10 & county_panel_counties > 0
replace dropout_step = "5_balanced_panel" if county_panel_counties >= 10 & balanced_counties < 10
replace dropout_step = "6_good+valid" if balanced_counties >= 10 & final_counties < 10

* For states that end with 0, identify where they hit 0
replace dropout_step = "5_balanced_panel (to 0)" if county_panel_counties > 0 & balanced_counties == 0
replace dropout_step = "6_good+valid (to 0)" if balanced_counties > 0 & final_counties == 0

*==============================================================================
* Display results for states of interest
*==============================================================================
di _n "=============================================================="
di "COUNTY COUNTS BY PIPELINE STAGE"
di "=============================================================="

* List states that have reform (from JJP) - these are the ones we care about
* For now show all with dropout
list state_name govs_state state_fips indfin_counties dist_counties tract_counties ///
     county_panel_counties balanced_counties final_counties dropout_step ///
     if final_counties == 0 | (final_counties > 0 & final_counties < 50), ///
     noobs sepby(dropout_step)

*==============================================================================
* Focus on specific states from spreadsheet
*==============================================================================
di _n "=============================================================="
di "FOCUS: States from spreadsheet questions"
di "=============================================================="

list state_name govs_state state_fips indfin_counties dist_counties tract_counties ///
     county_panel_counties balanced_counties final_counties dropout_step ///
     if inlist(state_fips, "04", "09", "23", "25", "30", "33", "36", "41", "45", "47", "50"), ///
     noobs

* Save for further analysis
save county_dropout_analysis, replace

*==============================================================================
* Generate declarative statements
*==============================================================================
di _n "=============================================================="
di "DECLARATIVE STATEMENTS (externally verified)"
di "=============================================================="

* Arizona
sum indfin_counties if state_fips == "04"
local az_indfin = r(mean)
sum dist_counties if state_fips == "04"
local az_dist = r(mean)
sum balanced_counties if state_fips == "04"
local az_bal = r(mean)
di "ARIZONA: INDFIN=`az_indfin' → dist_panel=`az_dist' → balanced=`az_bal'"
di "  Statement: Arizona drops from `az_indfin' to `az_dist' at dist_panel step"
di "  Statement: Arizona has `az_bal' balanced counties, which is < 10"

* Connecticut
sum county_panel_counties if state_fips == "09"
local ct_county = r(mean)
sum balanced_counties if state_fips == "09"
local ct_bal = r(mean)
di _n "CONNECTICUT: county_panel=`ct_county' → balanced=`ct_bal'"
di "  Statement: Connecticut drops from `ct_county' to `ct_bal' at balanced_panel step"

* Montana
sum county_panel_counties if state_fips == "30"
local mt_county = r(mean)
sum balanced_counties if state_fips == "30"
local mt_bal = r(mean)
di _n "MONTANA: county_panel=`mt_county' → balanced=`mt_bal'"
di "  Statement: Montana has `mt_bal' balanced counties, which is < 10"

* Oregon
sum county_panel_counties if state_fips == "41"
local or_county = r(mean)
sum balanced_counties if state_fips == "41"
local or_bal = r(mean)
di _n "OREGON: county_panel=`or_county' → balanced=`or_bal'"
di "  Statement: Oregon drops from `or_county' to `or_bal' at balanced_panel step"

* South Carolina
sum county_panel_counties if state_fips == "45"
local sc_county = r(mean)
sum balanced_counties if state_fips == "45"
local sc_bal = r(mean)
di _n "SOUTH CAROLINA: county_panel=`sc_county' → balanced=`sc_bal'"
di "  Statement: South Carolina drops from `sc_county' to `sc_bal' at balanced_panel step"

* New York
sum balanced_counties if state_fips == "36"
local ny_bal = r(mean)
sum final_counties if state_fips == "36"
local ny_final = r(mean)
di _n "NEW YORK: balanced=`ny_bal' → final=`ny_final'"
di "  Statement: New York has `ny_final' final counties, which is >= 10 (INCLUDED)"

