/*==============================================================================
Project    : School Spending – Jackknife Test: Equity vs Adequacy Reform Types
File       : 09_jackknife_equity_adequacy_test.do
Purpose    : Test hypothesis that collapsing reform types into Equity vs Adequacy
             will produce well-ordered quartile estimates in the jackknife procedure
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-12-28
───────────────────────────────────────────────────────────────────────────────

HYPOTHESIS BEING TESTED:
  The scrambled quartile ordering in "Spending * Income * Reform" specification
  is caused by single-state reform types. When a state is dropped in the jackknife,
  its unique reform type cannot be estimated, leading to incomplete predictions.

  SOLUTION BEING TESTED:
  Use reform_eq directly to distinguish reform types:
    - reform_eq = 0: Adequacy states (AL, ID, MI, OH, KY, MO)
    - reform_eq = 1: Equity states (TX, NM, AR)

  This gives us 6 states in "adequacy" and 3 states in "equity", so when we
  drop any one state, we still have data to estimate that reform category's effect.

ORIGINAL REFORM TYPE BREAKDOWN (from JJP 2016):
  Type 1: Adequacy only                     - ID, MI, OH (3 states)
  Type 2: Adequacy + Local Effort Equal.    - KY, MO (2 states)
  Type 3: Adequacy + Equalization Plan      - AL only (1 state)
  Type 4: Equity only                       - TX only (1 state)
  Type 5: Equity + Equalization Plan        - NM only (1 state)
  Type 6: Equity + Minimum Foundation Plan  - AR only (1 state)

COLLAPSED CATEGORIES (using reform_eq):
  reform_eq = 0 (Adequacy, Types 1-3): AL, ID, MI, OH, KY, MO  → 6 states
  reform_eq = 1 (Equity, Types 4-6):   TX, NM, AR              → 3 states

INPUTS:
  - jjp_balance2.dta       (balanced panel from 06_A_county_balanced_figure1.do)

OUTPUTS:
  - jackknife_predictions_spec_D.dta   (predicted spending with collapsed reform types)
  - jk_q_D_quartiles.png               (quartile event-study graph)

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Load Balanced Panel and Verify reform_eq
*** ---------------------------------------------------------------------------

use jjp_balance2, clear

*--- Rename baseline spending quartile for simplicity
rename pre_q1971 pre_q

*--- Diagnostic: Check the distribution of reform_eq by state
di _n "===== REFORM_EQ DISTRIBUTION BY STATE ====="
tab state_fips reform_eq if ever_treated == 1, m

* Count states in each category
preserve
keep if ever_treated == 1
collapse (max) reform_eq, by(state_fips)
count if reform_eq == 0
di "States in ADEQUACY category (reform_eq=0): `r(N)'"
count if reform_eq == 1
di "States in EQUITY category (reform_eq=1): `r(N)'"
list state_fips reform_eq, sep(0)
restore

save jjp_jackknife_prep_D, replace

*** ---------------------------------------------------------------------------
*** Section 2: Baseline Estimation (No Jackknife) - Spec D
*** Specification: Spending + Income + reform_eq (Equity vs Adequacy)
*** ---------------------------------------------------------------------------

use jjp_jackknife_prep_D, clear

*--- Full Specification with reform_eq ---
*    Three-way interactions: lag/lead × income quartile × reform_eq

areg lexp_ma_strict ///
    i.lag_*##i.pre_q     i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q##i.reform_eq i.lead_*##i.inc_q##i.reform_eq ///
    i.year_unified##(i.pre_q i.inc_q i.reform_eq) ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)

estimates save model_baseline_D, replace

*** ---------------------------------------------------------------------------
*** Section 3: Baseline Predictions (No Jackknife) - Spec D
*** ---------------------------------------------------------------------------

use jjp_jackknife_prep_D, clear
estimates use model_baseline_D

/* ---------------------------------------------------------
   1. Generate Global Time Trend (Lags 2-7)
   --------------------------------------------------------- */
forvalues t = 2/7 {
    gen main_`t' = .
    scalar coeff_main = _b[1.lag_`t']
    replace main_`t' = coeff_main
}
egen avg_main = rowmean(main_2-main_7)

/* ---------------------------------------------------------
   2. Generate Spending Trends
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen ppe_`t'_`q' = .
        scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
        replace ppe_`t'_`q' = coeff_ppe
    }
}
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean(ppe_2_`q'-ppe_7_`q')
}

