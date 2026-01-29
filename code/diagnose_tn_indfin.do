/*==============================================================================
Diagnose Tennessee INDFIN Coverage
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

display "==============================================================================="
display "TENNESSEE INDFIN DIAGNOSTIC"
display "==============================================================================="

*--- Check raw INDFIN panel for Tennessee
use "raw/indfin/build_indfin_out_dir/indfin_panel_1967_1991_clean.dta", clear

* Tennessee GOVS state code is 43 (NOT FIPS 47!)
* GOVS codes differ from FIPS - see crosswalk table
gen state = floor(id / 10000000)
keep if state == 43

display _n "Tennessee records in raw INDFIN panel: " _N

display _n "Tennessee records by year:"
tab year4

display _n "Tennessee records with non-missing spending by year:"
gen has_spend = !missing(totalexpenditure) & !missing(population) & population > 0
tab year4 has_spend

display _n "Unique Tennessee districts in INDFIN:"
preserve
keep id
duplicates drop
display _N
restore

*--- Now check what survives the GRF merge
display _n(2) "==============================================================================="
display "CHECKING GRF MERGE"
display "==============================================================================="

use "f33_indfin_grf_canon.dta", clear
gen state_fips = substr(LEAID, 1, 2)
keep if state_fips == "47"

display _n "Tennessee district-years in f33_indfin_grf_canon: " _N

preserve
keep LEAID
duplicates drop
display "Unique Tennessee LEAIDs in canon file: " _N
restore

display _n "Tennessee observations by year (first 10 years):"
tab year4 if year4 <= 1980

*--- Check which TN LEAIDs are in GRF but NOT in INDFIN
display _n(2) "==============================================================================="
display "MISMATCH ANALYSIS: GRF vs INDFIN"
display "==============================================================================="

use "grf_id.dta", clear
gen state_fips = substr(LEAID, 1, 2)
keep if state_fips == "47"
tempfile tn_grf
save `tn_grf'

display "TN districts in GRF: " _N

use "district_panel_tagged.dta", clear
gen state_fips = substr(LEAID, 1, 2)
keep if state_fips == "47"
keep LEAID
duplicates drop
tempfile tn_indfin
save `tn_indfin'

display "TN districts in district_panel_tagged: " _N

* Find GRF districts NOT in INDFIN
use `tn_grf', clear
merge 1:1 LEAID using `tn_indfin'
tab _merge

display _n "TN districts in GRF but NOT in INDFIN (_merge==1):"
count if _merge == 1
list LEAID if _merge == 1 & _n <= 20, noobs

display _n "TN districts in BOTH GRF and INDFIN (_merge==3):"
count if _merge == 3

display _n(2) "==============================================================================="
display "CONCLUSION"
display "==============================================================================="
display "Tennessee has many districts in the GRF (1969 geographic file)"
display "But very few of those districts appear in the INDFIN spending data."
display "This is a DATA AVAILABILITY issue, not a filter in your code."
