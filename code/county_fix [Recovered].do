/*==============================================================================
Project    : School Spending – Filtered Sample Analysis (≥10 Counties/State)
File       : county_fix.do
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-12-16
───────────────────────────────────────────────────────────────────────────────
PURPOSE:
    Re-estimate Figure 1 and Figure 2 (3 specifications each) with sample
    restricted to states that are either:
        (i)  Never treated, OR
        (ii) Ever-treated with ≥10 counties meeting the balance criteria

    This addresses potential instability from states with few counties.

SPECIFICATIONS:
    A. Pre-reform spending quartile only (pre_q)
    B. Pre-reform spending + income quartile (pre_q + inc_q)
    C. Pre-reform spending + income × reform types (pre_q + inc_q*reform_types)

INPUTS:
    - jjp_balance.dta : Balanced county panel with reform variables

OUTPUTS (saved to output/12_16_meeting/):
    - Event-study graphs for each specification
    - Jackknife heterogeneity analysis graphs
    - Intermediate data files for analysis
==============================================================================*/

*** ---------------------------------------------------------------------------
*** SETUP: Initialize environment
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** SECTION 1: Count Counties by State and Apply Sample Restriction
*** ---------------------------------------------------------------------------
* Goal: Keep only states with ≥10 counties in the balanced sample
*       This ensures stable estimates and avoids undue influence from
*       states with very few counties.

*--- Load balanced panel
use jjp_balance, clear

*--- Create state-level county counts
* Keep unique county-state pairs
preserve
keep county_id state_fips
duplicates drop

*--- Count counties per state
bysort state_fips: egen n_county = nvals(county_id)

*--- Preview distribution (for reference)
tab state_fips
restore

*--- Compute county counts in main dataset
keep county_id state_fips
duplicates drop
bysort state_fips: egen n_county = nvals(county_id)
keep county_id n_county

*--- Merge counts back to full panel
merge 1:m county_id using jjp_balance

*--- Apply restriction: keep only states with ≥10 counties
keep if n_county >= 10

*--- Save filtered sample

save jjp_balance2, replace


local var lexp_ma_strict

foreach v of local var {
    forvalues q = 1/4 {
        use jjp_balance2, clear
		
			


        *--- Weighted event-study regression
        areg  `v' ///
            i.lag_* i.lead_* ///
            i.year_unified [w=school_age_pop] ///
            if (pre_q == `q' | never_treated==1) & (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)

        *--- Extract coefficients
        tempfile results
        postfile handle str15 term float rel_year b se using `results', replace

        forvalues k = 5(-1)1 {
            lincom 1.lead_`k'
             post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
        }

        post handle ("base0") (0) (0) (0)

        forvalues k = 1/17 {
            lincom 1.lag_`k'
             post handle ("lag`k'") (`k') (r(estimate)) (r(se))
        }

        postclose handle

        *--- Create event-study plot
        use `results', clear
        sort rel_year

        gen ci_lo = b - 1.645*se
        gen ci_hi = b + 1.645*se

        twoway ///
            (rarea ci_lo ci_hi rel_year, color("59 91 132%20") lw(none)) ///
            (line b rel_year, lcolor("42 66 94") lwidth(medthick)), ///
            yline(0, lpattern(dash) lcolor(gs10)) ///
            xline(0, lpattern(dash) lcolor(gs10)) ///
            ytitle("Δ ln(13-yr rolling avg PPE)") ///
            title(" `v' | Q: `q' ", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)
			
			
	
	graph export "$SchoolSpending/output/12_16_meeting/bad_county_`q'.png", replace
    }
}



