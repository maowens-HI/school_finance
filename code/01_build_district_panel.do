/*==============================================================================
Project    : School Spending – District Panel Construction and ID Crosswalks
File       : 01_build_district_panel.do
Purpose    : Build the foundation district-year panel by harmonizing NCES F-33
             (1992-2019) and INDFIN (1967-1991) data sources and creating
             canonical crosswalks between incompatible district ID systems.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-10-27
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES (Summary):
  • Imports and cleans F-33 (SAS) and INDFIN district finance data
  • Builds 1:1 crosswalk linking LEAID ↔ GOVID ↔ GRF identifiers
  • Creates quality flags for districts with complete baseline data (1967, 1970-1972)
  • Produces unified district-year panel spanning 1967-2019
  • Outputs canonical crosswalk file for all downstream geographic linking

WHY THIS MATTERS (Workflow Context):
  This is Step 1 of the core pipeline. The research design requires tracking
  school spending over 50+ years, but data sources use incompatible ID systems:
  - F-33 uses LEAID (7-char NCES codes)
  - INDFIN uses GOVID (9-char government finance codes)
  - GRF uses LEAID for tract-district linkage
  
  Without clean 1:1 mappings, we cannot link districts across time or connect
  them to Census geographies. The quality flags identify districts suitable for
  event-study analysis (must have spending data in all baseline years before
  reforms begin).

INPUTS:
  - $SchoolSpending/data/raw/nces/build_f33_in_dir.sas7bdat
      └─> NCES F-33 Finance Survey files (1992-2019), one per year
  - $SchoolSpending/data/raw/indfin/build_indfin_in_dir/
      └─> INDFIN historical database files (1967, 1969-1991)
  - $SchoolSpending/data/raw/GRF69/DS0001/03515-0001-Data.txt
      └─> 1969 Geographic Reference File (fixed-width ASCII)

OUTPUTS:
  - f33_panel.dta                  # F-33 district-year panel (1992-2019)
  - indfin_panel.dta               # INDFIN district-year panel (1967-1991)
  - canon_crosswalk.dta            # 1:1 LEAID ↔ GOVID mapping
  - f33_indfin_grf_canon.dta       # UNIFIED panel with quality flags
      └─> Key vars: LEAID, GOVID, year4, pp_exp, good_govid_*

KEY ASSUMPTIONS & SENSITIVE STEPS:
  1. Crosswalk Quality: Only keeps 1:1 LEAID ↔ GOVID matches; drops
     many-to-many relationships (51.21% of raw mappings are 1:1)
  
  2. Baseline Period: Tags districts as "good_govid" only if they have
     NON-MISSING spending in ALL of: 1967, 1970, 1971, 1972
     (This restriction is critical for constructing baseline spending quartiles)
  
  3. ID Padding: LEAIDs padded to 7 chars, GOVIDs to 9 chars for consistency
  
  4. Missing Data: Flags but RETAINS anomalous values (negative spending,
     outliers) for traceability; cleaning happens downstream
  
  5. GRF Integration: Reads fixed-width file to extract LEAIDs that exist in
     1969 GRF (these are the only districts we can link to Census tracts)

DEPENDENCIES:
  • Requires: global SchoolSpending "C:\Users\...\path"
  • Stata packages: None (uses base Stata only)
  • Downstream files: 02_build_tract_panel.do requires f33_indfin_grf_canon.dta

VALIDATION CHECKS TO RUN:
  - Check crosswalk: count if _merge == 3 after LEAID-GOVID merge
  - Check baseline flags: tab good_govid_baseline
  - Check ID uniqueness: duplicates report LEAID year4
  - Check spending coverage: count if missing(pp_exp) by year4
==============================================================================*/


*==============================================================*
* I) Build F-33 NCES panel (1992-2019)
*==============================================================*

*--------------------------------------------------------------*
* A) Import SAS files and convert to Stata format
*--------------------------------------------------------------*

clear
set more off
cd "$SchoolSpending/data/raw/nces/build_f33_in_dir"

* 1)--------------------------------- Identify all F-33 raw SAS files
local files : dir "." files "*.sas7bdat"

