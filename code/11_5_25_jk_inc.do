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




*Median Family Income Quartiles
gen med_fam_inc = regexr(median_family_income, "[^0-9]", "")
destring med_fam_inc, replace
drop median_family_income

preserve
duplicates drop county_id, force
bysort state_fips: egen inc_q = xtile(med_fam_inc), n(4)
keep state_fips county_id inc_q
tempfile inc_q69
save `inc_q69'
restore

merge m:1 state_fips county_id using `inc_q69', nogen
tab inc_q, gen(inc_q_)
gen inc_btm_3 = .
replace inc_btm_3 = 1 if inlist(inc_q,1,2,3)
replace inc_btm_3 = 0 if inc_q==4


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


* Housekeeping
clear
set more off
cd "$SchoolSpending\data"


    use jjp_interp, clear

rename pre_q1971 pre_q

	tempfile reg_temp
	save `reg_temp'
/*	
use `reg_temp', clear

levelsof state_fips, local(states)
    foreach s of local states {
		preserve
drop if state_fips == "`s'"

areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
	i.lag_*##i.inc_q i.lead_*##i.inc_q ///
    i.year_unified##i.pre_q##i.inc_q ///
	 [w = school_age_pop] if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
	
		estimates save layer_mod_`s', replace
restore
	}
*/

levelsof state_fips, local(states)
foreach s of local states {
preserve
use `reg_temp', clear
estimates use layer_mod_`s'

	

**# Gen main -----------------------------
forvalues t = 2/7{
		gen main_`t' = .
	}

* Fill placeholders
forvalues t = 2/7{
		scalar coeff_main = _b[1.lag_`t']
		replace main_`t' = coeff_main
	}



**# Gen ppe ------------------------------
* Generate placeholders
forvalues t = 2/7{
	forvalues q = 2/4 {
		gen ppe_`t'_`q' = .
	}
}
* Fill placeholders
forvalues t = 2/7{
	forvalues q = 2/4 {
		scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
		replace ppe_`t'_`q' = coeff_ppe
	}
}


**# Gen inc ------------------------------
* Generate placeholders
forvalues t = 2/7{
	forvalues q = 2/4 {
		gen inc_`t'_`q' = .
	}
}
* Fill placeholders
forvalues t = 2/7{
	forvalues q = 2/4 {
		scalar coeff_inc = _b[1.lag_`t'#`q'.inc_q]
		replace inc_`t'_`q' = coeff_inc
	}
}


**# Gen averages ------------------------------

egen avg_main = rowmean(main_2 main_3 main_4 main_5 main_6 main_7)

forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q')
}


forvalues q = 2/4 {
    egen avg_inc_`q' = rowmean( ///
        inc_2_`q' inc_3_`q' inc_4_`q' inc_5_`q' inc_6_`q' inc_7_`q')
}



**# predicted spend ------------------------------


gen pred_spend = avg_main if !missing(pre_q)

forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_ppe_`q' if pre_q == `q'
}

forvalues q = 2/4 {
    replace pred_spend = pred_spend + avg_inc_`q' if inc_q == `q'
}


keep if state_fips == "`s'"
save pred_spend_ppe_`s', replace
restore
}

use `reg_temp', clear
levelsof state_fips, local(states)

clear
tempfile master
save `master', emptyok


foreach s of local states {
    append using pred_spend_ppe_`s'.dta
}
*-------------------------------------------------
* High / Low Predicted Spending (Include Never-Treated)
*-------------------------------------------------
/* New High

gen high = (pred_spend > 0) if !mi(pred_spend)

*/
* Old High
/*
gen byte high_treated = pred_spend > 0 if never_treated == 0 & !missing(pred_spend)
gen byte low_treated  = pred_spend <= 0 if never_treated == 0 & !missing(pred_spend)

label define highlbl 0 "Low/Control (≤0 or no reform)" 1 "High (>0, reform-state)"
label values high highlbl
tab high never_treated, m
*/

xtile pred_group = pred_spend if ever_treated==1, nq(2)
gen high_treated = pred_group == 2
gen low_treated  = pred_group == 1

save pred_spend_ppe_all, replace

*/
/*********************************
Pred_spend based on quartiles
**********************************/	
***pred_spend
use pred_spend_ppe_all, clear
capture postutil clear

* tabs
tab pre_q high,m
tab pre_q high if never_treated==0

