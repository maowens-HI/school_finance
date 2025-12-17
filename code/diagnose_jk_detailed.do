/*==============================================================================
Diagnostic: Jackknife Spec A - Why High Trends Below Low
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

use jackknife_predictions_spec_A, clear

* ============================================================================
* PART 1: Check the distribution of predicted spending
* ============================================================================

di as txt _n "=" * 80
di as txt "PART 1: Distribution of Predicted Spending"
di as txt "=" * 80

* Overall distribution
summ pred_spend, detail

* By baseline spending quartile
di as txt _n "Average pred_spend by baseline spending quartile (pre_q):"
table pre_q if ever_treated == 1, ///
    statistic(mean pred_spend) ///
    statistic(sd pred_spend) ///
    statistic(count pred_spend)

* ============================================================================
* PART 2: Check correlation between pre_q and pred_spend
* ============================================================================

di as txt _n "=" * 80
di as txt "PART 2: Correlation Analysis"
di as txt "=" * 80

pwcorr pre_q pred_spend if ever_treated == 1, sig

* Check if high baseline spending (pre_q=4) has LOWER predicted treatment effects
di as txt _n "Is there an INVERSE relationship? (i.e., rich counties have lower pred_spend?)"
reg pred_spend i.pre_q if ever_treated == 1

* ============================================================================
* PART 3: Examine the high/low group definition
* ============================================================================

di as txt _n "=" * 80
di as txt "PART 3: High/Low Group Definition Issues"
di as txt "=" * 80

* Create high_def_A as in county_fix.do
gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1
replace high_def_A = 0 if never_treated == 1

* Count how many counties in each group
di as txt _n "Number of treated counties in each group:"
tab high_def_A if ever_treated == 1

* Check what % of each pre_q falls into high vs low
di as txt _n "Cross-tab: pre_q vs high_def_A (showing row %)"
tab pre_q high_def_A if ever_treated == 1, row

* Average baseline spending in each group
di as txt _n "Average characteristics by group:"
table high_def_A if ever_treated == 1, ///
    statistic(mean pre_q) ///
    statistic(mean pred_spend) ///
    statistic(count county_id)

* ============================================================================
* PART 4: Check the interaction coefficients
* ============================================================================

di as txt _n "=" * 80
di as txt "PART 4: Interaction Coefficients (if available)"
di as txt "=" * 80

* Check if avg_ppe_* variables exist
capture confirm variable avg_ppe_2
if _rc == 0 {
    di as txt _n "Average interaction coefficients:"
    summ avg_main avg_ppe_2 avg_ppe_3 avg_ppe_4, detail

    di as txt _n "Are the interactions NEGATIVE? (This would explain the inversion)"
    di as txt "avg_ppe_2: " _b[avg_ppe_2]
    di as txt "avg_ppe_3: " _b[avg_ppe_3]
    di as txt "avg_ppe_4: " _b[avg_ppe_4]
}
else {
    di as txt "Interaction coefficient variables not found in dataset"
}

* ============================================================================
* PART 5: Alternative high/low definition (for comparison)
* ============================================================================

di as txt _n "=" * 80
di as txt "PART 5: Alternative High/Low Definitions"
di as txt "=" * 80

* Definition B: Top 2 quartiles
sort county_id
xtile pred_q = pred_spend if ever_treated == 1, nq(4)
gen high_def_B = (pred_q >= 3) if !missing(pred_q)

* Median split
xtile pred_median = pred_spend if ever_treated == 1, nq(2)
gen high_def_median = (pred_median == 2) if !missing(pred_median)

* Compare the different definitions
di as txt _n "Comparison of high/low definitions:"
tab high_def_A high_def_B if ever_treated == 1
tab high_def_A high_def_median if ever_treated == 1

* How do they differ by pre_q?
di as txt _n "Which pre_q quartiles are in 'high' group under each definition?"
di as txt "Definition A (pred_spend > 0):"
tab pre_q if high_def_A == 1 & ever_treated == 1

di as txt _n "Definition B (top 2 quartiles of pred_spend):"
tab pre_q if high_def_B == 1 & ever_treated == 1

* ============================================================================
* PART 6: Sample some counties to understand the pattern
* ============================================================================

di as txt _n "=" * 80
di as txt "PART 6: Sample Counties"
di as txt "=" * 80

* Sort by pred_spend to see extremes
preserve
bysort county_id: keep if _n == 1
keep if ever_treated == 1
sort pred_spend

di as txt _n "Bottom 20 counties (lowest pred_spend):"
list county_id state_fips pre_q pred_spend high_def_A in 1/20, clean noobs

di as txt _n "Top 20 counties (highest pred_spend):"
gsort -pred_spend
list county_id state_fips pre_q pred_spend high_def_A in 1/20, clean noobs
restore

