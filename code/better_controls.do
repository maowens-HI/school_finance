/*==============================================================================
Project    : School Spending – Improved Control Group Selection
File       : better_controls.do
Purpose    : Implement better control group selection strategies
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-21
───────────────────────────────────────────────────────────────────────────────

MOTIVATION:
  The strength of a difference-in-differences design depends critically on the
  quality of the control group. Currently using ALL never-treated states as
  controls may introduce bias if:
  1. Never-treated states are systematically different
  2. Timing of treatment varies (staggered adoption)
  3. Treatment effects are heterogeneous

APPROACHES:
  1. Matched controls based on pre-reform characteristics
  2. Restrict to "clean" never-treated controls (similar baseline trends)
  3. Sun & Abraham (2021) estimator for staggered adoption
  4. Callaway & Sant'Anna (2021) approach
  5. Synthetic control methods

==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

use jjp_balance, clear
drop if good_71 != 1

*** ---------------------------------------------------------------------------
*** Approach 1: Matched Controls (Mahalanobis Distance)
*** ---------------------------------------------------------------------------

* Calculate baseline (pre-reform) characteristics for matching
preserve
keep if inrange(year_unified, 1967, 1971)
collapse (mean) baseline_lexp = lexp_ma_strict ///
               baseline_pop = school_age_pop ///
         (sd)   sd_lexp = lexp_ma_strict, ///
    by(county_id state_fips treatment reform_year)

* For treated units, use characteristics from year before reform
* For never-treated, use 1970 characteristics

tempfile baseline_chars
save `baseline_chars'
restore

merge m:1 county_id using `baseline_chars', nogen

* Implement 1:1 nearest neighbor matching (within same region if possible)
* This requires the psmatch2 package: ssc install psmatch2

* First, create treatment indicator for counties treated before 2000
gen treated_pre2000 = (reform_year < 2000 & !missing(reform_year))

* Match on baseline spending, population, and spending volatility
* Restrict to pre-reform period for matching
preserve
keep if year_unified == 1971
keep county_id treated_pre2000 baseline_lexp baseline_pop sd_lexp state_fips

* Uncomment to run matching (requires psmatch2):
* psmatch2 treated_pre2000 baseline_lexp baseline_pop sd_lexp, ///
*     outcome(baseline_lexp) n(1) common

* For now, create simple distance-based matches
gen match_score = .
levelsof county_id if treated_pre2000 == 1, local(treated_counties)

gen matched_control = ""
gen match_distance = .

foreach tc of local treated_counties {
    * Get characteristics of treated county
    sum baseline_lexp if county_id == "`tc'", meanonly
    local tc_lexp = r(mean)
    sum baseline_pop if county_id == "`tc'", meanonly
    local tc_pop = r(mean)
    sum sd_lexp if county_id == "`tc'", meanonly
    local tc_sd = r(mean)

    * Calculate Mahalanobis distance to all control counties
    gen distance = sqrt( ///
        ((baseline_lexp - `tc_lexp')/sd(baseline_lexp))^2 + ///
        ((baseline_pop - `tc_pop')/sd(baseline_pop))^2 + ///
        ((sd_lexp - `tc_sd')/sd(sd_lexp))^2) ///
        if treated_pre2000 == 0

    * Find closest match
    sum distance, meanonly
    local min_dist = r(min)
    levelsof county_id if distance == `min_dist', local(match_id) clean

    replace matched_control = "`match_id'" if county_id == "`tc'"
    replace match_distance = `min_dist' if county_id == "`tc'"

    drop distance
}

* Create indicator for matched control counties
gen is_matched_control = 0
levelsof matched_control, local(matched_ids)
foreach mid of local matched_ids {
    replace is_matched_control = 1 if county_id == "`mid'"
}

keep county_id treated_pre2000 is_matched_control matched_control
tempfile matches
save `matches'
restore

merge m:1 county_id using `matches', nogen

*** ---------------------------------------------------------------------------
*** Approach 2: Restrict to Controls with Parallel Pre-Trends
*** ---------------------------------------------------------------------------

* Test for parallel pre-trends for each potential control state
preserve
keep if year_unified < 1975  // Pre-reform period for most states
collapse (mean) lexp_ma_strict, by(state_fips year_unified never_treated)

* Create state-specific time trends
bysort state_fips: gen time_trend = _n

* Run separate regressions for each control state
levelsof state_fips if never_treated == 1, local(control_states)

tempfile trend_tests
tempname memhold
postfile `memhold' str2 state_fips float slope using `trend_tests'

foreach cs of local control_states {
    quietly reg lexp_ma_strict time_trend if state_fips == "`cs'"
    local slope = _b[time_trend]
    post `memhold' ("`cs'") (`slope')
}

postclose `memhold'
use `trend_tests', clear

* Calculate median trend across all control states
sum slope, detail
local median_trend = r(p50)

* Flag control states with "similar" trends (within IQR of median)
gen similar_trend = abs(slope - `median_trend') < (r(p75) - r(p25))

keep state_fips similar_trend
tempfile good_controls
save `good_controls'
restore

merge m:1 state_fips using `good_controls', nogen
replace similar_trend = 0 if missing(similar_trend)

*** ---------------------------------------------------------------------------
*** Approach 3: Exclude Potentially Bad Controls
*** ---------------------------------------------------------------------------

* Identify never-treated states that may be poor controls
* 1. States with very different baseline spending
* 2. States with unusual spending trends
* 3. States with other concurrent reforms

preserve
keep if year_unified == 1971
collapse (mean) baseline_lexp = lexp_ma_strict, by(state_fips never_treated)

* Flag outliers (more than 1.5 IQR from median)
sum baseline_lexp if never_treated == 1, detail
gen outlier_control = (baseline_lexp < r(p25) - 1.5*(r(p75)-r(p25)) | ///
                       baseline_lexp > r(p75) + 1.5*(r(p75)-r(p25))) ///
                       if never_treated == 1

keep state_fips outlier_control
tempfile outliers
save `outliers'
restore

merge m:1 state_fips using `outliers', nogen
replace outlier_control = 0 if missing(outlier_control)

*** ---------------------------------------------------------------------------
*** Run Regressions with Different Control Groups
*** ---------------------------------------------------------------------------

* Baseline: All never-treated states
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
eststo all_controls

* Specification 1: Matched controls only
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971==4 & (is_matched_control==1 | treated_pre2000==1), ///
    absorb(county_id) vce(cluster county_id)
eststo matched_controls

* Specification 2: Similar trend controls only
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971==4 & (similar_trend==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
eststo similar_trend_controls

* Specification 3: Exclude outlier controls
areg lexp_ma_strict ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971==4 & (never_treated==1 | reform_year<2000) & outlier_control==0, ///
    absorb(county_id) vce(cluster county_id)
eststo no_outlier_controls

*** ---------------------------------------------------------------------------
*** Compare Results
*** ---------------------------------------------------------------------------

esttab all_controls matched_controls similar_trend_controls no_outlier_controls, ///
    keep(1.lag_5 1.lag_10 1.lag_15) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("All Controls" "Matched" "Similar Trends" "No Outliers") ///
    title("Comparison of Control Group Selection Strategies")

*** ---------------------------------------------------------------------------
*** Diagnostic: Test Pre-Trend Differences Across Specifications
*** ---------------------------------------------------------------------------

* Extract lead coefficients to check if pre-trends improve with better controls
esttab all_controls matched_controls similar_trend_controls no_outlier_controls, ///
    keep(1.lead_*) ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    mtitles("All Controls" "Matched" "Similar Trends" "No Outliers") ///
    title("Pre-Trend Comparison Across Control Group Specifications")

* Joint test: Are all pre-trends jointly zero?
test 1.lead_1 1.lead_2 1.lead_3 1.lead_4 1.lead_5
