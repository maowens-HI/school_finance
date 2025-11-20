/*==============================================================================
Project    : School Spending – District-Level Balanced Panel Figure 1 Regression
File       : 07_district_balanced_figure1.do
Purpose    : Construct balanced district panel and run weighted event-study regressions
             replicating Jackson, Johnson, Persico (2016) Figure 1 at district level
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-20
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES:
  • Loads district-year panel with tagged quality flags
  • Interpolates missing district-level spending (gaps ≤ 3 years)
  • Merges JJP reform treatment data
  • Creates 13-year strict rolling mean of log per-pupil expenditure
  • Generates baseline spending quartiles (1966, 1969, 1970, 1971)
  • Creates enrollment-based weights (average 1969-1971)
  • Constructs balanced panel based on event-time (-5 to +17) completeness
  • Runs weighted event-study regressions by baseline spending quartile
  • Produces Figure 1 style event-study plots at district level

WHY THIS MATTERS:
  This file provides a district-level analog to the county-level analysis in
  06_county_balanced_figure1.do. District-level analysis avoids aggregation
  and preserves within-county heterogeneity in treatment effects. This is
  particularly important for understanding how different types of school
  districts respond to finance reforms.

INPUTS:
  - district_panel_tagged.dta   (from 01_build_district_panel.do)
  - tabula-tabled2.xlsx         (reform data from JJP 2016)
  - state_fips_master.csv       (state FIPS codes)

OUTPUTS:
  - no_grf_district_panel.dta         (Interpolated district panel)
  - no_grf_district_panel_treat.dta   (With treatment indicators)
  - jjp_interp.dta                    (Full district panel with all variables)
  - jjp_balance.dta                   (Balanced panel only)
  - Event-study graphs by quartile and specification

==============================================================================*/

*** ---------------------------------------------------------------------------
*** Section 0: Setup
*** ---------------------------------------------------------------------------

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Load District Panel and Interpolate
*** ---------------------------------------------------------------------------

use district_panel_tagged, clear

*--- Clean
drop if missing(year4)  // Drop values with missing years
drop if missing(county_id)
gen state_fips = substr(LEAID, 1, 2)

*--- Convert string LEAID → numeric for panel operations
encode LEAID, gen(LEAID_num)

*--- Gap detector (for interpolation logic)
bysort LEAID (year4): gen gap_next = year[_n+1] - year4
gen too_far = gap_next > 3  // Don't impute gaps > 3 years

*--- Ensure full district-year panel
tsset LEAID_num year4
tsfill, full  // Creates missing values to fill for the whole range

*** ---------------------------------------------------------------------------
*** Section 2: Fill Identifiers and Interpolate Spending
*** ---------------------------------------------------------------------------

*--- Fill stable variables for the gaps we created
foreach var in GOVID LEAID good_govid_baseline state_fips {
    bys LEAID_num: egen __fill_`var' = mode(`var'), maxmode
    replace `var' = __fill_`var' if missing(`var')
    drop __fill_`var'
}

bys LEAID_num (year4): replace too_far = too_far[_n-1] if missing(too_far)

*--- Interpolate district expenditures and enrollment
bys LEAID_num: ipolate pp_exp year4 if too_far == 0, gen(exp2)
bys LEAID_num: ipolate enrollment year4 if too_far == 0, gen(enr2)

replace exp2 = pp_exp if !missing(pp_exp)
replace enr2 = enrollment if !missing(enrollment)

drop pp_exp gap_next too_far enrollment
rename exp2 pp_exp
rename enr2 enrollment

save no_grf_district_panel, replace

*** ---------------------------------------------------------------------------
*** Section 3: Merge JJP Reform Treatment Data
*** ---------------------------------------------------------------------------

*--- Load JJP reform mapping
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
bysort state_name: keep if _n == 1

*--- Parse funding formula types
gen mfp_pre = "MFP" if regexm(form_pre, "MFP")
gen ep_pre  = "EP"  if regexm(form_pre, "EP")
gen le_pre  = "LE"  if regexm(form_pre, "LE")
gen sl_pre  = "SL"  if regexm(form_pre, "SL")

gen mfp_post = "MFP" if regexm(form_post, "MFP")
gen ep_post  = "EP"  if regexm(form_post, "EP")
gen le_post  = "LE"  if regexm(form_post, "LE")
gen sl_post  = "SL"  if regexm(form_post, "SL")

*--- Create reform type indicators
gen reform = 0
replace reform = 1 if regexm(reform_type, "Equity")
drop reform_type
label define reform_lbl 0 "Adequacy" 1 "Equity"
label values reform reform_lbl
label variable reform "School finance reform type"
gen treatment = 1

*--- Generate formula change flags
gen mfp_flag = (mfp_post != "" & mfp_pre == "")
gen ep_flag  = (ep_post  != "" & ep_pre  == "")
gen le_flag  = (le_post  != "" & le_pre  == "")
gen sl_flag  = (sl_post  != "" & sl_pre  == "")

gen formula_new = .
replace formula_new = 1 if mfp_flag
replace formula_new = 2 if ep_flag
replace formula_new = 3 if le_flag
replace formula_new = 4 if sl_flag

label define formula_lbl 1 "MFP" 2 "EP" 3 "LE" 4 "SL"
label values formula_new formula_lbl

gen reform_mfp = mfp_flag == 1
gen reform_ep = ep_flag == 1
gen reform_le = le_flag == 1
gen reform_sl = sl_flag == 1
rename reform reform_eq

label variable reform_mfp "MFP Reform"
label variable reform_ep "EP Reform"
label variable reform_le "LE Reform"
label variable reform_sl "SL Reform"

tempfile temp
save `temp'

