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

*--- Rename baseline spending quartile for simplicity
rename pre_q1971 pre_q

save jjp_jackknife_prep, replace

*** ---------------------------------------------------------------------------
*** PHASE 1: BASELINE ESTIMATION (No Jackknife)
*** Store models for comparison and understanding
*** ---------------------------------------------------------------------------


use jjp_jackknife_prep, clear

*--- 1.A. Spending Quartile Only ---

areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.year_unified##i.pre_q ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)
eststo model_A
estimates save model_baseline_A, replace

*--- 1.B. Spending + Income Quartiles ---

areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q i.lead_*##i.inc_q ///
    i.year_unified##(i.pre_q i.inc_q) ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)
eststo model_B
estimates save model_baseline_B, replace

*--- 1.C. Full Specification (Spending + Income + Reform Types) ---
*    Three-way interactions: lag/lead × income quartile × reform types
*    This allows effects to vary by BOTH income level AND reform type
areg lexp_ma_strict ///
    i.lag_*##i.pre_q     i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
    i.lead_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
    i.year_unified##(i.pre_q i.inc_q i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)
eststo model_C
estimates save model_baseline_C, replace

*--- Export baseline comparison table ---
esttab model_A model_B model_C using "baseline_models_comparison.csv", ///
    replace csv se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(*.lag_*) label nonotes


*** ---------------------------------------------------------------------------
*** PHASE 1 PREDICTIONS: Calculate Predicted Spending from Baseline Models
*** (Following same approach as Phase 2 jackknife, but using full-sample estimates)
*** ---------------------------------------------------------------------------

*--- 1.A Predictions: Spending Quartile Only ---

use jjp_jackknife_prep, clear
estimates use model_baseline_A

**# Generate Main Effect Coefficients (lags 2-7)
forvalues t = 2/7 {
    gen main_`t' = .
}

* Fill with coefficient values
forvalues t = 2/7 {
    scalar coeff_main = _b[1.lag_`t']
    replace main_`t' = coeff_main
}

**# Generate Baseline Spending Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen ppe_`t'_`q' = .
    }
}

* Fill with coefficient values
forvalues t = 2/7 {
    forvalues q = 2/4 {
        scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
        replace ppe_`t'_`q' = coeff_ppe
    }
}

**# Calculate Averages Across Lags 2-7
*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}

**# Calculate Predicted Spending Increase
gen pred_spend = avg_main if !missing(pre_q)

*--- Add baseline spending interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

save baseline_predictions_spec_A, replace
di "  Saved: baseline_predictions_spec_A.dta"

*--- 1.B Predictions: Spending + Income Quartiles ---

use jjp_jackknife_prep, clear
estimates use model_baseline_B

**# Generate Main Effect Coefficients (lags 2-7)
forvalues t = 2/7 {
    gen main_`t' = .
}

* Fill with coefficient values
forvalues t = 2/7 {
    scalar coeff_main = _b[1.lag_`t']
    replace main_`t' = coeff_main
}

**# Generate Baseline Spending Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen ppe_`t'_`q' = .
    }
}

* Fill with coefficient values
forvalues t = 2/7 {
    forvalues q = 2/4 {
        scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
        replace ppe_`t'_`q' = coeff_ppe
    }
}

**# Generate Income Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc_`t'_`q' = .
    }
}

* Fill with coefficient values
forvalues t = 2/7 {
    forvalues q = 2/4 {
        scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
        replace inc_`t'_`q' = coeff_inc
    }
}

**# Calculate Averages Across Lags 2-7
*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}

*--- Average income interactions
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean( ///
        inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
}

**# Calculate Predicted Spending Increase
gen pred_spend = avg_main if !missing(pre_q)

*--- Add baseline spending interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

*--- Add income interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

save baseline_predictions_spec_B, replace

*--- 1.C Predictions: Spending + Income Quartiles + Reforms---

use jjp_jackknife_prep, clear
estimates use model_baseline_C

**# Generate Main Effect Coefficients (lags 2-7)
forvalues t = 2/7 {
    gen main_`t' = .
}

* Fill with coefficient values
forvalues t = 2/7 {
    scalar coeff_main = _b[1.lag_`t']
    replace main_`t' = coeff_main
}

**# Generate Baseline Spending Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen ppe_`t'_`q' = .
    }
}

