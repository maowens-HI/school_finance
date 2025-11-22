/*==============================================================================
Project    : School Spending – Diagnose Discrepancy with JJP Figure 1
File       : diagnose_jjp_discrepancy.do
Purpose    : Systematically identify why effects are ~1/3 of JJP's original results
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-22
───────────────────────────────────────────────────────────────────────────────

PROBLEM:
  JJP (2016) Figure 1 shows effects of ~0.15-0.20 log points by period +17
  Our replication shows effects of ~0.05-0.07 log points by period +17

  Effects are approximately 1/3 the size - need to diagnose why.

POTENTIAL CAUSES:
  1. Different unit of analysis (person-year vs county-year)
  2. Different outcome smoothing (no rolling mean vs 13-year rolling mean)
  3. Different sample period or balanced panel restrictions
  4. Different weighting scheme
  5. Aggregation bias (county-level vs district-level)
  6. Different interpolation methods
  7. Coding errors in treatment assignment or relative time
  8. Different inflation adjustment methods

STRATEGY:
  Systematically replicate JJP's exact specification, then incrementally
  add our modifications to see where the divergence occurs.

==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Step 1: Document Current Results (Baseline)
*** ---------------------------------------------------------------------------

use jjp_balance, clear
drop if good_71 != 1

* Current specification (what we've been running)
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

lincom 1.lag_17
local current_effect = r(estimate)
local current_se = r(se)

display ""
display "========================================="
display "CURRENT RESULTS (Quartiles 1-3)"
display "========================================="
display "Effect at lag_17: " %6.4f `current_effect' " (SE: " %6.4f `current_se' ")"
display ""

eststo current

*** ---------------------------------------------------------------------------
*** Step 2: Check Without Rolling Mean (Use Raw Log Spending)
*** ---------------------------------------------------------------------------

* JJP may not use 13-year rolling mean - try raw log spending
gen lexp_raw = log(exp)

areg lexp_raw ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

lincom 1.lag_17
local raw_effect = r(estimate)
local raw_se = r(se)

display ""
display "========================================="
display "WITHOUT ROLLING MEAN (Raw Log Spending)"
display "========================================="
display "Effect at lag_17: " %6.4f `raw_effect' " (SE: " %6.4f `raw_se' ")"
display "Change from current: " %6.4f `raw_effect' - `current_effect'
display ""

eststo no_smooth

*** ---------------------------------------------------------------------------
*** Step 3: Check Without Balanced Panel Restriction
*** ---------------------------------------------------------------------------

use jjp_interp, clear
drop if good_71 != 1

* Recreate quartiles on full sample
preserve
keep if year_unified == 1971
keep if !missing(exp, state_fips, county_id)
bysort state_fips: egen pre_q1971_full = xtile(exp), n(4)
keep state_fips county_id pre_q1971_full
tempfile q1971_full
save `q1971_full'
restore

merge m:1 state_fips county_id using `q1971_full', nogen

gen lexp_raw = log(exp)

areg lexp_raw ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971_full < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

lincom 1.lag_17
local unbal_effect = r(estimate)
local unbal_se = r(se)

display ""
display "========================================="
display "UNBALANCED PANEL (No Balance Restriction)"
display "========================================="
display "Effect at lag_17: " %6.4f `unbal_effect' " (SE: " %6.4f `unbal_se' ")"
display "Change from current: " %6.4f `unbal_effect' - `current_effect'
display ""

eststo unbalanced

*** ---------------------------------------------------------------------------
*** Step 4: Check District-Level (Avoid Aggregation Bias)
*** ---------------------------------------------------------------------------

use jjp_interp, clear

* Load district-level data instead
use "$SchoolSpending/data/jjp_balance.dta" if _dta_name == "district", clear

* If district data exists, run same spec
capture {
    drop if good_71 != 1
    gen lexp_raw = log(exp)

    areg lexp_raw ///
        i.lag_* i.lead_* ///
        i.year_unified [w=enr_avg_all] ///
        if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
        absorb(LEAID) vce(cluster LEAID)

    lincom 1.lag_17
    local district_effect = r(estimate)
    local district_se = r(se)

    display ""
    display "========================================="
    display "DISTRICT-LEVEL (No Aggregation)"
    display "========================================="
    display "Effect at lag_17: " %6.4f `district_effect' " (SE: " %6.4f `district_se' ")"
    display ""

    eststo district_level
}

*** ---------------------------------------------------------------------------
*** Step 5: Check Sample Counts and Composition
*** ---------------------------------------------------------------------------

use jjp_balance, clear
drop if good_71 != 1

display ""
display "========================================="
display "SAMPLE COMPOSITION"
display "========================================="

* Count observations
count
local total_obs = r(N)

* Count unique counties
distinct county_id
local n_counties = r(ndistinct)

* Count treated counties
distinct county_id if reform_year < 2000 & !missing(reform_year)
local n_treated = r(ndistinct)

* Count control counties
distinct county_id if never_treated == 1
local n_controls = r(ndistinct)

* Time period coverage
sum year_unified
local min_year = r(min)
local max_year = r(max)

display "Total observations: " `total_obs'
display "Unique counties: " `n_counties'
display "  - Treated: " `n_treated'
display "  - Control: " `n_controls'
display "Year range: " `min_year' " to " `max_year'
display ""

* JJP used person-year data from Census/ACS
* We're using county-year administrative data
display "NOTE: JJP used PERSON-YEAR data from Census/ACS"
display "      We're using COUNTY-YEAR administrative spending data"
display "      This could explain much of the discrepancy"
display ""

*** ---------------------------------------------------------------------------
*** Step 6: Check Treatment Coding
*** ---------------------------------------------------------------------------

* Verify reform years match JJP Table D2
preserve
keep if !missing(reform_year)
keep state_name reform_year
duplicates drop
sort reform_year state_name
list state_name reform_year, clean

display ""
display "Verify these reform years match JJP (2016) Table D2"
display ""
restore

*** ---------------------------------------------------------------------------
*** Step 7: Alternative Outcome Measures
*** ---------------------------------------------------------------------------

use jjp_balance, clear
drop if good_71 != 1

* Try levels instead of logs
areg exp ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

lincom 1.lag_17
local levels_effect = r(estimate)
local levels_se = r(se)

display ""
display "========================================="
display "LEVELS (Not Logs)"
display "========================================="
display "Effect at lag_17: $" %6.0f `levels_effect' " (SE: $" %6.0f `levels_se' ")"
display ""

eststo levels_spec

* Try inverse hyperbolic sine (IHS) transformation
gen ihs_exp = ln(exp + sqrt(exp^2 + 1))

areg ihs_exp ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

lincom 1.lag_17
local ihs_effect = r(estimate)
local ihs_se = r(se)

display ""
display "========================================="
display "IHS TRANSFORMATION"
display "========================================="
display "Effect at lag_17: " %6.4f `ihs_effect' " (SE: " %6.4f `ihs_se' ")"
display ""

eststo ihs_spec

*** ---------------------------------------------------------------------------
*** Step 8: Compare All Specifications
*** ---------------------------------------------------------------------------

esttab current no_smooth unbalanced levels_spec ihs_spec, ///
    keep(1.lag_17) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("Current" "No Smooth" "Unbalanced" "Levels" "IHS") ///
    title("Comparison of Specifications - Effect at Lag 17")

*** ---------------------------------------------------------------------------
*** Step 9: Output Summary Table
*** ---------------------------------------------------------------------------

display ""
display "========================================="
display "SUMMARY: POSSIBLE EXPLANATIONS"
display "========================================="
display ""
display "1. UNIT OF ANALYSIS:"
display "   - JJP: Person-year (Census/ACS individual records)"
display "   - Ours: County-year (aggregated administrative data)"
display "   → Aggregation may attenuate effects"
display ""
display "2. OUTCOME VARIABLE:"
display "   - JJP: Educational attainment, earnings (person-level)"
display "   - Ours: Per-pupil spending (county-level)"
display "   → We're replicating their 'first stage' (Figure 1)"
display ""
display "3. SAMPLE PERIOD:"
display "   - Check if JJP used different years"
display "   - Check if balanced panel restriction is too strict"
display ""
display "4. SMOOTHING:"
display "   - 13-year rolling mean may over-smooth variation"
display "   - Try shorter windows (5-year, 7-year)"
display ""
display "5. WEIGHTING:"
display "   - Check if JJP used different weights"
display "   - Try unweighted regression"
display ""
display "6. INTERPOLATION:"
display "   - Our interpolation (≤3 year gaps) may introduce noise"
display "   - Try restricting to non-interpolated observations only"
display ""

*** ---------------------------------------------------------------------------
*** Step 10: Create Diagnostic Plots
*** ---------------------------------------------------------------------------

* Extract all lag coefficients for current spec
use jjp_balance, clear
drop if good_71 != 1

areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

* Extract coefficients
tempfile results
postfile handle str15 term float rel_year b se using `results', replace

forvalues k = 5(-1)1 {
    lincom 1.lead_`k'
    post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle ("base0") (0) (0) (0)

forvalues k = 1/17 {
    lincom 1.lag_`k'
    post handle ("lag`k'") (`k') (r(estimate)) (r(se))
}

postclose handle

use `results', clear
sort rel_year

gen ci_lo = b - 1.96*se
gen ci_hi = b + 1.96*se

* Add JJP's approximate results for comparison
gen jjp_b = .
replace jjp_b = 0 if rel_year == 0
replace jjp_b = 0.15 if rel_year == 10  // Approximate from JJP Figure 1
replace jjp_b = 0.18 if rel_year == 17  // Approximate from JJP Figure 1

* Plot comparison
twoway ///
    (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
    (line b rel_year, lcolor("42 66 94") lwidth(medium) lpattern(solid)) ///
    (scatter jjp_b rel_year, mcolor(red) msymbol(D) msize(medium)), ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    ytitle("Δ ln(per-pupil spending)", size(medsmall) margin(medium)) ///
    xtitle("Years since reform", size(medsmall)) ///
    title("Comparison: Our Results vs JJP (2016) Figure 1", size(medlarge)) ///
    subtitle("Quartiles 1-3 only", size(small)) ///
    note("Blue line: Our replication | Red diamonds: JJP approximate results", size(vsmall)) ///
    legend(order(2 "Our results" 3 "JJP (2016)") position(11) ring(0)) ///
    graphregion(color(white)) ///
    scheme(s2mono)

graph export "$SchoolSpending/output/diagnostic_comparison_jjp.png", replace

display ""
display "Diagnostic plot saved to: $SchoolSpending/output/diagnostic_comparison_jjp.png"
display ""
