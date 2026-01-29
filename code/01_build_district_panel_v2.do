/*==============================================================================
Project    : School Spending – District Panel Construction and ID Crosswalks
File       : 01_build_district_panel_v2.do
Purpose    : EFFICIENT VERSION - Build the foundation district-year panel by
             harmonizing NCES F-33 (1992-2019) and INDFIN (1967-1991) data sources
             and creating canonical crosswalks between incompatible district ID systems.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-01-21
───────────────────────────────────────────────────────────────────────────────

EFFICIENCY IMPROVEMENTS OVER ORIGINAL:
  1. SAS files imported ONCE (not twice)
  2. Append operations use tempfile collection, not repeated disk writes
  3. All baseline flags computed in single pass (not 4 separate preserve/restore)
  4. Flag propagation uses loops instead of 7 copy-paste blocks
  5. Eliminated redundant intermediate saves
  6. Combined related operations to reduce data passes

METHODOLOGICAL CHANGE FROM ORIGINAL:
  The 1:1 crosswalk construction now applies CONSISTENT junk-cleaning logic:
  - Original: Counted LEAID-GOVID relationships BEFORE dropping junk GOVIDs ("N", missing)
  - V2: Drops junk LEAIDs AND junk GOVIDs BEFORE counting relationships

  This means districts with one valid GOVID plus a junk placeholder (e.g., "N")
  are now correctly classified as 1:1 and INCLUDED in the panel.

  Result: +104 districts in final output (9,376 vs 9,272)

  Intermediate counts:
    - xwalk_leaid_govid.dta:      14,778 (was 14,466, +312)
    - district_panel_tagged: 14,689 unique LEAIDs (was 14,321, +368)
    - dist_panel:   9,376 unique LEAIDs (was 9,272, +104)

OUTPUTS:
  - f33_panel.dta                  # F-33 district-year panel (1992-2019)
  - indfin_panel.dta               # INDFIN district-year panel (1967-1991)
  - xwalk_leaid_govid.dta               # 1:1 LEAID ↔ GOVID mapping (+312 vs original)
  - dist_panel.dta       # UNIFIED panel with quality flags (+104 districts)
==============================================================================*/

clear all
set more off

*==============================================================*
* I) Build F-33 NCES panel (1992-2019) - SINGLE PASS
*==============================================================*

cd "$SchoolSpending/data/raw/nces/build_f33_in_dir"

* 1)--------------------------------- Import SAS files ONCE and collect in tempfiles
local files : dir "." files "*.sas7bdat"
local filelist ""
local i = 1

foreach f of local files {
    disp "Processing `f'"

    * Extract year from filename (e.g., "sdf92.sas7bdat" → 1992)
    local shortyr = substr("`f'", 4, 2)
    local year = cond(real("`shortyr'") < 50, 2000 + real("`shortyr'"), 1900 + real("`shortyr'"))

    import sas using "`f'", clear

    * Standardize county variable name
    capture rename FIPSCO county_id
    capture rename CONUM county_id

    * Standardize county_id to 3 digits
    tostring county_id, replace
    replace county_id = trim(county_id)
    replace county_id = substr("000" + county_id, -3, 3)

    * Keep needed variables
    keep LEAID CENSUSID NAME V33 TOTALEXP SCHLEV county_id
    gen year = `year'

    * Save to tempfile
    tempfile tf`i'
    save `tf`i'', replace
    local filelist "`filelist' `tf`i''"
    local ++i
}

