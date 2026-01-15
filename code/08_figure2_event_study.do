/*================================================================================
Figure 2 Event-Study Regressions (Heterogeneity Analysis)
================================================================================

File: 08_figure2_event_study.do
Author: Myles Owens
Institution: Hoover Institution, Stanford University
Date: 2026-01-15 (Updated: reform_types now uses egen group())

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

High/Low graphs (JJP Figure 2 style):
- fig2_{outcome}_specA_nojk_{balance}.png  (Spec A, no jackknife)
- fig2_{outcome}_specA_jk_{balance}.png    (Spec A, jackknife)
- fig2_{outcome}_specB_nojk_{balance}.png  (Spec B, no jackknife)
- fig2_{outcome}_specB_jk_{balance}.png    (Spec B, jackknife)

Quartile graphs (4 lines by pred_spend quartile):
- fig2_{outcome}_specA_nojk_{balance}_quartiles.png
- fig2_{outcome}_specA_jk_{balance}_quartiles.png
- fig2_{outcome}_specB_nojk_{balance}_quartiles.png
- fig2_{outcome}_specB_jk_{balance}_quartiles.png

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
  Spec B: pred_spend = avg_main + avg_ppe(pre_q) + avg_inc(inc_q) + avg_ref(reform_types) + avg_triple(inc_q x reform_types)

NOTE: reform_types is created via:
  egen reform_types = group(reform_eq reform_mfp reform_ep reform_le reform_sl)
  replace reform_types = 0 if never_treated == 1
  Each unique combination of reform indicators becomes a discrete category.

Classification (FIXED 2026-01-15):
  - JJP (2016) approach: High = pred_spend > 0, Low = pred_spend <= 0
    "Roughly two thirds of districts in reform states had Spendd > 0"
  - Never-treated counties: assigned to Low group for regression (they serve as
    controls since their lag_*/lead_* are always 0)

  NOTE ON OVERLAPPING LINES: If all treated counties have pred_spend > 0 (due to
  large positive avg_main and small interaction terms), then:
    - High group = ALL treated counties
    - Low group = ALL never-treated (control) counties
  In this case, High vs Low is essentially Treated vs Control, and the lines will
  overlap because never-treated have no event-time variation (lag_k = 0 always).
  The Low line coefficients are poorly identified since controls don't contribute
  to lag_k estimation. This is a DATA characteristic, not a bug.

  ADDITIONAL OUTPUT: A quartile-based graph splits treated counties into 4 groups
  by pred_spend quartile (Q1-Q4), providing finer heterogeneity even when all
  pred_spend values have the same sign.

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

    *--- Classify High vs Low (JJP approach: threshold = 0)
    *    High = pred_spend > 0, Low = pred_spend <= 0
    *    JJP found roughly 2/3 of treated had pred_spend > 0
    *    NOTE: If all treated have pred_spend > 0, High = all treated, Low = all controls
    *          and lines will overlap (see header documentation)
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    *--- Create quartiles of pred_spend among TREATED counties
    *    This provides finer heterogeneity even when all pred_spend have same sign
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)

    * Calculate quartile cutoffs among treated only
    _pctile `county_pred' if year == 1971 & never_treated == 0, p(25 50 75)
    local p25 = r(r1)
    local p50 = r(r2)
    local p75 = r(r3)

    gen byte pred_q = .
    replace pred_q = 1 if pred_spend <= `p25' & never_treated == 0
    replace pred_q = 2 if pred_spend > `p25' & pred_spend <= `p50' & never_treated == 0
    replace pred_q = 3 if pred_spend > `p50' & pred_spend <= `p75' & never_treated == 0
    replace pred_q = 4 if pred_spend > `p75' & never_treated == 0

    *--- DIAGNOSTIC: Show High/Low and Quartile classification
    di "=== DIAGNOSTIC: High/Low Classification ==="
    tab high never_treated if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: Mean pred_spend by High/Low (Treated Only) ==="
    tabstat pred_spend if year == 1971, by(high) stat(mean sd n)
    di ""
    di "=== DIAGNOSTIC: pred_spend Quartiles (Treated Only) ==="
    di "Quartile cutoffs: p25=`p25' p50=`p50' p75=`p75'"
    tabstat pred_spend if year == 1971 & never_treated == 0, by(pred_q) stat(mean sd n)
    di ""

    *--- Save data with classifications for quartile graph later
    tempfile data_with_pred
    save `data_with_pred'

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

    *==========================================================================
    * QUARTILE GRAPH: 4 lines by pred_spend quartile
    *==========================================================================

    * Reload data with pred_q classification (saved earlier)
    use `data_with_pred', clear

    * Set pred_q = 0 for never_treated (controls)
    replace pred_q = 0 if never_treated == 1

    * Run regression with quartile interactions
    areg `v' ///
        i.lag_*##i.pred_q i.lead_*##i.pred_q ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    * Extract coefficients for each quartile
    tempfile results_q1 results_q2 results_q3 results_q4
    postfile hq1 str15 term float t b se str10 grp using `results_q1'
    postfile hq2 str15 term float t b se str10 grp using `results_q2'
    postfile hq3 str15 term float t b se str10 grp using `results_q3'
    postfile hq4 str15 term float t b se str10 grp using `results_q4'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.pred_q
        post hq1 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lead_`k' + 1.lead_`k'#2.pred_q
        post hq2 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lead_`k' + 1.lead_`k'#3.pred_q
        post hq3 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lead_`k' + 1.lead_`k'#4.pred_q
        post hq4 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q4")
    }
    post hq1 ("base") (0) (0) (0) ("Q1")
    post hq2 ("base") (0) (0) (0) ("Q2")
    post hq3 ("base") (0) (0) (0) ("Q3")
    post hq4 ("base") (0) (0) (0) ("Q4")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.pred_q
        post hq1 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lag_`k' + 1.lag_`k'#2.pred_q
        post hq2 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lag_`k' + 1.lag_`k'#3.pred_q
        post hq3 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lag_`k' + 1.lag_`k'#4.pred_q
        post hq4 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q4")
    }
    postclose hq1
    postclose hq2
    postclose hq3
    postclose hq4

    * Combine all quartiles
    use `results_q1', clear
    append using `results_q2'
    append using `results_q3'
    append using `results_q4'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    * Plot 4 lines
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (line b t if grp == "Q1", lcolor(navy) lwidth(medthick)) ///
        (line b t if grp == "Q2", lcolor(blue) lwidth(medthick) lpattern(dash)) ///
        (line b t if grp == "Q3", lcolor(cranberry) lwidth(medthick) lpattern(shortdash)) ///
        (line b t if grp == "Q4", lcolor(red) lwidth(medthick) lpattern(longdash)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(1 "Q1 (lowest pred)" 2 "Q2" 3 "Q3" 4 "Q4 (highest pred)") pos(6) col(4)) ///
        title("Spec A: By Quartile of Predicted Spending", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | No Jackknife", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("Quartiles of pred_spend among treated counties. Averaging window: lags 2-7", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specA_nojk_`balance_label'_quartiles.png", replace
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

    *--- Classify High vs Low (JJP approach: threshold = 0)
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    *--- Create quartiles of pred_spend among TREATED counties
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)

    _pctile `county_pred' if year == 1971 & never_treated == 0, p(25 50 75)
    local p25 = r(r1)
    local p50 = r(r2)
    local p75 = r(r3)

    gen byte pred_q = .
    replace pred_q = 1 if pred_spend <= `p25' & never_treated == 0
    replace pred_q = 2 if pred_spend > `p25' & pred_spend <= `p50' & never_treated == 0
    replace pred_q = 3 if pred_spend > `p50' & pred_spend <= `p75' & never_treated == 0
    replace pred_q = 4 if pred_spend > `p75' & never_treated == 0

    di "=== DIAGNOSTIC: High/Low Classification (Jackknife) ==="
    tab high never_treated if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: pred_spend Quartiles (Treated Only) ==="
    di "Quartile cutoffs: p25=`p25' p50=`p50' p75=`p75'"
    tabstat pred_spend if year == 1971 & never_treated == 0, by(pred_q) stat(mean sd n)
    di ""

    *--- Save data with classifications for quartile graph
    tempfile data_with_pred_jk
    save `data_with_pred_jk'

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

    *==========================================================================
    * QUARTILE GRAPH: 4 lines by pred_spend quartile (Jackknife)
    *==========================================================================

    * Reload data with pred_q classification
    use `data_with_pred_jk', clear
    replace pred_q = 0 if never_treated == 1

    * Run regression with quartile interactions
    areg `v' ///
        i.lag_*##i.pred_q i.lead_*##i.pred_q ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    * Extract coefficients for each quartile
    tempfile results_q1 results_q2 results_q3 results_q4
    postfile hq1 str15 term float t b se str10 grp using `results_q1'
    postfile hq2 str15 term float t b se str10 grp using `results_q2'
    postfile hq3 str15 term float t b se str10 grp using `results_q3'
    postfile hq4 str15 term float t b se str10 grp using `results_q4'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.pred_q
        post hq1 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lead_`k' + 1.lead_`k'#2.pred_q
        post hq2 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lead_`k' + 1.lead_`k'#3.pred_q
        post hq3 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lead_`k' + 1.lead_`k'#4.pred_q
        post hq4 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q4")
    }
    post hq1 ("base") (0) (0) (0) ("Q1")
    post hq2 ("base") (0) (0) (0) ("Q2")
    post hq3 ("base") (0) (0) (0) ("Q3")
    post hq4 ("base") (0) (0) (0) ("Q4")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.pred_q
        post hq1 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lag_`k' + 1.lag_`k'#2.pred_q
        post hq2 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lag_`k' + 1.lag_`k'#3.pred_q
        post hq3 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lag_`k' + 1.lag_`k'#4.pred_q
        post hq4 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q4")
    }
    postclose hq1
    postclose hq2
    postclose hq3
    postclose hq4

    * Combine all quartiles
    use `results_q1', clear
    append using `results_q2'
    append using `results_q3'
    append using `results_q4'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    * Plot 4 lines
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (line b t if grp == "Q1", lcolor(navy) lwidth(medthick)) ///
        (line b t if grp == "Q2", lcolor(blue) lwidth(medthick) lpattern(dash)) ///
        (line b t if grp == "Q3", lcolor(cranberry) lwidth(medthick) lpattern(shortdash)) ///
        (line b t if grp == "Q4", lcolor(red) lwidth(medthick) lpattern(longdash)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(1 "Q1 (lowest pred)" 2 "Q2" 3 "Q3" 4 "Q4 (highest pred)") pos(6) col(4)) ///
        title("Spec A: By Quartile of Predicted Spending (Jackknife)", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | Leave-One-State-Out", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("Quartiles of pred_spend among treated counties. Averaging window: lags 2-7", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specA_jk_`balance_label'_quartiles.png", replace
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

    *--- Create grouped reform types variable
    *    Each unique combination of reform dummies becomes a discrete category
    egen reform_types = group(reform_eq reform_mfp reform_ep reform_le reform_sl)

    *--- Set reform_types = 0 for never-treated (control) counties
    replace reform_types = 0 if never_treated == 1

    *--- Get list of reform_types levels (excluding controls)
    levelsof reform_types if never_treated == 0, local(reform_levels)

    di "=== DIAGNOSTIC: Reform Types Distribution ==="
    tab reform_types if year == 1971, m

    *--- Run fully interacted regression
    *    Spec B: i.lag_*##i.pre_q + i.lag_*##i.inc_q##i.reform_types
    areg `v' ///
        i.lag_*##i.pre_q i.lead_*##i.pre_q ///
        i.lag_*##i.inc_q##i.reform_types ///
        i.lead_*##i.inc_q##i.reform_types ///
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

    *--- 4. Extract reform type main effects and income x reform_types interactions
    *    Loop over reform_types levels (grouped combinations)
    foreach r of local reform_levels {

        * Main reform_types effect (base for inc_q == 1)
        forvalues t = 2/7 {
            capture scalar c_ref = _b[1.lag_`t'#`r'.reform_types]
            if _rc scalar c_ref = 0
            gen ref_main_`r'_`t' = c_ref
        }
        egen avg_ref_main_`r' = rowmean(ref_main_`r'_2 ref_main_`r'_3 ref_main_`r'_4 ///
                                         ref_main_`r'_5 ref_main_`r'_6 ref_main_`r'_7)

        * Income x reform_types triple interaction
        forvalues t = 2/7 {
            forvalues q = 2/4 {
                capture scalar c_trip = _b[1.lag_`t'#`q'.inc_q#`r'.reform_types]
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

    * Add reform_types effects (main + income x reform_types)
    foreach r of local reform_levels {
        replace pred_spend = pred_spend + avg_ref_main_`r' if reform_types == `r'

        forvalues q = 2/4 {
            replace pred_spend = pred_spend + avg_triple_`r'_`q' if reform_types == `r' & inc_q == `q'
        }
    }

    *--- DIAGNOSTIC: Show pred_spend distribution
    di "=== DIAGNOSTIC: Predicted Spending Distribution (Spec B) ==="
    tabstat pred_spend if year == 1971 & never_treated == 0, by(pre_q) stat(mean sd min max n)
    di ""

    *--- Classify High vs Low (JJP approach: threshold = 0)
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    *--- Create quartiles of pred_spend among TREATED counties
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)

    _pctile `county_pred' if year == 1971 & never_treated == 0, p(25 50 75)
    local p25 = r(r1)
    local p50 = r(r2)
    local p75 = r(r3)

    gen byte pred_q = .
    replace pred_q = 1 if pred_spend <= `p25' & never_treated == 0
    replace pred_q = 2 if pred_spend > `p25' & pred_spend <= `p50' & never_treated == 0
    replace pred_q = 3 if pred_spend > `p50' & pred_spend <= `p75' & never_treated == 0
    replace pred_q = 4 if pred_spend > `p75' & never_treated == 0

    di "=== DIAGNOSTIC: High/Low Classification (Spec B) ==="
    tab high never_treated if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: pred_spend Quartiles (Treated Only) ==="
    di "Quartile cutoffs: p25=`p25' p50=`p50' p75=`p75'"
    tabstat pred_spend if year == 1971 & never_treated == 0, by(pred_q) stat(mean sd n)
    di ""

    *--- Save data with classifications for quartile graph
    tempfile data_with_pred_B
    save `data_with_pred_B'

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

    *==========================================================================
    * QUARTILE GRAPH: 4 lines by pred_spend quartile (Spec B)
    *==========================================================================

    * Reload data with pred_q classification
    use `data_with_pred_B', clear
    replace pred_q = 0 if never_treated == 1

    * Run regression with quartile interactions
    areg `v' ///
        i.lag_*##i.pred_q i.lead_*##i.pred_q ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    * Extract coefficients for each quartile
    tempfile results_q1 results_q2 results_q3 results_q4
    postfile hq1 str15 term float t b se str10 grp using `results_q1'
    postfile hq2 str15 term float t b se str10 grp using `results_q2'
    postfile hq3 str15 term float t b se str10 grp using `results_q3'
    postfile hq4 str15 term float t b se str10 grp using `results_q4'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.pred_q
        post hq1 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lead_`k' + 1.lead_`k'#2.pred_q
        post hq2 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lead_`k' + 1.lead_`k'#3.pred_q
        post hq3 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lead_`k' + 1.lead_`k'#4.pred_q
        post hq4 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q4")
    }
    post hq1 ("base") (0) (0) (0) ("Q1")
    post hq2 ("base") (0) (0) (0) ("Q2")
    post hq3 ("base") (0) (0) (0) ("Q3")
    post hq4 ("base") (0) (0) (0) ("Q4")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.pred_q
        post hq1 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lag_`k' + 1.lag_`k'#2.pred_q
        post hq2 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lag_`k' + 1.lag_`k'#3.pred_q
        post hq3 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lag_`k' + 1.lag_`k'#4.pred_q
        post hq4 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q4")
    }
    postclose hq1
    postclose hq2
    postclose hq3
    postclose hq4

    * Combine all quartiles
    use `results_q1', clear
    append using `results_q2'
    append using `results_q3'
    append using `results_q4'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    * Plot 4 lines
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (line b t if grp == "Q1", lcolor(navy) lwidth(medthick)) ///
        (line b t if grp == "Q2", lcolor(blue) lwidth(medthick) lpattern(dash)) ///
        (line b t if grp == "Q3", lcolor(cranberry) lwidth(medthick) lpattern(shortdash)) ///
        (line b t if grp == "Q4", lcolor(red) lwidth(medthick) lpattern(longdash)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(1 "Q1 (lowest pred)" 2 "Q2" 3 "Q3" 4 "Q4 (highest pred)") pos(6) col(4)) ///
        title("Spec B: By Quartile of Predicted Spending", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | No Jackknife", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("Quartiles of pred_spend among treated counties. Averaging window: lags 2-7", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specB_nojk_`balance_label'_quartiles.png", replace
}


