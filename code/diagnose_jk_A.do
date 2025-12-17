/*==============================================================================
Project    : School Spending – Diagnostic for Jackknife Spec A
File       : diagnose_jk_A.do
Purpose    : Check if interaction coefficients are causing inverted predictions
Author     : Myles Owens (with Claude assistance)
Date       : 2025-12-17
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

use jackknife_predictions_spec_A, clear

* Check distribution of pred_spend
summ pred_spend, detail

* Check correlation between pre_q and pred_spend
pwcorr pre_q pred_spend if ever_treated == 1, sig

* Create high/low groups as in county_fix.do
gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1
replace high_def_A = 0 if never_treated == 1

* Cross-tabulate pre_q vs high_def_A
tab pre_q high_def_A if ever_treated == 1, row

* Average pred_spend by pre_q
table pre_q if ever_treated == 1, statistic(mean pred_spend) statistic(count pred_spend)

* Check average coefficients if available
capture summ avg_main avg_ppe_2 avg_ppe_3 avg_ppe_4, detail

* Look at first few observations
list county_id state_fips pre_q pred_spend high_def_A if ever_treated == 1 in 1/20, clean