* 2)--------------------------------- Append all tempfiles at once
local first : word 1 of `filelist'
use `first', clear
foreach tf of local filelist {
    if "`tf'" == "`first'" continue
    append using `tf'
}

* 3)--------------------------------- Clean and construct per-pupil expenditure
* Reconstruct full 5-digit FIPS
gen state_code = substr(LEAID, 1, 2)
replace county_id = state_code + county_id
drop state_code

* Drop bad observations
drop if V33 < 0 | TOTALEXP < 0

* Calculate per-pupil expenditure (in $1000s)
gen pp_exp = (TOTALEXP/1000) / V33
label var pp_exp "Per-pupil expenditure"

drop if year < 1992

* Extract 9-digit GOVID from 14-digit CENSUSID
gen str9 GOVID = substr(CENSUSID, 1, 9)
rename V33 enrollment
rename SCHLEV level

cd "$SchoolSpending/data"
save f33_panel, replace

* 4)--------------------------------- Build ID crosswalk (reuse data in memory)
* Extract unique LEAID-GOVID pairs for crosswalk
keep LEAID CENSUSID NAME year
gen str9 GOVID = substr(CENSUSID, 1, 9)
save f33_id, replace


*==============================================================*
* II) Build INDFIN historical panel (1967-1991)
*==============================================================*

local years 67 70 71 72 73 74 75 76 77 78 79 80 81 82 83 84 85 86 87 88 89 90 91
local inDir  "$SchoolSpending/data/raw/indfin/build_indfin_in_dir"
local outDir "$SchoolSpending/data/raw/indfin/build_indfin_out_dir"

local keepvars sortcode year4 id idchanged statecode typecode county name ///
    population elemeductotalexp totalexpenditure totaleductotalexp

* 1)--------------------------------- Load, filter, and collect in tempfiles
local filelist ""
local i = 1

foreach y of local years {
    di as txt "→ processing INDFIN `y'"
    use "`inDir'/indfin`y'a.dta", clear
    keep if typecode == 5
    keep `keepvars'

    tempfile inf`i'
    save `inf`i'', replace
    local filelist "`filelist' `inf`i''"
    local ++i
}

* 2)--------------------------------- Append all at once
local first : word 1 of `filelist'
use `first', clear
foreach tf of local filelist {
    if "`tf'" == "`first'" continue
    append using `tf'
}

* 3)--------------------------------- Create GOVID and per-pupil expenditure
gen str9 GOVID = string(id, "%09.0f")
gen pp_exp = totalexpenditure / population
label var pp_exp "Per-pupil expenditure"
rename population enrollment

cd "$SchoolSpending/data"
save indfin_panel, replace


*==============================================================*
* III) Import Geographic Reference File (GRF)
*==============================================================*

clear
local dfile "$SchoolSpending/data/raw/GRF69/DS0001/03515-0001-Data.txt"

infix ///
    byte  stc70  1-2      ///
    byte  stc60  3-4      ///
    int   coc70  5-7      ///
    int   ctabu  8-10     ///
    byte  cencc  11       ///
    int   mcd    12-14    ///
    int   placc  15-18    ///
    byte  platc  19       ///
    str2  plasc  20-21    ///
    str1  stcac  22-22    ///
    str4  smsa   23-26    ///
    int   urbca  27-30    ///
    int   trac   31-34    ///
    byte  uniap  35       ///
    int   uniac  36-40    ///
    str2  steac  41-42    ///
    str3  ecosc  43-45    ///
    str1  cebdc  46-46    ///
    str30 arnam  47-76    ///
    long  btc    77-80    ///
    int   tsc    81-82    ///
    byte  blgc   83       ///
    str5  endc   84-88    ///
    str1  urrc   89-89    ///
    int   warc   90-91    ///
    int   codc   92-93    ///
    long  houc   94-100   ///
    long  popc   101-108  ///
    long  sdc    109-113  ///
    byte  sdtc   114-114  ///
    int   aduc   115-116  ///
    int   perc   117-119  ///
using "`dfile'", clear

* Label key variables
label variable stc70  "1970 State Code"
label variable coc70  "1970 County Code"
label variable btc    "Basic Tract Code"
label variable tsc    "Tract Suffix Code"
label variable sdc    "School District Code"
label variable sdtc   "School District Type Code"
label variable popc   "Population Count"

* 1)--------------------------------- Clean tract codes and drop special areas
gen no_tract = missing(btc)
replace btc = 0 if missing(btc)
replace tsc = 0 if missing(tsc)

* Drop special geographic areas in one step
drop if tsc == 99 | (tsc >= 70 & tsc <= 98) | btc >= 9500