*** ---------------------------------------------------------------------------
*** Section 10: Event-Study Regressions - Bottom 3 Quartiles (Exclude Top)
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    use jjp_balance2, clear


    *--- Weighted regression excluding top quartile
    areg `v' ///
        i.lag_* i.lead_* ///
        i.year_unified [w=school_age_pop] ///
        if (pre_q1971 < 4 | never_treated==1) & (reform_year < 2000 | never_treated == 1) , ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract coefficients
    tempfile results
    postfile handle str15 term float rel_year b se using `results', replace

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k'
         post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
    }

    post handle ("base0") (0) (0) (0)

    forvalues k = 1/17 {
        lincom 1.lag_`k'
        post handle ("lag`k'") (`k') (r(estimate)) (r(se))
    }

    postclose handle

    *--- Create event-study plot
    use `results', clear
    sort rel_year

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    twoway ///
        (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
        (line b rel_year, lcolor("42 66 94") lwidth(medium)), ///
        yline(0, lpattern(dash) lcolor(gs10)) ///
        xline(0, lpattern(dash) lcolor(gs10)) ///
        ytitle("Δ ln(per-pupil spending)", size(medsmall) margin(medium)) ///
        title(" `v' | Q: 1-3 ", size(medlarge) color("35 45 60")) ///
        graphregion(color(white)) ///
        legend(off) ///
        scheme(s2mono)

    graph export "$SchoolSpending/output/12_16_meeting/bad_county_btm.png", replace
}

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Load Balanced Panel and Prepare Variables
*** ---------------------------------------------------------------------------

use jjp_balance2, clear




*--- Rename baseline spending quartile for simplicity
rename pre_q1971 pre_q
egen reform_types = group(reform_eq reform_mfp reform_ep reform_le reform_sl)
save jjp_jackknife_prep, replace

*** ---------------------------------------------------------------------------
*** PHASE 1: BASELINE ESTIMATION (No Jackknife)
*** Store models for comparison and understanding
*** ---------------------------------------------------------------------------


use jjp_jackknife_prep, clear

*--- 1.A. Spending Quartile Only ---

areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.year_unified ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)

estimates save model_baseline_A, replace

*--- 1.B. Spending + Income Quartiles ---

/*
areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q i.lead_*##i.inc_q ///
    i.year_unified##(i.pre_q i.inc_q) ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)


* Nick Reg:

areg lexp_ma_strict ///
	i.lag_*##i.pre_q i.lead_*##i.pre_q ///
	i.lag_*##i.inc_q i.lead_*##i.inc_q ///
	i.year_unified ///
	[w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
	absorb(county_id) vce(cluster county_id)
*/
*Nick Reg 2:
areg lexp_ma_strict ///
                  i.lag_*##i.pre_q##i.inc_q i.lead_*##i.pre_q##i.inc_q ///
                i.year_unified  ///
                [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
                absorb(county_id) vce(cluster county_id)
estimates save model_baseline_B, replace

*--- 1.C. Full Specification (Spending + Income + Reform Types) ---
*    Three-way interactions: lag/lead × income quartile × reform types
*    This allows effects to vary by BOTH income level AND reform type
/*
areg lexp_ma_strict ///
    i.lag_*##i.pre_q     i.lead_*##i.pre_q ///
    i.lag_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
    i.lead_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
    i.year_unified ///
    [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)
*/
set emptycells drop
areg lexp_ma_strict ///
i.lag_*##i.pre_q##i.inc_q##i.reform_types i.lead_*##i.pre_q##i.inc_q##i.reform_types ///
                i.year_unified  ///
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
*gen pred_spend = 0
*--- Add baseline spending interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

save baseline_predictions_spec_A, replace


*--- 1.B Predictions: Spending + Income Quartiles ---
/* Old
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
*/


* Interaction B

*--- 1.B Predictions: Spending + Income Quartiles + Triple Interaction ---
use jjp_jackknife_prep, clear
estimates use model_baseline_B

**# Generate Main Effect Coefficients (lags 2-7)
forvalues t = 2/7 {
    gen main_`t' = _b[1.lag_`t']
}

**# Generate Baseline Spending Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen ppe`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
    }
}

**# Generate Income Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc`t'_`q' = _b[1.lag_`t'#`q'.inc_q]
    }
}

**# Generate Triple Interaction Coefficients (NEW)
* These capture: lag × baseline spending × income
forvalues t = 2/7 {
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            gen triple`t'_`p'_`i' = _b[1.lag_`t'#`p'.pre_q#`i'.inc_q]
        }
    }
}

**# Calculate Averages Across Lags 2-7

*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean(ppe2_`q' ppe3_`q' ppe4_`q' ppe5_`q' ppe6_`q' ppe7_`q')
}

*--- Average income interactions
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc2_`q' inc3_`q' inc4_`q' inc5_`q' inc6_`q' inc7_`q')
}

*--- Average triple interactions (NEW)
forvalues p = 2/4 {
    forvalues i = 2/4 {
        egen avg_triple_`p'_`i' = rowmean( ///
            triple2_`p'_`i' triple3_`p'_`i' triple4_`p'_`i' ///
            triple5_`p'_`i' triple6_`p'_`i' triple7_`p'_`i')
    }
}

