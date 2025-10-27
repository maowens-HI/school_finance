*** ---------------------------------------------------------------------------
*** 1. Build f33 panel
*** ---------------------------------------------------------------------------


clear
set more off

*** Import
cd "$SchoolSpending\data\raw\nces\build_f33_in_dir"

local files : dir "." files "*.sas7bdat"

foreach f of local files {
    disp "Processing `f'"
    
    import sas using "`f'", clear

    local outname = subinstr("`f'", ".sas7bdat", ".dta", .)
    save "`outname'", replace
}

*** Append all F-33 files into one panel

local files : dir "." files "*.dta"
tempfile base

local first = 1
foreach f of local files {
    disp "Processing `f'"

    * Try to pull year (example: "sdf92.dta" → 1992)
    local shortyr = substr("`f'", 4, 2)
    local year = cond(real("`shortyr'") < 50, 2000 + real("`shortyr'"), 1900 + real("`shortyr'"))

    use LEAID CENSUSID NAME V33 TOTALEXP using "`f'", clear
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


cd "$SchoolSpending\data"

*** Flag anomalies, don't drop them
gen bad_pop   = (V33 <= 0)        // zero or negative pop
*gen bad_exp   = (TOTALEXP < 0)    // negative expenditure

label var bad_pop "Flag: zero or negative population"


*** Vars
gen pp_exp = .
replace pp_exp = TOTALEXP/1000 / V33 if V33 > 0
label var pp_exp "Per-pupil expenditure (valid only if V33>0)"

gen str9 GOVID = substr(CENSUSID,1,9)

save f33_panel, replace




*** ---------------------------------------------------------------------------
*** 2. Build indifn panel
*** ---------------------------------------------------------------------------

***Settings

local years 67 70 71 72 73 74 75 76 77 78 79 ///
            80 81 82 83 84 85 86 87 88 89   ///
            90 91   // 68 & 69 skipped

local inDir  "$SchoolSpending\data\raw\indfin\build_indfin_in_dir"
local outDir "$SchoolSpending\data\raw\indfin\build_indfin_out_dir"

local keepvars ///
    sortcode year4 id idchanged statecode typecode county name ///
    population elemeductotalexp totalexpenditure totaleductotalexp
	
*** Trim Each Year
foreach y of local years {
    di as txt "→ trimming `y'"
    use "`inDir'/indfin`y'a.dta", clear
    keep if typecode == 5                     // focus on school districts
    keep `keepvars'
    save "`outDir'/f`y'.dta", replace
}

*** Stack into one panel
local first : word 1 of `years'
use "`outDir'/f`first'.dta", clear

foreach y of local years {
    if "`y'" == "`first'" continue
    append using "`outDir'/f`y'.dta"
}

save "`outDir'/indfin_panel_1967_1991_clean.dta", replace
di as result "✓ INDFIN panel (1967‑1991) complete."

*tostring id, replace
gen str9 GOVID = string(id, "%09.0f")
*gen GOVID = substr(id,1,9) Old GOVID messing stuff up for 0N states



cd "$SchoolSpending\data"

save indfin_panel, replace



/*-------------------------------------------------------------------------------
File     : 03_build_f33_crosswalk.do
Purpose  : Construct raw crosswalk linking LEAID to CENSUSID (F-33)
Inputs   : raw NCES F-33 SAS files (*.sas7bdat)
Outputs  : f33_crosswalk_raw.dta
Requires : None
Notes    : - Appends yearly crosswalks into one file
           - Adds year variable from file names
           - Maintains panel structure for later cleaning
-------------------------------------------------------------------------------*/
*** ---------------------------------------------------------------------------
*** 1. Import F33 Data
*** ---------------------------------------------------------------------------

* Import
clear
set more off

*** Import
cd "$SchoolSpending\data\raw\nces\build_f33_in_dir"

local files : dir "." files "*.sas7bdat"

foreach f of local files {
    disp "Processing `f'"
    
    import sas using "`f'", clear

    local outname = subinstr("`f'", ".sas7bdat", ".dta", .)
    save "`outname'", replace
}

*** Append all F-33 files into one panel

local files : dir "." files "*.dta"
tempfile base

local first = 1
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



*Data
cd "$SchoolSpending\data"
gen str9 GOVID = substr(CENSUSID,1,9)


save f33_id, replace
*** ---------------------------------------------------------------------------
*** 2. Import master INDFIN ID list
*** ---------------------------------------------------------------------------

clear
set more off

cd "$SchoolSpending\data"





import delimited using "$SchoolSpending\data\ALLids.csv"
gen str9 GOVID = string(id, "%09.0f")
keep if typecode == 5 

drop id idchanged typecode county censusreg statecode ///
version population jacketunit zerodata


save indfin_id, replace



*** ---------------------------------------------------------------------------
*** 3. Import master GRF
*** ---------------------------------------------------------------------------


/*-------------------------------------------------------------------------------
File     : 05_grf_districts.do
Purpose  : Build a dataset of all school districts from the Geographic Reference 
           File (GRF).
Inputs   : 03515-0001-Data.txt   (GRF fixed-width ASCII, ICPSR layout)
Outputs  : grf_districts.dta     (district-level file with LEAIDs and type flag)
Requires : none
Notes    : - Imports raw GRF fixed-width file
           - Constructs district identifiers (LEAID, tract70, gisjoin2)
           - Aggregates tract rows up to the district level
           - Produces one row per district with 1969 tract population
-------------------------------------------------------------------------------*/

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



*** Basic Tract Code (btc) should be 4 digits; if missing, treat as 0000
*** Tract-Suffix Code (tsc) should be 2 digits; if missing, treat as 00  
replace btc = 0  if missing(btc)
replace tsc = 0 if tsc == .
gen no_tract = 0
replace no_tract = 1 if missing(trac)

*** Build padded strings 
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

	



*** one row per LEAID with its district-type flag (sdtc)
duplicates drop LEAID, force
keep LEAID arnam
save grf_id, replace



*** ---------------------------------------------------------------------------
*** 3. Buidl crosswalk GOVID x LEAID
*** ---------------------------------------------------------------------------

**# Bookmark #1
*=============================*
* Start
*=============================*
use f33_id, clear
drop CENSUSID

* 0) Drop exact duplicate rows for the same LEAID–GOVID combo
gsort LEAID GOVID -year
bysort LEAID GOVID: keep if _n==1