* Fill with coefficient values
forvalues t = 2/7 {
    forvalues q = 2/4 {
        scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
        replace ppe_`t'_`q' = coeff_ppe
    }
}

**# Generate Income Quartile Interaction Coefficients (two-way: lag x income)
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc_`t'_`q' = .
    }
}

* Fill with coefficient values
forvalues t = 2/7 {
    forvalues q = 2/4 {
        scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
        replace inc_`t'_`q' = coeff_inc
    }
}

**# Generate Reform Type Interaction Coefficients (two-way: lag x reform)
local reforms reform_eq reform_mfp reform_ep reform_le reform_sl
foreach r of local reforms {
    forvalues t = 2/7 {
        gen `r'_`t' = .
    }
}

* Fill with coefficient values
foreach r of local reforms {
    forvalues t = 2/7 {
        scalar coeff_ref = _b[1.lag_`t'#1.`r']
        replace `r'_`t' = coeff_ref
    }
}

**# Generate Three-Way Interaction Coefficients (lag x income x reform)
local reforms reform_eq reform_mfp reform_ep reform_le reform_sl
foreach r of local reforms {
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen inc_`r'_`t'_`q' = .
        }
    }
}

* Fill with coefficient values
foreach r of local reforms {
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            scalar coeff_3way = _b[1.lag_`t'#`q'.inc_q#1.`r']
            replace inc_`r'_`t'_`q' = coeff_3way
        }
    }
}

**# Calculate Averages Across Lags 2-7
*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}

*--- Average income interactions (two-way)
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean( ///
        inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
}

*--- Average reform type interactions (two-way)
foreach r of local reforms {
    egen avg_`r' = rowmean( ///
        `r'_2 `r'_3 `r'_4 `r'_5 `r'_6 `r'_7)
}

*--- Average three-way interactions (lag x income x reform)
foreach r of local reforms {
    forvalues q = 2/4 {
        egen avg_inc_`r'_`q' = rowmean( ///
            inc_`r'_2_`q' inc_`r'_3_`q' inc_`r'_4_`q' inc_`r'_5_`q' inc_`r'_6_`q' inc_`r'_7_`q')
    }
}

**# Calculate Predicted Spending Increase
gen pred_spend = avg_main if !missing(pre_q)

*--- Add baseline spending interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

*--- Add income interaction effects (two-way)
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

*--- Add reform type interaction effects (two-way)
foreach r of local reforms {
    replace pred_spend = pred_spend + avg_`r' if `r' == 1
}

*--- Add three-way interaction effects (lag x income x reform)
foreach r of local reforms {
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_inc_`r'_`q' if inc_q == `q' & `r' == 1
    }
}

save baseline_predictions_spec_C, replace
di "  Saved: baseline_predictions_spec_C.dta"

*** ---------------------------------------------------------------------------
*** PHASE 2: JACKKNIFE PROCEDURE (Leave-One-State-Out)
*** Following JJP (2016) Approach II methodology
*** Structure mirrors Phase 1: 2.A, 2.B, 2.C
*** ---------------------------------------------------------------------------

*--- Get list of all states
use jjp_jackknife_prep, clear
levelsof state_fips, local(states)
local n_states : word count `states'

*--- Save master file for repeated loading
tempfile master_data
save `master_data'

*** ---------------------------------------------------------------------------
*** 2.A. Jackknife: Spending Quartile Only
*** ---------------------------------------------------------------------------


local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1


 
        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec A regression excluding state `s'
        areg lexp_ma_strict ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.year_unified##i.pre_q ///
            [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        * Save estimates
        estimates save jackknife_A_state_`s', replace

}


*--- Extract coefficients and calculate predicted spending for Spec A ---

local counter = 0
foreach s of local states {
    local counter = `counter' + 1
    di as text "  [`counter'/`n_states'] Extracting enhanced coefficients for state `s'..."

    preserve
    use `master_data', clear
    estimates use jackknife_A_state_`s'

    **# Generate Main Effect Coefficients (REFORMED: lags 2-7 focus)
    forvalues t = 2/7 {
        gen main_`t' = .
    }

    * Fill with coefficient values
    forvalues t = 2/7 {
        scalar coeff_main = _b[1.lag_`t']
        replace main_`t' = coeff_main
    }

    **# Generate Baseline Spending Quartile Interaction Coefficients
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen ppe_`t'_`q' = .
        }
    }

    * Fill with coefficient values
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
            replace ppe_`t'_`q' = coeff_ppe
        }
    }


    **# Calculate Averages Across Lags 2-7 (REFORMED: focused window)
    
    *--- Average main effect
    egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

    *--- Average baseline spending interactions
    forvalues q = 2/4 {
        egen avg_ppe_`q' = rowmean( ///
            ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
    }

    

    **Calculate Enhanced Predicted Spending Increase
    gen pred_spend = avg_main if !missing(pre_q)

    *--- Add baseline spending interaction effects
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
    }

    *--- Keep only observations from the excluded state
    keep if state_fips == "`s'"
    save pred_temp_A_`s', replace
    restore
}


use `master_data', clear
levelsof state_fips, local(states)

clear
tempfile jk_empty_A
save `jk_empty_A', emptyok

*--- Append predicted spending from all states
foreach s of local states {
    append using pred_temp_A_`s'.dta
}

