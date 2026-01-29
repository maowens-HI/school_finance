/*==============================================================================
Project    : School Spending - Diagnose State Coverage
File       : diagnose_all_states.do
Purpose    : Compare state coverage between INDFIN (GOVS codes) and GRF (FIPS codes)
             to identify which states have data availability issues.
Author     : Myles Owens / Claude
Date       : 2026-01-21
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*===============================================================================
* Create GOVS to FIPS crosswalk
*===============================================================================

clear
input byte govs_code str20 state_name byte fips_code
	01	"Alabama"			01
	02	"Alaska"			02
	03	"Arizona"			04
	04	"Arkansas"			05
	05	"California"		06
	06	"Colorado"			08
	07	"Connecticut"		09
	08	"Delaware"			10
	09	"District of Columbia"	11
	10	"Florida"			12
	11	"Georgia"			13
	12	"Hawaii"			15
	13	"Idaho"				16
	14	"Illinois"			17
	15	"Indiana"			18
	16	"Iowa"				19
	17	"Kansas"			20
	18	"Kentucky"			21
	19	"Louisiana"			22
	20	"Maine"				23
	21	"Maryland"			24
	22	"Massachusetts"		25
	23	"Michigan"			26
	24	"Minnesota"			27
	25	"Mississippi"		28
	26	"Missouri"			29
	27	"Montana"			30
	28	"Nebraska"			31
	29	"Nevada"			32
	30	"New Hampshire"		33
	31	"New Jersey"		34
	32	"New Mexico"		35
	33	"New York"			36
	34	"North Carolina"	37
	35	"North Dakota"		38
	36	"Ohio"				39
	37	"Oklahoma"			40
	38	"Oregon"			41
	39	"Pennsylvania"		42
	40	"Rhode Island"		44
	41	"South Carolina"	45
	42	"South Dakota"		46
	43	"Tennessee"			47
	44	"Texas"				48
	45	"Utah"				49
	46	"Vermont"			50
	47	"Virginia"			51
	48	"Washington"		53
	49	"West Virginia"		54
	50	"Wisconsin"			55
	51	"Wyoming"			56
end

tempfile crosswalk
save `crosswalk'

*===============================================================================
* Count districts in INDFIN by GOVS state code
*===============================================================================

display _n(3)
display "==============================================================================="
display "STEP 1: COUNT DISTRICTS IN INDFIN (by GOVS code)"
display "==============================================================================="

use "raw/indfin/build_indfin_out_dir/indfin_panel_1967_1991_clean.dta", clear

* Extract GOVS state code from ID
gen byte govs_code = floor(id / 10000000)

* Count unique districts per state
preserve
keep id govs_code
duplicates drop
bysort govs_code: gen n_indfin = _N
keep govs_code n_indfin
duplicates drop
tempfile indfin_counts
save `indfin_counts'
restore

* Count districts with baseline data (1967, 1970, 1971, 1972)
preserve
keep if inlist(year4, 1967, 1970, 1971, 1972)
keep if !missing(totalexpenditure) & !missing(population) & population > 0

* Count how many baseline years each district has
bysort id: gen n_baseline_years = _N
keep id govs_code n_baseline_years
duplicates drop

* Districts with all 4 baseline years
gen byte has_all_baseline = (n_baseline_years == 4)

bysort govs_code: egen n_indfin_baseline = sum(has_all_baseline)
keep govs_code n_indfin_baseline
duplicates drop
tempfile indfin_baseline
save `indfin_baseline'
restore

*===============================================================================
* Count districts in GRF by FIPS state code
*===============================================================================

display _n(2)
display "==============================================================================="
display "STEP 2: COUNT DISTRICTS IN GRF (by FIPS code)"
display "==============================================================================="

use "grf_id.dta", clear

* Extract FIPS state code from LEAID
gen str2 fips_str = substr(LEAID, 1, 2)
destring fips_str, gen(fips_code)

* Count unique districts per state
bysort fips_code: gen n_grf = _N
keep fips_code n_grf
duplicates drop

tempfile grf_counts
save `grf_counts'

*===============================================================================
* Count districts in district_panel_tagged by FIPS
*===============================================================================

display _n(2)
display "==============================================================================="
display "STEP 3: COUNT DISTRICTS IN DISTRICT_PANEL_TAGGED (by FIPS code)"
display "==============================================================================="

use "district_panel_tagged.dta", clear

gen str2 fips_str = substr(LEAID, 1, 2)
destring fips_str, gen(fips_code)

preserve
keep LEAID fips_code
duplicates drop
bysort fips_code: gen n_tagged = _N
keep fips_code n_tagged
duplicates drop
tempfile tagged_counts
save `tagged_counts'
restore

*===============================================================================
* Count matched districts (in BOTH GRF and district_panel_tagged)
*===============================================================================

display _n(2)
display "==============================================================================="
display "STEP 4: COUNT MATCHED DISTRICTS (GRF ∩ INDFIN/F33)"
display "==============================================================================="

use "f33_indfin_grf_canon.dta", clear

gen str2 fips_str = substr(LEAID, 1, 2)
destring fips_str, gen(fips_code)

preserve
keep LEAID fips_code
duplicates drop
bysort fips_code: gen n_matched = _N
keep fips_code n_matched
duplicates drop
tempfile matched_counts
save `matched_counts'
restore

* Also count districts with good baseline data
preserve
keep LEAID fips_code good_govid_baseline
keep if good_govid_baseline == 1
duplicates drop
bysort fips_code: gen n_good_baseline = _N
keep fips_code n_good_baseline
duplicates drop
tempfile good_baseline_counts
save `good_baseline_counts'
restore

*===============================================================================
* Merge all counts together
*===============================================================================

display _n(2)
display "==============================================================================="
display "STEP 5: MERGE AND CREATE SUMMARY TABLE"
display "==============================================================================="

use `crosswalk', clear

* Merge INDFIN counts (by GOVS code)
merge 1:1 govs_code using `indfin_counts', nogen
merge 1:1 govs_code using `indfin_baseline', nogen

* Merge GRF and other counts (by FIPS code)
merge 1:1 fips_code using `grf_counts', nogen
merge 1:1 fips_code using `tagged_counts', nogen
merge 1:1 fips_code using `matched_counts', nogen
merge 1:1 fips_code using `good_baseline_counts', nogen

* Replace missing with 0
foreach v in n_indfin n_indfin_baseline n_grf n_tagged n_matched n_good_baseline {
    replace `v' = 0 if missing(`v')
}

* Calculate match rates
gen pct_grf_matched = 100 * n_matched / n_grf if n_grf > 0
gen pct_indfin_in_grf = 100 * n_matched / n_indfin if n_indfin > 0

* Sort alphabetically by state name for the full table
sort state_name

*===============================================================================
* Display Results - FULL TABLE (All 51 States/DC)
*===============================================================================

display _n(3)
display "==============================================================================="
display "STATE COVERAGE SUMMARY - ALL STATES"
display "==============================================================================="
display _n
display "Columns:"
display "  FIPS     = State FIPS code"
display "  GOVS     = GOVS code (used in INDFIN)"
display "  n_grf    = Districts in 1969 GRF"
display "  n_indfin = Districts in INDFIN 1967-1991"
display "  n_base   = INDFIN districts with ALL 4 baseline years (67,70,71,72)"
display "  n_match  = Districts in BOTH GRF and INDFIN/F33"
display "  n_good   = Matched districts with good baseline data"
display "  pct      = % of GRF districts that matched"
display _n

list state_name fips_code govs_code n_grf n_indfin n_indfin_baseline n_matched n_good_baseline pct_grf_matched, ///
    noobs clean abbreviate(10) separator(0)

*===============================================================================
* Summary Statistics
*===============================================================================

* Sort by match rate for problem states display
gsort pct_grf_matched

display _n(3)
display "==============================================================================="
display "PROBLEM STATES (< 50% GRF districts matched)"
display "==============================================================================="

list state_name fips_code n_grf n_indfin n_matched pct_grf_matched ///
    if pct_grf_matched < 50, noobs clean separator(0)

display _n(2)
display "==============================================================================="
display "STATES WITH ZERO INDFIN DATA"
display "==============================================================================="

list state_name fips_code n_grf n_indfin if n_indfin == 0, noobs clean separator(0)

display _n(2)
display "==============================================================================="
display "STATES WITH NO GOOD BASELINE DATA"
display "==============================================================================="

list state_name fips_code n_grf n_matched n_good_baseline ///
    if n_good_baseline == 0 & n_matched > 0, noobs clean separator(0)

display _n(2)
display "==============================================================================="
display "WELL-COVERED STATES (>= 90% GRF districts matched)"
display "==============================================================================="

gsort -pct_grf_matched
list state_name fips_code n_grf n_indfin n_matched n_good_baseline pct_grf_matched ///
    if pct_grf_matched >= 90, noobs clean separator(0)

*===============================================================================
* Save results to CSV for easy viewing
*===============================================================================

order state_name fips_code govs_code n_grf n_indfin n_indfin_baseline ///
      n_tagged n_matched n_good_baseline pct_grf_matched pct_indfin_in_grf

export delimited using "state_coverage_summary.csv", replace

* Also export to Excel
export excel using "state_coverage_summary.xlsx", firstrow(variables) replace

display _n(2)
display "==============================================================================="
display "Results saved to:"
display "  - state_coverage_summary.csv"
display "  - state_coverage_summary.xlsx"
display "==============================================================================="