**# Calculate Predicted Spending Increase
gen pred_spend = avg_main if !missing(pre_q) & !missing(inc_q)

*--- Add baseline spending interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

*--- Add income interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

*--- Add triple interaction effects (NEW)
forvalues p = 2/4 {
    forvalues i = 2/4 {
        replace pred_spend = pred_spend + avg_triple_`p'_`i' if pre_q == `p' & inc_q == `i'
    }
}

save baseline_predictions_spec_B, replace



use jjp_jackknife_prep, clear
/*
estimates use model_baseline_B

**# Generate Main Effect Coefficients (lags 2-7)
forvalues t = 2/7 {
    gen main_`t' = _b[1.lag_`t']
}

**# Generate Baseline Spending Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen ppe`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
    }
}

**# Generate Income Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc`t'_`q' = _b[1.lag_`t'#`q'.inc_q]
    }
}

**# Calculate Averages Across Lags 2-7

*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean(ppe2_`q' ppe3_`q' ppe4_`q' ppe5_`q' ppe6_`q' ppe7_`q')
}

*--- Average income interactions
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc2_`q' inc3_`q' inc4_`q' inc5_`q' inc6_`q' inc7_`q')
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
*/
*=============================================================================
* COEFFICIENT EXTRACTION FOR FOUR-WAY INTERACTION MODEL
* Model: i.lag_*##i.pre_q##i.inc_q##i.reform_types
*=============================================================================

use jjp_jackknife_prep, clear
estimates use model_baseline_C

/* ---------------------------------------------------------
   1. MAIN TIME EFFECT (Base: pre_q=1, inc_q=1, reform_types=1)
   --------------------------------------------------------- */
forvalues t = 2/7 {
    capture gen main_`t' = _b[1.lag_`t']
    if _rc gen main_`t' = 0
}
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

/* ---------------------------------------------------------
   2. TWO-WAY: lag × pre_q
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        capture gen ppe_`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
        if _rc gen ppe_`t'_`q' = 0
    }
}
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean(ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}

/* ---------------------------------------------------------
   3. TWO-WAY: lag × inc_q
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        capture gen inc_`t'_`q' = _b[1.lag_`t'#`q'.inc_q]
        if _rc gen inc_`t'_`q' = 0
    }
}
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
}

/* ---------------------------------------------------------
   4. TWO-WAY: lag × reform_types (levels 2-6, since 1 is base)
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        capture gen ref_`t'_`r' = _b[1.lag_`t'#`r'.reform_types]
        if _rc gen ref_`t'_`r' = 0
    }
    egen avg_ref_`r' = rowmean(ref_2_`r' ref_3_`r' ref_4_`r' ref_5_`r' ref_6_`r' ref_7_`r')
}

/* ---------------------------------------------------------
   5. THREE-WAY: lag × pre_q × inc_q
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            capture gen tw_pi_`t'_`p'_`i' = _b[1.lag_`t'#`p'.pre_q#`i'.inc_q]
            if _rc gen tw_pi_`t'_`p'_`i' = 0
        }
    }
}
forvalues p = 2/4 {
    forvalues i = 2/4 {
        egen avg_tw_pi_`p'_`i' = rowmean(tw_pi_2_`p'_`i' tw_pi_3_`p'_`i' tw_pi_4_`p'_`i' ///
                                          tw_pi_5_`p'_`i' tw_pi_6_`p'_`i' tw_pi_7_`p'_`i')
    }
}

/* ---------------------------------------------------------
   6. THREE-WAY: lag × pre_q × reform_types
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        forvalues p = 2/4 {
            capture gen tw_pr_`t'_`p'_`r' = _b[1.lag_`t'#`p'.pre_q#`r'.reform_types]
            if _rc gen tw_pr_`t'_`p'_`r' = 0
        }
    }
    forvalues p = 2/4 {
        egen avg_tw_pr_`p'_`r' = rowmean(tw_pr_2_`p'_`r' tw_pr_3_`p'_`r' tw_pr_4_`p'_`r' ///
                                          tw_pr_5_`p'_`r' tw_pr_6_`p'_`r' tw_pr_7_`p'_`r')
    }
}

/* ---------------------------------------------------------
   7. THREE-WAY: lag × inc_q × reform_types
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        forvalues i = 2/4 {
            capture gen tw_ir_`t'_`i'_`r' = _b[1.lag_`t'#`i'.inc_q#`r'.reform_types]
            if _rc gen tw_ir_`t'_`i'_`r' = 0
        }
    }
    forvalues i = 2/4 {
        egen avg_tw_ir_`i'_`r' = rowmean(tw_ir_2_`i'_`r' tw_ir_3_`i'_`r' tw_ir_4_`i'_`r' ///
                                          tw_ir_5_`i'_`r' tw_ir_6_`i'_`r' tw_ir_7_`i'_`r')
    }
}

/* ---------------------------------------------------------
   8. FOUR-WAY: lag × pre_q × inc_q × reform_types
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        forvalues p = 2/4 {
            forvalues i = 2/4 {
                capture gen quad_`t'_`p'_`i'_`r' = _b[1.lag_`t'#`p'.pre_q#`i'.inc_q#`r'.reform_types]
                if _rc gen quad_`t'_`p'_`i'_`r' = 0
            }
        }
    }
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            egen avg_quad_`p'_`i'_`r' = rowmean(quad_2_`p'_`i'_`r' quad_3_`p'_`i'_`r' ///
                quad_4_`p'_`i'_`r' quad_5_`p'_`i'_`r' quad_6_`p'_`i'_`r' quad_7_`p'_`i'_`r')
        }
    }
}

/* ---------------------------------------------------------
   9. BUILD TOTAL PREDICTED EFFECT
   --------------------------------------------------------- */
