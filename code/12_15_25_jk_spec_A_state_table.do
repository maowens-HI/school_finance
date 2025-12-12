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

* Keep only treated, get pred_spend_q per state × pre_q
keep if ever_treated == 1
collapse (median) pred_spend_q, by(state_fips pre_q)

* Reshape so states are columns
reshape wide pred_spend_q, i(pre_q) j(state_fips) string

* Rename to state abbreviations
rename pred_spend_q01 AL
rename pred_spend_q04 AZ
rename pred_spend_q05 AR
rename pred_spend_q08 CO
rename pred_spend_q10 DE
rename pred_spend_q12 FL
rename pred_spend_q13 GA
rename pred_spend_q16 ID
rename pred_spend_q17 IL
rename pred_spend_q18 IN
rename pred_spend_q19 IA
rename pred_spend_q21 KY
rename pred_spend_q22 LA
rename pred_spend_q23 ME
rename pred_spend_q25 MA
rename pred_spend_q26 MI
rename pred_spend_q27 MN
rename pred_spend_q28 MS
rename pred_spend_q29 MO
rename pred_spend_q30 MT
rename pred_spend_q31 NE
rename pred_spend_q32 NV
rename pred_spend_q33 NH
rename pred_spend_q35 NM
rename pred_spend_q38 ND
rename pred_spend_q39 OH
rename pred_spend_q40 OK
rename pred_spend_q42 PA
rename pred_spend_q44 RI
rename pred_spend_q46 SD
rename pred_spend_q47 TN
rename pred_spend_q48 TX
rename pred_spend_q49 UT
rename pred_spend_q50 VT

list, noobs clean
