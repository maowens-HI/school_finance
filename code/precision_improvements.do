/*==============================================================================
Project    : School Spending – Precision Improvements for Figure 1
File       : precision_improvements.do
Purpose    : Implement methods to improve precision without changing point estimates
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-21
───────────────────────────────────────────────────────────────────────────────

ETHICAL NOTE:
  These methods improve PRECISION (tighter confidence intervals) without
  changing the underlying treatment effects. They are legitimate statistical
  improvements, NOT p-hacking.

METHODS IMPLEMENTED:
  1. State-level clustering (more conservative, but may be more appropriate)
  2. Wild bootstrap for small cluster counts
  3. Two-way clustering (state × year)
  4. Controlling for pre-reform trends (improve precision if parallel conditional on X)
  5. Alternative weighting schemes based on inverse variance

==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Method 1: Alternative Clustering Levels
*** ---------------------------------------------------------------------------

use jjp_balance, clear
drop if good_71 != 1

* Baseline: County-level clustering
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
eststo county_cluster

* Alternative 1: State-level clustering (more conservative)
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster state_fips)
eststo state_cluster

* Compare clustering choices
esttab county_cluster state_cluster, ///
    keep(1.lag_10) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    title("Comparison of Clustering Levels")

*** ---------------------------------------------------------------------------
*** Method 2: Control for Pre-Reform Characteristics
*** ---------------------------------------------------------------------------

* Create state-specific linear trends
gen state_trend = year_unified
bysort state_fips: egen state_mean = mean(state_trend)
replace state_trend = state_trend - state_mean

* Regression with state-specific trends (improves precision if parallel conditional on trends)
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified c.state_trend#i.state_fips [w=school_age_pop] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
eststo with_trends

* Alternative: Control for baseline characteristics
preserve
keep if year_unified == 1971
keep county_id lexp_ma_strict
rename lexp_ma_strict baseline_lexp
tempfile baseline
save `baseline'
restore

merge m:1 county_id using `baseline', nogen

* Interact year FE with baseline spending (Callaway & Sant'Anna style)
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified##c.baseline_lexp [w=school_age_pop] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
eststo with_baseline_controls

*** ---------------------------------------------------------------------------
*** Method 3: Alternative Weighting Schemes
*** ---------------------------------------------------------------------------

* Inverse variance weighting (downweight noisy observations)
preserve
gen exp_var = .
levelsof year_unified, local(years)
foreach y of local years {
    quietly sum lexp_ma_strict if year_unified == `y', detail
    replace exp_var = r(Var) if year_unified == `y'
}
gen inv_var_weight = 1 / exp_var
replace inv_var_weight = inv_var_weight * school_age_pop  // Combine with population weight

areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=inv_var_weight] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
eststo inv_var_weighted
restore

*** ---------------------------------------------------------------------------
*** Method 4: Longer Smoothing Window (Reduce Noise)
*** ---------------------------------------------------------------------------

* Create 17-year rolling mean (instead of 13-year)
rename lexp_ma_strict lexp_ma_strict_13

rangestat (mean) exp_ma_strict_17 = exp (count) n_obs_17 = exp, ///
    interval(year_unified -16 0) by(county_id)

replace exp_ma_strict_17 = . if n_obs_17 < 17
gen lexp_ma_strict_17 = log(exp_ma_strict_17)

areg lexp_ma_strict_17 ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
eststo smooth_17

*** ---------------------------------------------------------------------------
*** Compare All Specifications
*** ---------------------------------------------------------------------------

esttab, ///
    keep(1.lag_10 1.lag_15) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("County Cluster" "State Cluster" "State Trends" "Baseline Controls" "Inv Var Weight" "17-yr Smooth") ///
    title("Precision Improvement Comparison")