gen pred_spend = avg_main

* Two-way: pre_q
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

* Two-way: inc_q
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

* Two-way: reform_types (only applies to reform_types 2-6)
forvalues r = 2/6 {
    replace pred_spend = pred_spend + avg_ref_`r' if reform_types == `r'
}

* Three-way: pre_q × inc_q
forvalues p = 2/4 {
    forvalues i = 2/4 {
        replace pred_spend = pred_spend + avg_tw_pi_`p'_`i' if pre_q == `p' & inc_q == `i'
    }
}

* Three-way: pre_q × reform_types
forvalues r = 2/6 {
    forvalues p = 2/4 {
        replace pred_spend = pred_spend + avg_tw_pr_`p'_`r' if pre_q == `p' & reform_types == `r'
    }
}

* Three-way: inc_q × reform_types
forvalues r = 2/6 {
    forvalues i = 2/4 {
        replace pred_spend = pred_spend + avg_tw_ir_`i'_`r' if inc_q == `i' & reform_types == `r'
    }
}

* Four-way: pre_q × inc_q × reform_types
forvalues r = 2/6 {
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            replace pred_spend = pred_spend + avg_quad_`p'_`i'_`r' ///
                if pre_q == `p' & inc_q == `i' & reform_types == `r'
        }
    }
}

save baseline_predictions_spec_C, replace


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
*--- 1.C Predictions: Spending + Income Quartiles + Reforms ---
/*
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
        capture scalar c_ref = _b[1.lag_`t'#1.reform_`r']
		if _rc scalar ref_main_`r'_`t' = 0
        replace ref_main_`r'_`t' = c_ref
    }
    egen avg_ref_main_`r' = rowmean(ref_main_`r'_2 - ref_main_`r'_7)

    /* B. Triple Interaction (The Extra Effect for Q2-4) */
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen triple_`r'_`t'_`q' = .
           capture  scalar c_trip = _b[1.lag_`t'#`q'.inc_q#1.reform_`r']
		   if _rc scalar triple_`r'_`t'_`q' = 0
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