*log using "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\10_10_25\jack_spend.log", replace
areg lexp_ma_strict ///
    i.lag_*##i.high_treated i.lead_*##i.high_treated ///
    i.year_unified##i.high_treated ///
	[aw = school_age_pop] if (reform_year<2000 ), ///
    absorb(county_id) vce(cluster county_id)
*log close
*------------------------------------------
* Loop: 0 = main only, 1 = main + interaction
*------------------------------------------


forvalues h = 0/1 {

    tempfile results
    postfile handle str15 term float relative_year b se using `results'

    if `h' == 1 {
        *** Main + Interaction (High group) ***
        forvalues k = 5(-1)1 {
            lincom 1.lead_`k' + 1.lead_`k'#1.high_treated
            if !_rc {
                post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
            }
        }

        post handle ("base0") (0) (0) (0)

        forvalues k = 1/17 {
            lincom 1.lag_`k' + 1.lag_`k'#1.high_treated
                post handle ("lag`k'") (`k') (r(estimate)) (r(se))
            }
        }

    }
    else {
        *** Main Only (Baseline group) ***
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
    }

    postclose handle

    *------------------------------------------
    * Plot and Export
    *------------------------------------------
    use `results', clear
    keep if inrange(relative_year, -5, 17)
    sort relative_year

    gen ci_lo = b - 1.96 * se
    gen ci_hi = b + 1.96 * se

    twoway (rarea ci_lo ci_hi relative_year, color(gs12%40) cmissing(n)) ///
           (line b relative_year, lcolor(black) lwidth(medthick)), ///
           yline(0, lpattern(dash) lcolor(gs8)) ///
           xline(0, lpattern(dash) lcolor(gs8)) ///
		   xline(2 7, lcolor(blue) lwidth(medthick)) ///
           ytitle("Change in ln(13-yr rolling avg PPE)") ///
           title("Event Study: High == `h'") legend(off)
    graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_5_25\jack_spend_`h'.png", replace
}

*------------------------------------------
* Loop: 0 = main only, 1 = main + interaction
*------------------------------------------
use pred_spend_ppe_all, clear
* tabs
tab pre_q high,m
tab pre_q high if never_treated==0

*log using "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\10_10_25\jack_spend.log", replace
areg lexp_ma_strict ///
    i.lag_*##i.low_treated  i.lead_*##i.low_treated  ///
    i.year_unified##i.low_treated  ///
	[aw = school_age_pop] if (reform_year<2000 ), ///
    absorb(county_id) vce(cluster county_id)

forvalues h = 0/1 {

    tempfile results2
    postfile handle2 str15 term float relative_year b se using `results2'

    if `h' == 1 {
        *** Main + Interaction (High group) ***
        forvalues k = 5(-1)1 {
            lincom 1.lead_`k' + 1.lead_`k'#1.low_treated
            if !_rc {
                post handle2 ("lead`k'") (-`k') (r(estimate)) (r(se))
            }
        }

        post handle2 ("base0") (0) (0) (0)

        forvalues k = 1/17 {
            lincom 1.lag_`k' + 1.lag_`k'#1.low_treated
            if !_rc {
                post handle2 ("lag`k'") (`k') (r(estimate)) (r(se))
            }
        }

    }
    else {
        *** Main Only (Baseline group) ***
        forvalues k = 5(-1)1 {
            lincom 1.lead_`k'
            if !_rc {
                post handle2 ("lead`k'") (-`k') (r(estimate)) (r(se))
            }
        }

        post handle2 ("base0") (0) (0) (0)

        forvalues k = 1/17 {
            lincom 1.lag_`k'
            if !_rc {
                post handle ("lag`k'") (`k') (r(estimate)) (r(se))
            }
        }
    }

    postclose handle2

    *------------------------------------------
    * Plot and Export
    *------------------------------------------
    use `results2', clear
    keep if inrange(relative_year, -5, 17)
    sort relative_year

    gen ci_lo = b - 1.96 * se
    gen ci_hi = b + 1.96 * se

    twoway (rarea ci_lo ci_hi relative_year, color(gs12%40) cmissing(n)) ///
           (line b relative_year, lcolor(black) lwidth(medthick)), ///
           yline(0, lpattern(dash) lcolor(gs8)) ///
           xline(0, lpattern(dash) lcolor(gs8)) ///
		   xline(2 7, lcolor(blue) lwidth(medthick)) ///
           ytitle("Change in ln(13-yr rolling avg PPE)") ///
           title("Event Study: Low == `h'") legend(off)
    graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_5_25\jack_spend_low_`h'.png", replace
}


/*
           
