/*==============================================================================
QUICK DIAGNOSTIC: Test Most Likely Causes of Small Effects
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*** Test 1: Remove Rolling Mean
use jjp_balance, clear
drop if good_71 != 1

gen lexp_raw = log(exp)

areg lexp_raw ///
    i.lag_* i.lead_* ///
    i.year_unified [w=school_age_pop] ///
    if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

display "TEST 1: WITHOUT ROLLING MEAN"
lincom 1.lag_17
display "Effect at lag_17: " %6.4f r(estimate) " (SE: " %6.4f r(se) ")"
eststo no_rolling

*** Test 2: Unweighted
areg lexp_raw ///
    i.lag_* i.lead_* ///
    i.year_unified ///
    if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

display ""
display "TEST 2: UNWEIGHTED"
lincom 1.lag_17
display "Effect at lag_17: " %6.4f r(estimate) " (SE: " %6.4f r(se) ")"
eststo unweighted

*** Test 3: District-level (no aggregation)
use "$SchoolSpending/data/no_grf_district_treat.dta", clear

* Quick panel setup
gen lexp_raw = log(pp_exp_real)
gen relative_year = year_unified - reform_year
encode LEAID, gen(LEAID_num)

* Create leads/lags
forvalues k = 1/17 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}
forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}
replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year)
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)

gen never_treated_flag = (treatment == 0)

* Baseline quartiles
preserve
keep if year_unified == 1971
keep if !missing(pp_exp_real, state_fips, LEAID)
bysort state_fips: egen pre_q1971_d = xtile(pp_exp_real), n(4)
keep state_fips LEAID pre_q1971_d
tempfile q1971_d
save `q1971_d'
restore
merge m:1 state_fips LEAID using `q1971_d', nogen

areg lexp_raw ///
    i.lag_* i.lead_* ///
    i.year_unified ///
    if pre_q1971_d < 4 & (never_treated_flag==1 | reform_year<2000), ///
    absorb(LEAID_num) vce(cluster LEAID_num)

display ""
display "TEST 3: DISTRICT-LEVEL (NO AGGREGATION)"
lincom 1.lag_17
display "Effect at lag_17: " %6.4f r(estimate) " (SE: " %6.4f r(se) ")"
eststo district_level

*** Summary
display ""
display "========================================="
display "SUMMARY"
display "========================================="
display "If district-level effect >> county-level:"
display "  → Aggregation bias is the problem"
display ""
display "If unweighted effect >> weighted:"
display "  → Weighting scheme is attenuating effects"
display ""
display "If raw log >> rolling mean:"
display "  → Over-smoothing is the problem"
display ""