/* ---------------------------------------------------------
   3. Generate Base Income Trends (Applies to EVERYONE)
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc_`t'_`q' = .
        scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
        replace inc_`t'_`q' = coeff_inc
    }
}
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc_2_`q'-inc_7_`q')
}

/* ---------------------------------------------------------
   4. Generate Reform Effects (reform_eq: 0=Adequacy, 1=Equity)
   --------------------------------------------------------- */

/* A. Main Reform Effect (for reform_eq = 1, i.e., Equity states) */
forvalues t = 2/7 {
    gen ref_main_`t' = .
    capture scalar c_ref = _b[1.lag_`t'#1.reform_eq]
    if _rc scalar c_ref = 0
    replace ref_main_`t' = c_ref
}
egen avg_ref_main = rowmean(ref_main_2 - ref_main_7)

/* B. Triple Interaction (Extra Effect for Q2-4 in Equity states) */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen triple_`t'_`q' = .
        capture scalar c_trip = _b[1.lag_`t'#`q'.inc_q#1.reform_eq]
        if _rc scalar c_trip = 0
        replace triple_`t'_`q' = c_trip
    }
}
forvalues q = 2/4 {
    egen avg_triple_`q' = rowmean(triple_2_`q' - triple_7_`q')
}

/* ---------------------------------------------------------
   5. Calculate Total Predicted Spending
   --------------------------------------------------------- */

/* A. Start with Global Time Trend */
gen pred_spend = avg_main if !missing(pre_q)

/* B. Add Pre-Reform Spending Quartile Trends (Applies to all) */
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

/* C. Add Base Income Quartile Trends (Applies to all) */
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

/* D. Add Reform Effects (Equity adjustment for reform_eq = 1) */
replace pred_spend = pred_spend + avg_ref_main if reform_eq == 1

forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_triple_`q' if reform_eq == 1 & inc_q == `q'
}

save baseline_predictions_spec_D, replace

*** ---------------------------------------------------------------------------
*** Section 4: JACKKNIFE PROCEDURE - Spec D (Using reform_eq)
*** Leave-One-State-Out with reform_eq
*** ---------------------------------------------------------------------------

*--- Get list of all states
use jjp_jackknife_prep_D, clear
levelsof state_fips, local(states)
local n_states : word count `states'

*--- Save master file for repeated loading
tempfile master_data
save `master_data'

di _n "===== STARTING JACKKNIFE PROCEDURE ====="
di "Total states to process: `n_states'"

*** ---------------------------------------------------------------------------
*** 4.A. Run Jackknife Regressions (Leave-One-State-Out)
*** ---------------------------------------------------------------------------

local counter = 0
foreach s of local states {
    local counter = `counter' + 1
    di as text "  [`counter'/`n_states'] Running regression excluding state `s'..."

    use `master_data', clear
    drop if state_fips == "`s'"

    * Run Spec D regression excluding state `s'
    areg lexp_ma_strict ///
        i.lag_*##i.pre_q     i.lead_*##i.pre_q ///
        i.lag_*##i.inc_q##i.reform_eq i.lead_*##i.inc_q##i.reform_eq ///
        i.year_unified##(i.pre_q i.inc_q i.reform_eq) ///
        [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    * Save estimates
    estimates save jackknife_D_state_`s', replace
}

*** ---------------------------------------------------------------------------
*** 4.B. Extract Coefficients and Calculate Predicted Spending
*** ---------------------------------------------------------------------------

di _n "===== EXTRACTING COEFFICIENTS ====="