* 2)--------------------------------- Build composite ID strings
gen str4 btc_str = string(btc, "%04.0f")
gen str2 tsc_str = string(tsc, "%02.0f")
gen str5 sdc_str = string(sdc, "%05.0f")

* Census 11-digit unique tract identifier
gen str11 tract70 = string(stc70, "%02.0f") + string(coc70, "%03.0f") + btc_str + tsc_str

* GIS join format
gen str13 gisjoin2 = string(stc70, "%02.0f") + "0" + string(coc70, "%03.0f") + "0" + btc_str + tsc_str
replace gisjoin2 = substr(gisjoin2, 1, 11) if substr(gisjoin2, -2, 2) == "00"

* NCES LEAID
gen str7 LEAID = string(stc70, "%02.0f") + sdc_str

* 3)--------------------------------- Save GRF outputs
gen str5 county_code = string(stc70, "%02.0f") + string(coc70, "%03.0f")

preserve
    keep LEAID tract70 county_code no_tract
    save "$SchoolSpending/data/grf_id_tractlevel", replace
restore

preserve
    keep LEAID sdtc
    save "$SchoolSpending/data/sdtc", replace
restore

* Master list of LEAIDs in GRF
keep LEAID
drop if missing(LEAID)
bysort LEAID: keep if _n == 1
save "$SchoolSpending/data/grf_id", replace


*==============================================================*
* IV) Create quality flags - SINGLE PASS
*==============================================================*

cd "$SchoolSpending/data"
use "indfin_panel.dta", clear
assert !missing(GOVID) & strlen(GOVID) == 9

* 1)--------------------------------- Compute ALL baseline flags in one collapse
* Create indicators for each baseline year having non-missing spending
gen byte has_1967 = (year4 == 1967 & !missing(pp_exp))
gen byte has_1970 = (year4 == 1970 & !missing(pp_exp))
gen byte has_1971 = (year4 == 1971 & !missing(pp_exp))
gen byte has_1972 = (year4 == 1972 & !missing(pp_exp))

* Single collapse to get all flags at GOVID level
collapse (max) has_1967 has_1970 has_1971 has_1972, by(GOVID)

* Create composite flags
gen byte n_baseline_years_present = has_1967 + has_1970 + has_1971 + has_1972
gen byte n_baseline_years_present_6771 = has_1967 + has_1970 + has_1971
gen byte n_baseline_years_present_7072 = has_1970 + has_1971 + has_1972

gen byte good_govid_baseline = (n_baseline_years_present == 4)
gen byte good_govid_baseline_6771 = (n_baseline_years_present_6771 == 3)
gen byte good_govid_baseline_7072 = (n_baseline_years_present_7072 == 3)

* Rename individual year flags
rename has_1967 good_govid_1967
rename has_1970 good_govid_1970
rename has_1971 good_govid_1971
rename has_1972 good_govid_1972

label var good_govid_baseline "Nonmissing spending all 4 baseline years (1967,1970-72)"
label var good_govid_1967 "Nonmissing spending in 1967"
label var good_govid_1970 "Nonmissing spending in 1970"
label var good_govid_1971 "Nonmissing spending in 1971"
label var good_govid_1972 "Nonmissing spending in 1972"

tempfile govtag
save `govtag', replace


*==============================================================*
* V) Build 1:1 LEAID↔GOVID crosswalk
*==============================================================*

use "f33_id.dta", clear

* 1)--------------------------------- Get unique LEAID-GOVID pairs and drop junk
keep LEAID GOVID
drop if missing(LEAID) | inlist(LEAID, "M", "N")
drop if missing(GOVID) | GOVID == "N"
bysort LEAID GOVID: keep if _n == 1

* 2)--------------------------------- Count relationships (after cleaning junk)
bysort LEAID: gen n_govid = _N
bysort GOVID: gen n_leaid = _N

* 3)--------------------------------- Keep only 1:1 matches
keep if n_govid == 1 & n_leaid == 1
drop n_govid n_leaid

isid LEAID
tempfile map1to1
save `map1to1', replace
save "xwalk_leaid_govid.dta", replace


