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

* Keep only treated, get modal pred_spend_q per state × pre_q
keep if ever_treated == 1
collapse (median) pred_spend_q, by(state_fips pre_q)

* Reshape so states are columns
reshape wide pred_spend_q, i(pre_q) j(state_fips) string

* Rename to state abbreviations
capture rename pred_spend_q01 AL
capture rename pred_spend_q04 AZ
capture rename pred_spend_q05 AR
capture rename pred_spend_q08 CO
capture rename pred_spend_q10 DE
capture rename pred_spend_q12 FL
capture rename pred_spend_q13 GA
capture rename pred_spend_q16 ID
capture rename pred_spend_q17 IL
capture rename pred_spend_q18 IN
capture rename pred_spend_q19 IA
capture rename pred_spend_q21 KY
capture rename pred_spend_q22 LA
capture rename pred_spend_q23 ME
capture rename pred_spend_q25 MA
capture rename pred_spend_q26 MI
capture rename pred_spend_q27 MN
capture rename pred_spend_q28 MS
capture rename pred_spend_q29 MO
capture rename pred_spend_q30 MT
capture rename pred_spend_q31 NE
capture rename pred_spend_q32 NV
capture rename pred_spend_q33 NH
capture rename pred_spend_q35 NM
capture rename pred_spend_q38 ND
capture rename pred_spend_q39 OH
capture rename pred_spend_q40 OK
capture rename pred_spend_q42 PA
capture rename pred_spend_q44 RI
capture rename pred_spend_q46 SD
capture rename pred_spend_q47 TN
capture rename pred_spend_q48 TX
capture rename pred_spend_q49 UT
capture rename pred_spend_q50 VT

* Show table with pre_q as rows, states as columns
list, sepby(pre_q) noobs abbreviate(20)
