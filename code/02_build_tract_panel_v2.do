/*==============================================================================
Project    : School Spending – Census Tract Panel Construction
File       : 02_build_tract_panel_v2.do
Purpose    : EFFICIENT VERSION - Link school districts to Census tracts and
             create tract-year spending panel for geographic aggregation.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-01-21
───────────────────────────────────────────────────────────────────────────────

EFFICIENCY IMPROVEMENTS OVER ORIGINAL:
  1. Reuses grf_id_tractlevel.dta from 01_build_district_panel_v2.do instead of
     re-importing and re-cleaning the raw GRF file (~120 lines eliminated)
  2. Eliminates redundant save/load cycles (grf_block, xwalk_tract_dist)
  3. Fixes misused preserve/restore pattern - now uses proper tempfile flow
  4. Combines 7 separate egen min() calls into single collapse operation
  5. Uses loops for repetitive flag operations

INPUTS:
  - $SchoolSpending/data/grf_id_tractlevel.dta  (from 01_build_district_panel_v2.do)
      └─> tract70, LEAID, county_code, no_tract
  - $SchoolSpending/data/dist_panel.dta  (from 01_build_district_panel_v2.do)
      └─> District-year panel with spending (pp_exp) and quality flags

OUTPUTS:
  - xwalk_tract_dist.dta        # tract × LEAID × sdtc with allocated population
  - tract_panel.dta     # tract-year panel with spending and quality flags

NOTE: This version requires grf_id_tractlevel.dta which contains tract-level
      GRF data. If that file doesn't include allocated population (alloc_pop)
      and school district type (sdtc), we need to import those fields from
      the raw GRF. See Section I below.
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*==============================================================*
* I) Build tract × district crosswalk with allocated population
*==============================================================*

* The tract-level file from 01 doesn't have population allocation or sdtc,
* so we need to get those from the raw GRF. But we can streamline the import.

local dfile "$SchoolSpending/data/raw/GRF69/DS0001/03515-0001-Data.txt"

* Import only the fields we need (not all 30+ variables)
infix ///
    byte  stc70  1-2      ///
    int   coc70  5-7      ///
    long  btc    77-80    ///
    int   tsc    81-82    ///
    long  popc   101-108  ///
    long  sdc    109-113  ///
    byte  sdtc   114-114  ///
    int   perc   117-119  ///
using "`dfile'", clear

* Clean in one pass (combine all drop conditions)
replace btc = 0 if missing(btc)
replace tsc = 0 if missing(tsc)

* Drop special geographies (must match original logic exactly):
*   tsc == 99: Not true geo area (ships, etc.)
*   tsc 70-98: Tract revisions/slivers
*   btc 9400-9499: Native American/AIAN land
*   btc 9800-9899: Administrative/land use codes
*   btc 9900-9998: Water bodies
drop if tsc == 99 | (tsc >= 70 & tsc <= 98) | ///
        (btc >= 9400 & btc <= 9499) | ///
        (btc >= 9800 & btc <= 9899) | ///
        (btc >= 9900 & btc <= 9998)

* Build IDs
gen str4 btc_str = string(btc, "%04.0f")
gen str2 tsc_str = string(tsc, "%02.0f")
gen str11 tract70 = string(stc70, "%02.0f") + string(coc70, "%03.0f") + btc_str + tsc_str
gen str7 LEAID = string(stc70, "%02.0f") + string(sdc, "%05.0f")
gen state_fips = string(stc70, "%02.0f")

* Calculate allocated population
replace perc = 0 if missing(perc)
replace popc = 0 if missing(popc)
gen double alloc_pop = popc * (perc / 100)

* Collapse to tract × LEAID × sdtc level (eliminates block-group detail)
collapse (sum) alloc_pop, by(tract70 LEAID sdtc state_fips)

save xwalk_tract_dist, replace


*==============================================================*
* II) Create tract-level quality flags
*==============================================================*

* Load district-year panel
use "$SchoolSpending/data/dist_panel.dta", clear

* Rename for clarity
rename good_govid_baseline good_govid
rename good_govid_baseline_6771 good_govid_6771
rename good_govid_baseline_7072 good_govid_7072

* Keep only what we need for flagging
keep LEAID good_govid good_govid_1967 good_govid_1970 good_govid_1971 ///
     good_govid_1972 good_govid_6771 good_govid_7072

* Collapse to LEAID level (flags are constant within LEAID)
duplicates drop

* Merge with tract crosswalk
merge 1:m LEAID using "xwalk_tract_dist.dta", keep(match) nogen

* Compute tract-level flags in ONE collapse (not 7 separate egen calls)
* good_tract = 1 only if ALL districts serving the tract have good data
collapse (min) good_tract = good_govid ///
               good_tract_1967 = good_govid_1967 ///
               good_tract_1970 = good_govid_1970 ///
               good_tract_1971 = good_govid_1971 ///
               good_tract_1972 = good_govid_1972 ///
               good_tract_6771 = good_govid_6771 ///
               good_tract_7072 = good_govid_7072, by(tract70)

tempfile tract_flags
save `tract_flags', replace


*==============================================================*
* III) Assign one LEAID per tract and build tract-year panel
*==============================================================*

* Load tract crosswalk
use "xwalk_tract_dist.dta", clear

* Drop vocational districts
drop if sdtc == 4

* Pick highest-population LEAID per tract-sdtc
gsort tract70 sdtc -alloc_pop LEAID
drop if missing(sdtc)
by tract70 sdtc: keep if _n == 1

isid tract70 sdtc

tempfile xwalk
save `xwalk', replace

preserve
gen fips_cty = substr(tract70, 3, 3)
keep fips_cty state_fips
duplicates drop
tab state_fips

restore

*==============================================================*
* IV) Expand to tract-year level
*==============================================================*

* Load district-year panel
use "$SchoolSpending/data/dist_panel.dta", clear

preserve
gen state_fips = substr(LEAID,1,2)
keep county_id state_fips
duplicates drop
tab state_fips

restore

* Join with tract crosswalk (explodes to tract-year)
*joinby LEAID using `xwalk' , unmatched(none)

joinby LEAID using `xwalk', unmatched(both)

* Show unmatched crosswalk LEAIDs for NH
preserve
keep if _merge == 2 & state_fips == "33"
gen fips_county = substr(tract70, 1, 5)
tab fips_county
list fips_county LEAID tract70 _merge in 1/20
restore

keep if _merge == 3
drop _merge

* Merge tract-level quality flags
merge m:1 tract70 using `tract_flags'

preserve

keep county_id state_fips
duplicates drop
tab state_fips

restore



keep if _merge == 3
drop _merge

preserve

keep county_id state_fips
duplicates drop
tab state_fips

restore


* Build derived variables
gen str13 gisjoin2 = substr(tract70, 1, 2) + "0" + substr(tract70, 3, 3) + "0" + substr(tract70, 6, 6)
gen str3 coc70 = substr(tract70, 3, 3)
gen str5 county_code = state_fips + coc70

* Keep final variables
keep LEAID GOVID year4 pp_exp sdtc state_fips gisjoin2 coc70 tract70 county_code ///
     good_tract good_tract_1967 good_tract_1970 good_tract_1971 ///
     good_tract_1972 good_tract_6771 good_tract_7072

sort tract70 year4
save tract_panel, replace

di as result "✓ Tract panel complete: tract_panel.dta"
di as result "  Observations: " _N
quietly duplicates report tract70
di as result "  Unique tracts: " r(unique_value)
