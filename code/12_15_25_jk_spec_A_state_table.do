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

* Reshape so states are columns
reshape wide n, i(pre_q pred_spend_q) j(state_fips) string

* Show table with pre_q as rows, states as columns
list, sepby(pre_q) noobs abbreviate(20)