*--- Save master file for repeated loading
tempfile master_data
save `master_data'

*** ---------------------------------------------------------------------------
*** 2.A. Jackknife: Spending Quartile Only
*** ---------------------------------------------------------------------------



foreach s of local states {
  
        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec A regression excluding state `s'
        areg lexp_ma_strict ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.year_unified ///
            [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        * Save estimates
        estimates save jackknife_A_state_`s', replace

}


*--- Extract coefficients and calculate predicted spending for Spec A ---


foreach s of local states {

    preserve
    use `master_data', clear
    estimates use jackknife_A_state_`s'

    **# Generate Main Effect Coefficients
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


foreach s of local states {
        use `master_data', clear
        drop if state_fips == "`s'"
/*
        * Run Spec B regression excluding state `s'
        areg lexp_ma_strict ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.lag_*##i.inc_q i.lead_*##i.inc_q ///
            i.year_unified##(i.pre_q i.inc_q) ///
            [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)
*/
areg lexp_ma_strict ///
                  i.lag_*##i.pre_q##i.inc_q i.lead_*##i.pre_q##i.inc_q ///
                i.year_unified  ///
                [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
                absorb(county_id) vce(cluster county_id)
        * Save estimates
        estimates save jackknife_B_state_`s', replace
    }

foreach s of local states {
    preserve
    use `master_data', clear
    estimates use jackknife_B_state_`s'

**# Generate Main Effect Coefficients (lags 2-7)
forvalues t = 2/7 {
    gen main_`t' = _b[1.lag_`t']
}

**# Generate Baseline Spending Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen ppe`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
    }
}

**# Generate Income Quartile Interaction Coefficients
forvalues t = 2/7 {
    forvalues q = 2/4 {
        gen inc`t'_`q' = _b[1.lag_`t'#`q'.inc_q]
    }
}

**# Generate Triple Interaction Coefficients (NEW)
* These capture: lag × baseline spending × income
forvalues t = 2/7 {
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            gen triple`t'_`p'_`i' = _b[1.lag_`t'#`p'.pre_q#`i'.inc_q]
        }
    }
}

**# Calculate Averages Across Lags 2-7

*--- Average main effect
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

*--- Average baseline spending interactions
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean(ppe2_`q' ppe3_`q' ppe4_`q' ppe5_`q' ppe6_`q' ppe7_`q')
}

*--- Average income interactions
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc2_`q' inc3_`q' inc4_`q' inc5_`q' inc6_`q' inc7_`q')
}

*--- Average triple interactions (NEW)
forvalues p = 2/4 {
    forvalues i = 2/4 {
        egen avg_triple_`p'_`i' = rowmean( ///
            triple2_`p'_`i' triple3_`p'_`i' triple4_`p'_`i' ///
            triple5_`p'_`i' triple6_`p'_`i' triple7_`p'_`i')
    }
}

**# Calculate Predicted Spending Increase
gen pred_spend = avg_main if !missing(pre_q) & !missing(inc_q)

*--- Add baseline spending interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

*--- Add income interaction effects
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

*--- Add triple interaction effects (NEW)
forvalues p = 2/4 {
    forvalues i = 2/4 {
        replace pred_spend = pred_spend + avg_triple_`p'_`i' if pre_q == `p' & inc_q == `i'
    }
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
/*
*--- Extract coefficients and calculate predicted spending for Spec B ---

foreach s of local states {
    preserve
    use `master_data', clear
    estimates use jackknife_B_state_`s'

    **# Generate Main Effect Coefficients
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
*/

*** ---------------------------------------------------------------------------
*** 2.C. Jackknife: Full Heterogeneity (Spending + Income + Reform Types)
*** ---------------------------------------------------------------------------
*--- Get list of all states
use jjp_jackknife_prep, clear
levelsof state_fips, local(states)


*--- Save master file for repeated loading
tempfile master_data
save `master_data'

/*OLD
foreach s of local states {
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

areg lexp_ma_strict ///
i.lag_*##i.pre_q##i.inc_q##i.reform_types i.lead_*##i.pre_q##i.inc_q##i.reform_types ///
                i.year_unified  ///
                [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
                absorb(county_id) vce(cluster county_id)

*/

/* NEW
foreach s of local states {
        use `master_data', clear
        drop if state_fips == "`s'"

        * Run Spec C regression excluding state `s'
areg lexp_ma_strict ///
i.lag_*##i.pre_q##i.inc_q##i.reform_types i.lead_*##i.pre_q##i.inc_q##i.reform_types ///
                i.year_unified  ///
                [w = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
                absorb(county_id) vce(cluster county_id)

        * Save estimates
        estimates save jackknife_C_state_`s', replace

}
*/
foreach s of local states {
        * Load master data and estimates for this state
        use `master_data', clear
        estimates use jackknife_C_state_`s'



        * Keep only the excluded state's predictions
        keep if state_fips == "`s'"
		
/* ---------------------------------------------------------
   1. MAIN TIME EFFECT (Base: pre_q=1, inc_q=1, reform_types=1)
   --------------------------------------------------------- */
forvalues t = 2/7 {
    capture gen main_`t' = _b[1.lag_`t']
    if _rc gen main_`t' = 0
}
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

/* ---------------------------------------------------------
   2. TWO-WAY: lag × pre_q
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        capture gen ppe_`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
        if _rc gen ppe_`t'_`q' = 0
    }
}
forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean(ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}

/* ---------------------------------------------------------
   3. TWO-WAY: lag × inc_q
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues q = 2/4 {
        capture gen inc_`t'_`q' = _b[1.lag_`t'#`q'.inc_q]
        if _rc gen inc_`t'_`q' = 0
    }
}
forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean(inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
}

/* ---------------------------------------------------------
   4. TWO-WAY: lag × reform_types (levels 2-6, since 1 is base)
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        capture gen ref_`t'_`r' = _b[1.lag_`t'#`r'.reform_types]
        if _rc gen ref_`t'_`r' = 0
    }
    egen avg_ref_`r' = rowmean(ref_2_`r' ref_3_`r' ref_4_`r' ref_5_`r' ref_6_`r' ref_7_`r')
}

/* ---------------------------------------------------------
   5. THREE-WAY: lag × pre_q × inc_q
   --------------------------------------------------------- */
forvalues t = 2/7 {
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            capture gen tw_pi_`t'_`p'_`i' = _b[1.lag_`t'#`p'.pre_q#`i'.inc_q]
            if _rc gen tw_pi_`t'_`p'_`i' = 0
        }
    }
}
forvalues p = 2/4 {
    forvalues i = 2/4 {
        egen avg_tw_pi_`p'_`i' = rowmean(tw_pi_2_`p'_`i' tw_pi_3_`p'_`i' tw_pi_4_`p'_`i' ///
                                          tw_pi_5_`p'_`i' tw_pi_6_`p'_`i' tw_pi_7_`p'_`i')
    }
}

