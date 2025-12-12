/*==============================================================================
Project    : School Spending – JK Spec A State-Level Diagnostic
File       : 12_15_25_jk_spec_A_state_table.do
Purpose    : Generate state-by-state cross-tabulations of baseline spending
             quartile (pre_q) vs predicted spending quartile (pred_spend_q)
             to diagnose why jackknife predictions don't match expectations
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-12-15
───────────────────────────────────────────────────────────────────────────────

MOTIVATION:
  The jackknife event-study graph shows unexpected patterns:
  - Q1 (lowest baseline spending) shows smallest effects
  - Q2 and Q3 show larger effects than expected
  This suggests the jackknife may not be predicting what we expect.

  This diagnostic examines the mapping between:
  - pre_q: Baseline spending quartile (from 1971 per-pupil expenditure)
  - pred_spend_q: Quartile of PREDICTED spending increase from jackknife

  If the jackknife works as intended, we'd expect:
  - Low baseline spending (pre_q=1) → High predicted increase (pred_spend_q=3,4)
  - High baseline spending (pre_q=4) → Low predicted increase (pred_spend_q=1,2)

INPUTS:
  - jk_reg_A.dta (from 08_jackknife_approach_ii.do)

OUTPUTS:
  - Console output with state-by-state cross-tabulations
  - jk_spec_A_state_diagnostics.dta (summary statistics by state)
  - jk_spec_A_state_crosstab.csv (exportable table)

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Load JK Spec A Data and Create Predicted Spending Quartiles
*** ---------------------------------------------------------------------------

use jk_reg_A, clear

*--- Create quartiles of predicted spending (for treated states only)
*    Note: pred_q may already exist but we recreate for clarity
capture drop pred_spend_q
astile pred_spend_q = pred_spend if ever_treated == 1, nq(4)

*--- Label the quartile variables for clarity
label define pre_q_lbl 1 "Q1 (Low Base)" 2 "Q2" 3 "Q3" 4 "Q4 (High Base)"
label values pre_q pre_q_lbl

label define pred_q_lbl 1 "Q1 (Low Pred)" 2 "Q2" 3 "Q3" 4 "Q4 (High Pred)"
label values pred_spend_q pred_q_lbl

*** ---------------------------------------------------------------------------
*** Section 2: Overall Cross-Tabulation (All States)
*** ---------------------------------------------------------------------------

display _n
display as result "=============================================================="
display as result "OVERALL CROSS-TABULATION: pre_q (rows) vs pred_spend_q (cols)"
display as result "=============================================================="
display as text "(Treated states only)"

tab pre_q pred_spend_q if ever_treated == 1, row

display _n
display as result "Row percentages show: Of counties in each baseline quartile,"
display as result "what % fall into each predicted spending quartile?"

*** ---------------------------------------------------------------------------
*** Section 3: State-by-State Cross-Tabulations
*** ---------------------------------------------------------------------------

display _n
display as result "=============================================================="
display as result "STATE-BY-STATE CROSS-TABULATIONS"
display as result "=============================================================="

*--- Get list of treated states
levelsof state_fips if ever_treated == 1, local(treated_states)

*--- Loop through each treated state
foreach s of local treated_states {

    display _n
    display as result "--------------------------------------------------------------"
    display as result "STATE FIPS: `s'"
    display as result "--------------------------------------------------------------"

    *--- Show basic counts
    quietly count if state_fips == "`s'" & ever_treated == 1
    display as text "Number of county-year observations: " r(N)

    quietly distinct county_id if state_fips == "`s'" & ever_treated == 1
    display as text "Number of unique counties: " r(ndistinct)

    *--- Cross-tab with row percentages
    tab pre_q pred_spend_q if state_fips == "`s'" & ever_treated == 1, row nofreq

    *--- Summary of predicted spending values
    quietly summarize pred_spend if state_fips == "`s'" & ever_treated == 1
    display as text "Predicted spending: mean=" %6.4f r(mean) " min=" %6.4f r(min) " max=" %6.4f r(max)
}

*** ---------------------------------------------------------------------------
*** Section 4: Create Summary Dataset by State
*** ---------------------------------------------------------------------------

display _n
display as result "=============================================================="
display as result "CREATING SUMMARY DATASET BY STATE"
display as result "=============================================================="

*--- Collapse to state-level summary for each pre_q × pred_spend_q cell
preserve

keep if ever_treated == 1

*--- Create a unique observation per county (use first year)
bysort county_id: keep if _n == 1

*--- Generate cell counts
gen n = 1

*--- Collapse to state × pre_q × pred_spend_q level
collapse (count) n_counties = n, by(state_fips pre_q pred_spend_q)

*--- Reshape to wide format for easier viewing
reshape wide n_counties, i(state_fips pre_q) j(pred_spend_q)

*--- Clean up variable names
rename n_counties1 pred_q1
rename n_counties2 pred_q2
rename n_counties3 pred_q3
rename n_counties4 pred_q4

*--- Replace missing with 0
foreach v in pred_q1 pred_q2 pred_q3 pred_q4 {
    replace `v' = 0 if missing(`v')
}

*--- Calculate row total
gen total = pred_q1 + pred_q2 + pred_q3 + pred_q4

*--- Calculate percentages
gen pct_pred_q1 = 100 * pred_q1 / total
gen pct_pred_q2 = 100 * pred_q2 / total
gen pct_pred_q3 = 100 * pred_q3 / total
gen pct_pred_q4 = 100 * pred_q4 / total

*--- Label variables
label var state_fips "State FIPS"
label var pre_q "Baseline Spending Quartile"
label var pred_q1 "N in Pred Q1 (Low)"
label var pred_q2 "N in Pred Q2"
label var pred_q3 "N in Pred Q3"
label var pred_q4 "N in Pred Q4 (High)"
label var total "Total Counties"
label var pct_pred_q1 "% in Pred Q1"
label var pct_pred_q2 "% in Pred Q2"
label var pct_pred_q3 "% in Pred Q3"
label var pct_pred_q4 "% in Pred Q4"

*--- Sort and display
sort state_fips pre_q
order state_fips pre_q pred_q1 pred_q2 pred_q3 pred_q4 total pct_pred_q1 pct_pred_q2 pct_pred_q3 pct_pred_q4

save jk_spec_A_state_diagnostics, replace

*--- Export to CSV for easy sharing
export delimited using "jk_spec_A_state_crosstab.csv", replace

display as result "Saved: jk_spec_A_state_diagnostics.dta"
display as result "Saved: jk_spec_A_state_crosstab.csv"

restore

*** ---------------------------------------------------------------------------
*** Section 5: Identify Problematic Patterns
*** ---------------------------------------------------------------------------

display _n
display as result "=============================================================="
display as result "DIAGNOSTIC: STATES WHERE MAPPING IS UNEXPECTED"
display as result "=============================================================="
display as text "Looking for states where low baseline spending (pre_q=1)"
display as text "maps to LOW predicted increase (pred_spend_q=1,2)"
display as text "This is the OPPOSITE of what we'd expect from reforms."
display _n

preserve

keep if ever_treated == 1
bysort county_id: keep if _n == 1

*--- For each state, calculate % of pre_q=1 counties in pred_spend_q=1,2
gen low_base = (pre_q == 1)
gen low_pred = (pred_spend_q <= 2)
gen unexpected = (low_base == 1 & low_pred == 1)

collapse (sum) n_low_base = low_base n_unexpected = unexpected (count) n_total = pre_q, by(state_fips)

*--- Calculate percentage
gen pct_unexpected = 100 * n_unexpected / n_low_base if n_low_base > 0

*--- Flag states with high unexpected rates
gen flag_unexpected = (pct_unexpected > 50 & !missing(pct_unexpected))

*--- Display problematic states
sort pct_unexpected
list state_fips n_low_base n_unexpected pct_unexpected if flag_unexpected == 1, noobs

display _n
display as result "States above have >50% of low-baseline counties"
display as result "receiving LOW predicted spending increases."

restore

*** ---------------------------------------------------------------------------
*** Section 6: Examine Predicted Spending Distribution by Pre_Q
*** ---------------------------------------------------------------------------

display _n
display as result "=============================================================="
display as result "PREDICTED SPENDING DISTRIBUTION BY BASELINE QUARTILE"
display as result "=============================================================="

preserve
keep if ever_treated == 1
bysort county_id: keep if _n == 1

*--- Summary statistics by baseline quartile
bysort pre_q: summarize pred_spend, detail

restore

*** ---------------------------------------------------------------------------
*** Section 7: Compare Coefficients That Drive Predictions
*** ---------------------------------------------------------------------------

display _n
display as result "=============================================================="
display as result "EXAMINING PREDICTION MECHANICS"
display as result "=============================================================="
display as text "The predicted spending is calculated as:"
display as text "  pred_spend = avg_main + avg_ppe_q (for q=2,3,4)"
display as text "  pred_spend = avg_main           (for q=1)"
display as text ""
display as text "If avg_ppe_q is POSITIVE for q=2,3,4, then higher baseline"
display as text "spending quartiles get HIGHER predicted increases."
display as text "This would be OPPOSITE to reform intent!"
display _n

*--- Show the distribution of key variables
preserve
keep if ever_treated == 1
bysort county_id: keep if _n == 1

display as result "Average predicted spending by baseline quartile:"
table pre_q, statistic(mean pred_spend) statistic(sd pred_spend) statistic(count pred_spend)

restore

*** ---------------------------------------------------------------------------
*** Section 8: Final Summary Table
*** ---------------------------------------------------------------------------

display _n
display as result "=============================================================="
display as result "FINAL SUMMARY: CROSS-TAB WITH PERCENTAGES"
display as result "=============================================================="

preserve
keep if ever_treated == 1
bysort county_id: keep if _n == 1

display as text "Each cell shows: count (row %)"
tab pre_q pred_spend_q, row

restore

display _n
display as result "=============================================================="
display as result "ANALYSIS COMPLETE"
display as result "=============================================================="
display as text "Key files created:"
display as text "  - jk_spec_A_state_diagnostics.dta"
display as text "  - jk_spec_A_state_crosstab.csv"
display _n
display as text "Next steps:"
display as text "  1. Check if avg_ppe coefficients have expected signs"
display as text "  2. Examine states with unexpected patterns"
display as text "  3. Consider whether model specification captures reform effects"
