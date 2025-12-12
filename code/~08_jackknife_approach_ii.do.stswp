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

/*
use jjp_jackknife_prep, clear

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
*/


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


use jjp_jackknife_prep, clear
estimates use model_baseline_C

* Define reforms local
local reforms "eq mfp ep le sl"

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
        /* Capture is good practice, though these should exist */
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
/* This was missing/buried in your previous code */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc_`t'_`q' = .
        /* Fetch the base income trend: lag # inc_q */
        scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
        replace inc_`t'_`q' = coeff_inc
    }
}
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc_2_`q'-inc_7_`q')
}

/* ---------------------------------------------------------
   4. Generate Reform Effects (Two Parts)
   --------------------------------------------------------- */
foreach r of local reforms {
    
    /* A. Main Reform Effect (The Base Effect for Q1) */
    forvalues t = 2/7 {
        gen ref_main_`r'_`t' = .
        /* Fetch lag # reform */
        scalar c_ref = _b[1.lag_`t'#1.reform_`r']
        replace ref_main_`r'_`t' = c_ref
    }
    egen avg_ref_main_`r' = rowmean(ref_main_`r'_2 - ref_main_`r'_7)

    /* B. Triple Interaction (The Extra Effect for Q2-4) */
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen triple_`r'_`t'_`q' = .
            scalar c_trip = _b[1.lag_`t'#`q'.inc_q#1.reform_`r']
            replace triple_`r'_`t'_`q' = c_trip
        }
    }
    forvalues q = 2/4 {
        egen avg_triple_`r'_`q' = rowmean(triple_`r'_2_`q' - triple_`r'_7_`q')
    }
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

/* C. Add Base Income Quartile Trends (Applies to all) - FIXES BUG 2 */
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

/* D. Add Reform Effects (Applies only to Reform States) */
foreach r of local reforms {
    
    /* 1. Add Main Reform Effect (Base for everyone in reform state, including Q1) */
    /* FIXES BUG 1 */
    replace pred_spend = pred_spend + avg_ref_main_`r' if reform_`r' == 1
    
    /* 2. Add Triple Interaction (Adjustment for Q2, Q3, Q4 in reform state) */
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_triple_`r'_`q' ///
            if reform_`r' == 1 & inc_q == `q'
    }
}

save baseline_predictions_spec_C, replace
*/
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

/*
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

*/
*--- Extract coefficients and calculate predicted spending for Spec A ---

local counter = 0
foreach s of local states {
    local counter = `counter' + 1

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
/*
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

*/

*--- Extract coefficients and calculate predicted spending for Spec B ---
local counter = 0
foreach s of local states {
    local counter = `counter' + 1


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

        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec C regression excluding state `s'
areg lexp_ma_strict                                                     ///
    i.lag_*##i.pre_q                i.lead_*##i.pre_q                   ///
    i.lag_*##i.inc_q##i.reform_eq   i.lead_*##i.inc_q##i.reform_eq      ///
    i.lag_*##i.inc_q##i.reform_mfp  i.lead_*##i.inc_q##i.reform_mfp     ///
    i.lag_*##i.inc_q##i.reform_ep   i.lead_*##i.inc_q##i.reform_ep      ///
    i.lag_*##i.inc_q##i.reform_le   i.lead_*##i.inc_q##i.reform_le      ///
    i.lag_*##i.inc_q##i.reform_sl   i.lead_*##i.inc_q##i.reform_sl      ///
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
*/

local state_count = 0
foreach s of local states {
    local state_count = `state_count' + 1




        * Load master data and estimates for this state
        use `master_data', clear
        estimates use jackknife_C_state_`s'

* Define reforms local
local reforms "eq mfp ep le sl"

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
        /* Capture is good practice, though these should exist */
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
/* This was missing/buried in your previous code */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc_`t'_`q' = .
        /* Fetch the base income trend: lag # inc_q */
        scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
        replace inc_`t'_`q' = coeff_inc
    }
}
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc_2_`q'-inc_7_`q')
}

/* ---------------------------------------------------------
   4. Generate Reform Effects (Two Parts)
   --------------------------------------------------------- */
foreach r of local reforms {
    
    /* A. Main Reform Effect (The Base Effect for Q1) */
    forvalues t = 2/7 {
        gen ref_main_`r'_`t' = .
        /* Fetch lag # reform */
        capture scalar c_ref = _b[1.lag_`t'#1.reform_`r']
		if _rc scalar c_ref = 0
        replace ref_main_`r'_`t' = c_ref
    }
    egen avg_ref_main_`r' = rowmean(ref_main_`r'_2 - ref_main_`r'_7)

    /* B. Triple Interaction (The Extra Effect for Q2-4) */
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen triple_`r'_`t'_`q' = .
            capture scalar c_trip = _b[1.lag_`t'#`q'.inc_q#1.reform_`r']
					if _rc scalar c_trip = 0
            replace triple_`r'_`t'_`q' = c_trip
        }
    }
    forvalues q = 2/4 {
        egen avg_triple_`r'_`q' = rowmean(triple_`r'_2_`q' - triple_`r'_7_`q')
    }
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

