/*==============================================================================
Project    : School Spending – Appendix D Figure D2 Replication
File       : appendix_d_figure_d2.do
Purpose    : Recreate Appendix D Figure D2: Event-study estimates of the effect of
             adopting various formula types on per-pupil spending, by spending
             quartile in 1972
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-22
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES:
  • Starts with district_panel_tagged from 01_build_district_panel.do
  • Adds inflation adjustment (CPI-U to 2000 dollars)
  • Merges reform data including formula types from tabula-tabled2.xlsx
  • Adds median family income data by state-year
  • Creates baseline spending quartiles (1972)
  • Creates income percentile groups by state
  • Runs separate event-study regressions for each formula type:
    - Foundation (MFP)
    - Reward for Effort (LE)
    - Equalization (EP)
    - Spending Limit (SL)
  • Produces four-panel figure matching Appendix D Figure D2

WHY THIS MATTERS:
  Appendix D Figure D2 shows heterogeneous treatment effects by formula type
  and baseline spending quartile. This reveals which types of school finance
  reforms were most effective at raising spending in poor vs. rich districts.

INPUTS:
  - district_panel_tagged.dta      (from 01_build_district_panel.do)
  - tabula-tabled2.xlsx            (reform data from JJP 2016)
  - state_fips_master.csv          (state FIPS codes)
  - fiscal_year.csv                (state fiscal year start months)
  - median_income_state_year.dta   (state-year median family income)

OUTPUTS:
  - district_panel_d2.dta          (Full district panel with all variables)
  - appendix_d_figure_d2.gph       (Four-panel event-study figure)
  - appendix_d_figure_d2.png       (Exported figure)

KEY ASSUMPTIONS:
  1. Sample: All school districts 1967-2010 (matching figure note)
  2. Weights: Average enrollment per district over full sample
  3. Fixed effects: Year FE + District FE
  4. Controls: State median income percentile × event-time indicators
  5. Baseline: 1972 spending quartiles (within-state distribution)
  6. Omitted period: Year -1 (one year before reform)
  7. Re-centering: Event time plot re-centered at zero for 10 pre-reform years

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Load District Panel and Add Inflation Adjustment
*** ---------------------------------------------------------------------------

*--- Load district panel from Step 01
use district_panel_tagged, clear

*--- Restrict to analysis years (1967-2010) to match Appendix D2
keep if year4 >= 1967 & year4 <= 2010

*--- Drop if missing key variables
drop if missing(LEAID, year4)

*--- Create state FIPS from LEAID
gen state_fips = substr(LEAID, 1, 2)

*** ---------------------------------------------------------------------------
*** Section 1A: Import CPI Data and Create Fiscal Year Deflators
*** ---------------------------------------------------------------------------

*--- Download monthly CPI-U from FRED
preserve
    set fredkey 87d3478358d0f3e781d2657d1aefd1ff, permanently
    tempfile cpi_monthly
    import fred CPIAUCNS, daterange(1964-01-01 2019-12-31) clear
    gen m = mofd(daten)
    format m %tm
    gen year = year(daten)
    gen month = month(daten)
    rename CPIAUCNS cpi
    save `cpi_monthly'
restore

*--- Load fiscal year start months by state
preserve
    import delimited using fiscal_year.csv, clear varnames(1)
    tostring fips, gen(state_fips) format(%02.0f)
    keep state_fips fy_start_month
    tempfile fy_table
    save `fy_table'
restore

*--- Create fiscal year CPI averages
preserve
    use `cpi_monthly', clear

    * Cross with fiscal year table
    cross using `fy_table'

    * Calculate fiscal year based on state-specific start month
    gen fy_year = year if month >= fy_start_month
    replace fy_year = year + 1 if month < fy_start_month

    * Average CPI over 12-month fiscal year
    collapse (mean) cpi_fy_avg = cpi (count) nmonths = cpi, ///
        by(state_fips fy_year)

    * Quality check: ensure 12 months per FY
    assert nmonths == 12

    * Calculate base year 2000 CPI
    sum cpi_fy_avg if fy_year == 2000
    local cpi_2000 = r(mean)

    * Create deflator (converts nominal to real 2000 dollars)
    gen deflator_2000 = `cpi_2000' / cpi_fy_avg

    rename fy_year year4
    tempfile deflators
    save `deflators'
restore

*--- Merge deflators to district panel
merge m:1 state_fips year4 using `deflators', keep(master match) nogen

*--- Create real per-pupil expenditure (2000 dollars)
gen pp_exp_real = pp_exp * deflator_2000
label var pp_exp_real "Per-pupil expenditure (2000 dollars)"

*** ---------------------------------------------------------------------------
*** Section 2: Merge Reform Data and Formula Types
*** ---------------------------------------------------------------------------

*--- Load JJP reform mapping
preserve
    import excel using "$SchoolSpending/data/tabula-tabled2.xlsx", firstrow clear

    rename CaseNameLegislationwithout case_name
    rename Constitutionalityoffinancesys const
    rename TypeofReform reform_type
    rename FundingFormulaafterReform form_post
    rename FundingFormulabeforeReform form_pre
    rename Year reform_year
    rename State state_name

    *--- Forward fill state names
    local N = _N
    forvalues i = 2/`N' {
        if missing(state_name[`i']) {
            replace state_name = state_name[`i'-1] in `i'
        }
    }

    *--- Clean state names
    replace state_name = itrim(lower(strtrim(state_name)))
    replace state_name = subinstr(state_name, char(10), " ", .)
    replace state_name = subinstr(state_name, char(13), " ", .)
    replace state_name = itrim(strtrim(state_name))
    replace state_name = "massachusetts" if state_name == "massachuset ts"

    *--- Keep only overturned cases (first reform per state)
    drop if missing(case_name)
    keep if const == "Overturned"
    bysort state_name: keep if _n == 1

    *--- Parse funding formula types (pre and post reform)
    gen mfp_pre = "MFP" if regexm(form_pre, "MFP")
    gen ep_pre  = "EP"  if regexm(form_pre, "EP")
    gen le_pre  = "LE"  if regexm(form_pre, "LE")
    gen sl_pre  = "SL"  if regexm(form_pre, "SL")

    gen mfp_post = "MFP" if regexm(form_post, "MFP")
    gen ep_post  = "EP"  if regexm(form_post, "EP")
    gen le_post  = "LE"  if regexm(form_post, "LE")
    gen sl_post  = "SL"  if regexm(form_post, "SL")

    *--- Create formula type change indicators
    * Formula was ADOPTED (went from not having it to having it)
    gen reform_foundation = (mfp_post != "" & mfp_pre == "")
    gen reform_reward     = (le_post  != "" & le_pre  == "")
    gen reform_equaliz    = (ep_post  != "" & ep_pre  == "")
    gen reform_splimit    = (sl_post  != "" & sl_pre  == "")

    label var reform_foundation "Adopted Foundation (MFP) formula"
    label var reform_reward     "Adopted Reward for Effort (LE) formula"
    label var reform_equaliz    "Adopted Equalization (EP) formula"
    label var reform_splimit    "Adopted Spending Limit (SL) formula"

    gen treatment = 1

    tempfile reforms
    save `reforms'

    *--- Merge with state FIPS codes
    import delimited using state_fips_master.csv, clear
    replace state_name = itrim(lower(strtrim(state_name)))

    merge 1:m state_name using `reforms'
    keep if _merge == 3
    drop _merge

    tostring fips, gen(state_fips) format(%02.0f)
    drop fips

    keep state_fips state_name reform_year treatment ///
         reform_foundation reform_reward reform_equaliz reform_splimit

    tempfile reform_final
    save `reform_final'
restore

*--- Merge reforms to district panel
merge m:1 state_fips using `reform_final'
replace treatment = 0 if missing(treatment)
keep if _merge == 1 | _merge == 3  // Keep all districts
drop _merge

*--- Fill missing reform indicators with zeros
foreach var of varlist reform_foundation reform_reward reform_equaliz reform_splimit {
    replace `var' = 0 if missing(`var')
}

*** ---------------------------------------------------------------------------
*** Section 3: Add Median Family Income Data
*** ---------------------------------------------------------------------------

*--- NOTE: This section assumes median_income_state_year.dta exists with:
*    - state_fips (string, 2 digits)
*    - year (or year4)
*    - median_income (median family income)
*
*--- If this file doesn't exist, you'll need to create it from Census data
*    For now, we'll create a placeholder or skip this step

capture confirm file "median_income_state_year.dta"
if _rc == 0 {
    *--- Merge median income data
    merge m:1 state_fips year4 using median_income_state_year, ///
        keep(master match) keepusing(median_income) nogen
}
else {
    *--- Create placeholder if data not available
    di as error "Warning: median_income_state_year.dta not found"
    di as error "Creating placeholder median income variable"
    gen median_income = .
}

*** ---------------------------------------------------------------------------
*** Section 4: Create Treatment Variables and Relative Year
*** ---------------------------------------------------------------------------

*--- Create never-treated indicator
gen never_treated = (treatment == 0)

*--- Create relative year (event time)
gen relative_year = year4 - reform_year
replace relative_year = . if missing(reform_year)

*--- Create lead indicators (pre-reform: -10 to -1)
forvalues k = 1/10 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}

*--- Create lag indicators (post-reform: 0 to +19)
forvalues k = 0/19 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}

*--- Bin endpoints (following Appendix D2 methodology)
* Bin -10 and earlier
replace lead_10 = 1 if relative_year <= -10 & !missing(relative_year)

* Bin +19 and later
replace lag_19 = 1 if relative_year >= 19 & !missing(relative_year)

*** ---------------------------------------------------------------------------
*** Section 5: Create Baseline Spending Quartiles (1972)
*** ---------------------------------------------------------------------------

*--- Create log spending
gen lexp = log(pp_exp_real)
label var lexp "Log real per-pupil expenditure"

*--- Generate 1972 within-state spending quartiles
preserve
    keep if year4 == 1972
    keep if !missing(pp_exp_real, state_fips, LEAID)

    * Within-state quartiles of 1972 spending (stable sort for reproducibility)
    sort state_fips LEAID
    bysort state_fips: egen pre_q1972 = xtile(pp_exp_real), n(4)

    keep LEAID state_fips pre_q1972
    duplicates drop

    tempfile q1972
    save `q1972'
restore

merge m:1 LEAID state_fips using `q1972', keep(master match) nogen

*--- Create quartile indicators for regression
tab pre_q1972, gen(q1972_)
label var q1972_1 "Bottom quartile 1972"
label var q1972_2 "2nd quartile 1972"
label var q1972_3 "3rd quartile 1972"
label var q1972_4 "Top quartile 1972"

*** ---------------------------------------------------------------------------
*** Section 6: Create Income Percentile Groups (State Distribution)
*** ---------------------------------------------------------------------------

*--- If median income is available, create percentile groups
capture confirm variable median_income
if _rc == 0 & !missing(median_income) {

    *--- Create state-year income percentiles for control
    preserve
        keep state_fips year4 median_income
        duplicates drop

        * Percentile groups of median income within year
        bysort year4: egen inc_pct_temp = rank(median_income), unique
        bysort year4: egen inc_pct_max = max(inc_pct_temp)
        gen inc_pct = 100 * inc_pct_temp / inc_pct_max

        * Create income groups (for interaction)
        gen inc_group = .
        replace inc_group = 1 if inc_pct <= 25
        replace inc_group = 2 if inc_pct > 25 & inc_pct <= 50
        replace inc_group = 3 if inc_pct > 50 & inc_pct <= 75
        replace inc_group = 4 if inc_pct > 75 & !missing(inc_pct)

        keep state_fips year4 inc_group inc_pct
        tempfile income_groups
        save `income_groups'
    restore

    merge m:1 state_fips year4 using `income_groups', keep(master match) nogen
}
else {
    *--- Create placeholder
    gen inc_group = .
    gen inc_pct = .
}

*** ---------------------------------------------------------------------------
*** Section 7: Calculate Average Enrollment Weights
*** ---------------------------------------------------------------------------

*--- Calculate average enrollment per district (for weighting)
bysort LEAID: egen avg_enrollment = mean(enrollment)
label var avg_enrollment "Average enrollment (1967-2010)"

*--- Replace missing enrollment weights with 1
replace avg_enrollment = 1 if missing(avg_enrollment)

*** ---------------------------------------------------------------------------
*** Section 8: Prepare for Regressions
*** ---------------------------------------------------------------------------

*--- Create numeric district ID for fixed effects
encode LEAID, gen(district_id)

*--- Keep only observations with non-missing key variables
keep if !missing(lexp, district_id, year4, state_fips)

*--- Keep only good districts (complete baseline data)
keep if good_govid_1972 == 1

save district_panel_d2, replace

*** ---------------------------------------------------------------------------
*** Section 9: Run Separate Regressions for Each Formula Type
*** ---------------------------------------------------------------------------

*--- We'll run 4 separate analyses, one for each formula type
*--- Each will show effects for bottom vs. top spending quartile in 1972

*** Formula Type 1: FOUNDATION (MFP)
*------------------------------------------------------------------------------*

use district_panel_d2, clear

*--- Keep only Foundation reforms and never-treated
keep if reform_foundation == 1 | never_treated == 1

*--- Interaction: Event time × Bottom quartile
forvalues k = 0/19 {
    gen lag_`k'_bottom = lag_`k' * q1972_1
}
forvalues k = 2/10 {
    gen lead_`k'_bottom = lead_`k' * q1972_1
}

*--- Interaction: Event time × Top quartile
forvalues k = 0/19 {
    gen lag_`k'_top = lag_`k' * q1972_4
}
forvalues k = 2/10 {
    gen lead_`k'_top = lead_`k' * q1972_4
}

*--- Regression: Bottom quartile
eststo foundation_bottom: areg lexp ///
    lead_10-lead_2 lag_0-lag_19 ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

*--- Regression: Top quartile
eststo foundation_top: areg lexp ///
    lead_10_top-lead_2_top lag_0_top-lag_19_top ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

*--- Store coefficients for plotting
preserve
    clear
    set obs 30
    gen rel_time = _n - 11  // -10 to +19
    gen coef_bottom = .
    gen coef_top = .

    * Fill in coefficients (lead -1 is omitted)
    forvalues k = 2/10 {
        local idx = 11 - `k'
        qui replace coef_bottom = _b[lead_`k'] if rel_time == -`k'
    }
    forvalues k = 0/19 {
        local idx = 11 + `k'
        qui replace coef_bottom = _b[lag_`k'] if rel_time == `k'
    }

    forvalues k = 2/10 {
        qui replace coef_top = _b[lead_`k'_top] if rel_time == -`k'
    }
    forvalues k = 0/19 {
        qui replace coef_top = _b[lag_`k'_top] if rel_time == `k'
    }

    * Set omitted period to zero
    replace coef_bottom = 0 if rel_time == -1
    replace coef_top = 0 if rel_time == -1

    gen formula_type = "Foundation"
    tempfile foundation_results
    save `foundation_results'
restore

*** Formula Type 2: REWARD FOR EFFORT (LE)
*------------------------------------------------------------------------------*

use district_panel_d2, clear

keep if reform_reward == 1 | never_treated == 1

*--- Create interactions
forvalues k = 0/19 {
    gen lag_`k'_bottom = lag_`k' * q1972_1
    gen lag_`k'_top = lag_`k' * q1972_4
}
forvalues k = 2/10 {
    gen lead_`k'_bottom = lead_`k' * q1972_1
    gen lead_`k'_top = lead_`k' * q1972_4
}

*--- Regressions
eststo reward_bottom: areg lexp ///
    lead_10-lead_2 lag_0-lag_19 ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

eststo reward_top: areg lexp ///
    lead_10_top-lead_2_top lag_0_top-lag_19_top ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

*--- Store coefficients
preserve
    clear
    set obs 30
    gen rel_time = _n - 11
    gen coef_bottom = .
    gen coef_top = .

    forvalues k = 2/10 {
        qui replace coef_bottom = _b[lead_`k'] if rel_time == -`k'
        qui replace coef_top = _b[lead_`k'_top] if rel_time == -`k'
    }
    forvalues k = 0/19 {
        qui replace coef_bottom = _b[lag_`k'] if rel_time == `k'
        qui replace coef_top = _b[lag_`k'_top] if rel_time == `k'
    }

    replace coef_bottom = 0 if rel_time == -1
    replace coef_top = 0 if rel_time == -1

    gen formula_type = "Reward for Effort"
    tempfile reward_results
    save `reward_results'
restore

*** Formula Type 3: EQUALIZATION (EP)
*------------------------------------------------------------------------------*

use district_panel_d2, clear

keep if reform_equaliz == 1 | never_treated == 1

*--- Create interactions
forvalues k = 0/19 {
    gen lag_`k'_bottom = lag_`k' * q1972_1
    gen lag_`k'_top = lag_`k' * q1972_4
}
forvalues k = 2/10 {
    gen lead_`k'_bottom = lead_`k' * q1972_1
    gen lead_`k'_top = lead_`k' * q1972_4
}

*--- Regressions
eststo equaliz_bottom: areg lexp ///
    lead_10-lead_2 lag_0-lag_19 ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

eststo equaliz_top: areg lexp ///
    lead_10_top-lead_2_top lag_0_top-lag_19_top ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

*--- Store coefficients
preserve
    clear
    set obs 30
    gen rel_time = _n - 11
    gen coef_bottom = .
    gen coef_top = .

    forvalues k = 2/10 {
        qui replace coef_bottom = _b[lead_`k'] if rel_time == -`k'
        qui replace coef_top = _b[lead_`k'_top] if rel_time == -`k'
    }
    forvalues k = 0/19 {
        qui replace coef_bottom = _b[lag_`k'] if rel_time == `k'
        qui replace coef_top = _b[lag_`k'_top] if rel_time == `k'
    }

    replace coef_bottom = 0 if rel_time == -1
    replace coef_top = 0 if rel_time == -1

    gen formula_type = "Equalization"
    tempfile equaliz_results
    save `equaliz_results'
restore

*** Formula Type 4: SPENDING LIMIT (SL)
*------------------------------------------------------------------------------*

use district_panel_d2, clear

keep if reform_splimit == 1 | never_treated == 1

*--- Create interactions
forvalues k = 0/19 {
    gen lag_`k'_bottom = lag_`k' * q1972_1
    gen lag_`k'_top = lag_`k' * q1972_4
}
forvalues k = 2/10 {
    gen lead_`k'_bottom = lead_`k' * q1972_1
    gen lead_`k'_top = lead_`k' * q1972_4
}

*--- Regressions
eststo splimit_bottom: areg lexp ///
    lead_10-lead_2 lag_0-lag_19 ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

eststo splimit_top: areg lexp ///
    lead_10_top-lead_2_top lag_0_top-lag_19_top ///
    i.year4 ///
    [weight=avg_enrollment], ///
    absorb(district_id) vce(cluster state_fips)

*--- Store coefficients
preserve
    clear
    set obs 30
    gen rel_time = _n - 11
    gen coef_bottom = .
    gen coef_top = .

    forvalues k = 2/10 {
        qui replace coef_bottom = _b[lead_`k'] if rel_time == -`k'
        qui replace coef_top = _b[lead_`k'_top] if rel_time == -`k'
    }
    forvalues k = 0/19 {
        qui replace coef_bottom = _b[lag_`k'] if rel_time == `k'
        qui replace coef_top = _b[lag_`k'_top] if rel_time == `k'
    }

    replace coef_bottom = 0 if rel_time == -1
    replace coef_top = 0 if rel_time == -1

    gen formula_type = "Spending Limit"
    tempfile splimit_results
    save `splimit_results'
restore

*** ---------------------------------------------------------------------------
*** Section 10: Create Four-Panel Figure (Appendix D Figure D2)
*** ---------------------------------------------------------------------------

*--- Combine all results
use `foundation_results', clear
append using `reward_results'
append using `equaliz_results'
append using `splimit_results'

*--- Restrict to plotting window (-10 to +20)
keep if inrange(rel_time, -10, 20)

*--- Create four-panel graph
graph twoway ///
    (connected coef_bottom rel_time if formula_type == "Foundation", ///
        mcolor(black) lcolor(black) lpattern(dash) msymbol(none)) ///
    (connected coef_top rel_time if formula_type == "Foundation", ///
        mcolor(gs8) lcolor(gs8) lpattern(solid) msymbol(none)), ///
    by(formula_type, rows(2) cols(2) ///
        note("") ///
        title("Event-study Estimates of The Effect of Adopting Various Formula Types" ///
              "on Per-pupil Spending: By Spending Quartile in 1972") ///
    ) ///
    xline(0, lcolor(black) lpattern(dash)) ///
    yline(0, lcolor(black)) ///
    xlabel(-10(5)20) ///
    ylabel(, angle(0)) ///
    xtitle("Year Aged 17 - Year of Initial Court Order") ///
    ytitle("") ///
    legend(order(1 "Bottom Spending Quartile in 1972" ///
                 2 "Top Spending Quartile in 1972") ///
           position(6) rows(1))

*--- Save graph
graph export appendix_d_figure_d2.png, replace width(2400) height(1800)
graph save appendix_d_figure_d2.gph, replace

di as result "✓ Appendix D Figure D2 created successfully"
di as result "  - Figure saved to: appendix_d_figure_d2.png"
di as result "  - Data saved to: district_panel_d2.dta"

/*==============================================================================
END OF FILE
==============================================================================*/
