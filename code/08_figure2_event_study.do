/*================================================================================
Figure 2 Event-Study Regressions (Heterogeneity Analysis)
================================================================================

File: 08_figure2_event_study.do
Author: Myles Owens
Institution: Hoover Institution, Stanford University
Date: 2026-01-15 (Fixed High/Low classification bug)

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

Classification (FIXED 2026-01-15):
  - JJP (2016) approach: High = pred_spend > 0, Low = pred_spend <= 0
    "Roughly two thirds of districts in reform states had Spendd > 0"
  - If threshold of 0 produces meaningful split (both High and Low have counties),
    use the JJP approach
  - If all treated counties have same sign (no variation around 0), fall back to
    median threshold to ensure meaningful heterogeneity split
  - Never-treated counties: assigned to Low group for regression (they serve as
    controls since their lag_*/lead_* are always 0)

  NOTE: Original code always used threshold of 0, but if all pred_spend > 0 (due to
  large positive avg_main), this classifies ALL treated as High, making High vs Low
  essentially Treated vs Control with overlapping lines.

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

    *--- DIAGNOSTIC: Show extracted coefficient values
    di ""
    di "=== DIAGNOSTIC: Extracted Coefficients ==="
    sum avg_main if _n == 1
    local avg_main_val = avg_main[1]
    di "avg_main (base lag effect for Q1) = `avg_main_val'"
    forvalues q = 2/4 {
        local avg_ppe_val = avg_ppe_`q'[1]
        di "avg_ppe_`q' (additional effect for Q`q') = `avg_ppe_val'"
    }
    di ""

    *--- Calculate predicted spending increase
    *    For Q1: pred_spend = avg_main (base effect)
    *    For Q2: pred_spend = avg_main + avg_ppe_2
    *    For Q3: pred_spend = avg_main + avg_ppe_3
    *    For Q4: pred_spend = avg_main + avg_ppe_4
    gen pred_spend = avg_main if !missing(pre_q)

    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
    }

    *--- DIAGNOSTIC: Show pred_spend distribution by pre_q and treatment status
    di "=== DIAGNOSTIC: Predicted Spending by Quartile ==="
    tabstat pred_spend if year == 1971 & never_treated == 0, by(pre_q) stat(mean sd min max n)
    di ""
    di "=== DIAGNOSTIC: Predicted Spending - Treated vs Control ==="
    tabstat pred_spend if year == 1971, by(never_treated) stat(mean sd min max n)
    di ""

    *--- Classify High vs Low
    *    JJP (2016) uses threshold of 0: High = pred_spend > 0, Low = pred_spend <= 0
    *    They found roughly 2/3 of treated districts had pred_spend > 0
    *
    *    If all treated have same sign (no variation), fall back to median threshold

    * Step 1: Check if there's variation around 0 among treated
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)  // county-level pred_spend

    count if `county_pred' > 0 & year == 1971 & never_treated == 0
    local n_high_0 = r(N)
    count if `county_pred' <= 0 & year == 1971 & never_treated == 0
    local n_low_0 = r(N)
    count if year == 1971 & never_treated == 0
    local n_total = r(N)

    di "=== CLASSIFICATION CHECK ==="
    di "Using threshold of 0: `n_high_0' High vs `n_low_0' Low among `n_total' treated counties"
    di "High pct: " %5.1f 100*`n_high_0'/`n_total' "%"

    * Step 2: Decide on threshold
    *    Use 0 if it produces meaningful split (JJP approach)
    *    Fall back to median if all treated have same sign
    local use_median = 0
    if `n_low_0' == 0 | `n_high_0' == 0 {
        di "WARNING: Threshold of 0 produces no variation. All treated have same sign."
        di "         Falling back to MEDIAN threshold for meaningful split."
        local use_median = 1
    }

    * Step 3: Apply chosen threshold
    gen byte high = .

    if `use_median' == 1 {
        sum `county_pred' if year == 1971 & never_treated == 0, detail
        local threshold = r(p50)
        di "=== Using MEDIAN threshold = `threshold' ==="
        replace high = 1 if pred_spend >= `threshold' & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend < `threshold' & never_treated == 0 & !missing(pred_spend)
    }
    else {
        local threshold = 0
        di "=== Using JJP threshold = 0 ==="
        replace high = 1 if pred_spend > 0 & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend <= 0 & never_treated == 0 & !missing(pred_spend)
    }
    di ""

    *--- DIAGNOSTIC: Verify High/Low classification
    di "=== DIAGNOSTIC: High/Low Classification (Treated Only) ==="
    tab high if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: Mean pred_spend by High/Low Group ==="
    tabstat pred_spend if year == 1971 & never_treated == 0, by(high) stat(mean sd min max n)
    di ""

    *--- Set high=0 for never_treated so they're included in regression
    *    They serve as controls for both groups (their lag_*/lead_* are always 0)
    replace high = 0 if never_treated == 1

    di "=== DIAGNOSTIC: Final High/Low Distribution (including never_treated as high=0) ==="
    tab high never_treated if year == 1971, m
    di ""

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

    *--- Classify High vs Low (JJP approach with median fallback)
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)

    count if `county_pred' > 0 & year == 1971 & never_treated == 0
    local n_high_0 = r(N)
    count if `county_pred' <= 0 & year == 1971 & never_treated == 0
    local n_low_0 = r(N)

    di "=== CLASSIFICATION CHECK (Jackknife) ==="
    di "Using threshold of 0: `n_high_0' High vs `n_low_0' Low"

    local use_median = 0
    if `n_low_0' == 0 | `n_high_0' == 0 {
        di "WARNING: Falling back to MEDIAN threshold"
        local use_median = 1
    }

    gen byte high = .

    if `use_median' == 1 {
        sum `county_pred' if year == 1971 & never_treated == 0, detail
        local threshold = r(p50)
        di "=== Using MEDIAN threshold = `threshold' ==="
        replace high = 1 if pred_spend >= `threshold' & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend < `threshold' & never_treated == 0 & !missing(pred_spend)
    }
    else {
        di "=== Using JJP threshold = 0 ==="
        replace high = 1 if pred_spend > 0 & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend <= 0 & never_treated == 0 & !missing(pred_spend)
    }

    * Set high=0 for never_treated
    replace high = 0 if never_treated == 1

    di "=== DIAGNOSTIC: High/Low Classification (Jackknife) ==="
    tab high if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: Mean pred_spend by High/Low Group ==="
    tabstat pred_spend if year == 1971 & never_treated == 0, by(high) stat(mean sd min max n)
    di ""

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

    *--- DIAGNOSTIC: Show pred_spend distribution
    di "=== DIAGNOSTIC: Predicted Spending Distribution (Spec B) ==="
    tabstat pred_spend if year == 1971 & never_treated == 0, by(pre_q) stat(mean sd min max n)
    di ""

    *--- Classify High vs Low (JJP approach with median fallback)
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)

    count if `county_pred' > 0 & year == 1971 & never_treated == 0
    local n_high_0 = r(N)
    count if `county_pred' <= 0 & year == 1971 & never_treated == 0
    local n_low_0 = r(N)

    di "=== CLASSIFICATION CHECK (Spec B) ==="
    di "Using threshold of 0: `n_high_0' High vs `n_low_0' Low"

    local use_median = 0
    if `n_low_0' == 0 | `n_high_0' == 0 {
        di "WARNING: Falling back to MEDIAN threshold"
        local use_median = 1
    }

    gen byte high = .

    if `use_median' == 1 {
        sum `county_pred' if year == 1971 & never_treated == 0, detail
        local threshold = r(p50)
        di "=== Using MEDIAN threshold = `threshold' ==="
        replace high = 1 if pred_spend >= `threshold' & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend < `threshold' & never_treated == 0 & !missing(pred_spend)
    }
    else {
        di "=== Using JJP threshold = 0 ==="
        replace high = 1 if pred_spend > 0 & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend <= 0 & never_treated == 0 & !missing(pred_spend)
    }

    * Set high=0 for never_treated
    replace high = 0 if never_treated == 1

    di "=== DIAGNOSTIC: High/Low Classification (Spec B) ==="
    tab high if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: Mean pred_spend by High/Low Group ==="
    tabstat pred_spend if year == 1971 & never_treated == 0, by(high) stat(mean sd min max n)
    di ""

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

    *--- Classify High vs Low (JJP approach with median fallback)
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)

    count if `county_pred' > 0 & year == 1971 & never_treated == 0
    local n_high_0 = r(N)
    count if `county_pred' <= 0 & year == 1971 & never_treated == 0
    local n_low_0 = r(N)

    di "=== CLASSIFICATION CHECK (Spec B Jackknife) ==="
    di "Using threshold of 0: `n_high_0' High vs `n_low_0' Low"

    local use_median = 0
    if `n_low_0' == 0 | `n_high_0' == 0 {
        di "WARNING: Falling back to MEDIAN threshold"
        local use_median = 1
    }

    gen byte high = .

    if `use_median' == 1 {
        sum `county_pred' if year == 1971 & never_treated == 0, detail
        local threshold = r(p50)
        di "=== Using MEDIAN threshold = `threshold' ==="
        replace high = 1 if pred_spend >= `threshold' & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend < `threshold' & never_treated == 0 & !missing(pred_spend)
    }
    else {
        di "=== Using JJP threshold = 0 ==="
        replace high = 1 if pred_spend > 0 & never_treated == 0 & !missing(pred_spend)
        replace high = 0 if pred_spend <= 0 & never_treated == 0 & !missing(pred_spend)
    }

    * Set high=0 for never_treated
    replace high = 0 if never_treated == 1

    di "=== DIAGNOSTIC: High/Low Classification (Spec B Jackknife) ==="
    tab high if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: Mean pred_spend by High/Low Group ==="
    tabstat pred_spend if year == 1971 & never_treated == 0, by(high) stat(mean sd min max n)
    di ""

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
