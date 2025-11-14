/*==============================================================================
Project    : School Spending - Compare Weighted vs Unweighted (Balanced Panel)
File       : fig1_bal_compare_weights.do
Purpose    : Run event studies with and without enrollment weights to diagnose
             why weighted results are weak
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-14
───────────────────────────────────────────────────────────────────────────────
Inputs:    - jjp_balance2.dta (from fig1_bal_wt_rest.do)
Outputs:   - Side-by-side graphs: weighted vs unweighted
           - Diagnostic table of weight distribution
Notes:     - Uses same balanced panel (822 counties)
           - Compares enrollment-weighted vs equal-weighted counties
==============================================================================*/

clear all
set more off
cd "$SchoolSpending\data"

use jjp_balance2, clear

/*******************************************************************************
   DIAGNOSTIC: Weight Distribution
*******************************************************************************/

* Summarize enrollment weights
summ enrollment, detail
gen log_enrollment = log(enrollment)
summ log_enrollment, detail

* See which counties get most/least weight
preserve
keep county_id enrollment
duplicates drop
gsort -enrollment
list county_id enrollment in 1/20
restore

/*******************************************************************************
   RUN SPECIFICATIONS: WEIGHTED VS UNWEIGHTED
*******************************************************************************/

* We'll focus on:
* - Outcome: lexp_ma_strict (13-year rolling mean)
* - Sample: Bottom 3 quartiles, pre_q1970
* - Balanced panel: 822 counties
* - good_70 restriction

local v lexp_ma_strict
local y pre_q1970
local g good_70

*--------------------------------------*
* SPECIFICATION 1: WEIGHTED (Current)
*--------------------------------------*

use jjp_balance2, clear
drop if `g' != 1
count
di "Sample size with `g' restriction: " r(N)

areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified [w=enrollment] if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo weighted

* Extract coefficients for plotting
tempfile results_wt
postfile handle str15 term float rel_year b se using `results_wt', replace

forvalues k = 5(-1)1 {
    lincom 1.lead_`k'
    if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle ("base0") (0) (0) (0)

forvalues k = 1/17 {
    lincom 1.lag_`k'
    if !_rc post handle ("lag`k'") (`k') (r(estimate)) (r(se))
}

postclose handle

*--------------------------------------*
* SPECIFICATION 2: UNWEIGHTED
*--------------------------------------*

use jjp_balance2, clear
drop if `g' != 1

areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo unweighted

* Extract coefficients for plotting
tempfile results_unwt
postfile handle str15 term float rel_year b se using `results_unwt', replace

forvalues k = 5(-1)1 {
    lincom 1.lead_`k'
    if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle ("base0") (0) (0) (0)

forvalues k = 1/17 {
    lincom 1.lag_`k'
    if !_rc post handle ("lag`k'") (`k') (r(estimate)) (r(se))
}

postclose handle

*--------------------------------------*
* PLOT: WEIGHTED
*--------------------------------------*

use `results_wt', clear
sort rel_year

gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se

twoway ///
    (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
    (line b rel_year, lcolor("42 66 94") lwidth(medium)), ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
    title("WEIGHTED: Event Study | Bottom 3 Quartiles", size(medlarge) color("35 45 60")) ///
    graphregion(color(white)) ///
    legend(off) ///
    scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\compare_WEIGHTED.png", replace

*--------------------------------------*
* PLOT: UNWEIGHTED
*--------------------------------------*

use `results_unwt', clear
sort rel_year

gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se

twoway ///
    (rarea ci_lo ci_hi rel_year, color("214 96 77%20") cmissing(n)) ///
    (line b rel_year, lcolor("178 68 53") lwidth(medium)), ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
    title("UNWEIGHTED: Event Study | Bottom 3 Quartiles", size(medlarge) color("35 45 60")) ///
    graphregion(color(white)) ///
    legend(off) ///
    scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\compare_UNWEIGHTED.png", replace

*--------------------------------------*
* PLOT: OVERLAY BOTH
*--------------------------------------*

use `results_wt', clear
rename b b_wt
rename se se_wt
rename ci_lo ci_lo_wt
rename ci_hi ci_hi_wt

merge 1:1 rel_year using `results_unwt', nogen
rename b b_unwt
rename se se_unwt

gen ci_lo_unwt = b_unwt - 1.645*se_unwt
gen ci_hi_unwt = b_unwt + 1.645*se_unwt

twoway ///
    (rarea ci_lo_wt ci_hi_wt rel_year, color("59 91 132%15") cmissing(n)) ///
    (rarea ci_lo_unwt ci_hi_unwt rel_year, color("214 96 77%15") cmissing(n)) ///
    (line b_wt rel_year, lcolor("42 66 94") lwidth(medium) lpattern(solid)) ///
    (line b_unwt rel_year, lcolor("178 68 53") lwidth(medium) lpattern(dash)), ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
    title("Comparison: Weighted vs Unweighted", size(medlarge) color("35 45 60")) ///
    legend(order(3 "Weighted (Enrollment)" 4 "Unweighted (Equal)") ///
           position(6) rows(1) region(lcolor(white))) ///
    graphregion(color(white)) ///
    scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\compare_OVERLAY.png", replace

*--------------------------------------*
* TABLE: Compare Coefficients
*--------------------------------------*

list rel_year b_wt se_wt b_unwt se_unwt

* Export regression table
esttab weighted unweighted using ///
    "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\compare_table.tex", ///
    replace tex ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(*.lag_* *.lead_*) ///
    label nonotes ///
    title("Comparison: Weighted vs Unweighted Event Study")
