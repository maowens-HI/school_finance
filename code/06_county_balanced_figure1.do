/*==============================================================================
Project    : School Spending – County-Level Balanced Panel Figure 1 Regression
File       : 06_county_balanced_figure1.do
Purpose    : Construct balanced county panel and run weighted event-study regressions
             replicating Jackson, Johnson, Persico (2016) Figure 1
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-20
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES:
  • Loads county-year panel with interpolated spending (output from 05_create_county_panel.do)
  • Creates 13-year strict rolling mean of log per-pupil expenditure
  • Generates baseline spending quartiles (1966, 1969, 1970, 1971)
  • Constructs balanced panel based on event-time (-5 to +17) completeness
  • Runs weighted event-study regressions by baseline spending quartile
  • Produces Figure 1 style event-study plots

WHY THIS MATTERS:
  This is the main replication of Jackson et al (2016) Figure 1 using a
  balanced panel restriction. The balanced panel ensures all treated counties
  have complete data coverage from 5 years pre-reform to 17 years post-reform,
  which strengthens the parallel trends assumption and comparability across units.

INPUTS:
  - county_clean.dta          (from 04_tag_county_quality.do)
  - county_exp_final.dta      (from 05_create_county_panel.do)
  - tabula-tabled2.xlsx       (reform data from JJP 2016)

OUTPUTS:
  - jjp_interp.dta            (Full county panel with all variables)
  - jjp_balance.dta           (Balanced panel only)
  - Event-study graphs by quartile and specification

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

* Keep only obs with full 13-year window (before 1979 cutoff)
replace exp_ma_strict = . if n_obs < 13 & year4 < 1979
gen lexp_ma_strict = log(exp_ma_strict)

*** ---------------------------------------------------------------------------
*** Section 3: Create Relative Year Indicators
*** ---------------------------------------------------------------------------

gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

* Convert string county_id → numeric for panel operations
encode county_id, gen(county_num)

drop if missing(exp)
save interp_temp, replace

*** ---------------------------------------------------------------------------
*** Section 4: Create Baseline Spending Quartiles
*** ---------------------------------------------------------------------------

local years 1966 1969 1970 1971
preserve
foreach y of local years {
    use interp_temp, clear
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

*--- Merge quartiles back to main data
foreach y of local years {
    merge m:1 state_fips county_id using `q`y'', nogen
}

*--- Create average baseline spending across multiple years
local number 66 69 70 71
foreach n of local number {
    gen base_`n' = .
    replace base_`n' = exp if year_unified == 19`n'
    bys county_id: egen base_`n'_max = max(base_`n')
    drop base_`n'
    rename base_`n'_max base_`n'
}

*--- Create quartiles based on multi-year averages
egen base_exp = rowmean(base_66 base_69 base_70 base_71)
bys state_fips: egen pre_q_66_71 = xtile(base_exp), n(4)

egen base_exp2 = rowmean(base_66 base_69 base_70)
bys state_fips: egen pre_q_66_70 = xtile(base_exp2), n(4)

egen base_exp3 = rowmean(base_69 base_70 base_71)
bys state_fips: egen pre_q_69_71 = xtile(base_exp3), n(4)

*** ---------------------------------------------------------------------------
*** Section 5: Create Lead and Lag Indicators
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
*** Section 6: Rename Good County Indicators
*** ---------------------------------------------------------------------------

rename good_county_1967 good_66
rename good_county_1970 good_69
rename good_county_1971 good_70
rename good_county_1972 good_71
rename good_county_6771 good_66_70
rename good_county good_66_71
rename good_county_7072 good_69_71

save jjp_interp, replace

*** ---------------------------------------------------------------------------
*** Section 7: Create Balanced Panel (Event-Time Restriction)
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
bys county_id: gen n_nonmiss = sum(!missing(lexp))
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

*--- Keep balanced counties and never-treated controls
keep if balance == 1 | never_treated2 == 1

*** ---------------------------------------------------------------------------
*** Section 8: Recalculate Baseline Quartiles on Balanced Sample
*** ---------------------------------------------------------------------------

drop pre_q* base_*

local years 1966 1969 1970 1971
preserve
foreach y of local years {
    use interp_temp, clear
    keep if year_unified == `y'
    keep if !missing(exp, state_fips, county_id)

    count
    if r(N)==0 {
        di as error "No observations for year `y' — skipping."
        continue
    }

    bysort state_fips: egen pre_q`y' = xtile(exp), n(4)
    keep state_fips county_id pre_q`y'

    tempfile q`y'
    save `q`y'', replace
}
restore

foreach y of local years {
    merge m:1 state_fips county_id using `q`y'', nogen
}

*--- Recreate multi-year baseline averages
local number 66 69 70 71
foreach n of local number {
    gen base_`n' = .
    replace base_`n' = exp if year_unified == 19`n'
    bys county_id: egen base_`n'_max = max(base_`n')
    drop base_`n'
    rename base_`n'_max base_`n'
}

egen base_exp = rowmean(base_66 base_69 base_70 base_71)
bys state_fips: egen pre_q_66_71 = xtile(base_exp), n(4)

egen base_exp2 = rowmean(base_66 base_69 base_70)
bys state_fips: egen pre_q_66_70 = xtile(base_exp2), n(4)

egen base_exp3 = rowmean(base_69 base_70 base_71)
bys state_fips: egen pre_q_69_71 = xtile(base_exp3), n(4)

drop _merge
save jjp_balance, replace

*** ---------------------------------------------------------------------------
*** Section 9: Event-Study Regressions by Quartile
*** ---------------------------------------------------------------------------

local var lexp lexp_ma lexp_ma_strict
local years   pre_q1966  pre_q1969 pre_q1970  pre_q1971 pre_q_66_70 pre_q_66_71 pre_q_69_71
local good good_66 good_69 good_70 good_71 good_66_70 good_66_71 good_69_71
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
                i.year_unified [w=school_age_pop] ///
                if `y'==`q' & (never_treated==1 | reform_year<2000), ///
                absorb(county_id) vce(cluster county_id)

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
                ytitle("Δ ln(per-pupil spending)", size(medsmall) margin(medium)) ///
                title("County Level: `v' | Quartile `q' | `y'", size(medlarge) color("35 45 60")) ///
                graphregion(color(white)) ///
                legend(off) ///
                scheme(s2mono)

            graph export "$SchoolSpending/output/county_reg_`v'_`q'_`y'.png", replace
        }
    }
}

*** ---------------------------------------------------------------------------
*** Section 10: Event-Study Regressions - Bottom 3 Quartiles (Exclude Top)
*** ---------------------------------------------------------------------------

local var lexp lexp_ma lexp_ma_strict
local years   pre_q1966  pre_q1969 pre_q1970  pre_q1971 pre_q_66_70 pre_q_66_71 pre_q_69_71
local good good_66 good_69 good_70 good_71 good_66_70 good_66_71 good_69_71
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
            i.year_unified [w=school_age_pop] ///
            if `y' < 4 & (never_treated==1 | reform_year<2000), ///
            absorb(county_id) vce(cluster county_id)

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
            ytitle("Δ ln(per-pupil spending)", size(medsmall) margin(medium)) ///
            title("County Level: `v' | Quartiles 1-3 | `y'", size(medlarge) color("35 45 60")) ///
            graphregion(color(white)) ///
            legend(off) ///
            scheme(s2mono)

        graph export "$SchoolSpanning/output/county_btm_`v'_`y'.png", replace
    }
}

di as result "County-level balanced panel Figure 1 regressions complete!"
