* JK Spec A: State-by-state cross-tab of pre_q vs pred_spend_q
* Date: 2025-12-15

clear all
set more off
cd "$SchoolSpending/data"

use jk_reg_A, clear

* Create predicted spending quartiles
capture drop pred_spend_q
astile pred_spend_q = pred_spend if ever_treated == 1, nq(4)

* Keep one obs per county
bysort county_id: keep if _n == 1

* Collapse to counts by state × pre_q × pred_spend_q
keep if ever_treated == 1
collapse (count) n = county_id, by(state_fips pre_q pred_spend_q)

* Reshape wide so pred_spend_q values become columns
reshape wide n, i(state_fips pre_q) j(pred_spend_q)

* Clean up
foreach v in n1 n2 n3 n4 {
    replace `v' = 0 if missing(`v')
}

rename n1 pred_q1
rename n2 pred_q2
rename n3 pred_q3
rename n4 pred_q4

list state_fips pre_q pred_q1 pred_q2 pred_q3 pred_q4, sepby(state_fips) noobs
