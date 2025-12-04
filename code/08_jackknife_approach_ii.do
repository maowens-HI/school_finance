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
set seed 12345  // Ensure reproducibility across runs
set more off
cd "$SchoolSpending/data"

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
drop if good_71 != 1
*--- 1.A. Spending Quartile Only ---

areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.year_unified##i.pre_q ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)

estimates save model_baseline_A, replace

*--- 1.B. Spending + Income Quartiles ---

areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q i.lead_*##i.inc_q ///
    i.year_unified##(i.pre_q i.inc_q) ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)

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

estimates save model_baseline_C, replace



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

*--- 1.C Predictions: Spending + Income Quartiles + Reforms ---
* Model 1.C has triple interactions: lag_*##inc_q##reform_*
* We need to extract:
* 1. Main effect: 1.lag_t
* 2. Spending quartile interaction: 1.lag_t#q.pre_q
* 3-5. Combined Reform Context: (Income + Reform + Triple Interaction)

use jjp_jackknife_prep, clear



estimates use model_baseline_C

* Define reforms local for reuse
local reforms "eq mfp ep le sl"

** ---------------------------------------------------------
** 1. Generate Main Effect Coefficients (lags 2-7)
** ---------------------------------------------------------
forvalues t = 2/7 {
    gen main_`t' = .
}

* Fill with coefficient values
forvalues t = 2/7 {
    scalar coeff_main = _b[1.lag_`t']
    replace main_`t' = coeff_main
}

** ---------------------------------------------------------
** 2. Generate Baseline Spending Quartile Interaction Coefficients
** ---------------------------------------------------------
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

** ---------------------------------------------------------
** 3, 4 & 5. Generate Combined Income + Reform + Triple Coefficients
** ---------------------------------------------------------
* Step A: Initialize variables for quartiles 2-4 
foreach r of local reforms {
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen comb_`r'_`t'_`q' = .
        }
    }
}

* Step B: Calculate intermediate coefficients and sum them.
foreach r of local reforms {
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            
            * Get component coefficients
            scalar coeff_ref    = _b[1.lag_`t'#1.reform_`r']
            scalar coeff_inc    = _b[1.lag_`t'#`q'.inc_q]
            scalar coeff_triple = _b[1.lag_`t'#`q'.inc_q#1.reform_`r']
            
            * Sum them up
            scalar coeff_total = coeff_ref + coeff_inc + coeff_triple
            
            * Single replace at the end
            replace comb_`r'_`t'_`q' = coeff_total
        }
    }
}

** ---------------------------------------------------------
** Calculate Averages Across Lags 2-7
** ---------------------------------------------------------

*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}

*--- Average Combined Interactions (3+4+5)
foreach r of local reforms {
    forvalues q = 2/4 {
        egen avg_comb_`r'_`q' = rowmean( ///
            comb_`r'_2_`q' comb_`r'_3_`q' comb_`r'_4_`q' ///
            comb_`r'_5_`q' comb_`r'_6_`q' comb_`r'_7_`q')
    }
}

** ---------------------------------------------------------
** Calculate Predicted Spending Increase
** ---------------------------------------------------------

* Sum all applicable components for each observation
gen pred_spend = avg_main if !missing(pre_q)

*--- Add baseline spending interaction effects (for pre_q = 2, 3, 4)
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

*--- Add Combined Effects (Income + Reform + Triple)

foreach r of local reforms {
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_comb_`r'_`q' ///
            if inc_q == `q' & reform_`r' == 1 & !missing(pre_q)
    }
}

save baseline_predictions_spec_C, replace

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

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1

        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec C regression excluding state `s'
areg lexp_ma_strict                                                     ///
    i.lag_*##i.pre_q                i.lead_*##i.pre_q                   ///
    i.lag_*##i.pre_q##i.reform_eq   i.lead_*##i.pre_q##i.reform_eq      ///
    i.lag_*##i.pre_q##i.reform_mfp  i.lead_*##i.pre_q##i.reform_mfp     ///
    i.lag_*##i.pre_q##i.reform_ep   i.lead_*##i.pre_q##i.reform_ep      ///
    i.lag_*##i.pre_q##i.reform_le   i.lead_*##i.pre_q##i.reform_le      ///
    i.lag_*##i.pre_q##i.reform_sl   i.lead_*##i.pre_q##i.reform_sl      ///
    i.year_unified##(                                                   ///
        i.pre_q                                                         ///
        i.inc_q                                                         ///
        i.reform_eq                                                     ///
        i.reform_mfp                                                    ///
        i.reform_ep                                                     ///
        i.reform_le                                                     ///
        i.reform_sl                                                     ///
    )                                                                   ///
    [aw = school_age_pop]                                               ///
    if (never_treated == 1 | reform_year < 2000),                       ///
    absorb(county_id) vce(cluster county_id)


        * Save estimates
        estimates save jackknife_C_state_`s', replace

}


