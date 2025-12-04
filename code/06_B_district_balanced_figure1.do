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
tsfill,full  // Creates missing values to fill for the whole range

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


*==============================================================*
* I) Import monthly CPI data from FRED
*==============================================================*

*--------------------------------------------------------------*
* A) Download CPI-U series and prepare tempfiles
*--------------------------------------------------------------*

* 1)--------------------------------- Register FRED API key
set fredkey 87d3478358d0f3e781d2657d1aefd1ff, permanently

* 2)--------------------------------- Import monthly CPI-U (NSA), 1964-2019
tempfile cpi_monthly fy_tbl cpi_fy deflators
import fred CPIAUCNS, daterange(1964-01-01 2019-12-31) clear
gen m = mofd(daten)
format m %tm
rename CPIAUCNS cpi_u_all_nsa
keep m cpi_u_all_nsa
save `cpi_monthly'

*==============================================================*
* II) Build state-specific fiscal year CPI averages
*==============================================================*

*--------------------------------------------------------------*
* A) Load fiscal year lookup and cross with CPI months
*--------------------------------------------------------------*

* 1)--------------------------------- Load state fiscal year start months
import delimited "$SchoolSpending/data/fiscal_year.csv", ///
    varnames(1) clear

*** Make sure state_fips is str2
tostring state_fips, replace format("%02.0f")
keep state_fips fy_start_month
duplicates drop
save `fy_tbl', replace

* 2)--------------------------------- Cross product CPI months with states
use `cpi_monthly', clear
cross using `fy_tbl'

gen cal_y = year(dofm(m))
gen cal_m = month(dofm(m))
gen fy_end_year = cal_y + (cal_m >= fy_start_month)

keep if inrange(fy_end_year, 1967,2019)

*--------------------------------------------------------------*
* B) Collapse to fiscal-year averages and build deflators
*--------------------------------------------------------------*

* 1)--------------------------------- Collapse to state-FY averages
*This was messing stuff up
*collapse (mean) cpi_u_all_nsa (count) nmonths = m, by(state_fips fy_end_year)
collapse (mean) cpi_u_all_nsa (count) nmonths = cpi_u_all_nsa, by(state_fips fy_end_year)
assert nmonths == 12
rename fy_end_year year4
rename cpi_u_all_nsa cpi_fy_avg
label var cpi_fy_avg "CPI-U (NSA) averaged over state fiscal year"
save `cpi_fy', replace

* 2)--------------------------------- Build 2000-dollar inflation factors
bys state_fips: egen base2000 = max(cond(year4==2000, cpi_fy_avg, .))
gen deflator_2000 = cpi_fy_avg / base2000
gen inflator_2000 = base2000 / cpi_fy_avg

order state_fips year4 cpi_fy_avg deflator_2000 inflator_2000
save `deflators', replace

*==============================================================*
* III) Merge deflators to tract panel
*==============================================================*

*--------------------------------------------------------------*
* A) Load tract panel and merge CPI deflators
*--------------------------------------------------------------*

* 1)--------------------------------- Load tract panel
use no_grf_district_panel, clear


* 3)--------------------------------- Merge deflators
merge m:1 state_fips year4 using `deflators', keep(match master) nogen

* 4)--------------------------------- Deflate per-pupil spending to 2000 dollars
gen pp_exp_real = pp_exp * inflator_2000
label var pp_exp_real "Per-pupil expenditure in 2000 dollars (state FY CPI-U avg)"
*/

*--------------------------------------------------------------*
* B) Save inflation-adjusted tract panel
*--------------------------------------------------------------*


save no_grf_district_real, replace



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
merge 1:m state_fips using no_grf_district_real
replace treatment = 0 if missing(treatment)
keep if _merge == 3
drop _merge
drop long_name sumlev region division state division_name region_name

save no_grf_district_treat, replace

*** ---------------------------------------------------------------------------
*** Section 4: Create Variables and Rolling Means
*** ---------------------------------------------------------------------------

use no_grf_district_treat, clear

gen never_treated = treatment == 0
bysort LEAID: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4 - 1

*--- Winsorize spending
winsor2 pp_exp_real, replace c(1 99) by(year_unified)

rename pp_exp_real exp
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
*** Section 5: Create Baseline Spending Quartiles (1971 only)
*** ---------------------------------------------------------------------------

preserve
use interp_temp, clear
keep if year_unified == 1971
keep if !missing(exp, state_fips, LEAID)


*--- Within-state quartiles (stable sort for reproducibility)
sort state_fips LEAID
bysort state_fips: egen pre_q1971 = xtile(exp), n(4)
keep state_fips LEAID pre_q1971

tempfile q1971
save `q1971', replace
restore

*--- Merge quartiles back
merge m:1 state_fips LEAID using `q1971', nogen


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

rename good_govid_1971 good_71

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
*** Section 10: Recalculate Baseline Quartiles on Balanced Sample (1971 only)
*** ---------------------------------------------------------------------------

drop pre_q*
preserve
drop if good_71 != 1
keep if year_unified == 1971
keep if !missing(exp, state_fips, LEAID)

*--- Stable sort for reproducibility
sort state_fips LEAID
bysort state_fips: egen pre_q1971 = xtile(exp), n(4)
keep state_fips LEAID pre_q1971

tempfile q1971
save `q1971', replace
restore