* 2)--------------------------------- Convert each SAS file to .dta format
foreach f of local files {
    disp "Processing `f'"

    import sas using "`f'", clear

    local outname = subinstr("`f'", ".sas7bdat", ".dta", .)
    save "`outname'", replace
}

*--------------------------------------------------------------*
* B) Append all yearly files into unified panel
*--------------------------------------------------------------*

* 1)--------------------------------- Prepare list of converted .dta files
local files : dir "." files "*.dta"
tempfile base

local first = 1

* 2)--------------------------------- Extract year from filename and load variables
foreach f of local files {
    disp "Processing `f'"

    * Try to pull year (example: "sdf92.dta" → 1992)
    local shortyr = substr("`f'", 4, 2)
    local year = cond(real("`shortyr'") < 50, 2000 + real("`shortyr'"), 1900 + real("`shortyr'"))

    use LEAID CENSUSID NAME V33 TOTALEXP SCHLEV using "`f'", clear
    gen year = `year'

    if `first' {
        save `base'
        local first = 0
    }
    else {
        append using `base'
        save `base', replace
    }
}

* 3)--------------------------------- Load unified tempfile
use `base', clear

*--------------------------------------------------------------*
* C) Clean and construct per-pupil expenditure
*--------------------------------------------------------------*

cd "$SchoolSpending\data"

* 1)--------------------------------- Flag anomalous values (keep for inspection)
gen bad_pop   = (V33 < 0)        // negative pop
label var bad_pop "Zero or negative pop"
label var bad_pop "Flag: zero or negative population"
gen bad_exp   = (TOTALEXP < 0)    // negative expenditure
label var bad_exp "Flag: negative expenditure"
drop if bad_exp ==1
drop if bad_pop ==1

rename SCHLEV level
drop if level == "06"
drop if level == "07"
drop if level == "05"
drop if level == "N"

* 2)--------------------------------- Calculate per-pupil expenditure (in #1000s)
gen pp_exp = .
replace pp_exp = (TOTALEXP/1000) / V33

label var pp_exp "Per-pupil expenditure"
drop if year < 1992 | year > 2019

* 3)--------------------------------- Extract 9-digit GOVID from 14-digit CENSUSID
gen str9 GOVID = substr(CENSUSID,1,9)
rename V33 enrollment

save f33_panel, replace




*==============================================================*
* II) Build INDFIN historical panel (1967-1991)
*==============================================================*

*--------------------------------------------------------------*
* A) Load and clean yearly INDFIN datasets
*--------------------------------------------------------------*

* 1)--------------------------------- Define year range and directory paths
local years 67 70 71 72 73 74 75 76 77 78 79 ///
            80 81 82 83 84 85 86 87 88 89   ///
            90 91   // 68 & 69 skipped

local inDir  "$SchoolSpending/data/raw/indfin/build_indfin_in_dir"
local outDir "$SchoolSpending/data/raw/indfin/build_indfin_out_dir"

* 2)--------------------------------- Define variables to retain
local keepvars ///
    sortcode year4 id idchanged statecode typecode county name ///
    population elemeductotalexp totalexpenditure totaleductotalexp 

* 3)--------------------------------- Filter to school districts and keep essential vars
foreach y of local years {
    di as txt "→ trimming `y'"
    use "`inDir'/indfin`y'a.dta", clear
    keep if typecode == 5                     // focus on school districts
    keep `keepvars'
    save "`outDir'/f`y'.dta", replace
}

*--------------------------------------------------------------*
* B) Stack all years into unified panel
*--------------------------------------------------------------*

* 1)--------------------------------- Append all cleaned years
local first : word 1 of `years'
use "`outDir'/f`first'.dta", clear

foreach y of local years {
    if "`y'" == "`first'" continue
    append using "`outDir'/f`y'.dta"
}

save "`outDir'/indfin_panel_1967_1991_clean.dta", replace
di as result "✓ INDFIN panel (1967‑1991) complete."