local counter = 0
foreach s of local states {
    local counter = `counter' + 1
    di as text "  [`counter'/`n_states'] Extracting coefficients for state `s'..."

    preserve
    use `master_data', clear
    estimates use jackknife_D_state_`s'

    /* ---------------------------------------------------------
       1. Generate Global Time Trend (Lags 2-7)
       --------------------------------------------------------- */
    forvalues t = 2/7 {
        gen main_`t' = .
        scalar coeff_main = _b[1.lag_`t']
        replace main_`t' = coeff_main
    }
    egen avg_main = rowmean(main_2-main_7)

    /* ---------------------------------------------------------
       2. Generate Spending Trends
       --------------------------------------------------------- */
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen ppe_`t'_`q' = .
            scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
            replace ppe_`t'_`q' = coeff_ppe
        }
    }
    forvalues q = 2/4 {
        egen avg_ppe_`q' = rowmean(ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
    }

    /* ---------------------------------------------------------
       3. Generate Base Income Trends
       --------------------------------------------------------- */
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen inc_`t'_`q' = .
            scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
            replace inc_`t'_`q' = coeff_inc
        }
    }
    forvalues q = 2/4 {
        egen avg_inc_`q' = rowmean(inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
    }

    /* ---------------------------------------------------------
       4. Generate Reform Effects (reform_eq: 0=Adequacy, 1=Equity)
       KEY: With collapsed categories, we should always have states
       remaining in each category even after dropping one state
       --------------------------------------------------------- */

    /* A. Main Reform Effect (for Equity states, reform_eq=1) */
    forvalues t = 2/7 {
        gen ref_main_`t' = .
        capture scalar c_ref = _b[1.lag_`t'#1.reform_eq]
        if _rc {
            di as text "    Note: Missing coefficient for lag_`t' # reform_eq (setting to 0)"
            scalar c_ref = 0
        }
        replace ref_main_`t' = c_ref
    }
    egen avg_ref_main = rowmean(ref_main_2 ref_main_3 ref_main_4 ref_main_5 ref_main_6 ref_main_7)

    /* B. Triple Interaction (Extra Effect for Q2-4 in Equity states) */
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen triple_`t'_`q' = .
            capture scalar c_trip = _b[1.lag_`t'#`q'.inc_q#1.reform_eq]
            if _rc scalar c_trip = 0
            replace triple_`t'_`q' = c_trip
        }
    }
    forvalues q = 2/4 {
        egen avg_triple_`q' = rowmean( ///
            triple_2_`q' triple_3_`q' triple_4_`q' ///
            triple_5_`q' triple_6_`q' triple_7_`q')
    }

    /* ---------------------------------------------------------
       5. Calculate Total Predicted Spending
       --------------------------------------------------------- */

    /* A. Start with Global Time Trend */
    gen pred_spend = avg_main if !missing(pre_q)

    /* B. Add Pre-Reform Spending Quartile Trends */
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
    }

    /* C. Add Base Income Quartile Trends */
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
    }

    /* D. Add Reform Effects (Equity adjustment for reform_eq = 1) */
    replace pred_spend = pred_spend + avg_ref_main if reform_eq == 1

    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_triple_`q' if reform_eq == 1 & inc_q == `q'
    }

    * Keep only the excluded state's predictions
    keep if state_fips == "`s'"
    save pred_temp_D_`s', replace
    restore
}

*** ---------------------------------------------------------------------------
*** Section 5: Combine Predictions and Create Quartiles
*** ---------------------------------------------------------------------------

di _n "===== COMBINING PREDICTIONS ====="

use `master_data', clear
levelsof state_fips, local(states)

clear
tempfile jk_empty_D
save `jk_empty_D', emptyok

*--- Append predicted spending from all states
foreach s of local states {
    append using pred_temp_D_`s'.dta
}

save jackknife_predictions_spec_D, replace

*--- Create quartiles of predicted spending
xtile pred_q = pred_spend if ever_treated == 1, nq(4)

* Setup Groups: Keep only specific Quartile (q) AND Control Group (0)
replace pred_q = 0 if never_treated == 1
tab pred_q, m

save jk_q_D, replace

*** ---------------------------------------------------------------------------
*** Section 6: Diagnostic - Compare Reform Type Distribution
*** ---------------------------------------------------------------------------

di _n "===== DIAGNOSTIC: REFORM_EQ BY PREDICTED SPENDING QUARTILE ====="

use jk_q_D, clear

* Check how reform_eq is distributed across predicted spending quartiles
tab pred_q reform_eq if ever_treated == 1, row

* Summary statistics for predicted spending by reform_eq
bysort reform_eq: summ pred_spend if ever_treated == 1

*** ---------------------------------------------------------------------------
*** Section 7: Generate Event-Study Graph (Quartiles)
*** ---------------------------------------------------------------------------

di _n "===== GENERATING QUARTILE EVENT-STUDY GRAPH ====="

