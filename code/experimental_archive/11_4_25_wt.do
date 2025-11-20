**************************************************************************
*   PREP: INTERPOLATED COUNTY PANEL + BASELINE QUARTILES + STRICT ROLLING
*   Author: Myles Owens
*   Purpose: Build clean county-year panel with interpolated exp vars,
*            baseline quartiles, and rolling mean (13-year strict)
**************************************************************************/

*--- 0. Setup -----------------------------------------------------------------
clear all
set more off
cd "$SchoolSpending\data"
use clean_cty, clear
drop year4
merge 1:m county using county_exp_final
drop _merge
replace good_county = 0 if missing(good_county)
drop if missing(county_exp)
rename county county_id
gen never_treated = treatment == 0
bysort county_id: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4-1
*keep if good_county ==1
winsor2 county_exp, replace c(1 99) by(year_unified)
*take the 99% value and any obs that are above the 99% replace with 99%

*keep if good_county == 1
/**************************************************************************
*   STRICT 13-YEAR ROLLING MEAN
**************************************************************************/
***log versions
*log current
rename county_exp exp

gen lexp = log(exp)

**log moving average
rangestat (mean) exp, interval(year_unified -12 -0) by(county_id)
rename exp_mean exp_ma
gen lexp_ma = log(exp_ma)

**log moving average STRICT
rangestat (mean) exp_ma_strict = exp (count) n_obs = exp, ///
    interval(year_unified -12 0) by(county_id)

* keep only obs with full 13-year window
replace exp_ma_strict = . if n_obs < 13
gen lexp_ma_strict = log(exp_ma_strict)

*--- 3. Relative year ---------------------------------------------------------

gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

* Convert string county_id → numeric
encode county_id, gen(county_num)

drop if missing(exp)
save interp_temp, replace



/**************************************************************************
*   BASELINE QUARTILES (1969–1971) + AVERAGE BASELINE
**************************************************************************/



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
* Merge quartiles back
foreach y of local years {
    merge m:1 state_fips county_id using `q`y'', nogen
}

* Average baseline 1969–1971
local number 66 69 70 71
foreach n of local number {
    gen base_`n' = .
    replace base_`n' = exp if year_unified == 19`n'
    bys county_id: egen base_`n'_max = max(base_`n')
    drop base_`n'
    rename base_`n'_max base_`n'
}
egen base_exp = rowmean( base_66 base_69 base_70 base_71) 
bys state_fips: egen pre_q_66_71 = xtile(base_exp), n(4)

egen base_exp2 = rowmean( base_66 base_69 base_70) 
bys state_fips: egen pre_q_66_70 = xtile(base_exp2), n(4)

egen base_exp3 = rowmean( base_69 base_70 base_71) 
bys state_fips: egen pre_q_69_71 = xtile(base_exp3), n(4)


**log using "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_4_25_wt\q_sum.*log", replace
local year 1966 1969 1970 1971
foreach y of local year{
	forvalues q = 1/4{
		di "`q' `y'"
	summ exp if pre_q`y' == `q'
}
}
**log close
/**************************************************************************
*   LEADS AND LAGS
**************************************************************************/

forvalues k = 1/17 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}
forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}

replace lag_17 = 1 if relative_year >= 17 & !missing(relative_year)
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)



drop if county_id == "06037"
/**************************************************************************
*   SAVE CLEAN INTERPOLATED DATASET
**************************************************************************/
save jjp_interp, replace


use jjp_interp, clear

rename good_county good_county_6671
keep county_id good_county_6671 school_age_pop

* Weighted tabulation of "good" vs "bad" counties
tab good_county_6671 [aw=school_age_pop]
duplicates drop county_id, force 
tab good_county_6671


summ school_age_pop
hist school_age_pop, bin(80) frequency

collapse (mean) exp, by(year4)
twoway line exp year4





/*********************************
* Simple event study of spending
**********************************/