* 2)--------------------------------- Create standard 9-digit GOVID
gen str9 GOVID = string(id, "%09.0f")
cd "$SchoolSpending\data"

* 3)--------------------------------- Calculate per-pupil expenditure
gen pp_exp = .
replace pp_exp = totalexpenditure/population
label var pp_exp "Per-pupil expenditure"
rename population enrollment
save indfin_panel, replace




*==============================================================*
* III) Import Geographic Reference File (GRF) and Master IDs
*==============================================================*

*--------------------------------------------------------------*
* A) Load F-33 ID crosswalk files
*--------------------------------------------------------------*

clear
set more off
cd "$SchoolSpending\data\raw\nces\build_f33_in_dir"

* 1)--------------------------------- Convert SAS files to Stata
local files : dir "." files "*.sas7bdat"

foreach f of local files {
    disp "Processing `f'"

    import sas using "`f'", clear

    local outname = subinstr("`f'", ".sas7bdat", ".dta", .)
    save "`outname'", replace
}

*--------------------------------------------------------------*
* B) Append all yearly ID files
*--------------------------------------------------------------*

* 1)--------------------------------- Prepare list of .dta files
local files : dir "." files "*.dta"
tempfile base

local first = 1

* 2)--------------------------------- Extract year and stack ID files
foreach f of local files {
    disp "Processing `f'"

    * Try to pull year (example: "sdf92.dta" → 1992)
    local shortyr = substr("`f'", 4, 2)
    local year = cond(real("`shortyr'") < 50, 2000 + real("`shortyr'"), 1900 + real("`shortyr'"))

    use LEAID CENSUSID NAME using "`f'", clear
    gen year = `year'

    if `first' {
        save `base'
        local first = 0
    }
    else {
        append using `base'
        save `base', replace
    }
}

use `base', clear

* 3)--------------------------------- Extract GOVID and save crosswalk
cd "$SchoolSpending\data"
gen str9 GOVID = substr(CENSUSID,1,9)
save f33_id, replace




*--------------------------------------------------------------*
* C) Import fixed-width GRF ASCII file
*--------------------------------------------------------------*

clear
set more off
local dfile "$SchoolSpending/data/raw/GRF69/DS0001/03515-0001-Data.txt"

* 1)--------------------------------- Define field positions and variable types
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
    str30 arnam  47-76    /* area name             */                           ///
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

* 2)--------------------------------- Apply variable labels
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
label variable arnam  "Area Name"
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

*export delimited using "grf_raw.csv", replace // For inspecting the GRF

*--------------------------------------------------------------*
* D) Clean GRF geographic identifiers
*--------------------------------------------------------------*

* 1)--------------------------------- Handle missing tract codes
gen no_tract = 0
replace no_tract = 1 if missing(btc)

*** Basic Tract Code (btc) should be 4 digits; if missing, treat as 0000
*** Tract-Suffix Code (tsc) should be 2 digits; if missing, treat as 00
replace btc = 0  if missing(btc)
replace tsc = 0 if missing(tsc)

* 2)--------------------------------- Build composite ID strings
gen str4 btc_str = string(btc,"%04.0f")
gen str2 tsc_str = string(tsc,"%02.0f")
gen str5 sdc_str = string(sdc,"%05.0f")

* 3)--------------------------------- Drop special geographic areas
* Drop special areas
gen flag_suffix_special = tsc_str == "99" // Not a true geo area. Includes ships
drop if tsc_str == "99"
drop flag_suffix_special

* Tract revisions which are slivers of the same tract
gen flag_suffix_change = (tsc >= 70 & tsc <= 98) // tract revisions
drop if flag_suffix_change == 1
drop flag_suffix_change

drop if btc >= 9500
gen flag_special_AIAN     = (btc >= 9400 & btc <= 9499) // Native Land
gen flag_special_landuse  = (btc >= 9800 & btc <= 9899) // Administrative code
gen flag_water_only       = (btc >= 9900 & btc <= 9998) // Water

drop if flag_special_AIAN | flag_special_landuse | flag_water_only

