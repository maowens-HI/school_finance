/*==============================================================================
Project    : School Spending - Diagnose State Coverage (County Level)
File       : diagnose_all_states_counties.do
Purpose    : Count counties per state in INDFIN and GRF
Author     : Myles Owens / Claude
Date       : 2026-01-21
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*===============================================================================
* Create state name lookup with GOVS codes
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

tempfile state_lookup
save `state_lookup'

*===============================================================================
* Step 1: Count counties in INDFIN (using GOVS codes)
*===============================================================================

display _n(2)
display "==============================================================================="
display "STEP 1: COUNT COUNTIES IN INDFIN (Historical spending 1967-1991)"
display "==============================================================================="

use "raw/indfin/build_indfin_out_dir/indfin_panel_1967_1991_clean.dta", clear

* GOVS ID structure: SS5CCCNNN (state 2, type 1, county 3, district 3)
* Extract GOVS state code and county portion
gen byte govs_code = floor(id / 10000000)
gen byte govs_county_only = mod(floor(id / 1000), 1000)  // Just CCC portion (county)

* Count unique counties per GOVS state
preserve
keep govs_code govs_county_only
duplicates drop
bysort govs_code: gen n_counties_indfin = _N
keep govs_code n_counties_indfin
duplicates drop
tempfile indfin_counties
save `indfin_counties'
restore

*===============================================================================
* Step 2: Count counties in GRF (from tract70)
*===============================================================================

display _n(2)
display "==============================================================================="
display "STEP 2: COUNT COUNTIES IN GRF (1969 Geographic Reference File)"
display "==============================================================================="

use "grf_tract_canon.dta", clear

* Extract state and county from tract70 (first 5 chars = state FIPS + county FIPS)
gen str2 state_str = substr(tract70, 1, 2)
gen str3 county_str = substr(tract70, 3, 3)
destring state_str, gen(fips_code)

* Count unique counties per state
preserve
keep fips_code county_str
duplicates drop
bysort fips_code: gen n_counties_grf = _N
keep fips_code n_counties_grf
duplicates drop
tempfile grf_counties
save `grf_counties'
restore

*===============================================================================
* Merge all counts together
*===============================================================================

display _n(2)
display "==============================================================================="
display "STEP 3: MERGE AND CREATE SUMMARY TABLE"
display "==============================================================================="

use `state_lookup', clear

* Merge INDFIN counts (by GOVS code)
merge 1:1 govs_code using `indfin_counties', nogen

* Merge GRF counts (by FIPS code)
merge 1:1 fips_code using `grf_counties', nogen

* Replace missing with 0
replace n_counties_indfin = 0 if missing(n_counties_indfin)
replace n_counties_grf = 0 if missing(n_counties_grf)

* Sort alphabetically
sort state_name

*===============================================================================
* Display Results
*===============================================================================

display _n(3)
display "==============================================================================="
display "COUNTY COVERAGE SUMMARY - ALL STATES"
display "==============================================================================="
display _n
display "Columns:"
display "  fips_code        = State FIPS code"
display "  govs_code        = GOVS code (used in INDFIN)"
display "  n_counties_grf   = Counties in 1969 GRF"
display "  n_counties_indfin = Counties in INDFIN 1967-1991"
display _n

list state_name fips_code govs_code n_counties_grf n_counties_indfin, ///
    noobs clean separator(0)

*===============================================================================
* Save results
*===============================================================================

order state_name fips_code govs_code n_counties_grf n_counties_indfin

export delimited using "state_county_coverage_summary.csv", replace
export excel using "state_county_coverage_summary.xlsx", firstrow(variables) replace

display _n(2)
display "==============================================================================="
display "Results saved to:"
display "  - state_county_coverage_summary.csv"
display "  - state_county_coverage_summary.xlsx"
display "  Location: $SchoolSpending/data/"
display "==============================================================================="
