/*==============================================================================
Project    : School Spending – Figure 1 Event-Study Regressions
File       : 07_figure1_event_study.do
Purpose    : Run event-study regressions by baseline spending quartile and
             generate Figure 1 style plots replicating JJP (2016).
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2026-01-05
-------------------------------------------------------------------------------

WHAT THIS FILE DOES:
  - Part A: Event-study regressions by individual quartile (Q1, Q2, Q3, Q4)
  - Part B: Event-study regression for bottom 3 quartiles pooled (Q1-Q3)
  - Produces coefficient plots with 90% confidence intervals

INPUTS:
  - jjp_final.dta (from 06_build_jjp_final.do)

OUTPUTS:
  - Event-study graphs by quartile
  - Optional: Export to PNG files

SPECIFICATIONS:
  - Outcome: lexp_ma_strict (log 13-year strict rolling mean PPE)
  - Fixed effects: county_id
  - Clustering: county_id
  - Weights: school_age_pop
  - Event window: -5 to +17 (lead_5 binned, lag_17 binned)
  - Sample: reform_year < 2000 (excludes late reforms)

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Event-Study Regressions by Quartile (Q1, Q2, Q3, Q4)
*** ---------------------------------------------------------------------------

local depvar lexp_ma_strict

foreach v of local depvar {
    forvalues q = 1/4 {
        use jjp_final, clear

        *--- Weighted event-study regression
        areg `v' ///
            i.lag_* i.lead_* ///
            i.year_unified [w=school_age_pop] ///
            if (pre_q == `q' | never_treated == 1) ///
             & (reform_year < 2000 | never_treated == 1), ///
            absorb(county_id) vce(cluster county_id)

        *--- Extract coefficients to dataset
        tempfile results
        postfile handle str15 term float rel_year b se using `results', replace

        * Pre-reform coefficients (leads)
        forvalues k = 5(-1)1 {
            lincom 1.lead_`k'
            post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
        }

        * Baseline (omitted year 0)
        post handle ("base0") (0) (0) (0)

        * Post-reform coefficients (lags)
        forvalues k = 1/17 {
            lincom 1.lag_`k'
            post handle ("lag`k'") (`k') (r(estimate)) (r(se))
        }

        postclose handle

        *--- Create event-study plot
        use `results', clear
        sort rel_year

        gen ci_lo = b - 1.645 * se
        gen ci_hi = b + 1.645 * se

        twoway ///
            (rarea ci_lo ci_hi rel_year, color("59 91 132%20") lw(none)) ///
            (line b rel_year, lcolor("42 66 94") lwidth(medthick)), ///
            yline(0, lpattern(dash) lcolor(gs10)) ///
            xline(0, lpattern(dash) lcolor(gs10)) ///
            ytitle("Δ ln(13-yr rolling avg PPE)") ///
            xtitle("Years since reform") ///
            title("`v' | Quartile `q'", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)

        * Uncomment to export:
        * graph export "$SchoolSpending/output/fig1_`v'_q`q'.png", replace
    }
}

*** ---------------------------------------------------------------------------
*** Section 2: Event-Study Regression - Bottom 3 Quartiles Pooled (Q1-Q3)
*** ---------------------------------------------------------------------------

local depvar lexp_ma_strict

foreach v of local depvar {
    use jjp_final, clear

    *--- Weighted regression excluding top quartile
    areg `v' ///
        i.lag_* i.lead_* ///
        i.year_unified [w=school_age_pop] ///
        if (pre_q < 4 | never_treated == 1) ///
         & (reform_year < 2000 | never_treated == 1), ///
        absorb(county_id) vce(cluster county_id)

    *--- Extract coefficients to dataset
    tempfile results
    postfile handle str15 term float rel_year b se using `results', replace

    * Pre-reform coefficients (leads)
    forvalues k = 5(-1)1 {
        lincom 1.lead_`k'
        post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
    }

    * Baseline (omitted year 0)
    post handle ("base0") (0) (0) (0)

    * Post-reform coefficients (lags)
    forvalues k = 1/17 {
        lincom 1.lag_`k'
        post handle ("lag`k'") (`k') (r(estimate)) (r(se))
    }

    postclose handle

    *--- Create event-study plot
    use `results', clear
    sort rel_year

    gen ci_lo = b - 1.645 * se
    gen ci_hi = b + 1.645 * se

    twoway ///
        (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
        (line b rel_year, lcolor("42 66 94") lwidth(medium)), ///
        yline(0, lpattern(dash) lcolor(gs10)) ///
        xline(0, lpattern(dash) lcolor(gs10)) ///
        ytitle("Δ ln(per-pupil spending)", size(medsmall) margin(medium)) ///
        xtitle("Years since reform") ///
        title("`v' | Quartiles 1-3", size(medlarge) color("35 45 60")) ///
        graphregion(color(white)) ///
        legend(off) ///
        scheme(s2mono)

    * Uncomment to export:
    * graph export "$SchoolSpending/output/fig1_`v'_q1to3.png", replace
}
