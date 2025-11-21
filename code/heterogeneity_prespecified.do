/*==============================================================================
Project    : School Spending – Pre-Specified Heterogeneity Analysis
File       : heterogeneity_prespecified.do
Purpose    : Explore theoretically-motivated treatment effect heterogeneity
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-21
───────────────────────────────────────────────────────────────────────────────

THEORETICAL MOTIVATION:
  School finance reforms should have STRONGER effects for:
  1. Low-baseline spending districts (equity channel)
  2. Equity reforms vs adequacy reforms (different mechanisms)
  3. States with larger funding formula changes
  4. Districts with higher baseline inequality

  These are NOT data-driven specifications - they are theory-driven and should
  be pre-specified in your analysis plan.

IMPORTANT: Run ALL specifications and report ALL results. Do not cherry-pick.

==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

use jjp_balance, clear
drop if good_71 != 1

*** ---------------------------------------------------------------------------
*** Heterogeneity Dimension 1: Baseline Spending (Theory: Equity Channel)
*** ---------------------------------------------------------------------------

* Interaction specification: Reform × Baseline Quartile
forvalues q = 1/4 {
    gen lag_q`q' = 0
    forvalues k = 1/17 {
        replace lag_q`q' = lag_`k' if pre_q1971 == `q' & lag_`k' == 1
    }
}

* Fully interacted model
areg lexp_ma_strict ///
    lag_q1 lag_q2 lag_q3 lag_q4 ///  // Separate effects by quartile
    i.lead_* ///                       // Common pre-trends
    i.year_unified##i.pre_q1971 ///    // Quartile-specific trends
    [w=school_age_pop] ///
    if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo heterog_quartiles

* Test for heterogeneity: H0: Effect equal across quartiles
test lag_q1 = lag_q2 = lag_q3 = lag_q4
local p_heterog = r(p)
display "P-value for heterogeneity test: `p_heterog'"

*** ---------------------------------------------------------------------------
*** Heterogeneity Dimension 2: Reform Type (Equity vs Adequacy)
*** ---------------------------------------------------------------------------

* Create reform type interactions
gen lag_equity = 0
gen lag_adequacy = 0

forvalues k = 1/17 {
    replace lag_equity = lag_`k' if reform_eq == 1 & lag_`k' == 1
    replace lag_adequacy = lag_`k' if reform_eq == 0 & lag_`k' == 1
}

areg lexp_ma_strict ///
    lag_equity lag_adequacy ///
    i.lead_* ///
    i.year_unified##i.reform_eq ///
    [w=school_age_pop] ///
    if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo heterog_reform_type

* Test if equity reforms have larger effects
test lag_equity = lag_adequacy
local p_reform_type = r(p)
display "P-value for reform type test: `p_reform_type'"

*** ---------------------------------------------------------------------------
*** Heterogeneity Dimension 3: Within-State Inequality
*** ---------------------------------------------------------------------------

* Create measure of baseline within-state spending inequality
preserve
keep if year_unified == 1971
collapse (sd) sd_spending = lexp_ma_strict ///
         (mean) mean_spending = lexp_ma_strict, ///
    by(state_fips)

gen cv_spending = sd_spending / mean_spending  // Coefficient of variation
xtile inequality_tercile = cv_spending, n(3)
keep state_fips inequality_tercile cv_spending
tempfile inequality
save `inequality'
restore

merge m:1 state_fips using `inequality', nogen

* Test if reforms have larger effects in high-inequality states
gen lag_high_ineq = 0
gen lag_low_ineq = 0

forvalues k = 1/17 {
    replace lag_high_ineq = lag_`k' if inequality_tercile == 3 & lag_`k' == 1
    replace lag_low_ineq = lag_`k' if inequality_tercile == 1 & lag_`k' == 1
}

areg lexp_ma_strict ///
    lag_high_ineq lag_low_ineq ///
    i.lead_* ///
    i.year_unified##i.inequality_tercile ///
    [w=school_age_pop] ///
    if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo heterog_inequality

*** ---------------------------------------------------------------------------
*** Heterogeneity Dimension 4: Intensity of Treatment (Formula Change)
*** ---------------------------------------------------------------------------

* Create measure of treatment intensity (change in funding formula generosity)
* This requires calculating how much the formula SHOULD increase spending

* Placeholder: Use pre-post spending growth as proxy for treatment intensity
preserve
keep if inrange(year_unified, 1967, 1975)
collapse (mean) pre_spending = lexp_ma_strict if year_unified < 1971, ///
         by(county_id)
tempfile pre
save `pre'
restore

preserve
keep if inrange(year_unified, 1976, 1985)
collapse (mean) post_spending = lexp_ma_strict, by(county_id)
tempfile post
save `post'
restore

merge m:1 county_id using `pre', nogen
merge m:1 county_id using `post', nogen

gen spending_growth = post_spending - pre_spending
xtile intensity_tercile = spending_growth, n(3)

gen lag_high_intensity = 0
gen lag_low_intensity = 0

forvalues k = 1/17 {
    replace lag_high_intensity = lag_`k' if intensity_tercile == 3 & lag_`k' == 1
    replace lag_low_intensity = lag_`k' if intensity_tercile == 1 & lag_`k' == 1
}

areg lexp_ma_strict ///
    lag_high_intensity lag_low_intensity ///
    i.lead_* ///
    i.year_unified##i.intensity_tercile ///
    [w=school_age_pop] ///
    if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

eststo heterog_intensity

*** ---------------------------------------------------------------------------
*** Export Results
*** ---------------------------------------------------------------------------

esttab, ///
    keep(lag_* 1.lag_*) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("By Quartile" "By Reform Type" "By Inequality" "By Intensity") ///
    title("Pre-Specified Heterogeneity Analysis")

*** ---------------------------------------------------------------------------
*** Create Heterogeneity Plots
*** ---------------------------------------------------------------------------

* Plot effects by quartile
coefplot heterog_quartiles, ///
    keep(lag_q*) ///
    vertical ///
    yline(0) ///
    title("Treatment Effects by Baseline Spending Quartile") ///
    xtitle("") ///
    ytitle("Coefficient on Post-Reform Indicator")

graph export "$SchoolSpending/output/heterogeneity_quartiles.png", replace
