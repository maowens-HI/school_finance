/*==============================================================================
Project    : School Spending – Census Tract Panel Construction
File       : 01_tract.do
Purpose    : Parse 1969 GRF to link school districts to Census tracts,
             assign single LEAID per tract based on population allocation,
             and create tract-year spending panel for geographic aggregation.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-10-27
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES (Summary):
  • Reads 1969 GRF fixed-width file and constructs tract70/gisjoin2 identifiers
  • Links each Census tract to its serving school district(s) via allocated population
  • Assigns exactly ONE LEAID per tract (using max population; tie-break by smallest LEAID)
  • Expands district-year spending data to tract-year level
  • Tags tracts by data quality (good_tract = linked to good_govid district)

WHY THIS MATTERS (Workflow Context):
  This is Step 2 of the core pipeline. The analysis requires county-level spending,
  but we only have DISTRICT-level finance data. The 1969 GRF provides the crucial
  link: it maps Census tracts to school districts using population allocation.

  Problem: Multiple districts can serve the same tract (e.g., elementary vs high school).
  Solution: Assign single "dominant" LEAID per tract based on allocated population share.

  Once we have tract→LEAID mapping, we can:
  - Expand district spending to tract level
  - Aggregate tracts to counties (next steps)
  - Link to Census demographic data by tract

INPUTS:
  - $SchoolSpending/data/raw/GRF69/DS0001/03515-0001-Data.txt
      └─> Fixed-width ASCII file with tract-district-population linkage
  - $SchoolSpending/data/grf_tracts.dta
      └─> Pre-built tract × LEAID with allocated population weights
  - $SchoolSpending/data/f33_indfin_grf_canon.dta  (from 00_cx.do)
      └─> District-year panel with spending (pp_exp) and quality flags

OUTPUTS:
  - grf_block.dta
      └─> Raw GRF-derived geographic IDs: tract70, gisjoin2, LEAID
  - tracts_panel_canon.dta  ★ MAIN OUTPUT ★
      └─> Tract-year panel with: tract70, LEAID, year4, pp_exp, good_tract
          Coverage: 1967-2019 for all tracts in 1970 Census

KEY ASSUMPTIONS & SENSITIVE STEPS:
  1. Population Allocation Logic:
     - Each tract may be served by multiple districts (different types/grades)
     - We assign the SINGLE district with highest allocated population
     - Tie-breaker: smallest LEAID (alphanumeric sort for reproducibility)

  2. Tract Identifier Construction:
     - tract70 = state(2) + county(3) + basic_tract(4) + tract_suffix(2) [11 chars]
     - Missing basic tract codes (btc) or suffix (tsc) are filled with "0000"/"00"
     - gisjoin2 format: state + "0" + county + "0" + tract [13 chars for NHGIS compatibility]

  3. Quality Flag Inheritance:
     - good_tract = 1 if assigned LEAID has good_govid_baseline = 1
     - This ensures tracts used in analysis have complete baseline spending data

  4. Special Geographies Handled:
     - Drops water bodies, Native American lands, and tract revisions
     - Drops special district codes (e.g., state-level aggregates)

  5. Untracted Areas:
     - Some counties have "non-tracted" areas (rural, too small for tracts)
     - These get separate treatment in county aggregation (Step 4)

DEPENDENCIES:
  • Requires: global SchoolSpending "C:\Users\...\path"
  • Requires: 00_cx.do must run first (creates f33_indfin_grf_canon.dta)
  • Stata packages: None (base Stata only)
  • Downstream: 03_infl.do uses tracts_panel_canon.dta

VALIDATION CHECKS TO RUN:
  - Uniqueness: duplicates report tract70 year4 (should be 0)
  - LEAID assignment: tab has_leaid (should be 100%)
  - Quality flags: tab good_tract (shows % tracts linked to good districts)
  - Merge success: tab _merge after district-year join (should be _merge==3)
==============================================================================*/


*** Housekeeping
clear 
set more off

*** File Location
local dfile "$SchoolSpending\data\raw\GRF69\DS0001\03515-0001-Data.txt"

