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

* Loop through treated states
levelsof state_fips if ever_treated == 1, local(states)

foreach s of local states {
    display "State: `s'"
    tab pre_q pred_spend_q if state_fips == "`s'"
}