* 1. Initialize results file
tempfile combined_results
postfile handle str15 term float(rel_year b se) int q_group using `combined_results'

* 2. Loop through Quartiles
forvalues q = 1/4 {
    di as text "  Running regression for Quartile `q'..."

    * Load Data
    use jk_q_D, clear

    * Keep only specific Quartile (q) AND Control Group (0)
    keep if pred_q == `q' | pred_q == 0

    *--- Weighted Event-Study Regression ---
    areg lexp_ma_strict ///
        i.lag_* i.lead_* ///
        i.year_unified [aw=school_age_pop] ///
        if (reform_year < 2000 | never_treated == 1), ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract coefficients ---

    * Leads
    forvalues k = 5(-1)1 {
        lincom 1.lead_`k'
        post handle ("lead`k'") (-`k') (r(estimate)) (r(se)) (`q')
    }

    * Base
    post handle ("base") (0) (0) (0) (`q')

    * Lags
    forvalues k = 1/17 {
        lincom 1.lag_`k'
        post handle ("lag`k'") (`k') (r(estimate)) (r(se)) (`q')
    }
}
postclose handle

*** ---------------------------------------------------------------------------
*** Section 8: Create Plot
*** ---------------------------------------------------------------------------

use `combined_results', clear

* Formatting
gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se
sort q_group rel_year

* Define Colors
local c1 "red"
local c2 "orange"
local c3 "forest_green"
local c4 "blue"

twoway ///
    (rarea ci_lo ci_hi rel_year if q_group == 1, fcolor(`c1'%10) lwidth(none)) ///
    (rarea ci_lo ci_hi rel_year if q_group == 2, fcolor(`c2'%10) lwidth(none)) ///
    (rarea ci_lo ci_hi rel_year if q_group == 3, fcolor(`c3'%10) lwidth(none)) ///
    (rarea ci_lo ci_hi rel_year if q_group == 4, fcolor(`c4'%10) lwidth(none)) ///
    (line b rel_year if q_group == 1, lcolor(`c1') lpattern(solid) lwidth(medthick)) ///
    (line b rel_year if q_group == 2, lcolor(`c2') lpattern(solid) lwidth(medthick)) ///
    (line b rel_year if q_group == 3, lcolor(`c3') lpattern(solid) lwidth(medthick)) ///
    (line b rel_year if q_group == 4, lcolor(`c4') lpattern(solid) lwidth(medthick)), ///
    yline(0, lcolor(gs12) lpattern(solid)) ///
    xline(0, lcolor(gs10) lpattern(dash)) ///
    xline(2 7, lcolor(blue) lpattern(dash)) ///
    legend(order(5 "Q1 (Lowest)" 6 "Q2" 7 "Q3" 8 "Q4 (Highest)") ///
           pos(6) rows(1) region(lcolor(none))) ///
    title("Jackknife: Spending * Income * Reform (Equity/Adequacy)") ///
    subtitle("Estimates by Quartile of Predicted Spending") ///
    ytitle("Change in ln(13-yr rolling avg PPE)", size(small)) ///
    xtitle("Years relative to reform", size(small)) ///
    note("reform_eq: 0=Adequacy (AL,ID,MI,OH,KY,MO), 1=Equity (TX,NM,AR)") ///
    graphregion(color(white)) plotregion(margin(medium))

* Save graph
graph export "$SchoolSpending/output/jk/jk_q_D_equity_adequacy_quartiles.png", replace

*** ---------------------------------------------------------------------------
*** Section 9: Summary Statistics and Validation
*** ---------------------------------------------------------------------------

di _n "===== SUMMARY: PREDICTED SPENDING BY QUARTILE ====="

use jk_q_D, clear

* Summary of predicted spending by quartile
bysort pred_q: summ pred_spend if ever_treated == 1, detail

* Check for well-ordered means (Q4 > Q3 > Q2 > Q1)
preserve
collapse (mean) mean_pred = pred_spend, by(pred_q)
list pred_q mean_pred, sep(0)
restore

di _n "===== ANALYSIS COMPLETE ====="
di "If the quartiles are well-ordered (Q4 highest, Q1 lowest), the hypothesis is supported."
di "Check the graph at: $SchoolSpending/output/jk/jk_q_D_equity_adequacy_quartiles.png"

*** ---------------------------------------------------------------------------
*** Section 10: Cleanup Temporary Files
*** ---------------------------------------------------------------------------

* Optionally remove temporary prediction files
* Uncomment to clean up:
/*
foreach s of local states {
    capture erase pred_temp_D_`s'.dta
    capture erase jackknife_D_state_`s'.ster
}
*/

di _n "===== DONE ====="
