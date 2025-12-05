/*==============================================================================
Diagnose Ties in xtile Assignment
Purpose: Quantify how many tied exp values exist at quartile boundaries
Run this AFTER running 06_A up through the point where interp_temp.dta is saved
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

* Load the data at the point where xtile is applied
use interp_temp, clear
keep if year_unified == 1971
keep if !missing(exp, state_fips, county_id)

di _newline "=============================================="
di "TIES DIAGNOSTIC FOR XTILE REPRODUCIBILITY"
di "=============================================="

* Count total observations
di _newline "Total counties in 1971: " _N

*** -------------------------------------------------------------------------
*** Part 1: General tie frequency
*** -------------------------------------------------------------------------

* Count how many counties share the same exp value within their state
bysort state_fips exp: gen n_ties = _N

di _newline "--- Distribution of tie group sizes ---"
tab n_ties

* How many counties share their exp value with at least one other?
count if n_ties > 1
local n_tied = r(N)
di _newline "Counties with tied exp values (n_ties > 1): " `n_tied'
di "Percentage of total: " %5.2f (`n_tied' / _N * 100) "%"

*** -------------------------------------------------------------------------
*** Part 2: Ties at quartile boundaries (where it matters)
*** -------------------------------------------------------------------------

* Compute quartile cutpoints within each state
bysort state_fips: egen p25 = pctile(exp), p(25)
bysort state_fips: egen p50 = pctile(exp), p(50)
bysort state_fips: egen p75 = pctile(exp), p(75)

* Flag observations exactly at a quartile boundary
gen at_p25 = (exp == p25)
gen at_p50 = (exp == p50)
gen at_p75 = (exp == p75)
gen at_boundary = (at_p25 | at_p50 | at_p75)

di _newline "--- Counties at quartile boundaries ---"
count if at_p25
di "At 25th percentile: " r(N)
count if at_p50
di "At 50th percentile: " r(N)
count if at_p75
di "At 75th percentile: " r(N)
count if at_boundary
di "At ANY boundary: " r(N)

* Of those at boundaries, how many are in tie groups?
di _newline "--- Boundary observations WITH ties (the problem cases) ---"
count if at_p25 & n_ties > 1
di "At 25th pctile with ties: " r(N)
count if at_p50 & n_ties > 1
di "At 50th pctile with ties: " r(N)
count if at_p75 & n_ties > 1
di "At 75th pctile with ties: " r(N)
count if at_boundary & n_ties > 1
local problem_cases = r(N)
di "At ANY boundary with ties: " `problem_cases'
di _newline ">>> These " `problem_cases' " observations can flip quartiles between runs <<<"

*** -------------------------------------------------------------------------
*** Part 3: States with most problematic ties
*** -------------------------------------------------------------------------

di _newline "--- States with most ties at boundaries ---"
preserve
keep if at_boundary & n_ties > 1
collapse (count) n_problem = county_id, by(state_fips)
gsort -n_problem
list in 1/10
restore

*** -------------------------------------------------------------------------
*** Part 4: Show example tie groups at boundaries
*** -------------------------------------------------------------------------

di _newline "--- Example: Counties that could flip quartiles ---"
list state_fips county_id exp n_ties p25 p50 p75 if at_boundary & n_ties > 1 & _n <= 20, ///
    sepby(state_fips exp)

di _newline "=============================================="
di "RECOMMENDATION:"
di "If problem cases > 0, add 'set seed 12345' before xtile"
di "=============================================="