*** import fixed-width ASCII [ICPSR layout]
infix ///
    /* numeric codes */                                                        ///
    byte  stc70  1-2      /* 1970 state code 01–56  */                         ///
    byte  stc60  3-4      /* 1960 state code       */                           ///
    int   coc70  5-7      /* 1970 county code      */                           ///
    int   ctabu  8-10     /* county of population  */                           ///
    byte  cencc  11       /* central-county flag   */                           ///
    int   mcd    12-14    /* minor civil division  */                           ///
    int   placc  15-18    /* place code            */                           ///
    byte  platc  19       /* place-type code       */                           ///
    /* strings (SPSS marks with (A)) */                                         ///
    str2  plasc  20-21    /* place-size code       */                           ///
    str1  stcac  22-22    /* consolidated-area code*/                           ///
    str4  smsa   23-26    /* SMSA code             */                           ///
    /* more numeric */                                                          ///
    int   urbca  27-30    /* urbanized-area code   */                           ///
    int   trac   31-34    /* tracted-area code     */                           ///
    byte  uniap  35       /* universal area prefix */                           ///
    int   uniac  36-40    /* universal area code   */                           ///
    /* strings again */                                                         ///
    str2  steac  41-42    /* state economic area   */                           ///
    str3  ecosc  43-45    /* economic sub-region   */                           ///
    str1  cebdc  46-46    /* CBD flag              */                           ///
    str30  arname 47-76    /* area name             */                           ///
    /* back to numeric (ICPSR dropped Gov. ID; BTC starts here) */              ///
    long  btc    77-80    /* basic tract code      */                           ///
    int   tsc    81-82    /* tract suffix code     */                           ///
    byte  blgc   83       /* block-group code      */                           ///
    str5  endc   84-88    /* enum.-district code   */                           ///
    str1  urrc   89-89    /* urban/rural flag      */                           ///
    int   warc   90-91    /* ward code             */                           ///
    int   codc   92-93    /* congressional district*/                           ///
    long  houc   94-100   /* housing count         */                           ///
    long  popc   101-108  /* population count      */                           ///
    long  sdc    109-113  /* school-district code  */                           ///
    byte  sdtc   114-114  /* school-district type  */                           ///
    int   aduc   115-116  /* admin-unit code       */                           ///
    int   perc   117-119  /* percent equivalent    */                           ///
using "`dfile'", clear


*** Labels
label variable stc70  "1970 State Code"
label variable stc60  "1960 State Code"
label variable coc70  "1970 County Code"
label variable ctabu  "County of Population"
label variable cencc  "Central County Code"
label variable mcd    "Minor Civil Division"
label variable placc  "Place Code"
label variable platc  "Place Type Code"
label variable plasc  "Place Size Code"
label variable stcac  "Std. Consolidated Area Code"
label variable smsa   "SMSA Code"
label variable urbca  "Urbanized Area Code"
label variable trac   "Tracted Area Code"
label variable uniap  "Universal Area Prefix"
label variable uniac  "Universal Area Code"
label variable steac  "State Economic Area Code"
label variable ecosc  "Economic Subregion Code"
label variable cebdc  "Central Business District Code"
label variable arname  "Area Name"
label variable btc    "Basic Tract Code"
label variable tsc    "Tract Suffix Code"
label variable blgc   "Block Group Code"
label variable endc   "Enumeration District Code"
label variable urrc   "Urban/Rural Class Code"
label variable warc   "Ward Code"
label variable codc   "Congressional District Code"
label variable houc   "Housing Count"
label variable popc   "Population Count"
label variable sdc    "School District Code"
label variable sdtc   "School District Type Code"
label variable aduc   "Administrative Unit Code"



*** Basic Tract Code (btc) should be 4 digits; if missing, treat as 0000
*** Tract-Suffix Code (tsc) should be 2 digits; if missing, treat as 00  
replace btc = 0  if missing(btc) & !missing(trac)
replace tsc = 0 if tsc == . & !missing(trac)
gen no_tract = 0
replace no_tract = 1 if missing(trac)

* Build composite identifiers
gen str4 btc_str = string(btc,"%04.0f")
gen str2 tsc_str = string(tsc,"%02.0f")
gen str5 sdc_str = string(sdc,"%05.0f")


*** Now build the 11-char tract ID safely
gen str11 tract70 = ///
    string(stc70,"%02.0f") + string(coc70,"%03.0f") + btc_str + tsc_str
gen str13 gisjoin2 = ///
	string(stc70,"%02.0f") + "0" + string(coc70,"%03.0f") + "0" + btc_str + tsc_str 
