/*==============================================================================
Project    : School Spending - Current Spending (No Rolling Mean)
File       : fig1_bal_current_spending.do
Purpose    : Test whether 13-year rolling mean is washing out effects
             Use lexp (current year) instead of lexp_ma_strict
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-14
───────────────────────────────────────────────────────────────────────────────
Notes:     - The 13-year rolling mean may be too conservative
           - Current year spending shows immediate effects faster
==============================================================================*/

clear all
set more off
cd "$SchoolSpending\data"

use jjp_balance2, clear

* Focus on current spending (lexp) not rolling mean
local v lexp
local y pre_q1970
local g good_70

*--------------------------------------*
* WEIGHTED
*--------------------------------------*

drop if `g' != 1
count
di "Sample size: " r(N)

areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified [w=enrollment] if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo current_wt

tempfile results
postfile handle str15 term float rel_year b se using `results', replace

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

use `results', clear
sort rel_year

gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se

twoway ///
    (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
    (line b rel_year, lcolor("42 66 94") lwidth(medium)), ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    ytitle("Δ ln(Current Year PPE)", size(medsmall) margin(medium)) ///
    title("Current Spending (No Rolling Mean): Weighted", size(medlarge) color("35 45 60")) ///
    note("Outcome: lexp (current year, not 13-yr rolling mean)") ///
    graphregion(color(white)) ///
    legend(off) ///
    scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\current_spending_weighted.png", replace

*--------------------------------------*
* UNWEIGHTED
*--------------------------------------*

use jjp_balance2, clear
drop if `g' != 1

areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo current_unwt

tempfile results2
postfile handle str15 term float rel_year b se using `results2', replace

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

use `results2', clear
sort rel_year

gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se

twoway ///
    (rarea ci_lo ci_hi rel_year, color("214 96 77%20") cmissing(n)) ///
    (line b rel_year, lcolor("178 68 53") lwidth(medium)), ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    ytitle("Δ ln(Current Year PPE)", size(medsmall) margin(medium)) ///
    title("Current Spending (No Rolling Mean): Unweighted", size(medlarge) color("35 45 60")) ///
    note("Outcome: lexp (current year, not 13-yr rolling mean)") ///
    graphregion(color(white)) ///
    legend(off) ///
    scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\current_spending_unweighted.png", replace
