/*==============================================================================
Project    : School Spending – Full Jackknife Heterogeneity Analysis
File       : 07_jackknife_heterogeneity.do
Purpose    : Implement leave-one-state-out jackknife to identify treatment effect
             heterogeneity based on predicted spending increases
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-20
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES:
  • Loads county-year panel with interpolated spending (output from 05_create_county_panel.do)
  • Creates 13-year strict rolling mean of log per-pupil expenditure
  • Generates baseline spending quartiles (1966, 1969, 1970, 1971)
  • Implements FULL JACKKNIFE procedure:
    1. For each state, run event-study regression EXCLUDING that state
    2. Extract coefficients for main effects and interactions with baseline quartiles
    3. Calculate predicted spending increase for each county
    4. Classify counties into high/low predicted spending groups
  • Runs event-study regressions comparing high vs low predicted spending groups
  • Produces comprehensive heterogeneity analysis plots

WHY THIS MATTERS:
  This jackknife approach addresses potential endogeneity in heterogeneity analysis.
  By excluding each state when predicting its treatment effects, we avoid
  mechanical correlation between the state's data and its predicted effects.
  The balanced panel restriction ensures all treated counties have complete data
  coverage from 5 years pre-reform to 17 years post-reform, strengthening the
  parallel trends assumption. This provides more credible estimates of which
  counties benefited most from school finance reforms.

METHODOLOGICAL NOTES:
  - Predicted spending = avg_main + avg_ppe_q2 + avg_ppe_q3 + avg_ppe_q4 + avg_inc_q
  - Average taken over lags 2-7 (years 2-7 post-reform) to capture medium-term effects
  - High/low classification based on median predicted spending among treated counties
  - Never-treated counties serve as control group for both high and low groups

INPUTS:
  - county_clean.dta          (from 04_tag_county_quality.do)
  - county_exp_final.dta      (from 05_create_county_panel.do)
  - tabula-tabled2.xlsx       (reform data from JJP 2016)

OUTPUTS:
  - jjp_interp_jk.dta               (Full county panel with all variables)
  - jjp_balance_jk.dta              (Balanced county panel)
  - pred_spend_ppe_all_jk.dta       (Dataset with predicted spending classifications)
  - Event-study graphs:
      * High predicted spending group
      * Low predicted spending group
      * Combined high vs low comparison
      * Quartiles of predicted spending

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending\data"

*** ---------------------------------------------------------------------------
*** Section 1: Load and Merge County Data
*** ---------------------------------------------------------------------------

use county_clean, clear
drop if missing(year4)
merge 1:m county using county_exp_final
drop _merge
replace good_county = 0 if missing(good_county)
drop if missing(county_exp)

*--- Create county ID and treatment indicators
rename county county_id
gen never_treated = treatment == 0
bysort county_id: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4 - 1

*--- Winsorize spending at 1st and 99th percentiles
winsor2 county_exp, replace c(1 99) by(year_unified)

*** ---------------------------------------------------------------------------
*** Section 2: Create 13-Year Strict Rolling Mean
*** ---------------------------------------------------------------------------

rename county_exp exp
gen lexp = log(exp)

*--- Simple 13-year rolling mean
rangestat (mean) exp, interval(year_unified -12 0) by(county_id)
rename exp_mean exp_ma
gen lexp_ma = log(exp_ma)

*--- Strict 13-year rolling mean (only if full 13-year window available)
rangestat (mean) exp_ma_strict = exp (count) n_obs = exp, ///
    interval(year_unified -12 0) by(county_id)

* Keep only obs with full 13-year window
replace exp_ma_strict = . if n_obs < 13
gen lexp_ma_strict = log(exp_ma_strict)

*** ---------------------------------------------------------------------------
*** Section 3: Create Relative Year Indicators
*** ---------------------------------------------------------------------------

gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

* Convert string county_id → numeric for panel operations
encode county_id, gen(county_num)

drop if missing(exp)
save interp_temp_jk, replace

*** ---------------------------------------------------------------------------
*** Section 4: Create Baseline Spending Quartiles (Multiple Years)
*** ---------------------------------------------------------------------------

*--- Create quartiles for years 1966, 1969, 1970, 1971
local years 1966 1969 1970 1971
preserve
foreach y of local years {
    use interp_temp_jk, clear
    keep if year_unified == `y'
    keep if !missing(exp, state_fips, county_id)

    count
    if r(N) == 0 {
        di as error "No observations for year `y' — skipping."
        continue
    }

    *--- Within-state quartiles
    bysort state_fips: egen pre_q`y' = xtile(exp), n(4)
    keep state_fips county_id pre_q`y'

    tempfile q`y'
    save `q`y'', replace
}
restore

*--- Merge quartiles back to main data
foreach y of local years {
    merge m:1 state_fips county_id using `q`y'', nogen
}

*--- Create average baseline spending measures
local number 66 69 70 71
foreach n of local number {
    gen base_`n' = .
    replace base_`n' = exp if year_unified == 19`n'
    bys county_id: egen base_`n'_max = max(base_`n')
    drop base_`n'
    rename base_`n'_max base_`n'
}

*--- Create average baseline quartiles across multiple years
egen base_exp = rowmean(base_66 base_69 base_70 base_71)
bys state_fips: egen pre_q_66_71 = xtile(base_exp), n(4)

egen base_exp2 = rowmean(base_66 base_69 base_70)
bys state_fips: egen pre_q_66_70 = xtile(base_exp2), n(4)

egen base_exp3 = rowmean(base_69 base_70 base_71)
bys state_fips: egen pre_q_69_71 = xtile(base_exp3), n(4)

*** ---------------------------------------------------------------------------
*** Section 5: Create Income Quartiles
*** ---------------------------------------------------------------------------

*--- Parse median family income from 1969 GRF data
gen med_fam_inc = regexr(median_family_income, "[^0-9]", "")
destring med_fam_inc, replace
drop median_family_income

*--- Create income quartiles (within state)
preserve
duplicates drop county_id, force
bysort state_fips: egen inc_q = xtile(med_fam_inc), n(4)
keep state_fips county_id inc_q
tempfile inc_q69
save `inc_q69'
restore

merge m:1 state_fips county_id using `inc_q69', nogen

*--- Create income quartile dummies
tab inc_q, gen(inc_q_)

*--- Create bottom 3 quartiles indicator
gen inc_btm_3 = .
replace inc_btm_3 = 1 if inlist(inc_q, 1, 2, 3)
replace inc_btm_3 = 0 if inc_q == 4

*** ---------------------------------------------------------------------------
*** Section 6: Create Lead and Lag Indicators
*** ---------------------------------------------------------------------------

*--- Post-reform indicators (lag_1 through lag_17)
forvalues k = 1/17 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}

*--- Pre-reform indicators (lead_1 through lead_5)
forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}

*--- Bin endpoints
replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year)  // Bin 17+
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)   // Bin -5 and earlier

*--- Drop LA County (06037) as in original JJP analysis
drop if county_id == "06037"

*** ---------------------------------------------------------------------------
*** Section 7: Save Intermediate Dataset
*** ---------------------------------------------------------------------------

save jjp_interp_jk, replace

*** ---------------------------------------------------------------------------
*** Section 8: Create Balanced Panel (Event-Time Restriction)
*** ---------------------------------------------------------------------------

di as result _n "***********************************************"
di as result "*** CREATING BALANCED PANEL ***"
di as result "***********************************************" _n

*--- Identify counties with complete event windows (-5 to +17)
preserve
keep if inrange(relative_year, -5, 17)  // Only check within the event window

* Find counties with complete windows
bys county_id: egen min_rel = min(relative_year)
bys county_id: egen max_rel = max(relative_year)
bys county_id: gen n_rel = _N

* Keep only if they have the full window
keep if min_rel == -5 & max_rel == 17 & n_rel == 23

* Count nonmissing lexp in the window
bys county_id: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys county_id: replace n_nonmiss = n_nonmiss[_N]

* Keep only counties with full window AND no missing spending
keep if min_rel == -5 & max_rel == 17 & n_rel == 23 & n_nonmiss == 23

keep county_id
duplicates drop
gen balance = 1
tempfile balance
save `balance'
restore

*--- Merge balance indicator back
merge m:1 county_id using `balance'
replace balance = 0 if missing(balance)

*--- Display balance statistics
di as text _n "Balance Statistics:"
tab balance
tab balance if ever_treated == 1

*--- Keep balanced counties and never-treated controls
keep if balance == 1 | never_treated2 == 1

di as text _n "Sample size after balanced panel restriction:"
unique county_id

save jjp_balance_jk, replace

*** ---------------------------------------------------------------------------
*** Section 9: JACKKNIFE PROCEDURE - Run Leave-One-State-Out Regressions
*** ---------------------------------------------------------------------------

di as result _n "***********************************************"
di as result "*** STARTING JACKKNIFE PROCEDURE ***"
di as result "***********************************************" _n

use jjp_balance_jk, clear

*--- Use 1971 baseline quartile as primary specification
rename pre_q1971 pre_q

tempfile reg_temp
save `reg_temp'

*--- Get list of all states in the data
levelsof state_fips, local(states)
local n_states : word count `states'
di as result "Running jackknife for `n_states' states on BALANCED PANEL..."

*--- Loop 1: Run regressions excluding each state and save estimates
local counter = 0
foreach s of local states {
    local counter = `counter' + 1
    di as text "  [`counter'/`n_states'] Running regression excluding state `s'..."

    preserve
    use `reg_temp', clear
    drop if state_fips == "`s'"

    *--- Main event-study regression with interactions on BALANCED PANEL
    quietly areg lexp_ma_strict ///
        i.lag_*##i.pre_q i.lead_*##i.pre_q ///
        i.lag_*##i.inc_q i.lead_*##i.inc_q ///
        i.year_unified##i.pre_q##i.inc_q ///
        [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    estimates save layer_mod_`s', replace
    restore
}

di as result _n "Jackknife regressions completed!" _n

*** ---------------------------------------------------------------------------
*** Section 10: Extract Coefficients and Calculate Predicted Spending
*** ---------------------------------------------------------------------------

di as result "***********************************************"
di as result "*** EXTRACTING COEFFICIENTS ***"
di as result "***********************************************" _n

*--- Loop 2: Extract coefficients from each jackknife regression
local counter = 0
foreach s of local states {
    local counter = `counter' + 1
    di as text "  [`counter'/`n_states'] Extracting coefficients for state `s'..."

    preserve
    use `reg_temp', clear
    estimates use layer_mod_`s'

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
    * Generate placeholders
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
    * Generate placeholders
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

    *--- Keep only observations from the excluded state
    keep if state_fips == "`s'"
    save pred_spend_ppe_`s', replace
    restore
}

di as result _n "Coefficient extraction completed!" _n

*** ---------------------------------------------------------------------------
*** Section 11: Combine Predicted Spending Across All States
*** ---------------------------------------------------------------------------

use `reg_temp', clear
levelsof state_fips, local(states)

clear
tempfile master
save `master', emptyok

*--- Append predicted spending from all states
foreach s of local states {
    append using pred_spend_ppe_`s'.dta
}

*** ---------------------------------------------------------------------------
*** Section 12: Create High/Low Predicted Spending Groups
*** ---------------------------------------------------------------------------

di as result "***********************************************"
di as result "*** CREATING TREATMENT GROUPS ***"
di as result "***********************************************" _n

*--- Create median split among treated counties
xtile pred_group = pred_spend if ever_treated == 1, nq(2)
gen high_treated = pred_group == 2
gen low_treated  = pred_group == 1

*--- Create quartiles of predicted spending
xtile pred_q = pred_spend if ever_treated == 1, nq(4)

*--- Label quartiles
label define q_lbl 1 "Q1 (Lowest)" 2 "Q2" 3 "Q3" 4 "Q4 (Highest)"
label values pred_q q_lbl

*--- Display summary statistics
summ pred_spend, detail
tab pre_q high_treated if never_treated == 0, m

save pred_spend_ppe_all_jk, replace

*** ---------------------------------------------------------------------------
*** Section 13: Event-Study Regression - High Predicted Spending Group
*** ---------------------------------------------------------------------------

di as result _n "***********************************************"
di as result "*** RUNNING EVENT-STUDY: HIGH GROUP ***"
di as result "***********************************************" _n

use pred_spend_ppe_all_jk, clear

*--- Display cross-tabulation
tab pre_q high_treated, m
tab pre_q high_treated if never_treated == 0

*--- Run event-study regression
areg lexp_ma_strict ///
    i.lag_*##i.high_treated i.lead_*##i.high_treated ///
    i.year_unified##i.high_treated ///
    [aw = school_age_pop] if (reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)

*--- Extract coefficients for plotting
capture postutil clear
tempfile results
postfile handle str15 term float relative_year b se using `results'

*** Main + Interaction (High group) ***
forvalues k = 5(-1)1 {
    lincom 1.lead_`k' + 1.lead_`k'#1.high_treated
    post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle ("base0") (0) (0) (0)

forvalues k = 1/17 {
    lincom 1.lag_`k' + 1.lag_`k'#1.high_treated
    post handle ("lag`k'") (`k') (r(estimate)) (r(se))
}

postclose handle

*--- Create plot
use `results', clear
keep if inrange(relative_year, -5, 17)
sort relative_year

gen ci_lo = b - 1.96 * se
gen ci_hi = b + 1.96 * se

twoway (rarea ci_lo ci_hi relative_year, color(gs12%40) cmissing(n)) ///
       (line b relative_year, lcolor(black) lwidth(medthick)), ///
       yline(0, lpattern(dash) lcolor(gs8)) ///
       xline(0, lpattern(dash) lcolor(gs8)) ///
       xline(2 7, lcolor(blue) lwidth(thin)) ///
       ytitle("Change in ln(13-yr rolling avg PPE)") ///
       xtitle("Years relative to reform") ///
       title("Event Study: High Predicted Spending Group") ///
       legend(off) ///
       graphregion(color(white))

*** ---------------------------------------------------------------------------
*** Section 14: Event-Study Regression - Low Predicted Spending Group
*** ---------------------------------------------------------------------------

di as result _n "***********************************************"
di as result "*** RUNNING EVENT-STUDY: LOW GROUP ***"
di as result "***********************************************" _n

use pred_spend_ppe_all_jk, clear

*--- Display cross-tabulation
tab pre_q low_treated, m
tab pre_q low_treated if never_treated == 0

*--- Run event-study regression
areg lexp_ma_strict ///
    i.lag_*##i.low_treated i.lead_*##i.low_treated ///
    i.year_unified##i.low_treated ///
    [aw = school_age_pop] if (reform_year < 2000), ///
    absorb(county_id) vce(cluster county_id)

*--- Extract coefficients for plotting
capture postutil clear
tempfile results2
postfile handle2 str15 term float relative_year b se using `results2'

*** Main + Interaction (Low group) ***
forvalues k = 5(-1)1 {
    lincom 1.lead_`k' + 1.lead_`k'#1.low_treated
    post handle2 ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle2 ("base0") (0) (0) (0)

forvalues k = 1/17 {
    lincom 1.lag_`k' + 1.lag_`k'#1.low_treated
    post handle2 ("lag`k'") (`k') (r(estimate)) (r(se))
}

postclose handle2

*--- Create plot
use `results2', clear
keep if inrange(relative_year, -5, 17)
sort relative_year

gen ci_lo = b - 1.96 * se
gen ci_hi = b + 1.96 * se

twoway (rarea ci_lo ci_hi relative_year, color(gs12%40) cmissing(n)) ///
       (line b relative_year, lcolor(black) lwidth(medthick)), ///
       yline(0, lpattern(dash) lcolor(gs8)) ///
       xline(0, lpattern(dash) lcolor(gs8)) ///
       xline(2 7, lcolor(blue) lwidth(thin)) ///
       ytitle("Change in ln(13-yr rolling avg PPE)") ///
       xtitle("Years relative to reform") ///
       title("Event Study: Low Predicted Spending Group") ///
       legend(off) ///
       graphregion(color(white))

*** ---------------------------------------------------------------------------
*** Section 15: Combined Plot - High vs Low Predicted Spending
*** ---------------------------------------------------------------------------

di as result _n "***********************************************"
di as result "*** CREATING COMBINED PLOT ***"
di as result "***********************************************" _n

*--- Combine high and low results
use `results', clear
gen group = "High"

append using `results2'
replace group = "Low" if missing(group)

keep if inrange(relative_year, -5, 17)
sort relative_year group

gen ci_lo = b - 1.96 * se
gen ci_hi = b + 1.96 * se

*--- Create combined plot
twoway ///
    (rarea ci_lo ci_hi relative_year if group == "High", color(blue%20)) ///
    (line b relative_year if group == "High", lcolor(blue) lwidth(medthick)) ///
    (rarea ci_lo ci_hi relative_year if group == "Low", color(red%20)) ///
    (line b relative_year if group == "Low", lcolor(red) lpattern(dash) lwidth(medthick)) ///
    , ///
    yline(0, lpattern(dash) lcolor(gs8)) ///
    xline(0, lpattern(dash) lcolor(gs8)) ///
    xline(2 7, lcolor(gs8) lwidth(thin)) ///
    ytitle("Change in ln(13-yr rolling avg PPE)") ///
    xtitle("Years relative to reform") ///
    legend(order(2 "High (Predicted Spend ↑)" 4 "Low (Predicted Spend ↓)") pos(5) ring(0)) ///
    title("Event Study: High vs Low Predicted Spending") ///
    graphregion(color(white))

*** ---------------------------------------------------------------------------
*** Section 16: Quartile Analysis - All Four Groups
*** ---------------------------------------------------------------------------

di as result _n "***********************************************"
di as result "*** RUNNING QUARTILE ANALYSIS ***"
di as result "***********************************************" _n

use pred_spend_ppe_all_jk, clear

*--- Run event-study regression with quartile interactions
areg lexp_ma_strict ///
    i.lag_*##i.pred_q i.lead_*##i.pred_q ///
    i.year_unified##i.pred_q ///
    [aw = school_age_pop] if (reform_year < 2000 | never_treated == 1), ///
    absorb(county_id) vce(cluster county_id)

*--- Extract coefficients for each quartile
capture postutil clear

foreach q in 1 2 3 4 {
    tempfile q`q'
    capture postclose h`q'
    postfile h`q' str15 term float relative_year b se quart using `q`q''

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k' + 1.lead_`k'#`q'.pred_q
        post h`q' ("lead`k'") (-`k') (r(estimate)) (r(se)) (`q')
    }

    post h`q' ("base0") (0) (0) (0) (`q')

    forvalues k = 1/17 {
        lincom 1.lag_`k' + 1.lag_`k'#`q'.pred_q
        post h`q' ("lag`k'") (`k') (r(estimate)) (r(se)) (`q')
    }

    postclose h`q'
}

*--- Combine all quartiles
use `q1', clear
replace quart = 1

append using `q2'
replace quart = 2 if missing(quart)

append using `q3'
replace quart = 3 if missing(quart)

append using `q4'
replace quart = 4 if missing(quart)

keep if inrange(relative_year, -5, 17)
gen ci_lo = b - 1.96 * se
gen ci_hi = b + 1.96 * se

label values quart q_lbl
sort relative_year quart

*--- Create quartile plot
twoway ///
    (line b relative_year if quart == 1, lcolor(navy) lwidth(medthick)) ///
    (line b relative_year if quart == 2, lcolor(forest_green) lwidth(medthick)) ///
    (line b relative_year if quart == 3, lcolor(orange) lwidth(medthick)) ///
    (line b relative_year if quart == 4, lcolor(cranberry) lwidth(medthick)) ///
    , ///
    yline(0, lpattern(dash) lcolor(gs8)) ///
    xline(0, lpattern(dash) lcolor(gs8)) ///
    xline(2 7, lcolor(blue) lwidth(thin)) ///
    ytitle("Change in ln(13-yr rolling avg PPE)") ///
    xtitle("Years relative to reform") ///
    legend(order(1 "Q1 (Lowest)" 2 "Q2" 3 "Q3" 4 "Q4 (Highest)") pos(6)) ///
    title("Event Study: School Spending by Predicted Quartiles") ///
    graphregion(color(white))

*** ---------------------------------------------------------------------------
*** Section 17: Summary Statistics and Diagnostics
*** ---------------------------------------------------------------------------

di as result _n "***********************************************"
di as result "*** SUMMARY STATISTICS ***"
di as result "***********************************************" _n

use pred_spend_ppe_all_jk, clear

*--- Display predicted spending distribution
di as text _n "Predicted Spending Distribution:"
summ pred_spend, detail

*--- Display group sizes
di as text _n "Sample sizes by group:"
tab high_treated
tab low_treated
tab pred_q

*--- Display cross-tabulation of baseline quartile and predicted spending
di as text _n "Cross-tabulation: Baseline Quartile × Predicted Spending Group"
tab pre_q high_treated if never_treated == 0, row col

di as text _n "Cross-tabulation: Income Quartile × Predicted Spending Group"
tab inc_q high_treated if never_treated == 0, row col

di as result _n "***********************************************"
di as result "*** JACKKNIFE ANALYSIS COMPLETE ***"
di as result "***********************************************" _n

*--- Clean up temporary files
foreach s of local states {
    capture erase layer_mod_`s'.ster
    capture erase pred_spend_ppe_`s'.dta
}

di as text "Output files saved:"
di as text "  - jjp_interp_jk.dta (full county panel)"
di as text "  - jjp_balance_jk.dta (balanced county panel)"
di as text "  - pred_spend_ppe_all_jk.dta (predicted spending classifications)"

*** ---------------------------------------------------------------------------
*** END OF FILE
*** ---------------------------------------------------------------------------