gen str7 LEAID = string(stc70,"%02.0f") + sdc_str
	
*** Drop the two-digit suffix only when it equals "00"
replace gisjoin2 = substr(gisjoin2, 1, 11) if substr(gisjoin2, -2, 2) == "00"

***Aggregate block-groups / EDs so (tract70, sdc) is unique
* Treat missing perc as 0 so they don't offset the sum later */
replace perc = 0   if missing(perc)
replace popc = 0   if missing(popc)


gen str9 govid = ///
    string(stc70,"%02.0f")   +  /* state (2)  */ ///
    "5"                      +  /* type code  */ ///
    string(coc70,"%03.0f")   +  /* county (3) */ ///
    substr(sdc_str,1,3)   /* first 3 of sdc */
	
	
* testing stuff
cd "$SchoolSpending\data"
gen double alloc_pop = popc * (perc/100)
gen double alloc_hou = houc * (perc/100)




save grf_block,replace

*** Housekeeping

use grf_block,clear  

collapse (sum) alloc_pop alloc_hou, by(tract70 sdtc LEAID)


gen state_fips = substr(LEAID,1,2)

save grf_tract_canon,replace


use grf_id_tractlevel,clear
duplicates drop tract70 no_tract,force
merge 1:m tract70 using grf_tract_canon

keep if no_tract==1

* Unique tract count per district (ignores duplicate tract–district rows)
bysort LEAID: egen tracts_per_district = nvals(tract70)

* Tag one row per district so counts aren't multiplied by number of tracts
egen district_tag = tag(LEAID)

* How many districts have exactly one tract?
count if district_tag
local total = r(N)

count if district_tag & tracts_per_district == 1
local one = r(N)

