/*==============================================================================
Project    : School Spending – County-Level Panel Using 1971 Enrollment Weights
File       : 06_C_county_enrollment_1971.do
Purpose    : Build county-year panel directly from district panel (f33_indfin_grf_canon),
             collapse using 1971 enrollment as fixed weights, adjust for inflation,
             and run Figure 1 event-study regressions.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-12-06
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES:
  • Loads district-year panel (f33_indfin_grf_canon.dta)
  • Creates year_unified variable (year4 - 1, school year convention)
  • Extracts 1971 enrollment by district as fixed weights
  • Adjusts district spending for inflation (to 2000 dollars)
  • Collapses district spending to county level using 1971 enrollment weights
  • Merges reform treatment data from Jackson et al (2016)
  • Creates balanced panel with complete event windows (-5 to +17)
  • Runs weighted event-study regressions by baseline spending quartile

WHY 1971 ENROLLMENT WEIGHTS:
  Using a fixed weight (1971 enrollment) avoids endogenous weighting issues
  where spending reforms could affect future enrollment patterns. The 1971
  baseline predates all court-ordered school finance reforms in the sample.

INPUTS:
  - f33_indfin_grf_canon.dta     (from 01_build_district_panel.do)
  - fiscal_year.csv              (state fiscal year definitions)
  - tabula-tabled2.xlsx          (reform data from JJP 2016)
  - state_fips_master.csv        (state FIPS crosswalk)

OUTPUTS:
  - county_1971enroll.dta        (county-year panel with 1971 enrollment weights)
  - county_1971enroll_balance.dta (balanced panel subset)
  - Event-study graphs by quartile

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Load District Panel and Create Year Variables
*** ---------------------------------------------------------------------------

use f33_indfin_grf_canon, clear

*--- Create year_unified (school year = fiscal year end - 1)
gen year_unified = year4 - 1
label var year_unified "School year (calendar year when school year began)"

*--- Generate county from county_id (ensure 5-digit format)
capture confirm string variable county_id
if _rc {
    tostring county_id, gen(county) format(%05.0f)
}
else {
    gen county = county_id
    replace county = substr("00000" + county, -5, 5)
}

*--- Extract state FIPS from county
gen state_fips = substr(county, 1, 2)

*** ---------------------------------------------------------------------------
*** Section 2: Extract 1971 Enrollment as Fixed Weights
*** ---------------------------------------------------------------------------

*--- Get 1971 enrollment by district
preserve
    keep if year_unified == 1971
    keep LEAID enrollment
    rename enrollment enrollment_1971

    *--- Handle missing enrollment
    drop if missing(enrollment_1971)
    drop if enrollment_1971 <= 0

    *--- One row per district
    duplicates drop LEAID, force

    tempfile enroll_1971
    save `enroll_1971', replace
restore

*--- Merge 1971 enrollment back to full panel
merge m:1 LEAID using `enroll_1971', keep(master match) nogen

*--- Flag districts with valid 1971 enrollment
gen has_1971_enroll = !missing(enrollment_1971)
label var has_1971_enroll "District has non-missing 1971 enrollment"

*** ---------------------------------------------------------------------------
*** Section 3: Inflation Adjustment (State Fiscal Year CPI)
*** ---------------------------------------------------------------------------

*--- Register FRED API key
set fredkey 87d3478358d0f3e781d2657d1aefd1ff, permanently

*--- Import monthly CPI-U (NSA), 1964-2019
tempfile cpi_monthly fy_tbl cpi_fy deflators
import fred CPIAUCNS, daterange(1964-01-01 2019-12-31) clear
gen m = mofd(daten)
format m %tm
rename CPIAUCNS cpi_u_all_nsa
keep m cpi_u_all_nsa
save `cpi_monthly'

*--- Load fiscal year lookup
import delimited "$SchoolSpending/data/fiscal_year.csv", varnames(1) clear
tostring state_fips, replace format("%02.0f")
keep state_fips fy_start_month
duplicates drop
save `fy_tbl', replace

*--- Cross product CPI months with states
use `cpi_monthly', clear
cross using `fy_tbl'

gen cal_y = year(dofm(m))
gen cal_m = month(dofm(m))
gen fy_end_year = cal_y + (cal_m >= fy_start_month)

keep if inrange(fy_end_year, 1967, 2019)

*--- Collapse to state-FY averages
collapse (mean) cpi_u_all_nsa (count) nmonths = cpi_u_all_nsa, by(state_fips fy_end_year)
assert nmonths == 12
rename fy_end_year year4
rename cpi_u_all_nsa cpi_fy_avg
label var cpi_fy_avg "CPI-U (NSA) averaged over state fiscal year"
save `cpi_fy', replace

*--- Build 2000-dollar inflation factors
bys state_fips: egen base2000 = max(cond(year4 == 2000, cpi_fy_avg, .))
gen deflator_2000 = cpi_fy_avg / base2000
gen inflator_2000 = base2000 / cpi_fy_avg

order state_fips year4 cpi_fy_avg deflator_2000 inflator_2000
save `deflators', replace

*--- Reload district panel and merge deflators
use f33_indfin_grf_canon, clear

*--- Recreate necessary variables
gen year_unified = year4 - 1
capture confirm string variable county_id
if _rc {
    tostring county_id, gen(county) format(%05.0f)
}
else {
    gen county = county_id
    replace county = substr("00000" + county, -5, 5)
}
gen state_fips = substr(county, 1, 2)

*--- Merge 1971 enrollment
merge m:1 LEAID using `enroll_1971', keep(master match) nogen
gen has_1971_enroll = !missing(enrollment_1971)

*--- Merge CPI deflators
merge m:1 state_fips year4 using `deflators', keep(master match) nogen

*--- Deflate per-pupil spending to 2000 dollars
gen pp_exp_real = pp_exp * inflator_2000
label var pp_exp_real "Per-pupil expenditure in 2000 dollars (state FY CPI-U avg)"

*** ---------------------------------------------------------------------------
*** Section 4: Collapse to County Level Using 1971 Enrollment Weights
*** ---------------------------------------------------------------------------

*--- Keep only districts with valid 1971 enrollment
drop if missing(enrollment_1971)
drop if enrollment_1971 <= 0

*--- Winsorize spending at 1st and 99th percentiles before collapse
winsor2 pp_exp_real, replace c(1 99) by(year_unified)

*--- Collapse to county level using 1971 enrollment as weights
preserve
    *--- Get county-level weighted mean spending
    collapse (mean) county_exp = pp_exp_real [w = enrollment_1971], by(county year4 year_unified state_fips)
    tempfile county_exp
    save `county_exp', replace
restore

*--- Get total 1971 enrollment by county (for later weighting in regressions)
preserve
    keep if year_unified == 1971
    collapse (sum) county_enroll_1971 = enrollment_1971, by(county)
    tempfile county_enroll
    save `county_enroll', replace
restore

*--- Merge enrollment totals back
use `county_exp', clear
merge m:1 county using `county_enroll', keep(master match) nogen

label var county_exp "Enrollment-weighted avg per-pupil expenditure (2000$)"
label var county_enroll_1971 "Total county enrollment in 1971 (weight for regressions)"

*** ---------------------------------------------------------------------------
*** Section 5: Merge Reform Treatment Data (Jackson et al 2016)
*** ---------------------------------------------------------------------------

*--- Save county panel temporarily
tempfile county_panel
save `county_panel', replace

*--- Load JJP reform mapping
import excel using "$SchoolSpending/data/tabula-tabled2.xlsx", firstrow clear

rename CaseNameLegislationwithout case_name
rename Constitutionalityoffinancesys const
rename TypeofReform reform_type
rename FundingFormulaafterReform form_post
rename FundingFormulabeforeReform form_pre
rename Year reform_year
rename State state_name

*--- Forward fill state_name for multi-row states
local N = _N
forvalues i = 2/`N' {
    if missing(state_name[`i']) {
        replace state_name = state_name[`i'-1] in `i'
    }
    else {
        replace state_name = state_name[`i'] in `i'
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
sort state_name reform_year
bysort state_name: keep if _n == 1

*--- Create reform type indicators
gen reform_equity = regexm(reform_type, "Equity")
gen reform_adequacy = regexm(reform_type, "Adequacy")
gen treatment = 1

keep state_name reform_year treatment reform_equity reform_adequacy

tempfile reforms
save `reforms', replace

*--- Load state FIPS crosswalk
import delimited using "$SchoolSpending/data/state_fips_master.csv", clear
replace state_name = itrim(lower(strtrim(state_name)))

merge 1:m state_name using `reforms'
drop if _merge == 2  // States not in FIPS file
drop _merge
tostring fips, gen(state_fips) format(%02.0f)
keep state_fips reform_year treatment reform_equity reform_adequacy

*--- Merge reforms to county panel
merge 1:m state_fips using `county_panel'
replace treatment = 0 if missing(treatment)
keep if _merge == 3
drop _merge

*** ---------------------------------------------------------------------------
*** Section 6: Create Log Spending and Rolling Means
*** ---------------------------------------------------------------------------

*--- Log per-pupil expenditure
gen lexp = log(county_exp)
label var lexp "Log per-pupil expenditure (2000$)"

*--- Convert county to numeric for panel operations
encode county, gen(county_num)

*--- 13-year rolling mean
rangestat (mean) county_exp, interval(year_unified -12 0) by(county_num)
rename county_exp_mean exp_ma
gen lexp_ma = log(exp_ma)
label var lexp_ma "Log 13-year rolling mean spending"

*--- Strict 13-year rolling mean (only if full 13-year window available)
rangestat (mean) exp_ma_strict = county_exp (count) n_obs = county_exp, ///
    interval(year_unified -12 0) by(county_num)
replace exp_ma_strict = . if n_obs < 13
gen lexp_ma_strict = log(exp_ma_strict)
label var lexp_ma_strict "Log 13-year strict rolling mean spending"

*** ---------------------------------------------------------------------------
*** Section 7: Create Relative Year and Event-Time Indicators
*** ---------------------------------------------------------------------------

*--- Relative year to reform
gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

*--- Treatment indicators
gen never_treated = treatment == 0
bysort county_num: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0

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
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)  // Bin -5 and earlier

*** ---------------------------------------------------------------------------
*** Section 8: Create Baseline Spending Quartiles (1971)
*** ---------------------------------------------------------------------------

preserve
    keep if year_unified == 1971
    keep if !missing(county_exp, state_fips, county)

    *--- Within-state quartiles (stable sort for reproducibility)
    sort state_fips county
    bysort state_fips: egen pre_q1971 = xtile(county_exp), n(4)
    keep state_fips county pre_q1971

    tempfile q1971
    save `q1971', replace
restore

*--- Merge quartiles back to main data
merge m:1 state_fips county using `q1971', nogen

*** ---------------------------------------------------------------------------
*** Section 9: Save Full Panel
*** ---------------------------------------------------------------------------

order county state_fips year4 year_unified county_exp lexp lexp_ma lexp_ma_strict ///
      county_enroll_1971 reform_year relative_year treatment never_treated pre_q1971

save county_1971enroll, replace

*** ---------------------------------------------------------------------------
*** Section 10: Create Balanced Panel (Event-Time Restriction)
*** ---------------------------------------------------------------------------

*--- Identify counties with complete event windows (-5 to +17)
preserve
    keep if inrange(relative_year, -5, 17)

    *--- Find counties with complete windows
    bys county_num: egen min_rel = min(relative_year)
    bys county_num: egen max_rel = max(relative_year)
    bys county_num: gen n_rel = _N

    *--- Keep only if they have the full window
    keep if min_rel == -5 & max_rel == 17 & n_rel == 23

    *--- Count nonmissing lexp in the window
    bys county_num: gen n_nonmiss = sum(!missing(lexp_ma_strict))
    bys county_num: replace n_nonmiss = n_nonmiss[_N]

    *--- Keep only counties with full window AND no missing spending
    keep if min_rel == -5 & max_rel == 17 & n_rel == 23 & n_nonmiss == 23

    keep county
    duplicates drop
    gen balance = 1

    tempfile balance
    save `balance'
restore

merge m:1 county using `balance'
replace balance = 0 if missing(balance)
drop _merge

*--- Create balanced-only dataset
keep if balance == 1 | never_treated2 == 1

save county_1971enroll_balance, replace

*** ---------------------------------------------------------------------------
*** Section 11: Event-Study Regressions by Quartile
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    forvalues q = 1/4 {
        use county_1971enroll_balance, clear

        *--- Weighted event-study regression using 1971 enrollment
        areg `v' ///
            i.lag_* i.lead_* ///
            i.year_unified [w = county_enroll_1971] ///
            if pre_q1971 == `q' & (reform_year < 2000 | never_treated == 1), ///
            absorb(county_num) vce(cluster county_num)

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
            ytitle("Change in log(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
            xtitle("Years relative to reform", size(medsmall)) ///
            title("Quartile `q' | 1971 Enrollment Weights", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)

        graph export "$SchoolSpending/output/06C_q`q'_1971enroll.png", replace
    }
}

*** ---------------------------------------------------------------------------
*** Section 12: Event-Study Regression - Bottom 3 Quartiles (Pooled)
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    use county_1971enroll_balance, clear

    *--- Weighted regression excluding top quartile
    areg `v' ///
        i.lag_* i.lead_* ///
        i.year_unified [w = county_enroll_1971] ///
        if pre_q1971 < 4 & (reform_year < 2000 | never_treated == 1), ///
        absorb(county_num) vce(cluster county_num)

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
        ytitle("Change in log(per-pupil spending)", size(medsmall) margin(medium)) ///
        xtitle("Years relative to reform", size(medsmall)) ///
        title("Bottom 3 Quartiles | 1971 Enrollment Weights", size(medlarge) color("35 45 60")) ///
        graphregion(color(white)) ///
        legend(off) ///
        scheme(s2mono)

    graph export "$SchoolSpending/output/06C_bottom3_1971enroll.png", replace
}

*** ---------------------------------------------------------------------------
*** Section 13: Summary Statistics
*** ---------------------------------------------------------------------------

use county_1971enroll_balance, clear

*--- Sample size by quartile
tab pre_q1971 if year_unified == 1971, m

*--- Summary of weights
summ county_enroll_1971, detail

*--- Coverage by treatment status
tab treatment balance if year_unified == 1971

di as result "========================================"
di as result "06_C_county_enrollment_1971.do complete"
di as result "========================================"
