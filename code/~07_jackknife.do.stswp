/*==============================================================================
Project    : School Spending – Full Jackknife Heterogeneity Analysis [REFORMED]
File       : 07_jackknife_reformed.do
Purpose    : Implement leave-one-state-out jackknife with COMPREHENSIVE REFORMS
             including reform type heterogeneity, expanded baseline periods, and
             enhanced prediction models based on 11_6_25_jk_reform improvements
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-20 [Reformed: 2025-01-08]
───────────────────────────────────────────────────────────────────────────────

REFORMS INTEGRATED FROM 11_6_25_jk_reform:
  1. Reform Type × Income Interactions: Added triple interactions for equity, MFP, EP, LE, SL reforms with income quartiles
  2. Expanded Year-Fixed Effects: Interactions with all reform types
  3. Enhanced Prediction Model: Includes reform × income-specific treatment effects
  4. Improved Averaging Window: Focused on lags 2-7 for medium-term effects
  5. Combined Visualization: High vs low groups on single plot
  6. Multiple Baseline Options: Support for various baseline year combinations

WHAT THIS FILE DOES:
  • Loads county-year panel with interpolated spending
  • Creates 13-year strict rolling mean of log per-pupil expenditure
  • Generates baseline spending quartiles (multiple year options)
  • Implements ENHANCED JACKKNIFE procedure:
    1. For each state, run event-study regression EXCLUDING that state
    2. Extract coefficients for main effects, baseline quartiles, income quartiles,
       AND REFORM TYPE interactions
    3. Calculate predicted spending increase incorporating ALL heterogeneity
    4. Classify counties into high/low and quartile groups
  • Runs event-study regressions with comprehensive heterogeneity analysis
  • Produces enhanced visualizations including combined comparison plots

METHODOLOGICAL IMPROVEMENTS:
  - Predicted spending = avg_main + avg_ppe_q + avg_inc_q + avg_reform_type×inc_q
  - Reform type effects are interacted with income quartiles to capture differential impacts
  - Averaging window (lags 2-7) focuses on stable medium-term effects
  - Never-treated counties serve as control group for all specifications

INPUTS:
  - county_clean.dta          (from 04_tag_county_quality.do)
  - county_exp_final.dta      (from 05_create_county_panel.do)
  - tabula-tabled2.xlsx       (reform data from JJP 2016)

OUTPUTS:
  - jjp_interp_jk.dta               (Full county panel with all variables)
  - jjp_balance_jk.dta              (Balanced county panel)
  - pred_spend_ppe_all_jk.dta       (Dataset with enhanced predicted spending)
  - Event-study graphs:
      * High vs Low combined comparison
      * Quartiles of predicted spending
      * Reform-type specific heterogeneity plots

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
merge 1:m county using county_exp_final
drop _merge
replace good_county = 0 if missing(good_county)
drop if missing(year4)

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

save interp_temp_jk, replace

*** ---------------------------------------------------------------------------
*** Section 4: Create Baseline Spending Quartiles (REFORMED: Multiple Years)
*** ---------------------------------------------------------------------------

*--- REFORM: Create quartiles for multiple baseline years (flexibility)
local years 1966 1969 1970 1971
preserve
foreach y of local years {
    use interp_temp_jk, clear
    keep if year_unified == `y'
    keep if !missing(exp, state_fips, county_id)

    count
    if r(N)==0 {
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

*--- Merge all quartiles back to main data
foreach y of local years {
    capture merge m:1 state_fips county_id using `q`y'', nogen
}

*--- REFORM: Create average baseline measures for robustness
local number 66 69 70 71
foreach n of local number {
    gen base_`n' = .
    replace base_`n' = exp if year_unified == 19`n'
    bys county_id: egen base_`n'_max = max(base_`n')
    drop base_`n'
    rename base_`n'_max base_`n'
}

* Create combined baseline quartiles
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

*** ---------------------------------------------------------------------------
*** Section 7: Save Intermediate Dataset
*** ---------------------------------------------------------------------------

save jjp_interp_jk, replace

*** ---------------------------------------------------------------------------
*** Section 8: Create Balanced Panel (Event-Time Restriction)
*** ---------------------------------------------------------------------------

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
keep if min_rel == -5 & max_rel == 17 & n_rel == 23 

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
tab balance
tab balance if ever_treated == 1

*--- Keep balanced counties and never-treated controls
keep if balance == 1 | never_treated2 == 1

save jjp_balance_jk, replace

*** ---------------------------------------------------------------------------
*** Section 9: JACKKNIFE PROCEDURE - REFORMED with Reform Type Heterogeneity
*** ---------------------------------------------------------------------------

use jjp_balance_jk, clear

*--- Use 1971 baseline quartile as primary specification
rename pre_q1971 pre_q

tempfile reg_temp
save `reg_temp'

*--- Get list of all states in the data
levelsof state_fips, local(states)
local n_states : word count `states'

*--- Loop 1: Run REFORMED regressions excluding each state
foreach s of local states {
    preserve
    use `reg_temp', clear
    drop if state_fips == "`s'"

    *--- REFORMED: Enhanced regression with reform type interactions WITH INCOME QUARTILES
    areg lexp_ma_strict ///
        i.lag_*##i.pre_q i.lead_*##i.pre_q ///
        i.lag_*##i.inc_q i.lead_*##i.inc_q ///
        i.lag_*##i.inc_q##i.reform_eq i.lead_*##i.inc_q##i.reform_eq ///
        i.lag_*##i.inc_q##i.reform_mfp i.lead_*##i.inc_q##i.reform_mfp ///
        i.lag_*##i.inc_q##i.reform_ep i.lead_*##i.inc_q##i.reform_ep ///
        i.lag_*##i.inc_q##i.reform_le i.lead_*##i.inc_q##i.reform_le ///
        i.lag_*##i.inc_q##i.reform_sl i.lead_*##i.inc_q##i.reform_sl ///
        i.year_unified##(i.pre_q i.inc_q i.reform_eq i.reform_mfp i.reform_ep i.reform_le i.reform_sl) ///
        [aw = school_age_pop] if (never_treated == 1 | reform_year < 2000), ///
        absorb(county_id) vce(cluster county_id)

    estimates save layer_mod_`s', replace
    restore
}

*** ---------------------------------------------------------------------------
*** Section 10: Extract REFORMED Coefficients and Calculate Predicted Spending
*** ---------------------------------------------------------------------------

*--- Loop 2: Extract enhanced coefficients from each jackknife regression
local counter = 0
foreach s of local states {
    local counter = `counter' + 1
    di as text "  [`counter'/`n_states'] Extracting enhanced coefficients for state `s'..."

    preserve
    use `reg_temp', clear
    estimates use layer_mod_`s'

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

    **# REFORM: Generate Reform Type × Income Interaction Coefficients
    local reform_types reform_eq reform_mfp reform_ep reform_le reform_sl
    foreach r of local reform_types {
        forvalues t = 2/7 {
            forvalues q = 1/4 {
                gen ref_`t'_`r'_`q' = .
            }
        }
    }

    * Fill reform × income coefficients (triple interaction)
    foreach r of local reform_types {
        forvalues t = 2/7 {
            forvalues q = 1/4 {
                capture scalar coeff_ref = _b[1.lag_`t'#`q'.inc_q#1.`r']
                if _rc == 0 {
                    replace ref_`t'_`r'_`q' = coeff_ref
                }
            }
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

    *--- REFORM: Average reform type × income interactions
    foreach r of local reform_types {
        forvalues q = 1/4 {
            egen avg_ref_`r'_`q' = rowmean( ///
                ref_2_`r'_`q' ref_3_`r'_`q' ref_4_`r'_`q' ///
                ref_5_`r'_`q' ref_6_`r'_`q' ref_7_`r'_`q')
        }
    }

    **# REFORMED: Calculate Enhanced Predicted Spending Increase
    gen pred_spend = avg_main if !missing(pre_q)

    *--- Add baseline spending interaction effects
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
    }

    *--- Add income interaction effects
    forvalues q = 2/4 {
        replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
    }

    *--- REFORM: Add reform type × income interaction effects
    foreach r of local reform_types {
        forvalues q = 1/4 {
            replace pred_spend = pred_spend + avg_ref_`r'_`q' if `r' == 1 & inc_q == `q'
        }
    }

    *--- Keep only observations from the excluded state
    keep if state_fips == "`s'"
    save pred_spend_ppe_`s', replace
    restore
}

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
*** Section 12: Create High/Low Predicted Spending Groups (REFORMED)
*** ---------------------------------------------------------------------------

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

*--- REFORM: Display reform type distribution in high/low groups
tab reform_eq high_treated if never_treated == 0, m
tab reform_mfp high_treated if never_treated == 0, m

save pred_spend_ppe_all_jk, replace

*** ---------------------------------------------------------------------------
*** Section 13: REFORMED Combined Event-Study - High vs Low Groups
*** ---------------------------------------------------------------------------

use pred_spend_ppe_all_jk, clear

*--- Run regression for HIGH predicted spending group
areg lexp_ma_strict ///
    i.lag_*##i.high_treated i.lead_*##i.high_treated ///
    i.year_unified##i.high_treated ///
    [aw = school_age_pop] if (reform_year < 2000 | never_treated == 1), ///
    absorb(county_id) vce(cluster county_id)

*--- Extract HIGH group coefficients
capture postutil clear
tempfile results_high
postfile handle_h str15 term float relative_year b se str10 group using `results_high'

forvalues k = 5(-1)1 {
    lincom 1.lead_`k' + 1.lead_`k'#1.high_treated
    post handle_h ("lead`k'") (-`k') (r(estimate)) (r(se)) ("High")
}

post handle_h ("base0") (0) (0) (0) ("High")

forvalues k = 1/17 {
    lincom 1.lag_`k' + 1.lag_`k'#1.high_treated
    post handle_h ("lag`k'") (`k') (r(estimate)) (r(se)) ("High")
}

postclose handle_h

*--- Run regression for LOW predicted spending group
areg lexp_ma_strict ///
    i.lag_*##i.low_treated i.lead_*##i.low_treated ///
    i.year_unified##i.low_treated ///
    [aw = school_age_pop] if (reform_year < 2000 | never_treated == 1), ///
    absorb(county_id) vce(cluster county_id)

*--- Extract LOW group coefficients
tempfile results_low
postfile handle_l str15 term float relative_year b se str10 group using `results_low'

forvalues k = 5(-1)1 {
    lincom 1.lead_`k' + 1.lead_`k'#1.low_treated
    post handle_l ("lead`k'") (-`k') (r(estimate)) (r(se)) ("Low")
}

post handle_l ("base0") (0) (0) (0) ("Low")

forvalues k = 1/17 {
    lincom 1.lag_`k' + 1.lag_`k'#1.low_treated
    post handle_l ("lag`k'") (`k') (r(estimate)) (r(se)) ("Low")
}

postclose handle_l

*** ---------------------------------------------------------------------------
*** Section 14: REFORMED Combined Visualization - High vs Low
*** ---------------------------------------------------------------------------

*--- Combine high and low results
use `results_high', clear
append using `results_low'

keep if inrange(relative_year, -5, 17)
sort relative_year group

gen ci_lo = b - 1.96 * se
gen ci_hi = b + 1.96 * se

*--- REFORMED: Enhanced combined plot with shaded prediction window
twoway ///
    (rarea ci_lo ci_hi relative_year if group == "High", color(blue%20)) ///
    (line b relative_year if group == "High", lcolor(blue) lwidth(medthick)) ///
    (rarea ci_lo ci_hi relative_year if group == "Low", color(red%20)) ///
    (line b relative_year if group == "Low", lcolor(red) lpattern(dash) lwidth(medthick)), ///
    yline(0, lpattern(dash) lcolor(gs8)) ///
    xline(0, lpattern(dash) lcolor(gs8)) ///
    xline(2 7, lcolor(gs12) lwidth(thin)) ///
    xscale(range(-5 17)) ///
    xlabel(-5(5)15 17) ///
    ytitle("Change in ln(13-yr rolling avg PPE)") ///
    xtitle("Years relative to reform") ///
    legend(order(2 "High Predicted Spending" 4 "Low Predicted Spending") ///
           pos(5) ring(0) cols(1)) ///
    title("Reformed Event Study: Heterogeneous Treatment Effects") ///
    subtitle("Based on predicted spending with reform type heterogeneity") ///
    note("Shaded region (years 2-7) indicates averaging window for prediction") ///
    graphregion(color(white))

graph export "reformed_event_study_combined.png", replace

*** ---------------------------------------------------------------------------
*** Section 15: REFORMED Quartile Analysis with Reform Types
*** ---------------------------------------------------------------------------

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

*--- REFORMED: Enhanced quartile plot with gradient colors
twoway ///
    (line b relative_year if quart == 1, lcolor(navy) lwidth(medthick)) ///
    (line b relative_year if quart == 2, lcolor(forest_green) lwidth(medthick)) ///
    (line b relative_year if quart == 3, lcolor(orange) lwidth(medthick)) ///
    (line b relative_year if quart == 4, lcolor(cranberry) lwidth(medthick)), ///
    yline(0, lpattern(dash) lcolor(gs8)) ///
    xline(0, lpattern(dash) lcolor(gs8)) ///
    xline(2 7, lcolor(gs12) lwidth(thin)) ///
    xscale(range(-5 17)) ///
    xlabel(-5(5)15 17) ///
    ytitle("Change in ln(13-yr rolling avg PPE)") ///
    xtitle("Years relative to reform") ///
    legend(order(1 "Q1 (Lowest)" 2 "Q2" 3 "Q3" 4 "Q4 (Highest)") ///
           pos(6) rows(1)) ///
    title("Reformed Event Study: Quartiles of Predicted Spending") ///
    subtitle("Including reform type heterogeneity") ///
    note("Prediction based on baseline spending, income, and reform type") ///
    graphregion(color(white))

graph export "reformed_event_study_quartiles.png", replace

*** ---------------------------------------------------------------------------
*** Section 16: REFORM DIAGNOSTIC - Reform Type Distribution Analysis
*** ---------------------------------------------------------------------------

use pred_spend_ppe_all_jk, clear

*--- Create table of reform types by predicted spending groups
preserve
keep if ever_treated == 1
collapse (mean) reform_eq reform_mfp reform_ep reform_le reform_sl pred_spend, ///
    by(pred_q)
    
list pred_q reform_* pred_spend, sep(0)
export delimited using "reform_type_by_quartile.csv", replace
restore

*--- Statistical tests for reform type differences
foreach r in reform_eq reform_mfp reform_ep reform_le reform_sl {
    di _n "Testing `r' across high/low groups:"
    ttest `r' if ever_treated == 1, by(high_treated)
}


*** ---------------------------------------------------------------------------