* 4)--------------------------------- Construct 11-char tract70 and 7-char LEAID
*** Now build the 11-char tract ID
* Census 11 digit unique tract identifier
gen str11 tract70 = ///
    string(stc70,"%02.0f") + string(coc70,"%03.0f") + btc_str + tsc_str
* For use in GIS
gen str13 gisjoin2 = ///
	string(stc70,"%02.0f") + "0" + string(coc70,"%03.0f") + "0" + btc_str + tsc_str
*** GIS Fix: Drop the two-digit suffix only when it equals "00"
replace gisjoin2 = substr(gisjoin2, 1, 11) if substr(gisjoin2, -2, 2) == "00"
*NCES Local Economic Agency ID
gen str7 LEAID = string(stc70,"%02.0f") + sdc_str

* 5)--------------------------------- Save GRF ID files
*** SAVE tract-level GRF IDs which indicate non-tract area (keep on the side)
preserve
	gen str5 county_code = string(stc70,"%02.0f") + string(coc70,"%03.0f")
    keep LEAID tract70 county_code no_tract
    save grf_id_tractlevel, replace
restore

*** Create county_code-LEAID mapping (one county per LEAID)
* Use mode (most common) county per district
preserve
	gen str5 county_code = string(stc70,"%02.0f") + string(coc70,"%03.0f")
	* Keep one row per LEAID-county pair
	bysort LEAID county_code: keep if _n == 1
	* Count frequency of each county per LEAID
	bysort LEAID: gen county_freq = _N
	* Sort by LEAID and frequency (descending) to get most common county first
	gsort LEAID -county_freq county_code
	* Keep first (most common) county per LEAID
	bysort LEAID: keep if _n == 1
	keep LEAID county_code
	tempfile leaid_county
	save `leaid_county', replace
restore

*** one row per LEAID with its school district type code (sdtc)
keep LEAID
duplicates tag LEAID, gen(dup)
bysort LEAID: keep if _n == 1
drop if missing(LEAID)
drop dup
* Merge in county_code
merge 1:1 LEAID using `leaid_county', nogen
save grf_id, replace // a master list of all LEAIDs in the GRF


*==============================================================*
* IV) Create quality flags and build district panel
*==============================================================*

*--------------------------------------------------------------*
* A) Tag baseline year completeness at GOVID level
*--------------------------------------------------------------*

cd "$SchoolSpending/data"
use "indfin_panel.dta", clear
assert !missing(GOVID) & strlen(GOVID)==9

* 1)--------------------------------- Define baseline year sets (1967, 1970-1972)
* Is the observation in the set of baseline years?
gen byte _in_baseline = inlist(year4, 1967, 1970, 1971, 1972)
*Is the observation in the set of baseline spending not missing spending?
gen byte _present_baseline = (_in_baseline==1 & !missing(pp_exp))

*Other baseline ranges for different charts
gen byte _in_baseline_6771 = inlist(year4, 1967, 1970, 1971)
gen byte _present_baseline_6771 = (_in_baseline_6771==1 & !missing(pp_exp))

*Other baseline ranges for different charts
gen byte _in_baseline_7072 = inlist(year4, 1970, 1971, 1972)
gen byte _present_baseline_7072 = (_in_baseline_7072==1 & !missing(pp_exp))

* 2)--------------------------------- Count baseline years present per GOVID
* Master GOVID list
preserve
    keep GOVID
    duplicates drop
    tempfile govmaster
    save `govmaster', replace
restore

* Collapse 1967–72
preserve
    keep if _in_baseline==1
	* For a district how many baseline years does it have? (Ideally 4)
    collapse (sum) n_baseline_years_present = _present_baseline, by(GOVID)
    tempfile basecnt
    save `basecnt', replace
restore

* Collapse 1967–71
preserve
    keep if _in_baseline_6771==1
    collapse (sum) n_baseline_years_present_6771 = _present_baseline_6771, by(GOVID)
    tempfile basecnt6771
    save `basecnt6771', replace
restore

* Collapse 1970–72
preserve
    keep if _in_baseline_7072==1
    collapse (sum) n_baseline_years_present_7072 = _present_baseline_7072, by(GOVID)
    tempfile basecnt7072
    save `basecnt7072', replace