merge m:1 state_fips LEAID using `q1971', nogen

drop _merge

save jjp_balance, replace

/**************************************************************************
*  Weight Investigation
**************************************************************************/

use jjp_balance, clear
* County-year table statistics
egen total_weight = total(enr_avg_all)
bys LEAID: egen LEAID_weight = sum(enr_avg_all)
gen weight_share = LEAID_weight / total_weight

* Share of county-year observations
egen total_obs = count(LEAID)
bys LEAID: egen LEAID_obs = count(LEAID)
gen obs_share = LEAID_obs / total_obs

* Create ranking dataset: one row per county
keep LEAID weight_share obs_share 
order LEAID obs_share weight_share
duplicates drop

* Rank by weight_share (stable sort for reproducibility)
gsort -weight_share LEAID
gen rank = _n
keep LEAID rank
tempfile rank
save `rank'

merge 1:m LEAID using jjp_balance
keep if _merge ==3
drop _merge
save jjp_rank,replace
*** ---------------------------------------------------------------------------
*** Section 11: Event-Study Regressions by Quartile
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    forvalues q = 1/4 {
        use jjp_balance, clear
        *drop if good_71 != 1

        count
        display "Remaining obs in this iteration: " r(N)

        *--- Weighted event-study regression
        areg `v' ///
            i.lag_* i.lead_* ///
            i.year_unified [w=enr_avg_all] ///
            if pre_q1971==`q' & (never_treated==1 | reform_year<2000), ///
            absorb(LEAID) vce(cluster LEAID)

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
            ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
            title("District Level: `v' | Quartile `q' | 1971", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)

        *graph export "$SchoolSpending/output/district_reg_`v'_`q'.png", replace
graph export "$SchoolSpending/output/district_reg_`v'_`q'.png", replace
    }
}

*** ---------------------------------------------------------------------------
*** Section 12: Event-Study Regressions - Bottom 3 Quartiles (Exclude Top)
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    use jjp_balance, clear
    *drop if good_71 != 1

    *--- Weighted regression excluding top quartile
    areg `v' ///
        i.lag_* i.lead_* ///
        i.year_unified [w=enr_avg_all] ///
        if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
        absorb(LEAID) vce(cluster LEAID)

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
        ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
        title("District Level: `v' | Quartiles 1-3 | 1971", size(medlarge) color("35 45 60")) ///
        graphregion(color(white)) ///
        legend(off) ///
        scheme(s2mono)

    *graph export "$SchoolSpending/output/district_btm_`v'.png", replace
graph export "$SchoolSpending/output/district_btm_`v'.png", replace
}


*** ---------------------------------------------------------------------------
*** Section 11: Event-Study Regressions by Quartile
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    forvalues q = 1/4 {
        use jjp_rank, clear
        drop if good_71 != 1
		drop if rank > 1000
        count
        display "Remaining obs in this iteration: " r(N)

        *--- Weighted event-study regression
        areg `v' ///
            i.lag_* i.lead_* ///
            i.year_unified [w=enr_avg_all] ///
            if pre_q1971==`q' & (never_treated==1 | reform_year<2000), ///
            absorb(LEAID) vce(cluster LEAID)

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
            ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
            title("District Level: `v' | Quartile `q' | 1971", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)

        *graph export "$SchoolSpending/output/district_reg_`v'_`q'.png", replace
graph export "$SchoolSpending/output/top100/district_reg_`v'_`q'.png", replace
    }
}

*** ---------------------------------------------------------------------------
*** Section 12: Event-Study Regressions - Bottom 3 Quartiles (Exclude Top)
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    use jjp_rank, clear
    drop if good_71 != 1
	drop if rank > 1000
    *--- Weighted regression excluding top quartile
    areg `v' ///
        i.lag_* i.lead_* ///
        i.year_unified [w=enr_avg_all] ///
        if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
        absorb(LEAID) vce(cluster LEAID)

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
        ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
        title("District Level: `v' | Quartiles 1-3 | 1971", size(medlarge) color("35 45 60")) ///
        graphregion(color(white)) ///
        legend(off) ///
        scheme(s2mono)

    *graph export "$SchoolSpending/output/district_btm_`v'.png", replace
graph export "$SchoolSpending/output/top100/district_btm_`v'.png", replace
}

*** ---------------------------------------------------------------------------
*** Section 11: Event-Study Regressions by Quartile
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    forvalues q = 1/4 {
        use jjp_rank, clear
        drop if good_71 != 1
		drop if rank <= 1000
        count
        display "Remaining obs in this iteration: " r(N)

        *--- Weighted event-study regression
        areg `v' ///
            i.lag_* i.lead_* ///
            i.year_unified [w=enr_avg_all] ///
            if pre_q1971==`q' & (never_treated==1 | reform_year<2000), ///
            absorb(LEAID) vce(cluster LEAID)

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
            ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
            title("District Level: `v' | Quartile `q' | 1971", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)

        *graph export "$SchoolSpending/output/district_reg_`v'_`q'.png", replace
graph export "$SchoolSpending/output/btm100/district_reg_`v'_`q'.png", replace
    }
}

*** ---------------------------------------------------------------------------
*** Section 12: Event-Study Regressions - Bottom 3 Quartiles (Exclude Top)
*** ---------------------------------------------------------------------------

local var lexp_ma_strict

foreach v of local var {
    use jjp_rank, clear
    drop if good_71 != 1
	drop if rank <= 1000
    *--- Weighted regression excluding top quartile
    areg `v' ///
        i.lag_* i.lead_* ///
        i.year_unified [w=enr_avg_all] ///
        if pre_q1971 < 4 & (never_treated==1 | reform_year<2000), ///
        absorb(LEAID) vce(cluster LEAID)

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
        ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
        title("District Level: `v' | Quartiles 1-3 | 1971", size(medlarge) color("35 45 60")) ///
        graphregion(color(white)) ///
        legend(off) ///
        scheme(s2mono)

    *graph export "$SchoolSpending/output/district_btm_`v'.png", replace
graph export "$SchoolSpending/output/btm100/district_btm_`v'.png", replace
}