*==============================================================*
* 1) Build unique LEAID×GOVID crosswalk and label relationship
*    Types: 1:1, 1:M (LEAID→GOVID), 1:M (GOVID→LEAID), M:M
*==============================================================*
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
    tempfile pairtypes
    save `pairtypes'
restore

* Attach the relationship label to every observation in your panel
merge m:1 LEAID GOVID using `pairtypes'

* Optional sanity check
tab rel_type

*==============================================================*
* 2) Canonical IDs (deterministic, prefer valid over junk)
*    - GOVID_canon: prefer non-junk GOVID; if only junk exists → missing
*    - LEAID_canon: exclude junk LEAID entirely (unusable)
*    Ties break by smallest code.
*==============================================================*

*-------------------------------*
* Canonical GOVID for each LEAID
*-------------------------------*
preserve
    keep LEAID GOVID
    drop if missing(LEAID) | inlist(LEAID,"M","N")   // LEAID must be usable
    duplicates drop LEAID GOVID, force

    contract LEAID GOVID                              // _freq
    gen byte is_govid_junk = missing(GOVID) | inlist(GOVID,"M","N")

    * Sort: within LEAID, prefer non-junk (0), then higher freq, then smallest code
    gsort LEAID is_govid_junk -_freq GOVID
    by LEAID: gen byte pick = _n==1
    keep if pick
    drop pick

    * If all GOVIDs were junk for a LEAID, the top one is still junk.
    * We'll keep it for inspection, but blank it out so canon never equals "M"/"N".
    replace GOVID = "" if is_govid_junk
    drop is_govid_junk

    rename GOVID GOVID_canon
    keep LEAID GOVID_canon
    tempfile canon_leaid
    save `canon_leaid'
restore
merge m:1 LEAID using `canon_leaid', nogen

*-------------------------------*
* Canonical LEAID for each GOVID
*-------------------------------*
preserve
    keep LEAID GOVID
    drop if missing(LEAID) | inlist(LEAID,"M","N")   // junk LEAID unusable
    duplicates drop LEAID GOVID, force

    contract GOVID LEAID
    * Here we can keep junk GOVIDs in the pool; we're choosing a LEAID for each GOVID.
    gsort GOVID -_freq LEAID
    by GOVID: gen byte pick = _n==1
    keep if pick
    drop pick

    rename LEAID LEAID_canon
    keep GOVID LEAID_canon
    tempfile canon_govid
    save `canon_govid'
restore
merge m:1 GOVID using `canon_govid', nogen

* Optional QA flags
gen byte canon_govid_is_junk = inlist(GOVID_canon,"M","N") | missing(GOVID_canon)
gen byte canon_leaid_is_junk = inlist(LEAID_canon,"M","N") | missing(LEAID_canon)
drop _merge
save canon_crosswalk, replace
* If you actually want to collapse onto canon IDs:
* replace GOVID = GOVID_canon if !missing(GOVID_canon)
* replace LEAID = LEAID_canon if !missing(LEAID_canon)

*-------------------------------*
* Merge into indfin
*-------------------------------*
use canon_crosswalk,clear
drop if missing(GOVID)
keep if rel_type ==1
merge 1:m GOVID using indfin_panel
drop if _merge == 1
drop _merge
tempfile indfin_11
save `indfin_11',replace

use canon_crosswalk,clear
drop if missing(GOVID) | inlist(GOVID, "N", "M")
keep if rel_type ==3
duplicates drop GOVID, force
merge 1:m GOVID using `indfin_11'
drop if _merge == 1
drop _merge
tempfile indfin_11_1M
drop year n_govid n_leaid rel_type GOVID_canon
replace LEAID = LEAID_canon if !missing(LEAID_canon)   
tempfile indfin_11_1M           
save `indfin_11_1M',replace

use canon_crosswalk,clear
drop if missing(GOVID) | inlist(GOVID, "N", "M")
keep if rel_type ==2
merge 1:m GOVID using `indfin_11_1M'
drop if _merge == 1
drop _merge
replace GOVID = GOVID_canon if !missing(GOVID_canon)  
drop year n_govid n_leaid rel_type GOVID_canon LEAID_canon
tempfile indfin_11_1M_M1
save `indfin_11_1M_M1',replace

*-------------------------------*
* Merge into F33
*-------------------------------*
use canon_crosswalk,clear
duplicates drop LEAID, force
drop year
merge 1:m LEAID using f33_panel
replace LEAID = LEAID_canon if !missing(LEAID_canon)   
replace GOVID = GOVID_canon if !missing(GOVID_canon)  

rename year year4
rename V33 population
rename TOTALEXP totalexpenditure
drop n_govid n_leaid rel_type GOVID_canon LEAID_canon
append using  `indfin_11_1M_M1'
drop _merge
save f33_indfin_canon, replace


use grf_id,clear
merge 1:m LEAID using f33_indfin_canon
keep if _merge == 3
drop arnam _merge

save f33_indfin_grf_canon, replace