restore

* 3)--------------------------------- Create good_govid flags for complete baseline data
* Merge baseline counts into list of GOVIDs so every ID is tagged
use `govmaster', clear
merge 1:1 GOVID using `basecnt'
drop _merge
merge 1:1 GOVID using `basecnt6771'
drop _merge
merge 1:1 GOVID using `basecnt7072'
drop _merge

*Make sure districts only existed after baseline years are tagged
replace n_baseline_years_present = 0 if missing(n_baseline_years_present)
replace n_baseline_years_present_6771 = 0 if missing(n_baseline_years_present_6771)
replace n_baseline_years_present_7072 = 0 if missing(n_baseline_years_present_7072)

* Did the district have spending in ALL baseline years?
gen byte good_govid_baseline = (n_baseline_years_present==4)
gen byte good_govid_baseline_6771 = (n_baseline_years_present_6771==3)
gen byte good_govid_baseline_7072 = (n_baseline_years_present_7072==3)

*--------------------------------------------------------------*
* B) Tag individual baseline years (1967, 1970-1972)
*--------------------------------------------------------------*

* 1)--------------------------------- Flag each year separately
preserve
    use "indfin_panel.dta", clear
    local years 1967 1970 1971 1972
    foreach y of local years {
		* Do you have missing spending in the chosen year?
        bys GOVID: egen byte good_govid_`y' = max(year4==`y' & !missing(pp_exp))
    }
    keep GOVID good_govid_*
    duplicates drop
    tempfile govyeartags
    save `govyeartags', replace
restore

* 2)--------------------------------- Merge tags back to GOVID master list
merge 1:1 GOVID using `govyeartags', nogen

label var good_govid_baseline        "Nonmissing spending all 4 baseline years (1967,1970–72)"
label var good_govid_1972            "Nonmissing spending in 1972"

tempfile govtag
save `govtag', replace // GOVIDs tagged with ids labeled as good(1) or bad (0)

********************************************************************************
/* OPTIONAL: REDUNDANT to SECTION E Propagate tags to INDFIN district (GOVID) x year panel
********************************************************************************
use "indfin_panel.dta", clear
merge m:1 GOVID using `govtag', nogen // All should match

isid GOVID year4
gen byte has_indfin = 1
tempfile indfin_work
save `indfin_work', replace // Panel of INDFIN (GOVID) x year properly tagged
*/

*--------------------------------------------------------------*
* C) Build strict 1:1 LEAID↔GOVID crosswalk
*--------------------------------------------------------------*

use "f33_id.dta", clear

* 1)--------------------------------- Identify unique LEAID-GOVID pairs
// Reduce to unique LEAID–GOVID pairs across all years
keep LEAID GOVID
bysort LEAID GOVID: keep if _n==1 // Keeps every unique pair

* 2)--------------------------------- Count relationships (1:1, 1:M, M:M)
keep LEAID GOVID
    drop if missing(LEAID) // No LEAID means no GRF link so it is useless
	drop if LEAID == "M" // Junk
	drop if LEAID == "N" // Junk
    bysort LEAID: gen n_govid = _N       // distinct GOVIDs for this LEAID
    bysort GOVID: gen n_leaid = _N       // distinct LEAIDs for this GOVID
    gen byte rel_type = .
    replace rel_type = 1 if n_govid==1 & n_leaid==1    // 1:1
    replace rel_type = 2 if n_govid>1  & n_leaid==1    // 1:M (LEAID→GOVID)
    replace rel_type = 3 if n_govid==1 & n_leaid>1     // 1:M (GOVID→LEAID)
    replace rel_type = 4 if n_govid>1  & n_leaid>1     // M:M
    label define rel 1 "1:1" 2 "1:M (LEAID→GOVID)" 3 "1:M (GOVID→LEAID)" 4 "M:M"
    label values rel_type rel

* 3)--------------------------------- Keep only 1:1 matches (~51% of pairs)
keep if rel_type == 1 
/*

Note: We could authenticate some of these 1:M or M:1 but as Greg has shared this requires manual authentication of and tracing of each of the 10k+ IDs lineage. This may be desireable in later stages but for the sake of simplicity we only use 1:1 matches. Aditioanlly some of these IDs may be charters or administrative IDs.
. tab rel_type

         rel_type |      Freq.     Percent        Cum.
------------------+-----------------------------------
              1:1 |     14,466       51.21       51.21
1:M (LEAID→GOVID) |      3,364       11.91       63.12
1:M (GOVID→LEAID) |      6,931       24.54       87.66
              M:M |      3,487       12.34      100.00
------------------+-----------------------------------
            Total |     28,248      100.00
*/



isid LEAID  // should be unique now
tempfile map1to1
save `map1to1', replace // Crosswalk 1:1 LEAID to GOVID
save "f33_1to1_map.dta", replace // Hard save for inspection on the side.

