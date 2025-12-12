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

* Rename to state abbreviations
capture rename n01 AL
capture rename n04 AZ
capture rename n05 AR
capture rename n08 CO
capture rename n10 DE
capture rename n12 FL
capture rename n13 GA
capture rename n16 ID
capture rename n17 IL
capture rename n18 IN
capture rename n19 IA
capture rename n21 KY
capture rename n22 LA
capture rename n23 ME
capture rename n25 MA
capture rename n26 MI
capture rename n27 MN
capture rename n28 MS
capture rename n29 MO
capture rename n30 MT
capture rename n31 NE
capture rename n32 NV
capture rename n33 NH
capture rename n35 NM
capture rename n38 ND
capture rename n39 OH
capture rename n40 OK
capture rename n42 PA
capture rename n44 RI
capture rename n46 SD
capture rename n47 TN
capture rename n48 TX
capture rename n49 UT
capture rename n50 VT

* Show table with pre_q as rows, states as columns
list, sepby(pre_q) noobs abbreviate(20)