save jackknife_predictions_spec_A, replace


*** ---------------------------------------------------------------------------
*** 2.B. Jackknife: Spending + Income Quartiles
*** ---------------------------------------------------------------------------

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec B regression excluding state `s'
        areg lexp_ma_strict ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.lag_*##i.inc_q i.lead_*##i.inc_q ///
            i.year_unified##(i.pre_q i.inc_q) ///
            [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        * Save estimates
        estimates save jackknife_B_state_`s', replace
    }



*--- Extract coefficients and calculate predicted spending for Spec B ---
local counter = 0
foreach s of local states {
    local counter = `counter' + 1
    di as text "  [`counter'/`n_states'] Extracting enhanced coefficients for state `s'..."

    preserve
    use `master_data', clear
    estimates use jackknife_B_state_`s'

    **# Generate Main Effect Coefficients (REFORMED: lags 2-7 focus)
    forvalues t = 2/7 {
        gen main_`t' = .
    }

    * Fill with coefficient values
    forvalues t = 2/7 {
        scalar coeff_main = _b[1.lag_`t']
        replace main_`t' = coeff_main
    }

    **# Generate Baseline Spending Quartile Interaction Coefficients
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen ppe_`t'_`q' = .
        }
    }

    * Fill with coefficient values
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
            replace ppe_`t'_`q' = coeff_ppe
        }
    }
	
	 **# Generate Income Quartile Interaction Coefficients
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen inc_`t'_`q' = .
        }
    }

    * Fill with coefficient values
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
            replace inc_`t'_`q' = coeff_inc
        }
    }

    **# Calculate Averages Across Lags 2-7 (REFORMED: focused window)
    
    *--- Average main effect
    egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

    *--- Average baseline spending interactions
    forvalues q = 2/4 {
        egen avg_ppe_`q' = rowmean( ///
            ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
    }
	
	 *--- Average income interactions
    forvalues q = 2/4 {
        egen avg_inc_`q' = rowmean( ///
            inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
    }



    **Calculate Enhanced Predicted Spending Increase
    gen pred_spend = avg_main if !missing(pre_q)

    *--- Add baseline spending interaction effects
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
    }
	
	*--- Add income interaction effects
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
    }


    *--- Keep only observations from the excluded state
    keep if state_fips == "`s'"
    save pred_temp_B_`s', replace
    restore
}

*** 

use `master_data', clear
levelsof state_fips, local(states)

clear
tempfile jk_empty_B
save `jk_empty_B', emptyok

*--- Append predicted spending from all states
foreach s of local states {
    append using pred_temp_B_`s'.dta
}

save jackknife_predictions_spec_B, replace


*** ---------------------------------------------------------------------------
*** 2.C. Jackknife: Full Heterogeneity (Spending + Income + Reform Types)
*** ---------------------------------------------------------------------------
/*
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

*/

*** ---------------------------------------------------------------------------
*** PHASE 3: GRAPH GENERATION
*** Create high/low classifications and event-study plots
*** First: Phase 1 baseline predictions, Then: Phase 2 jackknife predictions
*** ---------------------------------------------------------------------------

*==============================================================================
* PART 3A: PHASE 1 BASELINE PREDICTIONS GRAPHS
*==============================================================================