local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1




        * Load master data and estimates for this state
        use `master_data', clear
        estimates use jackknife_C_state_`s'

* Define reforms local for reuse
local reforms "eq mfp ep le sl"

** ---------------------------------------------------------
** 1. Generate Main Effect Coefficients (lags 2-7)
** ---------------------------------------------------------
forvalues t = 2/7 {
    gen main_`t' = .
}

* Fill with coefficient values
forvalues t = 2/7 {
    scalar coeff_main = _b[1.lag_`t']
    replace main_`t' = coeff_main
}

** ---------------------------------------------------------
** 2. Generate Baseline Spending Quartile Interaction Coefficients
** ---------------------------------------------------------
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

** ---------------------------------------------------------
** 3, 4 & 5. Generate Combined Income + Reform + Triple Coefficients
** ---------------------------------------------------------
* Step A: Initialize variables for quartiles 2-4 
foreach r of local reforms {
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen comb_`r'_`t'_`q' = .
        }
    }
}

* Step B: Calculate intermediate coefficients and sum them.
foreach r of local reforms {
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            
            * Get component coefficients
            scalar coeff_ref    = _b[1.lag_`t'#1.reform_`r']
            scalar coeff_inc    = _b[1.lag_`t'#`q'.inc_q]
            scalar coeff_triple = _b[1.lag_`t'#`q'.inc_q#1.reform_`r']
            
            * Sum them up
            scalar coeff_total = coeff_ref + coeff_inc + coeff_triple
            
            * Single replace at the end
            replace comb_`r'_`t'_`q' = coeff_total
        }
    }
}

** ---------------------------------------------------------
** Calculate Averages Across Lags 2-7
** ---------------------------------------------------------

*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}

*--- Average Combined Interactions (3+4+5)
foreach r of local reforms {
    forvalues q = 2/4 {
        egen avg_comb_`r'_`q' = rowmean( ///
            comb_`r'_2_`q' comb_`r'_3_`q' comb_`r'_4_`q' ///
            comb_`r'_5_`q' comb_`r'_6_`q' comb_`r'_7_`q')
    }
}

** ---------------------------------------------------------
** Calculate Predicted Spending Increase
** ---------------------------------------------------------

* Sum all applicable components for each observation
gen pred_spend = avg_main if !missing(pre_q)

*--- Add baseline spending interaction effects (for pre_q = 2, 3, 4)
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

*--- Add Combined Effects (Income + Reform + Triple)

foreach r of local reforms {
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_comb_`r'_`q' ///
            if inc_q == `q' & reform_`r' == 1 & !missing(pre_q)
    }
}
        * Keep only the excluded state's predictions
        keep if state_fips == "`s'"


        save pred_temp_C_`s', replace
    
}


*** 

use `master_data', clear
levelsof state_fips, local(states)

clear
tempfile jk_empty_B\C
save `jk_empty_C', emptyok

*--- Append predicted spending from all states
foreach s of local states {
    append using pred_temp_C_`s'.dta
}

save jackknife_predictions_spec_C, replace



*** ---------------------------------------------------------------------------
*** PHASE 3: GRAPH GENERATION
*** Create high/low classifications and event-study plots
*** First: Phase 1 baseline predictions, Then: Phase 2 jackknife predictions
*** ---------------------------------------------------------------------------

*==============================================================================
* PART 3A: PHASE 1 BASELINE PREDICTIONS GRAPHS
*==============================================================================