display as text "Districts with exactly one tract: " as result `one' ///
    as text " out of " as result `total' ///
    as text " (" as result %5.2f (100*`one'/`total') as text "%)"

* Optional: distribution of tracts per district
*tab tracts_per_district if district_tag

/*****************************************************************************
Tag a tract if ANY of its districts has missing data for that year
*******************************************************************************/
* Build tag BEFORE assigning a single LEAID per tract
preserve
    use grf_tract_canon, clear
    keep LEAID tract70 sdtc alloc_pop
    tempfile xwalk_multi
    save `xwalk_multi'

use "$SchoolSpending\data\f33_indfin_grf_canon.dta", clear

rename good_govid_baseline        good_govid
rename good_govid_baseline_6771   good_govid_6771

keep LEAID year4 pp_exp good_govid ///
    good_govid_1967 good_govid_1970 good_govid_1971 ///
    good_govid_1972 good_govid_6771


joinby LEAID using `xwalk_multi'

* Aggregate all GOVID-level tags to tract-year level
bys tract70 year4: egen good_tract          = max(good_govid)
bys tract70 year4: egen good_tract_6771     = max(good_govid_6771)
bys tract70 year4: egen good_tract_1967     = max(good_govid_1967)
bys tract70 year4: egen good_tract_1970     = max(good_govid_1970)
bys tract70 year4: egen good_tract_1971     = max(good_govid_1971)
bys tract70 year4: egen good_tract_1972     = max(good_govid_1972)

keep tract70 sdtc year4 good_tract ///
    good_tract_1967 good_tract_1970 good_tract_1971 ///
    good_tract_1972 good_tract_6771

    duplicates drop
    tempfile tract_flag
    save `tract_flag'
restore






/*****************************************************************************
Assign one LEAID to each tract based on allocated population
*******************************************************************************/


/* Drop hopeless tracts (no allocated pop across all LEAIDs)
bys tract70 sdtc: egen tot_alloc = total(alloc_pop)
drop if missing(tot_alloc) | tot_alloc==0
drop tot_alloc */

* Guard against . sorting to the top
gen byte has_alloc = alloc_pop < .

* Pick exactly one LEAID per (tract70 sdtc):
*   max alloc_pop; tie fallback = smallest LEAID
gsort tract70 sdtc -has_alloc -alloc_pop LEAID
by tract70 sdtc: keep if _n==1
drop if missing(tract70)
drop if missing(sdtc)  
* Sanity
isid tract70 sdtc

* Save crosswalk
tempfile xwalk
save `xwalk', replace


***Merge panel to tracts
*District Year Spending
use "$SchoolSpending\data\f33_indfin_grf_canon.dta", clear
drop if year4 == 9999

*ExplodeL one row per tract-year
joinby LEAID using `xwalk', unmatched(both) _merge(join_merge)

*** Clean and Save
sort tract70 year4
cd "$SchoolSpending\data"


merge m:1 tract70 sdtc year4 using `tract_flag', nogen
keep if join_merge ==3
gen str13 gisjoin2 = substr(tract70, 1, 2) + "0" + substr(tract70, 3, 3) + "0" + substr(tract70, 6, 6)
gen str3 coc70 = substr(tract70, 3, 3)
keep LEAID GOVID year4 pp_exp good_tract sdtc state_fips gisjoin2 coc70 tract70 ///
    good_tract_1967 good_tract_1970 good_tract_1971 ///
    good_tract_1972 good_tract_6771
save tracts_panel_canon, replace



use grf_id_tractlevel, clear
duplicates drop tract70,force
merge 1:m tract70 using tracts_panel_canon
rename county_code county
* Identify county-year types:
* Type 1 = all tracted (no_tract==0)
* Type 2 = all untracted (no_tract==1)
* Type 3 = mixture (both 0 and 1 present)

* assumes vars: county (str/num), year4 (int), no_tract (0/1)

preserve

* restrict to observations with defined no_tract
keep if inlist(no_tract,0,1)

* counts within county-year
bys county year4: egen n_total = count(no_tract)
bys county year4: egen n_untr  = total(no_tract)       // since 1's sum
gen n_tr   = n_total - n_untr

* classify
gen byte county_type = .
replace county_type = 1 if n_tr   == n_total & n_total>0          // all tracted
replace county_type = 2 if n_untr == n_total & n_total>0          // all untracted
replace county_type = 3 if n_tr>0 & n_untr>0                      // mixture

label define ctype 1 "Type 1: all tracted" ///
                   2 "Type 2: all untracted" ///
                   3 "Type 3: mixed", replace
label values county_type ctype

* keep one row per county-year for merge back if needed
bys county year4: keep if _n==1
keep county year4 county_type

tempfile county_types
save `county_types', replace

restore

* merge classification back if desired
merge m:1 county year4 using `county_types', nogen


* County ID = SS0CCC (6 chars). Make sure inputs are strings.
capture confirm string variable state_fips
if _rc tostring state_fips, replace
capture confirm string variable coc70
if _rc tostring coc70, replace
gen str6 county = state_fips + "0" + coc70

* Manual renames (shifted baseline + per-year flags)
rename good_tract               good_tract_6671
rename good_tract_6771          good_tract_6670
rename good_tract_1967          good_tract_1966
rename good_tract_1970          good_tract_1969
rename good_tract_1971          good_tract_1970
rename good_tract_1972          good_tract_1971

* ---------- TRACT-LEVEL TABS (panel-wide) ----------
di as text "== good_tract_6671 =="
tab good_tract_6671, missing
di as text "== good_tract_6670 =="
tab good_tract_6670, missing
di as text "== good_tract_1966 =="
tab good_tract_1966, missing
di as text "== good_tract_1969 =="
tab good_tract_1969, missing
di as text "== good_tract_1970 =="
tab good_tract_1970, missing
di as text "== good_tract_1971 =="
tab good_tract_1971, missing

* ---------- COUNTY x YEAR COLLAPSE ----------
preserve
    collapse (max) ///
        good_county_6671 = good_tract_6671 ///
        good_county_6670 = good_tract_6670 ///
        good_county_1966 = good_tract_1966 ///
        good_county_1969 = good_tract_1969 ///
        good_county_1970 = good_tract_1970 ///
        good_county_1971 = good_tract_1971, ///
        by(county year4)

    * ---------- COUNTY-LEVEL TABS (panel-wide) ----------
    di as text "== good_county_6671 =="
    tab good_county_6671, missing
    di as text "== good_county_6670 =="
    tab good_county_6670, missing
    di as text "== good_county_1966 =="
    tab good_county_1966, missing
    di as text "== good_county_1969 =="
    tab good_county_1969, missing
    di as text "== good_county_1970 =="
    tab good_county_1970, missing
    di as text "== good_county_1971 =="
    tab good_county_1971, missing
restore

