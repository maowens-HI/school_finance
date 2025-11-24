/*==============================================================================
Project    : School Spending – Jackknife Regression Estimation (Approach II)
File       : 08_jackknife_approach_ii.do
Purpose    : Implement JJP (2016) Approach II - Leave-One-State-Out Jackknife
             with comprehensive heterogeneity analysis
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-01-24
───────────────────────────────────────────────────────────────────────────────

METHODOLOGY (Following JJP 2016 Approach II):
  This file implements the leave-one-state-out jackknife approach described in
  Jackson, Johnson, and Persico (2016) footnotes 20-21. The predicted spending
  change for each state is calculated using coefficients estimated from all
  OTHER states, creating an instrumental variable for heterogeneity analysis.

WORKFLOW (Following Whiteboard):

  PHASE 1: BASELINE ESTIMATION (No Jackknife)
    1.A. Spending Quartile only
    1.B. Spending + Income Quartile
    1.C. Spending + Income + Reform types

  PHASE 2: JACKKNIFE (Leave-One-Out) - MIRRORS PHASE 1 STRUCTURE
    2.A. Spending Quartile only
    2.B. Spending + Income Quartile
    2.C. Spending + Income + Reform types

  PHASE 3: GRAPHS
    Definition A: high = (pred_spend > 0)
    Definition B: high = (quartile(pred_spend) > 2)

    Graph I:  High vs Low groups
    Graph II: All 4 predicted spending quartiles

INPUTS:
  - jjp_balance.dta        (balanced panel from 06_A_county_balanced_figure1.do)

OUTPUTS:
  - jackknife_predictions_spec_[A|B|C].dta  (predicted spending by specification)
  - Event-study graphs by definition and specification

KEY VARIABLES:
  - lexp_ma_strict         : Log per-pupil expenditure (13-yr rolling mean)
  - pre_q1971              : Baseline spending quartile (1971)
  - inc_q                  : Income quartile (1969 median family income)
  - reform_eq, reform_mfp, etc. : Reform type indicators
  - pred_spend             : Predicted spending increase from jackknife

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending\data"

*** ---------------------------------------------------------------------------
*** Section 1: Load Balanced Panel and Prepare Variables
*** ---------------------------------------------------------------------------

use jjp_balance, clear

*--- Verify key variables exist
ds pre_q1971 inc_q reform_eq reform_mfp reform_ep reform_le reform_sl
if _rc != 0 {
    di as error "ERROR: Required variables missing from jjp_balance.dta"
    di as error "Expected: pre_q1971, inc_q, reform_eq, reform_mfp, reform_ep, reform_le, reform_sl"
    exit 111
}

*--- Rename baseline spending quartile for simplicity
capture rename pre_q1971 pre_q

*--- Ensure reform types are binary (0 if missing)
local reforms reform_eq reform_mfp reform_ep reform_le reform_sl
foreach r of local reforms {
    replace `r' = 0 if missing(`r')
}

*--- Create income quartile if missing (from median family income)
capture confirm variable inc_q
if _rc != 0 {
    di as text "Creating income quartile from median family income..."

    * Parse median family income from GRF data
    capture gen med_fam_inc = real(regexr(median_family_income, "[^0-9]", ""))

    * Create income quartiles within state
    preserve
    duplicates drop county_id, force
    bysort state_fips: egen inc_q = xtile(med_fam_inc), n(4)
    keep state_fips county_id inc_q
    tempfile inc_q_temp
    save `inc_q_temp'
    restore

    merge m:1 state_fips county_id using `inc_q_temp', nogen
}

*--- Display summary statistics
di _n "=== SAMPLE SUMMARY ==="
tab ever_treated
tab pre_q if ever_treated == 1
tab inc_q if ever_treated == 1
foreach r of local reforms {
    summ `r' if ever_treated == 1
}

save jjp_jackknife_prep, replace

*** ---------------------------------------------------------------------------
*** PHASE 1: BASELINE ESTIMATION (No Jackknife)
*** Store models for comparison and understanding
*** ---------------------------------------------------------------------------

di _n(2) "========================================"
di "PHASE 1: BASELINE ESTIMATION (No Jackknife)"
di "========================================"

use jjp_jackknife_prep, clear

*--- 1.A. Spending Quartile Only ---
di _n "--- Specification 1.A: Spending Quartile ---"
areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.year_unified##i.pre_q ///
    [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)
eststo model_A
estimates save model_baseline_A, replace

*--- 1.B. Spending + Income Quartiles ---
di _n "--- Specification 1.B: Spending + Income ---"
areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q i.lead_*##i.inc_q ///
    i.year_unified##(i.pre_q i.inc_q) ///
    [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)
eststo model_B
estimates save model_baseline_B, replace

*--- 1.C. Full Specification (Spending + Income + Reform Types) ---
di _n "--- Specification 1.C: Full Heterogeneity ---"
areg lexp_ma_strict ///
    i.lag_*##i.pre_q     i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q     i.lead_*##i.inc_q ///
    i.lag_*##i.reform_eq i.lead_*##i.reform_eq ///
    i.lag_*##i.reform_mfp i.lead_*##i.reform_mfp ///
    i.lag_*##i.reform_ep i.lead_*##i.reform_ep ///
    i.lag_*##i.reform_le i.lead_*##i.reform_le ///
    i.lag_*##i.reform_sl i.lead_*##i.reform_sl ///
    i.year_unified##(i.pre_q i.inc_q i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
    [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)
eststo model_C
estimates save model_baseline_C, replace

*--- Export baseline comparison table ---
esttab model_A model_B model_C using "baseline_models_comparison.csv", ///
    replace csv se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(*.lag_*) label nonotes

di _n "Phase 1 Complete: All baseline models estimated and saved"

*** ---------------------------------------------------------------------------
*** PHASE 2: JACKKNIFE PROCEDURE (Leave-One-State-Out)
*** Following JJP (2016) Approach II methodology
*** Structure mirrors Phase 1: 2.A, 2.B, 2.C
*** ---------------------------------------------------------------------------

di _n(2) "========================================"
di "PHASE 2: JACKKNIFE ESTIMATION"
di "========================================"

*--- Get list of all states
use jjp_jackknife_prep, clear
levelsof state_fips, local(states)
local n_states : word count `states'
di "Total states to jackknife: `n_states'"

*--- Save master file for repeated loading
tempfile master_data
save `master_data'

*** ---------------------------------------------------------------------------
*** 2.A. Jackknife: Spending Quartile Only
*** ---------------------------------------------------------------------------

di _n(2) "--- Specification 2.A: Spending Quartile (Jackknife) ---"

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

    * Show progress every 5 states
    if mod(`state_count', 5) == 0 {
        di "  [2.A] Progress: `state_count'/`n_states' states processed..."
    }

    quietly {
        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec A regression excluding state `s'
        areg lexp_ma_strict ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.year_unified##i.pre_q ///
            [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        * Save estimates
        estimates save jackknife_A_state_`s', replace
    }
}
di "  Specification 2.A complete: `n_states' jackknife regressions run"

*--- Extract coefficients and calculate predicted spending for Spec A ---
di "  Extracting coefficients and calculating predictions..."

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

    if mod(`state_count', 10) == 0 {
        di "    Extracting: `state_count'/`n_states'..."
    }

    quietly {
        * Load master data and estimates for this state
        use `master_data', clear
        estimates use jackknife_A_state_`s'

        * Initialize prediction variable
        gen pred_spend_A = 0 if state_fips == "`s'"

        *--- Extract and average main effects (lags 2-7 per JJP) ---
        local sum_main = 0
        local n_lags = 0
        forvalues t = 2/7 {
            capture scalar beta_main = _b[1.lag_`t']
            if _rc == 0 & !missing(beta_main) {
                local sum_main = `sum_main' + beta_main
                local n_lags = `n_lags' + 1
            }
        }
        if `n_lags' > 0 {
            replace pred_spend_A = pred_spend_A + (`sum_main' / `n_lags') ///
                if state_fips == "`s'"
        }

        *--- Add baseline spending quartile interactions ---
        forvalues q = 2/4 {
            local sum_ppe = 0
            local n_ppe = 0
            forvalues t = 2/7 {
                capture scalar beta_ppe = _b[1.lag_`t'#`q'.pre_q]
                if _rc == 0 & !missing(beta_ppe) {
                    local sum_ppe = `sum_ppe' + beta_ppe
                    local n_ppe = `n_ppe' + 1
                }
            }
            if `n_ppe' > 0 {
                replace pred_spend_A = pred_spend_A + (`sum_ppe' / `n_ppe') ///
                    if state_fips == "`s'" & pre_q == `q'
            }
        }

        * Keep only the excluded state's predictions
        keep if state_fips == "`s'"
        keep county_id state_fips year_unified relative_year pred_spend_A ///
             pre_q inc_q reform_* never_treated ever_treated school_age_pop ///
             lexp_ma_strict reform_year

        save pred_temp_A_`s', replace
    }
}

* Combine all states for Spec A
clear
foreach s of local states {
    append using pred_temp_A_`s'
    erase pred_temp_A_`s'.dta
}

* Merge with full dataset
merge 1:1 county_id year_unified using `master_data', ///
    update replace nogen

* Summary statistics
di _n "  Predicted Spending Distribution - Spec A:"
summ pred_spend_A if ever_treated == 1, detail

save jackknife_predictions_spec_A, replace
di "  Saved: jackknife_predictions_spec_A.dta"

*** ---------------------------------------------------------------------------
*** 2.B. Jackknife: Spending + Income Quartiles
*** ---------------------------------------------------------------------------

di _n(2) "--- Specification 2.B: Spending + Income (Jackknife) ---"

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

    * Show progress every 5 states
    if mod(`state_count', 5) == 0 {
        di "  [2.B] Progress: `state_count'/`n_states' states processed..."
    }

    quietly {
        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec B regression excluding state `s'
        areg lexp_ma_strict ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.lag_*##i.inc_q i.lead_*##i.inc_q ///
            i.year_unified##(i.pre_q i.inc_q) ///
            [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        * Save estimates
        estimates save jackknife_B_state_`s', replace
    }
}
di "  Specification 2.B complete: `n_states' jackknife regressions run"

*--- Extract coefficients and calculate predicted spending for Spec B ---
di "  Extracting coefficients and calculating predictions..."

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

    if mod(`state_count', 10) == 0 {
        di "    Extracting: `state_count'/`n_states'..."
    }

    quietly {
        * Load master data and estimates for this state
        use `master_data', clear
        estimates use jackknife_B_state_`s'

        * Initialize prediction variable
        gen pred_spend_B = 0 if state_fips == "`s'"

        *--- Extract and average main effects (lags 2-7) ---
        local sum_main = 0
        local n_lags = 0
        forvalues t = 2/7 {
            capture scalar beta_main = _b[1.lag_`t']
            if _rc == 0 & !missing(beta_main) {
                local sum_main = `sum_main' + beta_main
                local n_lags = `n_lags' + 1
            }
        }
        if `n_lags' > 0 {
            replace pred_spend_B = pred_spend_B + (`sum_main' / `n_lags') ///
                if state_fips == "`s'"
        }

        *--- Add baseline spending quartile interactions ---
        forvalues q = 2/4 {
            local sum_ppe = 0
            local n_ppe = 0
            forvalues t = 2/7 {
                capture scalar beta_ppe = _b[1.lag_`t'#`q'.pre_q]
                if _rc == 0 & !missing(beta_ppe) {
                    local sum_ppe = `sum_ppe' + beta_ppe
                    local n_ppe = `n_ppe' + 1
                }
            }
            if `n_ppe' > 0 {
                replace pred_spend_B = pred_spend_B + (`sum_ppe' / `n_ppe') ///
                    if state_fips == "`s'" & pre_q == `q'
            }
        }

        *--- Add income quartile interactions ---
        forvalues q = 2/4 {
            local sum_inc = 0
            local n_inc = 0
            forvalues t = 2/7 {
                capture scalar beta_inc = _b[1.lag_`t'#`q'.inc_q]
                if _rc == 0 & !missing(beta_inc) {
                    local sum_inc = `sum_inc' + beta_inc
                    local n_inc = `n_inc' + 1
                }
            }
            if `n_inc' > 0 {
                replace pred_spend_B = pred_spend_B + (`sum_inc' / `n_inc') ///
                    if state_fips == "`s'" & inc_q == `q'
            }
        }

        * Keep only the excluded state's predictions
        keep if state_fips == "`s'"
        keep county_id state_fips year_unified relative_year pred_spend_B ///
             pre_q inc_q reform_* never_treated ever_treated school_age_pop ///
             lexp_ma_strict reform_year

        save pred_temp_B_`s', replace
    }
}

* Combine all states for Spec B
clear
foreach s of local states {
    append using pred_temp_B_`s'
    erase pred_temp_B_`s'.dta
}

* Merge with full dataset
merge 1:1 county_id year_unified using `master_data', ///
    update replace nogen

* Summary statistics
di _n "  Predicted Spending Distribution - Spec B:"
summ pred_spend_B if ever_treated == 1, detail

save jackknife_predictions_spec_B, replace
di "  Saved: jackknife_predictions_spec_B.dta"

*** ---------------------------------------------------------------------------
*** 2.C. Jackknife: Full Heterogeneity (Spending + Income + Reform Types)
*** ---------------------------------------------------------------------------

di _n(2) "--- Specification 2.C: Full Heterogeneity (Jackknife) ---"

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

    * Show progress every 5 states
    if mod(`state_count', 5) == 0 {
        di "  [2.C] Progress: `state_count'/`n_states' states processed..."
    }

    quietly {
        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec C regression excluding state `s'
        areg lexp_ma_strict ///
            i.lag_*##i.pre_q     i.lead_*##i.pre_q ///
            i.lag_*##i.inc_q     i.lead_*##i.inc_q ///
            i.lag_*##i.reform_eq i.lead_*##i.reform_eq ///
            i.lag_*##i.reform_mfp i.lead_*##i.reform_mfp ///
            i.lag_*##i.reform_ep i.lead_*##i.reform_ep ///
            i.lag_*##i.reform_le i.lead_*##i.reform_le ///
            i.lag_*##i.reform_sl i.lead_*##i.reform_sl ///
            i.year_unified##(i.pre_q i.inc_q i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
            [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        * Save estimates
        estimates save jackknife_C_state_`s', replace
    }
}
di "  Specification 2.C complete: `n_states' jackknife regressions run"

*--- Extract coefficients and calculate predicted spending for Spec C ---
di "  Extracting coefficients and calculating predictions..."

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

    if mod(`state_count', 10) == 0 {
        di "    Extracting: `state_count'/`n_states'..."
    }

    quietly {
        * Load master data and estimates for this state
        use `master_data', clear
        estimates use jackknife_C_state_`s'

        * Initialize prediction variable
        gen pred_spend_C = 0 if state_fips == "`s'"

        *--- Extract and average main effects (lags 2-7) ---
        local sum_main = 0
        local n_lags = 0
        forvalues t = 2/7 {
            capture scalar beta_main = _b[1.lag_`t']
            if _rc == 0 & !missing(beta_main) {
                local sum_main = `sum_main' + beta_main
                local n_lags = `n_lags' + 1
            }
        }
        if `n_lags' > 0 {
            replace pred_spend_C = pred_spend_C + (`sum_main' / `n_lags') ///
                if state_fips == "`s'"
        }

        *--- Add baseline spending quartile interactions ---
        forvalues q = 2/4 {
            local sum_ppe = 0
            local n_ppe = 0
            forvalues t = 2/7 {
                capture scalar beta_ppe = _b[1.lag_`t'#`q'.pre_q]
                if _rc == 0 & !missing(beta_ppe) {
                    local sum_ppe = `sum_ppe' + beta_ppe
                    local n_ppe = `n_ppe' + 1
                }
            }
            if `n_ppe' > 0 {
                replace pred_spend_C = pred_spend_C + (`sum_ppe' / `n_ppe') ///
                    if state_fips == "`s'" & pre_q == `q'
            }
        }

        *--- Add income quartile interactions ---
        forvalues q = 2/4 {
            local sum_inc = 0
            local n_inc = 0
            forvalues t = 2/7 {
                capture scalar beta_inc = _b[1.lag_`t'#`q'.inc_q]
                if _rc == 0 & !missing(beta_inc) {
                    local sum_inc = `sum_inc' + beta_inc
                    local n_inc = `n_inc' + 1
                }
            }
            if `n_inc' > 0 {
                replace pred_spend_C = pred_spend_C + (`sum_inc' / `n_inc') ///
                    if state_fips == "`s'" & inc_q == `q'
            }
        }

        *--- Add reform type interactions ---
        local reforms reform_eq reform_mfp reform_ep reform_le reform_sl
        foreach r of local reforms {
            local sum_ref = 0
            local n_ref = 0
            forvalues t = 2/7 {
                capture scalar beta_ref = _b[1.lag_`t'#1.`r']
                if _rc == 0 & !missing(beta_ref) {
                    local sum_ref = `sum_ref' + beta_ref
                    local n_ref = `n_ref' + 1
                }
            }
            if `n_ref' > 0 {
                replace pred_spend_C = pred_spend_C + (`sum_ref' / `n_ref') ///
                    if state_fips == "`s'" & `r' == 1
            }
        }

        * Keep only the excluded state's predictions
        keep if state_fips == "`s'"
        keep county_id state_fips year_unified relative_year pred_spend_C ///
             pre_q inc_q reform_* never_treated ever_treated school_age_pop ///
             lexp_ma_strict reform_year

        save pred_temp_C_`s', replace
    }
}

* Combine all states for Spec C
clear
foreach s of local states {
    append using pred_temp_C_`s'
    erase pred_temp_C_`s'.dta
}

* Merge with full dataset
merge 1:1 county_id year_unified using `master_data', ///
    update replace nogen

* Summary statistics
di _n "  Predicted Spending Distribution - Spec C:"
summ pred_spend_C if ever_treated == 1, detail

save jackknife_predictions_spec_C, replace
di "  Saved: jackknife_predictions_spec_C.dta"

di _n(2) "Phase 2 Complete: All jackknife predictions calculated"

*** ---------------------------------------------------------------------------
*** PHASE 3: GRAPH GENERATION
*** Create high/low classifications and event-study plots
*** ---------------------------------------------------------------------------

di _n(2) "========================================"
di "PHASE 3: GRAPH GENERATION"
di "========================================"

* Process each specification
foreach spec in A B C {
    di _n "--- Graphs for Specification `spec' ---"

    use jackknife_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend_`spec' > 0) if !missing(pred_spend_`spec')
    replace high_def_A = 0 if never_treated == 1

    *--- Definition B: High = Top 2 Quartiles ---
    xtile pred_q = pred_spend_`spec' if ever_treated == 1, nq(4)
    gen high_def_B = (pred_q >= 3) if !missing(pred_q)
    replace high_def_B = 0 if never_treated == 1

    save jackknife_predictions_spec_`spec', replace

    *===========================================================================
    * GRAPH I: High vs Low Comparison (Both Definitions)
    *===========================================================================

    foreach def in A B {
        di "  Creating Graph I for Specification `spec', Definition `def'..."

        * Run event study
        quietly areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified##i.high_def_`def' ///
            [aw = school_age_pop] if (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)

        * Extract coefficients for High group
        tempfile results_high results_low
        postfile h_high str15 term float t b se str10 group using `results_high'

        forvalues k = 5(-1)1 {
            quietly lincom 1.lead_`k' + 1.lead_`k'#1.high_def_`def'
            post h_high ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
        }
        post h_high ("base") (0) (0) (0) ("High")
        forvalues k = 1/17 {
            quietly lincom 1.lag_`k' + 1.lag_`k'#1.high_def_`def'
            post h_high ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
        }
        postclose h_high

        * Extract coefficients for Low group
        postfile h_low str15 term float t b se str10 group using `results_low'

        forvalues k = 5(-1)1 {
            quietly lincom 1.lead_`k'
            post h_low ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Low")
        }
        post h_low ("base") (0) (0) (0) ("Low")
        forvalues k = 1/17 {
            quietly lincom 1.lag_`k'
            post h_low ("lag`k'") (`k') (r(estimate)) (r(se)) ("Low")
        }
        postclose h_low

        * Combine and plot
        use `results_high', clear
        append using `results_low'

        gen ci_lo = b - 1.96*se
        gen ci_hi = b + 1.96*se

        * Title text
        local def_text = cond("`def'" == "A", "High = Predicted > 0", "High = Top 2 Quartiles")

        twoway ///
            (rarea ci_lo ci_hi t if group == "High", color(blue%20) lw(none)) ///
            (line b t if group == "High", lcolor(blue) lwidth(medthick)) ///
            (rarea ci_lo ci_hi t if group == "Low", color(red%20) lw(none)) ///
            (line b t if group == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
            yline(0, lcolor(gs10) lpattern(dash)) ///
            xline(0, lcolor(gs10) lpattern(dash)) ///
            xline(2 7, lcolor(gs12) lwidth(vthin)) ///
            legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
            title("Spec `spec' - Definition `def': High vs Low") ///
            subtitle("`def_text'") ///
            ytitle("Change in ln(13-yr rolling avg PPE)") ///
            xtitle("Years relative to reform") ///
            note("Averaging window: lags 2-7 (vertical lines)") ///
            graphregion(color(white))

        graph export "jackknife_spec_`spec'_def_`def'_high_vs_low.png", replace
    }

    *===========================================================================
    * GRAPH II: All 4 Quartiles
    *===========================================================================

    di "  Creating Graph II (All Quartiles) for Specification `spec'..."

    quietly areg lexp_ma_strict ///
        i.lag_*##i.pred_q i.lead_*##i.pred_q ///
        i.year_unified##i.pred_q ///
        [aw = school_age_pop] if (reform_year < 2000 | never_treated == 1), ///
        absorb(county_id) vce(cluster county_id)

    * Extract coefficients for each quartile
    clear
    tempfile all_quartiles
    save `all_quartiles', emptyok

    forvalues q = 1/4 {
        tempfile q`q'_file
        postfile h_q`q' str15 term float t b se byte quart using `q`q'_file'

        forvalues k = 5(-1)1 {
            quietly lincom 1.lead_`k' + 1.lead_`k'#`q'.pred_q
            post h_q`q' ("lead`k'") (-`k') (r(estimate)) (r(se)) (`q')
        }
        post h_q`q' ("base") (0) (0) (0) (`q')
        forvalues k = 1/17 {
            quietly lincom 1.lag_`k' + 1.lag_`k'#`q'.pred_q
            post h_q`q' ("lag`k'") (`k') (r(estimate)) (r(se)) (`q')
        }
        postclose h_q`q'

        use `q`q'_file', clear
        append using `all_quartiles'
        save `all_quartiles', replace
    }

    use `all_quartiles', clear
    gen ci_lo = b - 1.96*se
    gen ci_hi = b + 1.96*se

    twoway ///
        (line b t if quart == 1, lcolor(navy) lwidth(medthick)) ///
        (line b t if quart == 2, lcolor(forest_green) lwidth(medthick)) ///
        (line b t if quart == 3, lcolor(orange) lwidth(medthick)) ///
        (line b t if quart == 4, lcolor(cranberry) lwidth(medthick)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(1 "Q1 (Lowest)" 2 "Q2" 3 "Q3" 4 "Q4 (Highest)") pos(6) rows(1)) ///
        title("Spec `spec': All Quartiles of Predicted Spending") ///
        ytitle("Change in ln(13-yr rolling avg PPE)") ///
        xtitle("Years relative to reform") ///
        note("Averaging window: lags 2-7 (vertical lines)") ///
        graphregion(color(white))

    graph export "jackknife_spec_`spec'_all_quartiles.png", replace
}

*** ---------------------------------------------------------------------------
*** FINAL SUMMARY AND DIAGNOSTICS
*** ---------------------------------------------------------------------------

di _n(2) "========================================"
di "JACKKNIFE ESTIMATION COMPLETE"
di "========================================"

* Compare predicted spending across specifications
use jackknife_predictions_spec_A, clear
merge 1:1 county_id year_unified using jackknife_predictions_spec_B, nogen
merge 1:1 county_id year_unified using jackknife_predictions_spec_C, nogen

* Summary statistics by specification
di _n "=== Predicted Spending Comparison ==="
summ pred_spend_A pred_spend_B pred_spend_C if ever_treated == 1, detail

* Correlation between specifications
di _n "=== Correlation Between Specifications ==="
corr pred_spend_A pred_spend_B pred_spend_C if ever_treated == 1

* Distribution of high/low classifications
preserve
keep if ever_treated == 1
collapse (first) pred_spend_* high_def_*, by(county_id)

di _n "=== High/Low Classification (Definition A: pred > 0) ==="
tab high_def_A

di _n "=== High/Low Classification (Definition B: top 2 quartiles) ==="
tab high_def_B

* Agreement between definitions
di _n "=== Agreement Between Definitions ==="
tab high_def_A high_def_B
restore

save jackknife_predictions_all_specs, replace

di _n "=== OUTPUT FILES ==="
di "  1. jackknife_predictions_spec_A.dta"
di "  2. jackknife_predictions_spec_B.dta"
di "  3. jackknife_predictions_spec_C.dta"
di "  4. jackknife_predictions_all_specs.dta"
di "  5. 9 PNG graphs (3 specs × 3 types: 2 definitions + 1 quartiles)"
di _n "All jackknife estimation complete!"

*** ---------------------------------------------------------------------------
*** Clean up temporary estimate files
*** ---------------------------------------------------------------------------

foreach spec in A B C {
    foreach s of local states {
        capture erase jackknife_`spec'_state_`s'.ster
    }
}

di _n "Temporary files cleaned up."
di "Script finished successfully."

*** ---------------------------------------------------------------------------