*==============================================================*
* VI) Merge crosswalk with quality flags
*==============================================================*

* Merge GOVID tags with 1:1 crosswalk
use `govtag', clear
merge m:1 GOVID using `map1to1'

* Flag mapping status
gen byte mapped_1to1 = !missing(LEAID)
gen byte fail_unmapped = (mapped_1to1 == 0)
label var mapped_1to1 "INDFIN GOVID mapped to LEAID via F-33 1:1"
label var fail_unmapped "GOVID had no 1:1 LEAID map"

* Drop GOVIDs without LEAID (can't link to tracts)
drop if _merge == 1

* Fill missing flags for using-only observations
local flagvars good_govid_baseline good_govid_baseline_6771 good_govid_baseline_7072 ///
               good_govid_1967 good_govid_1970 good_govid_1971 good_govid_1972
foreach v of local flagvars {
    replace `v' = 0 if missing(`v') & _merge == 2
}
drop _merge

assert !missing(LEAID)
isid LEAID

* Get county_id from F-33
preserve
    use "f33_panel.dta", clear
    keep LEAID county_id
    drop if missing(county_id)
    bysort LEAID county_id: gen n = _N
    bysort LEAID: egen max_n = max(n)
    keep if n == max_n
    duplicates drop LEAID, force
    drop n max_n
    tempfile county_map
    save `county_map', replace
restore

merge m:1 LEAID using `county_map', keepusing(county_id) keep(master match) nogen

tempfile crosswalk_with_flags
save `crosswalk_with_flags', replace


*==============================================================*
* VII) Build unified district-year panel
*==============================================================*

* 1)--------------------------------- Merge flags to INDFIN panel
use `crosswalk_with_flags', clear
merge 1:m GOVID using "indfin_panel.dta"
drop if _merge == 2
drop _merge

* Fill any remaining missing flags
local flagvars good_govid_baseline good_govid_baseline_6771 good_govid_baseline_7072 ///
               good_govid_1967 good_govid_1970 good_govid_1971 good_govid_1972
foreach v of local flagvars {
    replace `v' = 0 if missing(`v')
}

save "indfin_panel_tagged.dta", replace

* 2)--------------------------------- Append F-33 panel
use "xwalk_leaid_govid.dta", clear
merge 1:m LEAID GOVID using "f33_panel.dta"
keep if _merge == 3
drop _merge
rename year year4

append using "indfin_panel_tagged.dta"

* Keep essential variables
keep LEAID GOVID county_id year4 pp_exp enrollment level ///
     good_govid_baseline good_govid_baseline_6771 good_govid_baseline_7072 ///
     good_govid_1967 good_govid_1970 good_govid_1971 good_govid_1972

duplicates drop LEAID GOVID year4 pp_exp, force

* 3)--------------------------------- Propagate flags across all years (using loop)
local flagvars good_govid_baseline good_govid_baseline_6771 good_govid_baseline_7072 ///
               good_govid_1967 good_govid_1970 good_govid_1971 good_govid_1972

foreach v of local flagvars {
    bysort LEAID: egen __temp = max(`v')
    replace `v' = __temp if missing(`v')
    drop __temp
}

drop if missing(year4)
save "district_panel_tagged.dta", replace


*==============================================================*
* VIII) Create final canonical panel with GRF
*==============================================================*

use "$SchoolSpending/data/grf_id", clear
isid LEAID
merge 1:m LEAID using "district_panel_tagged.dta"

* Save districts NOT in GRF (using-only) for reference
preserve
    keep if _merge == 2
    drop _merge
    save "district_panel_not_in_grf.dta", replace
    di as result "Saved " _N " obs (" r(N) " districts) not in GRF to district_panel_not_in_grf.dta"
restore

keep if _merge == 3
drop _merge

isid LEAID year4
save dist_panel, replace

di as result "✓ Pipeline complete. Final output: dist_panel.dta"