di _n(2) "Generating Phase 3A: Baseline Predictions Graphs..."

* Process Phase 1 baseline predictions
foreach spec in A B C { 

    use baseline_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1

    *--- Definition B: High = Top 2 Quartiles ---
    xtile pred_q = pred_spend if ever_treated == 1, nq(4)
    gen high_def_B = (pred_q >= 3) if !missing(pred_q)

    save baseline_reg_`spec', replace

    *---------------------------------------------------------------------------
    * GRAPH I: High vs Low Comparison for Baseline Predictions (Both Definitions)
    *---------------------------------------------------------------------------
    foreach def in A B {
        use baseline_reg_`spec', clear

        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified##i.high_def_`def' ///
            [aw = school_age_pop] if (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)

        * Extract coefficients for High group
        tempfile results_high results_low
        postfile h_high str15 term float t b se str10 group using `results_high'

        forvalues k = 5(-1)1 {
            lincom 1.lead_`k' + 1.lead_`k'#1.high_def_`def'
            post h_high ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
        }
        post h_high ("base") (0) (0) (0) ("High")
        forvalues k = 1/17 {
            lincom 1.lag_`k' + 1.lag_`k'#1.high_def_`def'
            post h_high ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
        }
        postclose h_high

        * Extract coefficients for Low group
        postfile h_low str15 term float t b se str10 group using `results_low'

        forvalues k = 5(-1)1 {
             lincom 1.lead_`k'
            post h_low ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Low")
        }
        post h_low ("base") (0) (0) (0) ("Low")
        forvalues k = 1/17 {
             lincom 1.lag_`k'
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
            title("BASELINE Spec `spec' - Definition `def': High vs Low") ///
            subtitle("`def_text' | Full-sample estimates (no jackknife)") ///
            ytitle("Change in ln(13-yr rolling avg PPE)") ///
            xtitle("Years relative to reform") ///
            note("Averaging window: lags 2-7 (vertical lines)") ///
            graphregion(color(white))

        graph export "baseline_spec_`spec'_def_`def'_high_vs_low.png", replace
    }
}

*==============================================================================
* PART 3B: PHASE 2 JACKKNIFE PREDICTIONS GRAPHS
*==============================================================================

di _n(2) "Generating Phase 3B: Jackknife Predictions Graphs..."

* Process each jackknife specification
foreach spec in A B  { // C

    use jackknife_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1


    *--- Definition B: High = Top 2 Quartiles ---
    xtile pred_q = pred_spend if ever_treated == 1, nq(4)
    gen high_def_B = (pred_q >= 3) if !missing(pred_q)


    save jk_reg_`spec', replace

}

    *---------------------------------------------------------------------------
    * GRAPH I: High vs Low Comparison for Jackknife (Both Definitions)
    *---------------------------------------------------------------------------
foreach spec in A B { // C
    foreach def in A B {
		use jk_reg_`spec', clear

        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified##i.high_def_`def' ///
            [aw = school_age_pop] if (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)

        * Extract coefficients for High group
        tempfile results_high results_low
        postfile h_high str15 term float t b se str10 group using `results_high'

        forvalues k = 5(-1)1 {
            lincom 1.lead_`k' + 1.lead_`k'#1.high_def_`def'
            post h_high ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
        }
        post h_high ("base") (0) (0) (0) ("High")
        forvalues k = 1/17 {
            lincom 1.lag_`k' + 1.lag_`k'#1.high_def_`def'
            post h_high ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
        }
        postclose h_high

        * Extract coefficients for Low group
        postfile h_low str15 term float t b se str10 group using `results_low'

        forvalues k = 5(-1)1 {
             lincom 1.lead_`k'
            post h_low ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Low")
        }
        post h_low ("base") (0) (0) (0) ("Low")
        forvalues k = 1/17 {
             lincom 1.lag_`k'
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
            title("JACKKNIFE Spec `spec' - Definition `def': High vs Low") ///
            subtitle("`def_text' | Leave-one-state-out predictions") ///
            ytitle("Change in ln(13-yr rolling avg PPE)") ///
            xtitle("Years relative to reform") ///
            note("Averaging window: lags 2-7 (vertical lines)") ///
            graphregion(color(white))

        graph export "jackknife_spec_`spec'_def_`def'_high_vs_low.png", replace
    }
}