/* C. Add Base Income Quartile Trends (Applies to all) - FIXES BUG 2 */
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

/* D. Add Reform Effects (Applies only to Reform States) */
foreach r of local reforms {
    
    /* 1. Add Main Reform Effect (Base for everyone in reform state, including Q1) */
    /* FIXES BUG 1 */
    replace pred_spend = pred_spend + avg_ref_main_`r' if reform_`r' == 1
    
    /* 2. Add Triple Interaction (Adjustment for Q2, Q3, Q4 in reform state) */
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_triple_`r'_`q' ///
            if reform_`r' == 1 & inc_q == `q'
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
tempfile jk_empty_C
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
foreach spec in  C{ 

    use baseline_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1
	replace high_def_A = 0 if never_treated == 1
    *--- Definition B: High = Top 2 Quartiles (stable sort for reproducibility) ---
    sort county_id
    xtile pred_q = pred_spend if ever_treated == 1, nq(4)
    gen high_def_B = (pred_q >= 3) if !missing(pred_q)

    save baseline_reg_`spec', replace

    *---------------------------------------------------------------------------
    * GRAPH I: High vs Low Comparison for Baseline Predictions (Both Definitions)
    *---------------------------------------------------------------------------
foreach def in A{
        use baseline_reg_`spec', clear
			
        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified [aw = school_age_pop] ///
            if (reform_year < 2000 | never_treated == 1), ///
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
        local spec_label = cond("`spec'"=="A","Spending", ///
                           cond("`spec'"=="B","Spending + Income", ///
                                               "Spending + Income * Reform"))

        twoway ///
            (rarea ci_lo ci_hi t if group == "High", color(blue%20) lw(none)) ///
            (line b t if group == "High", lcolor(blue) lwidth(medthick)) ///
            (rarea ci_lo ci_hi t if group == "Low", color(red%20) lw(none)) ///
            (line b t if group == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
            yline(0, lcolor(gs10) lpattern(dash)) ///
            xline(0, lcolor(gs10) lpattern(dash)) ///
            xline(2 7, lcolor(blue) lwidth(vthin)) ///
            legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
            title("`spec_label'") ///
            subtitle("Full-sample estimates (no jackknife)") ///
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
foreach spec in  A B C{ // 

    use jackknife_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1
		replace high_def_A = 0 if never_treated == 1
		*replace high_def_A = 0 if (state_fips == "39" & pre_q == 4) | (state_fips == "48" & pre_q == 3)
    *--- Definition B: High = Top 2 Quartiles (stable sort for reproducibility) ---
    sort county_id
    xtile pred_q = pred_spend if ever_treated == 1, nq(4)
    gen high_def_B = (pred_q >= 3) if !missing(pred_q)


    save jk_reg_`spec', replace

}

    *---------------------------------------------------------------------------
    * GRAPH I: High vs Low Comparison for Jackknife (Both Definitions)
    *---------------------------------------------------------------------------
foreach spec in  A B C{ // C
    foreach def in A  {
        use jk_reg_`spec', clear
		
        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified [aw = school_age_pop] ///
            if (reform_year < 2000 | never_treated == 1), ///
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
        local spec_label = cond("`spec'"=="A","Spending", cond("`spec'"=="B","Spending + Income","Spending + Income * Reform"))

        twoway ///
            (rarea ci_lo ci_hi t if group == "High", color(blue%20) lw(none)) ///
            (line b t if group == "High", lcolor(blue) lwidth(medthick)) ///
            (rarea ci_lo ci_hi t if group == "Low", color(red%20) lw(none)) ///
            (line b t if group == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
            yline(0, lcolor(gs10) lpattern(dash)) ///
            xline(0, lcolor(gs10) lpattern(dash)) ///
            xline(2 7, lcolor(blue) lwidth(vthin)) ///
            legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
            title("JACKKNIFE: `spec_label'") ///
            subtitle("Leave-one-state-out predictions") ///
            ytitle("Change in ln(13-yr rolling avg PPE)") ///
            xtitle("Years relative to reform") ///
            note("Averaging window: lags 2-7 (vertical lines)") ///
            graphregion(color(white))

        graph export "$SchoolSpending/output/jk/jackknife_spec_`spec'_def_`def'_high_vs_low.png", replace
    }
}

*==============================================================================
* PART 3C: PREDICTION QUARTILES HETEROGENEITY (4-LINE CHART)
*==============================================================================

*==============================================================================
* PART 3C: JACKKNIFE PREDICTION QUARTILES (SEPARATE REGRESSIONS LOOP)
*==============================================================================

foreach spec in A B C {

    * 1. Initialize results file
    tempfile combined_results
    postfile handle str15 term float(rel_year b se) int q_group using `combined_results'

    * 2. Loop through Quartiles
    forvalues q = 1/4 {

        * Load Data (JACKKNIFE)
        use jk_reg_`spec', clear

        * Generate Quartiles
        drop pred_q 
        astile pred_q = pred_spend if ever_treated == 1, nq(4)
        
        * --- FIX: The closing bracket '}' was here. I removed it. ---

        * Setup Groups: Keep only specific Quartile (q) AND Control Group (0)
        replace pred_q = 0 if never_treated == 1
        keep if pred_q == `q' | pred_q == 0

        *--- Weighted Event-Study Regression ---
        areg lexp_ma_strict ///
            i.lag_* i.lead_* ///
            i.year_unified [aw=school_age_pop] ///
            if (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)

        *--- Extract coefficients (Direct Lincoms) ---

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
    }  // <--- FIX: The closing bracket belongs here
    
    postclose handle

    *---------------------------------------------------------------------------
    * 3. Plot
    *---------------------------------------------------------------------------
    use `combined_results', clear

    * Formatting
    local spec_label = cond("`spec'"=="A","Spending", cond("`spec'"=="B","Spending + Income", "Spending + Income * Reform"))
    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se
    sort q_group rel_year

    * Define Colors: Bright / Vibrant (Standard Saturated Colors)
    local c1 "red"
    local c2 "orange"
    local c3 "forest_green"  // Vivid Green
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
        title("Jackknife: `spec_label'") ///
        subtitle("Estimates by Quartile of Predicted Spending") ///
        ytitle("Change in ln(13-yr rolling avg PPE)", size(small)) ///
        xtitle("Years relative to reform", size(small)) ///
        graphregion(color(white)) plotregion(margin(medium))

    * Save with 'jk' prefix
    graph export "$SchoolSpending/output/jk/jk_q_`spec'_quartiles.png", replace

}
*==============================================================================
* PART 3C: BASELINE PREDICTION QUARTILES (SEPARATE REGRESSIONS LOOP)
*==============================================================================

foreach spec in A B C{

    * 1. Initialize results file
    tempfile combined_results
    postfile handle str15 term float(rel_year b se) int q_group using `combined_results'

    * 2. Loop through Quartiles
    forvalues q = 1/4 {

        * Load Data
        use baseline_reg_`spec', clear
        drop pred_q
        * --- CONDITIONAL QUARTILE CREATION ---
        if "`spec'" == "A" {
			
gen pred_q = .

replace pred_q = 1 if pre_q == 4 & ever_treated
replace pred_q = 2 if pre_q == 3 & ever_treated
replace pred_q = 3 if pre_q == 1 & ever_treated
replace pred_q = 4 if pre_q == 2 & ever_treated


		
        }
        else {
            * SPEC B & C STRATEGY: Standard Quantiles (using astile)
            astile pred_q = pred_spend if ever_treated == 1, nq(4)
        }

        * Setup Groups: Keep only specific Quartile (q) AND Control Group (0)
        replace pred_q = 0 if never_treated == 1
        keep if pred_q == `q' | pred_q == 0

        *--- Weighted Event-Study Regression ---
        areg lexp_ma_strict ///
            i.lag_* i.lead_* ///
            i.year_unified [aw=school_age_pop] ///
            if (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)

        *--- Extract coefficients (Direct Lincoms) ---

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

    *---------------------------------------------------------------------------
    * 3. Plot
    *---------------------------------------------------------------------------
    use `combined_results', clear

    * Formatting
    local spec_label = cond("`spec'"=="A","Spending", cond("`spec'"=="B","Spending + Income", "Spending + Income * Reform"))
    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se
    sort q_group rel_year


* Define Colors: Bright / Vibrant (Standard Saturated Colors)
    local c1 "red"
    local c2 "orange"
    local c3 "forest_green"  // 'green' can be too light; forest_green is vivid but readable
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
        xline(2 7, lcolor(blue) lpattern(dash)) /// Note: Changed to gray (gs10) to avoid confusion with Q4 Blue line
        legend(order(5 "Q1 (Lowest)" 6 "Q2" 7 "Q3" 8 "Q4 (Highest)") ///
               pos(6) rows(1) region(lcolor(none))) ///
        title("No Jackknife:`spec_label'") ///
        subtitle("Estimates by Quartile of Predicted Spending") ///
        ytitle("Change in ln(13-yr rolling avg PPE)", size(small)) ///
        xtitle("Years relative to reform", size(small)) ///
        graphregion(color(white)) plotregion(margin(medium))

    graph export "$SchoolSpending/output/jk/base_q_`spec'_quartiles_separate.png", replace
}

/*
        use baseline_reg_A, clear
        drop pred_q
			
		xtile pred_q = pred_spend if ever_treated == 1, nq(4)
		replace pred_q = 4 if pre_q == 4 & ever_treated == 1
		        replace pred_q = 0 if never_treated == 1


foreach spec in A   {
	use baseline_reg_`spec',clear
	display "Spec `spec'"
	tab pre_q high_def_A
}






	use baseline_reg_A,clear
	keep if pre_q == 3
	tab state_fips high_def_A


	use jk_reg_A,clear
	keep if pre_q == 3
	tab state_fips high_def_A



use jk_reg_A, clear
keep if state_fips == "39"
tab pre_q pred_q


use jk_reg_A, clear
keep if state_fips == "48"
tab pre_q pred_q



use baseline_reg_A,clear
keep if inlist(state_fips, "39", "48")




* Full sample
estimates use model_baseline_A
scalar full_main = _b[1.lag_4]
scalar full_ppe3 = _b[1.lag_4#3.pre_q]
scalar full_ppe4 = _b[1.lag_4#4.pre_q]

* Leave-Ohio
estimates use jackknife_A_state_39
scalar oh_main = _b[1.lag_4]
scalar oh_ppe3 = _b[1.lag_4#3.pre_q]
scalar oh_ppe4 = _b[1.lag_4#4.pre_q]

* Leave-Texas
estimates use jackknife_A_state_48
scalar tx_main = _b[1.lag_4]
scalar tx_ppe3 = _b[1.lag_4#3.pre_q]
scalar tx_ppe4 = _b[1.lag_4#4.pre_q]

di "Full:  main=" full_main " ppe3=" full_ppe3 " ppe4=" full_ppe4
di "No-OH: main=" oh_main   " ppe3=" oh_ppe3   " ppe4=" oh_ppe4
di "No-TX: main=" tx_main   " ppe3=" tx_ppe3   " ppe4=" tx_ppe4



* Full sample
estimates use model_baseline_A

scalar full_main = 0
scalar full_ppe3 = 0
scalar full_ppe4 = 0

forvalues t = 2/7 {
    scalar full_main = full_main + _b[1.lag_`t']
    scalar full_ppe3 = full_ppe3 + _b[1.lag_`t'#3.pre_q]
    scalar full_ppe4 = full_ppe4 + _b[1.lag_`t'#4.pre_q]
}

scalar full_main = full_main / 6
scalar full_ppe3 = full_ppe3 / 6
scalar full_ppe4 = full_ppe4 / 6

* Leave-Ohio
estimates use jackknife_A_state_39

scalar oh_main = 0
scalar oh_ppe3 = 0
scalar oh_ppe4 = 0

forvalues t = 2/7 {
    scalar oh_main = oh_main + _b[1.lag_`t']
    scalar oh_ppe3 = oh_ppe3 + _b[1.lag_`t'#3.pre_q]
    scalar oh_ppe4 = oh_ppe4 + _b[1.lag_`t'#4.pre_q]
}

scalar oh_main = oh_main / 6
scalar oh_ppe3 = oh_ppe3 / 6
scalar oh_ppe4 = oh_ppe4 / 6

* Leave-Texas
estimates use jackknife_A_state_48

scalar tx_main = 0
scalar tx_ppe3 = 0
scalar tx_ppe4 = 0

forvalues t = 2/7 {
    scalar tx_main = tx_main + _b[1.lag_`t']
    scalar tx_ppe3 = tx_ppe3 + _b[1.lag_`t'#3.pre_q]
    scalar tx_ppe4 = tx_ppe4 + _b[1.lag_`t'#4.pre_q]
}

scalar tx_main = tx_main / 6
scalar tx_ppe3 = tx_ppe3 / 6
scalar tx_ppe4 = tx_ppe4 / 6

* Display results
di "Averaged over lags 2-7:"
di "Full:  main=" full_main " ppe3=" full_ppe3 " ppe4=" full_ppe4
di "No-OH: main=" oh_main   " ppe3=" oh_ppe3   " ppe4=" oh_ppe4
di "No-TX: main=" tx_main   " ppe3=" tx_ppe3   " ppe4=" tx_ppe4

* Compute predicted values
di " "
di "Predicted spending (main + ppe_q):"
di "Full:  pred_q3=" full_main + full_ppe3 " pred_q4=" full_main + full_ppe4
di "No-OH: pred_q3=" oh_main + oh_ppe3     " pred_q4=" oh_main + oh_ppe4
di "No-TX: pred_q3=" tx_main + tx_ppe3     " pred_q4=" tx_main + tx_ppe4