local var lexp lexp_ma lexp_ma_strict

foreach v of local var {
	
 *log using "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\10_17_*log\base_`v'.*log", replace
    use jjp_interp, clear

    areg `v' ///
        i.lag_* i.lead_* ///
        i.year_unified [w = school_age_pop] if (never_treated==1 | (reform_year<2000)), ///
        absorb(county_id) vce(cluster county_id)

    *log close

    tempfile results
    postfile handle str15 term float relative_year b se using `results'

    forvalues k = 5(-1)1 {
        lincom 1.lead_`k'
        if !_rc {
            post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
        }
    }

    post handle ("base0") (0) (0) (0)

    forvalues k = 1/17 {
        lincom 1.lag_`k'
        if !_rc {
            post handle ("lag`k'") (`k') (r(estimate)) (r(se))
        }
    }

    postclose handle

    use `results', clear
    sort relative_year
    gen ci_lo = b - 1.645*se
    gen ci_hi = b + 1.645*se

    twoway ///
        (rarea ci_lo ci_hi relative_year, color("59 91 132%20") cmissing(n)) ///
        (line b relative_year, lcolor("42 66 94") lwidth(medthick)), ///
        yline(0, lpattern(dash) lcolor(gs10)) ///
        xline(0, lpattern(dash) lcolor(gs10)) ///
        ytitle("Δ ln(13-yr rolling avg PPE)") ///
        title("Event: `v' Simple", color("35 45 60")) ///
        legend(off) ///
        graphregion(color(white)) ///
        scheme(s2mono)

    graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_4_25_wt\event_`v'_simple.png", replace
}


/*********************************
* Split by quartiles of baseline spending
**********************************/
local var lexp lexp_ma lexp_ma_strict
local years  pre_q1971 pre_q1966 pre_q1969 pre_q1970 pre_q_66_70 pre_q_66_71 pre_q_69_71

foreach y of local years {
    foreach v of local var {
        forvalues q = 1/4 {

*log using "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\10_17_*log\reg_`v'_`q'_`y'.*log", replace
            use jjp_interp, clear

            areg `v' ///
                i.lag_* i.lead_* ///
                i.year_unified [w = school_age_pop] if `y'==`q' & (never_treated==1 | reform_year<2000), ///
                absorb(county_id) vce(cluster county_id)
            *log close

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
                title("Event Study: `v' | Quartile `q' | `y'", size(medlarge) color("35 45 60")) ///
                graphregion(color(white)) ///
                legend(off) ///
                scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_4_25_wt\reg_`v'_`q'_`y'.png", replace
        }
    }
}


*--------------------------------------*
* Regression: exclude top quartile (q == 4)
*--------------------------------------*
local var lexp lexp_ma lexp_ma_strict
local years  pre_q1971 pre_q1966 pre_q1969 pre_q1970 pre_q_66_70 pre_q_66_71 pre_q_69_71

foreach y of local years {
foreach v of local var{
	use jjp_interp, clear
areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified [w = school_age_pop] if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

*--------------------------------------*
* Extract coefficients
*--------------------------------------*
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

*--------------------------------------*
* Plot event study
*--------------------------------------*
use `results', clear
keep if inrange(rel_year, -20, 20)
sort rel_year

gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se


            twoway ///
                (rarea ci_lo ci_hi rel_year, color("59 91 132%20") cmissing(n)) ///
                (line b rel_year, lcolor("42 66 94") lwidth(medium)), ///
                yline(0, lpattern(dash) lcolor(gs10)) ///
                xline(0, lpattern(dash) lcolor(gs10)) ///
                ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
                title("Event Study: `v' | Quartile 1-3 | `y'", size(medlarge) color("35 45 60")) ///
                graphregion(color(white)) ///
                legend(off) ///
                scheme(s2mono)
				
graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_4_25_wt\btm_`v'_`y'.png", replace
	
}
}