/* ---------------------------------------------------------
   6. THREE-WAY: lag × pre_q × reform_types
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        forvalues p = 2/4 {
            capture gen tw_pr_`t'_`p'_`r' = _b[1.lag_`t'#`p'.pre_q#`r'.reform_types]
            if _rc gen tw_pr_`t'_`p'_`r' = 0
        }
    }
    forvalues p = 2/4 {
        egen avg_tw_pr_`p'_`r' = rowmean(tw_pr_2_`p'_`r' tw_pr_3_`p'_`r' tw_pr_4_`p'_`r' ///
                                          tw_pr_5_`p'_`r' tw_pr_6_`p'_`r' tw_pr_7_`p'_`r')
    }
}

/* ---------------------------------------------------------
   7. THREE-WAY: lag × inc_q × reform_types
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        forvalues i = 2/4 {
            capture gen tw_ir_`t'_`i'_`r' = _b[1.lag_`t'#`i'.inc_q#`r'.reform_types]
            if _rc gen tw_ir_`t'_`i'_`r' = 0
        }
    }
    forvalues i = 2/4 {
        egen avg_tw_ir_`i'_`r' = rowmean(tw_ir_2_`i'_`r' tw_ir_3_`i'_`r' tw_ir_4_`i'_`r' ///
                                          tw_ir_5_`i'_`r' tw_ir_6_`i'_`r' tw_ir_7_`i'_`r')
    }
}

/* ---------------------------------------------------------
   8. FOUR-WAY: lag × pre_q × inc_q × reform_types
   --------------------------------------------------------- */