*--- Merge with state FIPS codes
import delimited using state_fips_master, clear
replace state_name = itrim(lower(strtrim(state_name)))

merge 1:m state_name using `temp'
drop _merge
tostring fips, gen(state_fips) format(%02.0f)
drop fips

*--- Merge with district panel
merge 1:m state_fips using no_grf_district_panel
replace treatment = 0 if missing(treatment)
keep if _merge == 3
drop _merge
drop long_name sumlev region division state division_name region_name

save "$SchoolSpending/data/no_grf_district_panel_treat", replace

*** ---------------------------------------------------------------------------
*** Section 4: Create Variables and Rolling Means
*** ---------------------------------------------------------------------------

use no_grf_district_panel_treat, clear

gen never_treated = treatment == 0
bysort LEAID: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4 - 1

*--- Winsorize spending
winsor2 pp_exp, replace c(1 99) by(year_unified)

rename pp_exp exp
gen lexp = log(exp)

*--- Simple 13-year rolling mean
rangestat (mean) exp, interval(year_unified -12 0) by(LEAID)
rename exp_mean exp_ma
gen lexp_ma = log(exp_ma)

*--- Strict 13-year rolling mean
rangestat (mean) exp_ma_strict = exp (count) n_obs = exp, ///
    interval(year_unified -12 0) by(LEAID)

replace exp_ma_strict = . if n_obs < 13
gen lexp_ma_strict = log(exp_ma_strict)

*--- Create relative year
gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

save interp_temp, replace

*** ---------------------------------------------------------------------------
*** Section 5: Create Baseline Spending Quartiles
*** ---------------------------------------------------------------------------

local years 1966 1969 1970 1971
preserve
foreach y of local years {
    use interp_temp, clear
    keep if year_unified == `y'
    keep if !missing(exp, state_fips, LEAID)

    count
    if r(N)==0 {
        di as error "No observations for year `y' — skipping."
        continue
    }

    *--- Within-state quartiles
    bysort state_fips: egen pre_q`y' = xtile(exp), n(4)
    keep state_fips LEAID pre_q`y'

    tempfile q`y'
    save `q`y'', replace
}
restore

*--- Merge quartiles back
foreach y of local years {
    merge m:1 state_fips LEAID using `q`y'', nogen
}


*** ---------------------------------------------------------------------------
*** Section 6: Create Enrollment Weights
*** ---------------------------------------------------------------------------

*--- Weight option 1: Average enrollment over all years
bys LEAID: egen enr_avg_all = mean(enrollment)

*--- Weight option 2: Average enrollment for 1969-1971 (preferred)
gen enr_temp = enrollment if inrange(year_unified, 1969, 1971)
bys LEAID: egen enr_avg_6971 = mean(enr_temp)
drop enr_temp

label variable enr_avg_all "Average enrollment over all years"
label variable enr_avg_6971 "Average enrollment 1969-1971"

*** ---------------------------------------------------------------------------
*** Section 7: Create Lead and Lag Indicators
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
replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year)
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)

*** ---------------------------------------------------------------------------
*** Section 8: Rename Good District Indicators
*** ---------------------------------------------------------------------------

rename good_govid_1967          good_66
rename good_govid_1970          good_69
rename good_govid_1971          good_70
rename good_govid_1972          good_71
rename good_govid_baseline_6771 good_66_70
rename good_govid_baseline      good_66_71
rename good_govid_baseline_7072 good_69_71

save jjp_interp, replace

*** ---------------------------------------------------------------------------
*** Section 9: Create Balanced Panel (Event-Time Restriction)
*** ---------------------------------------------------------------------------

preserve
keep if inrange(relative_year, -5, 17)  // Only check within the event window

*--- Find districts with complete windows
bys LEAID: egen min_rel = min(relative_year)
bys LEAID: egen max_rel = max(relative_year)
bys LEAID: gen n_rel = _N

*--- Keep only if they have the full window
keep if min_rel == -5 & max_rel == 17 & n_rel == 23

*--- Count nonmissing lexp_ma_strict in the window
bys LEAID: gen n_nonmiss = sum(!missing(lexp_ma_strict))
bys LEAID: replace n_nonmiss = n_nonmiss[_N]

*--- Keep only districts with full window AND no missing spending
keep if min_rel == -5 & max_rel == 17 & n_rel == 23 & n_nonmiss == 23

keep LEAID
duplicates drop
gen balance = 1
tempfile balance
save `balance'
restore