*** ---------------------------------------------------------------------------
*** Section 2B: Spec B Jackknife (Leave-One-State-Out)
*** ---------------------------------------------------------------------------

foreach v of local outcomes {

    di "=============================================="
    di "SPEC B JACKKNIFE: `v'"
    di "=============================================="

    use `datafile', clear

    *--- Create grouped reform types variable
    egen reform_types = group(reform_eq reform_mfp reform_ep reform_le reform_sl)
    replace reform_types = 0 if never_treated == 1

    *--- Get list of reform_types levels (excluding controls)
    levelsof reform_types if never_treated == 0, local(reform_levels)

    di "=== DIAGNOSTIC: Reform Types Distribution ==="
    tab reform_types if year == 1971, m

    *--- Get list of all states
    levelsof state_fips, local(states)

    *--- Save master file for repeated loading
    tempfile master_data
    save `master_data'

    *--- Jackknife loop: for each state, exclude it and estimate
    foreach s of local states {

        use `master_data', clear
        drop if state_fips == "`s'"

        *--- Run Spec B regression excluding state s
        capture areg `v' ///
            i.lag_*##i.pre_q i.lead_*##i.pre_q ///
            i.lag_*##i.inc_q##i.reform_types ///
            i.lead_*##i.inc_q##i.reform_types ///
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

        *--- 4. Extract reform_types effects
        foreach r of local reform_levels {

            * Main reform_types effect
            forvalues t = 2/7 {
                capture scalar c_ref = _b[1.lag_`t'#`r'.reform_types]
                if _rc scalar c_ref = 0
                gen ref_main_`r'_`t' = c_ref
            }
            egen avg_ref_main_`r' = rowmean(ref_main_`r'_2 ref_main_`r'_3 ref_main_`r'_4 ///
                                             ref_main_`r'_5 ref_main_`r'_6 ref_main_`r'_7)

            * Income x reform_types interaction
            forvalues t = 2/7 {
                forvalues q = 2/4 {
                    capture scalar c_trip = _b[1.lag_`t'#`q'.inc_q#`r'.reform_types]
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

        foreach r of local reform_levels {
            replace pred_spend = pred_spend + avg_ref_main_`r' if reform_types == `r'

            forvalues q = 2/4 {
                replace pred_spend = pred_spend + avg_triple_`r'_`q' if reform_types == `r' & inc_q == `q'
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

    *--- Classify High vs Low (JJP approach: threshold = 0)
    gen byte high = (pred_spend > 0) if !missing(pred_spend) & never_treated == 0
    replace high = 0 if never_treated == 1

    *--- Create quartiles of pred_spend among TREATED counties
    tempvar county_pred
    bysort county_id: egen `county_pred' = mean(pred_spend)

    _pctile `county_pred' if year == 1971 & never_treated == 0, p(25 50 75)
    local p25 = r(r1)
    local p50 = r(r2)
    local p75 = r(r3)

    gen byte pred_q = .
    replace pred_q = 1 if pred_spend <= `p25' & never_treated == 0
    replace pred_q = 2 if pred_spend > `p25' & pred_spend <= `p50' & never_treated == 0
    replace pred_q = 3 if pred_spend > `p50' & pred_spend <= `p75' & never_treated == 0
    replace pred_q = 4 if pred_spend > `p75' & never_treated == 0

    di "=== DIAGNOSTIC: High/Low Classification (Spec B Jackknife) ==="
    tab high never_treated if year == 1971, m
    di ""
    di "=== DIAGNOSTIC: pred_spend Quartiles (Treated Only) ==="
    di "Quartile cutoffs: p25=`p25' p50=`p50' p75=`p75'"
    tabstat pred_spend if year == 1971 & never_treated == 0, by(pred_q) stat(mean sd n)
    di ""

    *--- Save data with classifications for quartile graph
    tempfile data_with_pred_B_jk
    save `data_with_pred_B_jk'

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

    *==========================================================================
    * QUARTILE GRAPH: 4 lines by pred_spend quartile (Spec B Jackknife)
    *==========================================================================

    * Reload data with pred_q classification
    use `data_with_pred_B_jk', clear
    replace pred_q = 0 if never_treated == 1

    * Run regression with quartile interactions
    areg `v' ///
        i.lag_*##i.pred_q i.lead_*##i.pred_q ///
        i.year [w=school_age_pop] ///
        if good == 1 & valid_st_gd == 1 & (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    * Extract coefficients for each quartile
    tempfile results_q1 results_q2 results_q3 results_q4
    postfile hq1 str15 term float t b se str10 grp using `results_q1'
    postfile hq2 str15 term float t b se str10 grp using `results_q2'
    postfile hq3 str15 term float t b se str10 grp using `results_q3'
    postfile hq4 str15 term float t b se str10 grp using `results_q4'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#1.pred_q
        post hq1 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lead_`k' + 1.lead_`k'#2.pred_q
        post hq2 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lead_`k' + 1.lead_`k'#3.pred_q
        post hq3 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lead_`k' + 1.lead_`k'#4.pred_q
        post hq4 ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Q4")
    }
    post hq1 ("base") (0) (0) (0) ("Q1")
    post hq2 ("base") (0) (0) (0) ("Q2")
    post hq3 ("base") (0) (0) (0) ("Q3")
    post hq4 ("base") (0) (0) (0) ("Q4")
    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#1.pred_q
        post hq1 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q1")
        lincom 1.lag_`k' + 1.lag_`k'#2.pred_q
        post hq2 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q2")
        lincom 1.lag_`k' + 1.lag_`k'#3.pred_q
        post hq3 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q3")
        lincom 1.lag_`k' + 1.lag_`k'#4.pred_q
        post hq4 ("lag`k'") (`k') (r(estimate)) (r(se)) ("Q4")
    }
    postclose hq1
    postclose hq2
    postclose hq3
    postclose hq4

    * Combine all quartiles
    use `results_q1', clear
    append using `results_q2'
    append using `results_q3'
    append using `results_q4'

    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    * Plot 4 lines
    if "`v'" == "lexp" local ytitle "Δ ln(PPE)"
    if "`v'" == "lexp_ma" local ytitle "Δ ln(13-yr rolling avg PPE)"
    if "`v'" == "lexp_ma_strict" local ytitle "Δ ln(13-yr strict rolling avg PPE)"

    twoway ///
        (line b t if grp == "Q1", lcolor(navy) lwidth(medthick)) ///
        (line b t if grp == "Q2", lcolor(blue) lwidth(medthick) lpattern(dash)) ///
        (line b t if grp == "Q3", lcolor(cranberry) lwidth(medthick) lpattern(shortdash)) ///
        (line b t if grp == "Q4", lcolor(red) lwidth(medthick) lpattern(longdash)), ///
        yline(0, lcolor(gs10) lpattern(dash)) ///
        xline(0, lcolor(gs10) lpattern(dash)) ///
        xline(2 7, lcolor(gs12) lwidth(vthin)) ///
        legend(order(1 "Q1 (lowest pred)" 2 "Q2" 3 "Q3" 4 "Q4 (highest pred)") pos(6) col(4)) ///
        title("Spec B: By Quartile of Predicted Spending (Jackknife)", size(medium)) ///
        subtitle("Outcome: `v' | Balance: `balance_label' | Leave-One-State-Out", size(small) color(gs6)) ///
        ytitle("`ytitle'") ///
        xtitle("Years since reform") ///
        note("Quartiles of pred_spend among treated counties. Averaging window: lags 2-7", size(vsmall) color(gs6)) ///
        graphregion(color(white))

    graph export "$SchoolSpending/output/alt_test/fig2_`v'_specB_jk_`balance_label'_quartiles.png", replace
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
di "High/Low graphs (JJP Figure 2 style):"
di "  - fig2_{outcome}_specA_nojk_`balance_label'.png"
di "  - fig2_{outcome}_specA_jk_`balance_label'.png"
di "  - fig2_{outcome}_specB_nojk_`balance_label'.png"
di "  - fig2_{outcome}_specB_jk_`balance_label'.png"
di ""
di "Quartile graphs (4 lines by pred_spend quartile):"
di "  - fig2_{outcome}_specA_nojk_`balance_label'_quartiles.png"
di "  - fig2_{outcome}_specA_jk_`balance_label'_quartiles.png"
di "  - fig2_{outcome}_specB_nojk_`balance_label'_quartiles.png"
di "  - fig2_{outcome}_specB_jk_`balance_label'_quartiles.png"
di ""
di "Outcomes: lexp, lexp_ma, lexp_ma_strict"
di "=============================================="