* Process Phase 1 baseline predictions
foreach spec in A B C{ 

    use baseline_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1
	replace high_def_A = 0 if never_treated == 1

    *--- Definition B: High = Top 2 Quartiles ---
    *--- Stable sort to ensure reproducibility with ties
    sort county_id
    xtile pred_q = pred_spend if ever_treated == 1, nq(4)
    gen high_def_B = (pred_q >= 3) if !missing(pred_q)

    save baseline_reg_`spec', replace

    *---------------------------------------------------------------------------
    * GRAPH I: High vs Low Comparison for Baseline Predictions (Both Definitions)
    *---------------------------------------------------------------------------
    foreach def in A {
        use baseline_reg_`spec', clear
			
        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified ///
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

        gen ci_lo = b - 1.645*se
        gen ci_hi = b + 1.645*se

        * Title text
        local def_text = cond("`def'" == "A", "High = Predicted > 0", "High = Top 2 Quartiles")

        twoway ///
            (rarea ci_lo ci_hi t if group == "High", color(blue%20) lw(none)) ///
            (line b t if group == "High", lcolor(blue) lwidth(medthick)) ///
            (rarea ci_lo ci_hi t if group == "Low", color(red%20) lw(none)) ///
            (line b t if group == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
            yline(0, lcolor(gs10) lpattern(dash)) ///
            xline(0, lcolor(gs10) lpattern(dash)) ///
            xline(2 7, lcolor(blue) lwidth(vthin)) ///
            legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
            title("BASELINE Spec `spec' - Definition `def': High vs Low") ///
            subtitle("`def_text' | Full-sample estimates (no jackknife)") ///
            ytitle("Change in ln(13-yr rolling avg PPE)") ///
            xtitle("Years relative to reform") ///
            note("Averaging window: lags 2-7 (vertical lines)") ///
            graphregion(color(white))

        graph export "$SchoolSpending/output/jk/baseline_spec_`spec'_def_`def'_high_vs_low.png", replace
    }
}



*==============================================================================
* PART 3B: PHASE 2 JACKKNIFE PREDICTIONS GRAPHS
*==============================================================================


* Process each jackknife specification
foreach spec in A B C { // 

    use jackknife_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1
		replace high_def_A = 0 if never_treated == 1

    *--- Definition B: High = Top 2 Quartiles ---
    *--- Stable sort to ensure reproducibility with ties
    sort county_id
    xtile pred_q = pred_spend if ever_treated == 1, nq(4)
    gen high_def_B = (pred_q >= 3) if !missing(pred_q)


    save jk_reg_`spec', replace

}

    *---------------------------------------------------------------------------
    * GRAPH I: High vs Low Comparison for Jackknife (Both Definitions)
    *---------------------------------------------------------------------------
foreach spec in A B { // C
    foreach def in A  {
		use jk_reg_`spec', clear

        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified ///
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

        gen ci_lo = b - 1.645*se
        gen ci_hi = b + 1.645*se

        * Title text
        local def_text = cond("`def'" == "A", "High = Predicted > 0", "High = Top 2 Quartiles")

        twoway ///
            (rarea ci_lo ci_hi t if group == "High", color(blue%20) lw(none)) ///
            (line b t if group == "High", lcolor(blue) lwidth(medthick)) ///
            (rarea ci_lo ci_hi t if group == "Low", color(red%20) lw(none)) ///
            (line b t if group == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
            yline(0, lcolor(gs10) lpattern(dash)) ///
            xline(0, lcolor(gs10) lpattern(dash)) ///
            xline(2 7, lcolor(blue) lwidth(vthin)) ///
            legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
            title("JACKKNIFE Spec `spec' - Definition `def': High vs Low") ///
            subtitle("`def_text' | Leave-one-state-out predictions") ///
            ytitle("Change in ln(13-yr rolling avg PPE)") ///
            xtitle("Years relative to reform") ///
            note("Averaging window: lags 2-7 (vertical lines)") ///
            graphregion(color(white))

        graph export "$SchoolSpending/output/jk/jackknife_spec_`spec'_def_`def'_high_vs_low.png", replace
    }
}

foreach spec in A B  C{
	use baseline_reg_`spec',clear
	display "Spec `spec'"
	tab pre_q high_def_A
}



foreach spec in A B  {
	use jk_reg_`spec',clear
		display "Spec `spec'"
	tab pre_q high_def_A
}
