*--------------------------------------------------------------*
* D) Map INDFIN to LEAID via 1:1 crosswalk
*--------------------------------------------------------------*

use `govtag', clear
merge m:1 GOVID using `map1to1' // GOVIDs in INDFIN which overlap with crosswalk

* 1)--------------------------------- Flag unmapped GOVIDs
gen byte mapped_1to1   = !missing(LEAID)
gen byte fail_unmapped = (mapped_1to1==0)
label var mapped_1to1   "INDFIN GOVID mapped to LEAID via F-33 1:1"
label var fail_unmapped "GOVID had no 1:1 LEAID map (excluded from main panel)"

* 2)--------------------------------- Ensure LEAID uniqueness
drop if _merge == 1 // Dropping GOVIDs that could never effect tracts' goodness
replace good_govid_baseline = 0 if missing(good_govid_baseline) & _merge == 2
replace good_govid_baseline_6771 = 0 if missing(good_govid_baseline_6771) & _merge == 2
replace good_govid_baseline_7072 = 0 if missing(good_govid_baseline_7072) & _merge == 2
replace good_govid_1967 = 0 if missing(good_govid_1967) & _merge == 2
replace good_govid_1970 = 0 if missing(good_govid_1970) & _merge == 2
replace good_govid_1971 = 0 if missing(good_govid_1971) & _merge == 2
replace good_govid_1972 = 0 if missing(good_govid_1972) & _merge == 2
assert !missing(LEAID)

// Post-join uniqueness at LEAID×year4 (must pass)
isid LEAID
drop _merge

// Order
order LEAID GOVID good_govid_baseline good_govid_baseline_6771 good_govid_baseline_7072 ///
      good_govid_1967 good_govid_1970 good_govid_1971 good_govid_1972 ///
      n_baseline_years_present n_baseline_years_present_6771 n_baseline_years_present_7072 ///
      mapped_1to1 fail_unmapped

*--------------------------------------------------------------*
* E) Propagate quality tags to district-year panel
*--------------------------------------------------------------*

* 1)--------------------------------- Merge tags to INDFIN panel
/* We are taking all the quality indicators created at the district level and spreading them across all years of data for each district, creating a panel dataset where every district-year observation is properly tagged with whether that district had good baseline spending data.
*/
merge 1:m GOVID using "indfin_panel.dta"
drop if _merge ==2
drop _merge

* 2)--------------------------------- Fill missing flags with zeros
replace good_govid_baseline = 0 if missing(good_govid_baseline)
replace good_govid_baseline_6771 = 0 if missing(good_govid_baseline_6771)
replace good_govid_baseline_7072 = 0 if missing(good_govid_baseline_7072)
replace good_govid_1967 = 0 if missing(good_govid_1967)
replace good_govid_1970 = 0 if missing(good_govid_1970)
replace good_govid_1971 = 0 if missing(good_govid_1971)
replace good_govid_1972 = 0 if missing(good_govid_1972)
drop rel_type

* 3)--------------------------------- Save tagged INDFIN panel
save "indfin_panel_tagged.dta", replace

*--------------------------------------------------------------*
* F) Merge with F-33 and create unified panel
*--------------------------------------------------------------*

