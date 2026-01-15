/*================================================================================
Figure 2 Event-Study Regressions (Heterogeneity Analysis)
================================================================================

File: 08_figure2_event_study.do
Author: Myles Owens
Institution: Hoover Institution, Stanford University
Date: 2026-01-15

--------------------------------------------------------------------------------
OVERVIEW
--------------------------------------------------------------------------------

This script runs Figure 2 heterogeneity analysis following JJP (2016) Approach II.
Counties are classified as "High" vs "Low" predicted spending increase based on
their baseline characteristics, then event-study coefficients are estimated
separately for each group.

Two specifications:
  Spec A: Baseline spending quartile only (i.lag_*##i.pre_q)
  Spec B: Baseline spending + income x reform (i.lag_*##i.pre_q + i.lag_*##i.inc_q##i.reform_types)

Two estimation approaches for each spec:
  Non-Jackknife: Use full-sample coefficients for prediction
  Jackknife: Leave-one-state-out predictions (JJP Approach II)

--------------------------------------------------------------------------------
OPTIONS (set below in Section 0)
--------------------------------------------------------------------------------

use_alt:  0 = use jjp_final.dta (balanced on lexp_ma_strict)
          1 = use jjp_final_alt.dta (balanced on lexp)

outcomes: lexp, lexp_ma, lexp_ma_strict (loops over all three)

--------------------------------------------------------------------------------
INPUTS
--------------------------------------------------------------------------------

- jjp_final.dta (from 06_build_jjp_final.do) if use_alt == 0
- jjp_final_alt.dta (from 06_jjp_alt.do) if use_alt == 1

--------------------------------------------------------------------------------
OUTPUTS (saved to output/alt_test/)
--------------------------------------------------------------------------------

- fig2_{outcome}_specA_nojk_{balance}.png  (Spec A, no jackknife)
- fig2_{outcome}_specA_jk_{balance}.png    (Spec A, jackknife)
- fig2_{outcome}_specB_nojk_{balance}.png  (Spec B, no jackknife)
- fig2_{outcome}_specB_jk_{balance}.png    (Spec B, jackknife)

--------------------------------------------------------------------------------
SPECIFICATIONS
--------------------------------------------------------------------------------

Spec A regression:
  areg outcome i.lag_*##i.pre_q i.lead_*##i.pre_q i.year [w=school_age_pop], absorb(county_id)

Spec B regression:
  areg outcome i.lag_*##i.pre_q i.lead_*##i.pre_q ///
               i.lag_*##i.inc_q##i.reform_types i.lead_*##i.inc_q##i.reform_types ///
               i.year [w=school_age_pop], absorb(county_id)

Predicted spending (averaging over lags 2-7):
  Spec A: pred_spend = avg_main + avg_ppe(pre_q)
  Spec B: pred_spend = avg_main + avg_ppe(pre_q) + avg_inc(inc_q) + avg_ref(reform) + avg_triple(inc_q x reform)

Classification: High = (pred_spend > 0), Low = (pred_spend <= 0)

Final event-study:
  areg outcome i.lag_*##i.high i.lead_*##i.high i.year [w=school_age_pop], absorb(county_id)

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*--- OPTIONS: Set these before running ---
global use_alt 1        // 0 = jjp_final (balance on lexp_ma_strict)
                        // 1 = jjp_final_alt (balance on lexp)

*--- Determine which dataset to use
if $use_alt == 1 {
    local datafile "jjp_final_alt"
    local balance_label "alt"
}
else {
    local datafile "jjp_final"
    local balance_label "orig"
}

di "=============================================="
di "Figure 2 Event-Study Analysis"
di "Using dataset: `datafile'.dta"
di "Balance method: `balance_label'"
di "=============================================="

*--- California Check (state_fips == "06")
use `datafile', clear
di "=== CALIFORNIA CHECK (state_fips = '06') ==="
count if state_fips == "06"
if r(N) > 0 {
    di "California IS included in the sample"
    tab state_fips if state_fips == "06" & year == 1971
}
else {
    di "WARNING: California is NOT in the sample"
}

*--- Define outcomes to loop over
local outcomes lexp lexp_ma lexp_ma_strict

*--- Create output directory if needed
capture mkdir "$SchoolSpending/output/alt_test"


/*==============================================================================
                    PART 1: SPEC A - BASELINE SPENDING ONLY
==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 1A: Spec A Non-Jackknife
*** ---------------------------------------------------------------------------

foreach v of local outcomes {

    di "=============================================="
    di "SPEC A NON-JACKKNIFE: `v'"
    di "=============================================="

    use `datafile', clear

    *--- Run fully interacted regression
    areg `v' ///
        i.lag_*##i.pre_q i.lead_*##i.pre_q ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract main effect coefficients (lags 2-7)
    forvalues t = 2/7 {
        gen main_`t' = _b[1.lag_`t']
    }

    *--- Extract spending quartile interaction coefficients
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen ppe_`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
        }
    }

    *--- Calculate averages across lags 2-7
    egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

    forvalues q = 2/4 {
        egen avg_ppe_`q' = rowmean(ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
    }

    *--- Calculate predicted spending increase
    gen pred_spend = avg_main if !missing(pre_q)

    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
    }

    *--- Classify High vs Low
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    tab high if year == 1971, m

    *--- Run final event-study with High/Low interaction
    areg `v' ///
        i.lag_*##i.high i.lead_*##i.high ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract coefficients for High group
    tempfile results_high results_low
    postfile h_high str15 term float t b se str10 grp using `results_high'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.high
        post h_high ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
    }
    post h_high ("base") (0) (0) (0) ("High")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.high
        post h_high ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
    }
    postclose h_high

    *--- Extract coefficients for Low group
    postfile h_low str15 term float t b se str10 grp using `results_low'

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

    *--- Combine and plot
    use `results_high', clear
    append using `results_low'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    *--- Set y-axis title based on outcome
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (rarea ci_lo ci_hi t if grp == "High", color(blue%20) lw(none)) ///
        (line b t if grp == "High", lcolor(blue) lwidth(medthick)) ///
        (rarea ci_lo ci_hi t if grp == "Low", color(red%20) lw(none)) ///
        (line b t if grp == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
        title("Spec A: Baseline Spending Only", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | No Jackknife", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("90% CI. Averaging window: lags 2-7 (vertical lines)", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specA_nojk_`balance_label'.png", replace
}


*** ---------------------------------------------------------------------------
*** Section 1B: Spec A Jackknife (Leave-One-State-Out)
*** ---------------------------------------------------------------------------

foreach v of local outcomes {

    di "=============================================="
    di "SPEC A JACKKNIFE: `v'"
    di "=============================================="

    use `datafile', clear

    *--- Get list of all states
    levelsof state_fips, local(states)

    *--- Save master file for repeated loading
    tempfile master_data
    save `master_data'

    *--- Jackknife loop: for each state, exclude it and estimate
    foreach s of local states {

        use `master_data', clear
        drop if state_fips == "`s'"

        *--- Run Spec A regression excluding state s
        capture areg `v' ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.year [w=school_age_pop] ///
            if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        if _rc != 0 {
            di "Warning: Regression failed for excluded state `s', skipping..."
            continue
        }

        *--- Load full data to predict for excluded state
        use `master_data', clear

        *--- Extract main effect coefficients
        forvalues t = 2/7 {
            gen main_`t' = _b[1.lag_`t']
        }

        *--- Extract spending quartile interaction coefficients
        forvalues t = 2/7 {
            forvalues q = 2/4 {
                gen ppe_`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
            }
        }

        *--- Calculate averages
        egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

        forvalues q = 2/4 {
            egen avg_ppe_`q' = rowmean(ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
        }

        *--- Calculate predicted spending
        gen pred_spend = avg_main if !missing(pre_q)

        forvalues q = 2/4 {
            replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
        }

        *--- Keep only the excluded state
        keep if state_fips == "`s'"
        save pred_temp_A_`v'_`s', replace
    }

    *--- Combine predictions from all states
    clear
    foreach s of local states {
        capture append using pred_temp_A_`v'_`s'.dta
        capture erase pred_temp_A_`v'_`s'.dta
    }

    *--- Classify High vs Low
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    tab high if year == 1971, m

    save jk_pred_specA_`v'_`balance_label', replace

    *--- Run final event-study
    areg `v' ///
        i.lag_*##i.high i.lead_*##i.high ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract coefficients for High group
    tempfile results_high results_low
    postfile h_high str15 term float t b se str10 grp using `results_high'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.high
        post h_high ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
    }
    post h_high ("base") (0) (0) (0) ("High")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.high
        post h_high ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
    }
    postclose h_high

    *--- Extract coefficients for Low group
    postfile h_low str15 term float t b se str10 grp using `results_low'

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

    *--- Combine and plot
    use `results_high', clear
    append using `results_low'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    *--- Set y-axis title based on outcome
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (rarea ci_lo ci_hi t if grp == "High", color(blue%20) lw(none)) ///
        (line b t if grp == "High", lcolor(blue) lwidth(medthick)) ///
        (rarea ci_lo ci_hi t if grp == "Low", color(red%20) lw(none)) ///
        (line b t if grp == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
        title("Spec A: Baseline Spending Only (Jackknife)", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | Leave-One-State-Out", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("90% CI. Averaging window: lags 2-7 (vertical lines)", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specA_jk_`balance_label'.png", replace
}


/*==============================================================================
                    PART 2: SPEC B - SPENDING + INCOME x REFORM
==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 2A: Spec B Non-Jackknife
*** ---------------------------------------------------------------------------

foreach v of local outcomes {

    di "=============================================="
    di "SPEC B NON-JACKKNIFE: `v'"
    di "=============================================="

    use `datafile', clear

    *--- Define reform types local
    local reforms "eq mfp ep le sl"

    *--- Run fully interacted regression
    *    Spec B: i.lag_*##i.pre_q + i.lag_*##i.inc_q##i.reform_types
    areg `v' ///
        i.lag_*##i.pre_q i.lead_*##i.pre_q ///
        i.lag_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
        i.lead_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    *--- 1. Extract main effect coefficients (lags 2-7)
    forvalues t = 2/7 {
        gen main_`t' = _b[1.lag_`t']
    }
    egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

    *--- 2. Extract spending quartile interaction coefficients
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            gen ppe_`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
        }
    }
    forvalues q = 2/4 {
        egen avg_ppe_`q' = rowmean(ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
    }

    *--- 3. Extract base income quartile coefficients
    forvalues t = 2/7 {
        forvalues q = 2/4 {
            capture gen inc_`t'_`q' = _b[1.lag_`t'#`q'.inc_q]
            if _rc gen inc_`t'_`q' = 0
        }
    }
    forvalues q = 2/4 {
        egen avg_inc_`q' = rowmean(inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
    }

    *--- 4. Extract reform main effects and income x reform interactions
    foreach r of local reforms {

        * Main reform effect (base for inc_q == 1)
        forvalues t = 2/7 {
            capture scalar c_ref = _b[1.lag_`t'#1.reform_`r']
            if _rc scalar c_ref = 0
            gen ref_main_`r'_`t' = c_ref
        }
        egen avg_ref_main_`r' = rowmean(ref_main_`r'_2 ref_main_`r'_3 ref_main_`r'_4 ///
                                         ref_main_`r'_5 ref_main_`r'_6 ref_main_`r'_7)

        * Income x reform triple interaction
        forvalues t = 2/7 {
            forvalues q = 2/4 {
                capture scalar c_trip = _b[1.lag_`t'#`q'.inc_q#1.reform_`r']
                if _rc scalar c_trip = 0
                gen triple_`r'_`t'_`q' = c_trip
            }
        }
        forvalues q = 2/4 {
            egen avg_triple_`r'_`q' = rowmean(triple_`r'_2_`q' triple_`r'_3_`q' triple_`r'_4_`q' ///
                                               triple_`r'_5_`q' triple_`r'_6_`q' triple_`r'_7_`q')
        }
    }

    *--- 5. Calculate predicted spending increase
    gen pred_spend = avg_main if !missing(pre_q)

    * Add spending quartile effects
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
    }

    * Add base income effects
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
    }

    * Add reform effects (main + income x reform)
    foreach r of local reforms {
        replace pred_spend = pred_spend + avg_ref_main_`r' if reform_`r' == 1

        forvalues q = 2/4 {
            replace pred_spend = pred_spend + avg_triple_`r'_`q' if reform_`r' == 1 & inc_q == `q'
        }
    }

    *--- Classify High vs Low
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    tab high if year == 1971, m

    *--- Run final event-study with High/Low interaction
    areg `v' ///
        i.lag_*##i.high i.lead_*##i.high ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract coefficients for High group
    tempfile results_high results_low
    postfile h_high str15 term float t b se str10 grp using `results_high'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.high
        post h_high ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
    }
    post h_high ("base") (0) (0) (0) ("High")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.high
        post h_high ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
    }
    postclose h_high

    *--- Extract coefficients for Low group
    postfile h_low str15 term float t b se str10 grp using `results_low'

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

    *--- Combine and plot
    use `results_high', clear
    append using `results_low'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    *--- Set y-axis title based on outcome
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (rarea ci_lo ci_hi t if grp == "High", color(blue%20) lw(none)) ///
        (line b t if grp == "High", lcolor(blue) lwidth(medthick)) ///
        (rarea ci_lo ci_hi t if grp == "Low", color(red%20) lw(none)) ///
        (line b t if grp == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
        title("Spec B: Spending + Income x Reform", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | No Jackknife", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("90% CI. Averaging window: lags 2-7 (vertical lines)", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specB_nojk_`balance_label'.png", replace
}


*** ---------------------------------------------------------------------------
*** Section 2B: Spec B Jackknife (Leave-One-State-Out)
*** ---------------------------------------------------------------------------

foreach v of local outcomes {

    di "=============================================="
    di "SPEC B JACKKNIFE: `v'"
    di "=============================================="

    use `datafile', clear

    *--- Get list of all states
    levelsof state_fips, local(states)

    *--- Save master file for repeated loading
    tempfile master_data
    save `master_data'

    *--- Define reform types local
    local reforms "eq mfp ep le sl"

    *--- Jackknife loop: for each state, exclude it and estimate
    foreach s of local states {

        use `master_data', clear
        drop if state_fips == "`s'"

        *--- Run Spec B regression excluding state s
        capture areg `v' ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.lag_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
            i.lead_*##i.inc_q##(i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
            i.year [w=school_age_pop] ///
            if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
            absorb(county_id) vce(cluster county_id)

        if _rc != 0 {
            di "Warning: Regression failed for excluded state `s', skipping..."
            continue
        }

        *--- Load full data to predict for excluded state
        use `master_data', clear

        *--- 1. Extract main effect coefficients
        forvalues t = 2/7 {
            gen main_`t' = _b[1.lag_`t']
        }
        egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

        *--- 2. Extract spending quartile interaction coefficients
        forvalues t = 2/7 {
            forvalues q = 2/4 {
                gen ppe_`t'_`q' = _b[1.lag_`t'#`q'.pre_q]
            }
        }
        forvalues q = 2/4 {
            egen avg_ppe_`q' = rowmean(ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
        }

        *--- 3. Extract base income quartile coefficients
        forvalues t = 2/7 {
            forvalues q = 2/4 {
                capture scalar c_inc = _b[1.lag_`t'#`q'.inc_q]
                if _rc scalar c_inc = 0
                gen inc_`t'_`q' = c_inc
            }
        }
        forvalues q = 2/4 {
            egen avg_inc_`q' = rowmean(inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
        }

        *--- 4. Extract reform effects
        foreach r of local reforms {

            * Main reform effect
            forvalues t = 2/7 {
                capture scalar c_ref = _b[1.lag_`t'#1.reform_`r']
                if _rc scalar c_ref = 0
                gen ref_main_`r'_`t' = c_ref
            }
            egen avg_ref_main_`r' = rowmean(ref_main_`r'_2 ref_main_`r'_3 ref_main_`r'_4 ///
                                             ref_main_`r'_5 ref_main_`r'_6 ref_main_`r'_7)

            * Income x reform interaction
            forvalues t = 2/7 {
                forvalues q = 2/4 {
                    capture scalar c_trip = _b[1.lag_`t'#`q'.inc_q#1.reform_`r']
                    if _rc scalar c_trip = 0
                    gen triple_`r'_`t'_`q' = c_trip
                }
            }
            forvalues q = 2/4 {
                egen avg_triple_`r'_`q' = rowmean(triple_`r'_2_`q' triple_`r'_3_`q' triple_`r'_4_`q' ///
                                                   triple_`r'_5_`q' triple_`r'_6_`q' triple_`r'_7_`q')
            }
        }

        *--- 5. Calculate predicted spending
        gen pred_spend = avg_main if !missing(pre_q)

        forvalues q = 2/4 {
            replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
        }

        forvalues q = 2/4 {
            replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
        }

        foreach r of local reforms {
            replace pred_spend = pred_spend + avg_ref_main_`r' if reform_`r' == 1

            forvalues q = 2/4 {
                replace pred_spend = pred_spend + avg_triple_`r'_`q' if reform_`r' == 1 & inc_q == `q'
            }
        }

        *--- Keep only the excluded state
        keep if state_fips == "`s'"
        save pred_temp_B_`v'_`s', replace
    }

    *--- Combine predictions from all states
    clear
    foreach s of local states {
        capture append using pred_temp_B_`v'_`s'.dta
        capture erase pred_temp_B_`v'_`s'.dta
    }

    *--- Classify High vs Low
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    tab high if year == 1971, m

    save jk_pred_specB_`v'_`balance_label', replace

    *--- Run final event-study
    areg `v' ///
        i.lag_*##i.high i.lead_*##i.high ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract coefficients for High group
    tempfile results_high results_low
    postfile h_high str15 term float t b se str10 grp using `results_high'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.high
        post h_high ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
    }
    post h_high ("base") (0) (0) (0) ("High")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.high
        post h_high ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
    }
    postclose h_high

    *--- Extract coefficients for Low group
    postfile h_low str15 term float t b se str10 grp using `results_low'

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

    *--- Combine and plot
    use `results_high', clear
    append using `results_low'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    *--- Set y-axis title based on outcome
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (rarea ci_lo ci_hi t if grp == "High", color(blue%20) lw(none)) ///
        (line b t if grp == "High", lcolor(blue) lwidth(medthick)) ///
        (rarea ci_lo ci_hi t if grp == "Low", color(red%20) lw(none)) ///
        (line b t if grp == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(2 "High Predicted" 4 "Low Predicted") pos(6) col(2)) ///
        title("Spec B: Spending + Income x Reform (Jackknife)", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | Leave-One-State-Out", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("90% CI. Averaging window: lags 2-7 (vertical lines)", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specB_jk_`balance_label'.png", replace
}


*** ---------------------------------------------------------------------------
*** Section 3: Summary
*** ---------------------------------------------------------------------------

di "=============================================="
di "FIGURE 2 ANALYSIS COMPLETE"
di "=============================================="
di "Dataset used: `datafile'.dta"
di "Balance method: `balance_label'"
di ""
di "Outputs saved to: $SchoolSpending/output/alt_test/"
di ""
di "Files generated:"
di "  - fig2_{outcome}_specA_nojk_`balance_label'.png"
di "  - fig2_{outcome}_specA_jk_`balance_label'.png"
di "  - fig2_{outcome}_specB_nojk_`balance_label'.png"
di "  - fig2_{outcome}_specB_jk_`balance_label'.png"
di ""
di "Outcomes: lexp, lexp_ma, lexp_ma_strict"
di "=============================================="