*--- Merge balance indicator back
merge m:1 LEAID using `balance'
replace balance = 0 if missing(balance)

*--- Keep balanced districts and never-treated controls
keep if balance == 1 | never_treated2 == 1

*** ---------------------------------------------------------------------------
*** Section 10: Recalculate Baseline Quartiles on Balanced Sample
*** ---------------------------------------------------------------------------

drop pre_q* base_*

local years 1966 1969 1970 1971
preserve
foreach y of local years {
    use interp_temp, clear
    keep if year_unified == `y'
    keep if !missing(exp, state_fips, LEAID)

    count
    if r(N)==0 {
        di as error "No observations for year `y' — skipping."
        continue
    }

    bysort state_fips: egen pre_q`y' = xtile(exp), n(4)
    keep state_fips LEAID pre_q`y'

    tempfile q`y'
    save `q`y'', replace
}
restore

foreach y of local years {
    merge m:1 state_fips LEAID using `q`y'', nogen
}

save jjp_balance, replace

*** ---------------------------------------------------------------------------
*** Section 11: Event-Study Regressions by Quartile
*** ---------------------------------------------------------------------------

local var lexp_ma_strict
local years   pre_q1971
local good good_71
local n: word count `years'

forvalues i = 1/`n' {
    local y : word `i' of `years'
    local g : word `i' of `good'

    foreach v of local var {
        forvalues q = 1/4 {
            use jjp_balance, clear
            drop if `g' != 1
            count
            display "Remaining obs in this iteration: " r(N)

            *--- Weighted event-study regression
            areg `v' ///
                i.lag_* i.lead_* ///
                i.year_unified [w=enr_avg_6971] ///
                if `y'==`q' & (never_treated==1 | reform_year<2000), ///
                absorb(LEAID) vce(cluster county_id)

            *--- Extract coefficients
            tempfile results
            postfile handle str15 term float rel_year b se using `results', replace

            forvalues k = 5(-1)1 {
                lincom 1.lead_`k'
                if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
            }

            post handle ("base0") (0) (0) (0)

            forvalues k = 1/17 {
                lincom 1.lag_`k'
                if !_rc post handle ("lag`k'") (`k') (r(estimate)) (r(se))
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
                ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
                title("District Level: `v' | Quartile `q' | `y' | `g'", size(medlarge) color("35 45 60")) ///
                graphregion(color(white)) ///
                legend(off) ///
                scheme(s2mono)

            graph export "$SchoolSpending/output/district_reg_`v'_`q'_`y'.png", replace
        }
    }
}

*** ---------------------------------------------------------------------------
*** Section 12: Event-Study Regressions - Bottom 3 Quartiles (Exclude Top)
*** ---------------------------------------------------------------------------

local var lexp_ma_strict
local years   pre_q1971
local good good_71
local n: word count `years'

forvalues i = 1/`n' {
    local y : word `i' of `years'
    local g : word `i' of `good'

    foreach v of local var {
        use jjp_balance, clear
        drop if `g' != 1

        *--- Weighted regression excluding top quartile
        areg `v' ///
            i.lag_* i.lead_* ///
            i.year_unified [w=enr_avg_6971] ///
            if `y' < 4 & (never_treated==1 | reform_year<2000), ///
            absorb(LEAID) vce(cluster county_id)

        *--- Extract coefficients
        tempfile results
        postfile handle str15 term float rel_year b se using `results', replace

        forvalues k = 5(-1)1 {
            lincom 1.lead_`k'
            if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
        }

        post handle ("base0") (0) (0) (0)

        forvalues k = 1/17 {
            lincom 1.lag_`k'
            if !_rc post handle ("lag`k'") (`k') (r(estimate)) (r(se))
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
            ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
            title("District Level: `v' | Quartiles 1-3 | `y' | `g'", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)

        graph export "$SchoolSpending/output/district_btm_`v'_`y'.png", replace
    }
}

di as result "District-level balanced panel Figure 1 regressions complete!"