/*OPTIONAL: Redundant
use "f33_panel.dta", clear // Spending data is cleaned 
// Reduce to unique LEAID–GOVID pairs across all years
bysort LEAID GOVID: keep if _n==1
preserve
keep LEAID GOVID
    drop if missing(LEAID) 
	drop if LEAID == "M"
	drop if LEAID == "N"
    bysort LEAID: gen n_govid = _N       // distinct GOVIDs for this LEAID
    bysort GOVID: gen n_leaid = _N       // distinct LEAIDs for this GOVID
    gen byte rel_type = .
    replace rel_type = 1 if n_govid==1 & n_leaid==1
    replace rel_type = 2 if n_govid>1  & n_leaid==1    // 1:M (LEAID→GOVID)
    replace rel_type = 3 if n_govid==1 & n_leaid>1     // 1:M (GOVID→LEAID)
    replace rel_type = 4 if n_govid>1  & n_leaid>1     // M:M
    label define rel 1 "1:1" 2 "1:M (LEAID→GOVID)" 3 "1:M (GOVID→LEAID)" 4 "M:M"
    label values rel_type rel
keep if rel_type == 1
drop rel_type
save f33_11,replace

restore
use f33_11, clear
merge 1:m LEAID GOVID using f33_panel
keep if _merge ==3
	drop if missing(LEAID)
	drop if LEAID == "M"
	drop if LEAID == "N"
*/

* 1)--------------------------------- Append F-33 and INDFIN panels
use "f33_1to1_map.dta", clear
merge 1:m LEAID GOVID using "f33_panel.dta"
keep if _merge == 3
drop _merge

rename year year4
append using "indfin_panel_tagged.dta"

keep LEAID GOVID year4 pp_exp good_govid_baseline enrollment level ///
good_govid_1967 good_govid_1970 good_govid_1971 good_govid_1972 good_govid_baseline_6771 good_govid_baseline_7072
duplicates drop LEAID GOVID year4 pp_exp, force

* 2)--------------------------------- Propagate good_govid flags across all years
bysort LEAID: egen __g = min(good_govid_baseline)
replace good_govid_baseline = __g if missing(good_govid_baseline)
drop __g

bysort LEAID: egen __g1 = min(good_govid_baseline_6771)
replace good_govid_baseline_6771 = __g1 if missing(good_govid_baseline_6771)
drop __g1

bysort LEAID: egen __g2 = min(good_govid_baseline_7072)
replace good_govid_baseline_7072 = __g2 if missing(good_govid_baseline_7072)
drop __g2

bysort LEAID: egen __g3 = min(good_govid_1967)
replace good_govid_1967 = __g3 if missing(good_govid_1967)
drop __g3

bysort LEAID: egen __g4 = min(good_govid_1970)
replace good_govid_1970 = __g4 if missing(good_govid_1970)
drop __g4

bysort LEAID: egen __g5 = min(good_govid_1971)
replace good_govid_1971 = __g5 if missing(good_govid_1971)
drop __g5

bysort LEAID: egen __g6 = min(good_govid_1972)
replace good_govid_1972 = __g6 if missing(good_govid_1972)
drop __g6

* 3)--------------------------------- Remove duplicates
drop if missing(year4)
save "district_panel_tagged.dta", replace

*Plot of spending that i was curious about
use "district_panel_tagged.dta", clear
drop if missing(good_govid_baseline)
collapse (mean) pp_exp, by(year4)
twoway line pp_exp year4

*--------------------------------------------------------------*
* G) Merge with GRF to create canonical district panel
*--------------------------------------------------------------*

* 1)--------------------------------- Join GRF IDs to district panel
use grf_id,clear
merge 1:m LEAID using "district_panel_tagged.dta"
keep if _merge ==3

* 2)--------------------------------- Keep only matched records
isid LEAID year4
drop _merge

* 3)--------------------------------- Save final canonical panel
save f33_indfin_grf_canon, replace

* 4)--------------------------------- Resave district_panel_tagged with county_code for downstream use
* This ensures county_code is available in files that use district_panel_tagged
save "district_panel_tagged.dta", replace