forvalues r = 2/6 {
    forvalues t = 2/7 {
        forvalues p = 2/4 {
            forvalues i = 2/4 {
                capture gen quad_`t'_`p'_`i'_`r' = _b[1.lag_`t'#`p'.pre_q#`i'.inc_q#`r'.reform_types]
                if _rc gen quad_`t'_`p'_`i'_`r' = 0
            }
        }
    }
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            egen avg_quad_`p'_`i'_`r' = rowmean(quad_2_`p'_`i'_`r' quad_3_`p'_`i'_`r' ///
                quad_4_`p'_`i'_`r' quad_5_`p'_`i'_`r' quad_6_`p'_`i'_`r' quad_7_`p'_`i'_`r')
        }
    }
}

/* ---------------------------------------------------------
   9. BUILD TOTAL PREDICTED EFFECT
   --------------------------------------------------------- */
gen pred_spend = avg_main

* Two-way: pre_q
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

* Two-way: inc_q
forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}

* Two-way: reform_types (only applies to reform_types 2-6)
forvalues r = 2/6 {
    replace pred_spend = pred_spend + avg_ref_`r' if reform_types == `r'
}

* Three-way: pre_q × inc_q
forvalues p = 2/4 {
    forvalues i = 2/4 {
        replace pred_spend = pred_spend + avg_tw_pi_`p'_`i' if pre_q == `p' & inc_q == `i'
    }
}

* Three-way: pre_q × reform_types
forvalues r = 2/6 {
    forvalues p = 2/4 {
        replace pred_spend = pred_spend + avg_tw_pr_`p'_`r' if pre_q == `p' & reform_types == `r'
    }
}

* Three-way: inc_q × reform_types
forvalues r = 2/6 {
    forvalues i = 2/4 {
        replace pred_spend = pred_spend + avg_tw_ir_`i'_`r' if inc_q == `i' & reform_types == `r'
    }
}

* Four-way: pre_q × inc_q × reform_types
forvalues r = 2/6 {
    forvalues p = 2/4 {
        forvalues i = 2/4 {
            replace pred_spend = pred_spend + avg_quad_`p'_`i'_`r' ///
                if pre_q == `p' & inc_q == `i' & reform_types == `r'
        }
    }
}





        save pred_temp_C_`s', replace
    
}



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
/* Old Pre-Edit
foreach s of local states {
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
egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

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
    egen avg_inc_`q' = rowmean(inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
}

/* ---------------------------------------------------------
   4. Generate Reform Effects (Two Parts)
   --------------------------------------------------------- */
foreach r of local reforms {

    /* A. Main Reform Effect (The Base Effect for Q1) */
    forvalues t = 2/7 {
        gen ref_main_`r'_`t' = .
        /* We use capture due to reform_sl only occuring in one state.
		   It is given the value of 0 when it is missing.
		*/
        capture scalar c_ref = _b[1.lag_`t'#1.reform_`r']
		if _rc scalar c_ref = 0
        replace ref_main_`r'_`t' = c_ref
    }
    egen avg_ref_main_`r' = rowmean( ///
	ref_main_`r'_2 ref_main_`r'_3 ref_main_`r'_4 ///
	ref_main_`r'_5 ref_main_`r'_6 ref_main_`r'_7)

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
        egen avg_triple_`r'_`q' = rowmean( ///
		triple_`r'_2_`q' triple_`r'_3_`q' triple_`r'_4_`q' ///
		triple_`r'_5_`q' triple_`r'_6_`q' triple_`r'_7_`q')
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
*/



*** ---------------------------------------------------------------------------
*** PHASE 3: GRAPH GENERATION
*** Create high/low classifications and event-study plots
*** First: Phase 1 baseline predictions, Then: Phase 2 jackknife predictions
*** ---------------------------------------------------------------------------
*==============================================================================
* PREP Quartiles
*==============================================================================
* QUARTILES BASELINE
foreach spec in A B C{
	use baseline_predictions_spec_`spec',clear


        * --- CONDITIONAL QUARTILE CREATION ---
        if "`spec'" == "A" {
			
gen pred_q = .

replace pred_q = 1 if pre_q == 4 & ever_treated
replace pred_q = 2 if pre_q == 3 & ever_treated
replace pred_q = 3 if pre_q == 2 & ever_treated
replace pred_q = 4 if pre_q == 1 & ever_treated


		
        }
        else {
            * SPEC B & C STRATEGY: Standard Quantiles (using astile)
            xtile pred_q = pred_spend if ever_treated == 1, nq(4)
        }

        * Setup Groups: Keep only specific Quartile (q) AND Control Group (0)
        replace pred_q = 0 if never_treated == 1

		tab pred_q
		save base_q_`spec', replace
	
}

* QUARTILES JACKKNIFE
foreach spec in A B C{
	use jackknife_predictions_spec_`spec',clear
	xtile pred_q = pred_spend if ever_treated == 1, nq(4)

        * Setup Groups: Keep only specific Quartile (q) AND Control Group (0)
        replace pred_q = 0 if never_treated == 1
		tab pred_q,m
		
		save jk_q_`spec', replace
	

}


*==============================================================================
* PART 3A: PHASE 1 BASELINE PREDICTIONS GRAPHS
*==============================================================================


* Process Phase 1 baseline predictions
foreach spec in   A B C{ 

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
foreach def in A {
        use baseline_reg_`spec', clear
			
        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified [w = school_age_pop] ///
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
                           cond("`spec'"=="B","Spending * Income", ///
                                               "Spending * Income * Reform"))

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

        graph export "$SchoolSpending/output/12_16_edit/baseline_spec_`spec'_def_`def'_high_vs_low.png", replace
    }
}




*==============================================================================
* PART 3B: PHASE 2 JACKKNIFE PREDICTIONS GRAPHS
*==============================================================================


* Process each jackknife specification
foreach spec in  A B { // 

    use jackknife_predictions_spec_`spec', clear

    *--- Definition A: High = (pred_spend > 0) ---
    gen high_def_A = (pred_spend > 0) if !missing(pred_spend) & ever_treated == 1
		replace high_def_A = 2 if never_treated == 1
		*replace high_def_A = 0 if (state_fips == "39" & pre_q == 4) | (state_fips == "48" & pre_q == 3)


    save jk_reg_`spec', replace

}

    *---------------------------------------------------------------------------
    * GRAPH I: High vs Low Comparison for Jackknife (Both Definitions)
    *---------------------------------------------------------------------------
foreach spec in  A B { // C
    foreach def in A  {
        use jk_reg_`spec', clear
		
        * Run event study
        areg lexp_ma_strict ///
            i.lag_*##i.high_def_`def' i.lead_*##i.high_def_`def' ///
            i.year_unified [w = school_age_pop] ///
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
        local spec_label = cond("`spec'"=="A","Spending", cond("`spec'"=="B","Spending * Income","Spending * Income * Reform"))

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

        graph export "$SchoolSpending/output/12_16_edit/jackknife_spec_`spec'_def_`def'_high_vs_low.png", replace
    }
}

*==============================================================================
* PART 3C: PREDICTION QUARTILES HETEROGENEITY (4-LINE CHART)
*==============================================================================

*==============================================================================
* PART 3C: JACKKNIFE PREDICTION QUARTILES (SEPARATE REGRESSIONS LOOP)
*==============================================================================

foreach spec in A  B  C{

    * 1. Initialize results file
    tempfile combined_results
    postfile handle str15 term float(rel_year b se) int q_group using `combined_results'

    * 2. Loop through Quartiles
    forvalues q = 1/4 {

        * Load Data (JACKKNIFE)
        use jk_q_`spec', clear

        
        * --- FIX: The closing bracket '}' was here. I removed it. ---


        *--- Weighted Event-Study Regression ---
        areg lexp_ma_strict ///
            i.lag_* i.lead_* ///
            i.year_unified [w=school_age_pop] ///
            if ( (pred_q == `q' & reform_year < 2000) | never_treated == 1), ///
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
    local spec_label = cond("`spec'"=="A","Spending", cond("`spec'"=="B","Spending * Income", "Spending * Income * Reform"))
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
    graph export "$SchoolSpending/output/12_16_edit/jk_q_`spec'_quartiles.png", replace

}
*==============================================================================
* PART 3C: BASELINE PREDICTION QUARTILES (SEPARATE REGRESSIONS LOOP)
*==============================================================================

foreach spec in  A B  C{

    * 1. Initialize results file
    tempfile combined_results
    postfile handle str15 term float(rel_year b se) int q_group using `combined_results'

    * 2. Loop through Quartiles
    forvalues q = 1/4 {
		use base_q_`spec',clear
		/*
		        keep if pred_q == `q' | pred_q == 0


        *--- Weighted Event-Study Regression ---
        areg lexp_ma_strict ///
            i.lag_* i.lead_* ///
            i.year_unified [aw=school_age_pop] ///
            if (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)
*/
*Nick reg
        areg lexp_ma_strict ///
            i.lag_* i.lead_* ///
            i.year_unified [w=school_age_pop] ///
            if ( (pred_q == `q' & reform_year < 2000) | never_treated == 1), ///
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
    local spec_label = cond("`spec'"=="A","Spending", cond("`spec'"=="B","Spending * Income", "Spending * Income * Reform"))
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

    graph export "$SchoolSpending/output/12_16_edit/base_q_`spec'_quartiles_separate.png", replace
}

