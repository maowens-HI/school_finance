
* Housekeeping
clear
set more off
cd "$SchoolSpending\data"


    use jjp_interp, clear

rename pre_q1971 pre_q

	tempfile reg_temp
	save `reg_temp'
	
use `reg_temp', clear

levelsof state_fips, local(states)
    foreach s of local states {
		preserve
drop if state_fips == "`s'"

areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
     i.year_unified##pre_q ///
	 [w = school_age_pop] if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
	
		estimates save layer_mod_`s', replace
restore
	}


levelsof state_fips, local(states)
foreach s of local states {
preserve
use `reg_temp', clear
estimates use layer_mod_`s'

	

**# Gen main -----------------------------
forvalues t = 1/17{
		gen main_`t' = .
	}

* Fill placeholders
forvalues t = 1/17{
		scalar coeff_main = _b[1.lag_`t']
		replace main_`t' = coeff_main
	}



**# Gen ppe ------------------------------
* Generate placeholders
forvalues t = 1/17{
	forvalues q = 2/4 {
		gen ppe_`t'_`q' = .
	}
}
* Fill placeholders
forvalues t = 1/17{
	forvalues q = 2/4 {
		scalar coeff_ppe = _b[1.lag_`t'#`q'.pre_q]
		replace ppe_`t'_`q' = coeff_ppe
	}
}

**# Gen averages ------------------------------

egen avg_main = rowmean(main_1 main_2 main_3 main_4 main_5 main_6 main_7 main_8 main_9 main_10 main_11 main_12 main_13 main_14 main_15 main_16 main_17)

forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_1_`q' ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q' ///
        ppe_8_`q' ppe_9_`q' ppe_10_`q' ppe_11_`q' ppe_12_`q' ppe_13_`q' ///
        ppe_14_`q' ppe_15_`q' ppe_16_`q' ppe_17_`q')
}

**# predicted spend ------------------------------

gen pred_spend = avg_main if !missing(pre_q)

forvalues q = 2/4 {
    replace pred_spend = avg_main + avg_ppe_`q' if pre_q == `q' & !missing(pre_q)
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
gen high = 0  if !missing(pred_spend) // start missing so missing pred_spend stays missing

* High predicted spending increase: positive predicted change or never-treated
replace high = 1 if (pred_spend > .0580935 & !missing(pred_spend)) | never_treated == 1

replace high = . if missing(pred_spend)

save pred_spend_ppe_all, replace

*/
/*********************************
Pred_spend based on quartiles
**********************************/	
***pred_spend
use pred_spend_ppe_all, clear
* tabs
tab pre_q high,m
tab pre_q high if never_treated==0

*log using "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\10_10_25\jack_spend.log", replace
areg lexp_ma_strict ///
    i.lag_*##i.high i.lead_*##i.high ///
    i.year_unified##high ///
	[w = school_age_pop] if reform_year<2000, ///
    absorb(county_id) vce(cluster county_id)
*log close
*------------------------------------------
* Loop: 0 = main only, 1 = main + interaction
*------------------------------------------


forvalues h = 0/0 {

    tempfile results
    postfile handle str15 term float relative_year b se using `results'

    if `h' == 1 {
        *** Main + Interaction (High group) ***
        forvalues k = 5(-1)1 {
            lincom 1.lead_`k' + 1.lead_`k'#1.high
            if !_rc {
                post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
            }
        }

        post handle ("base0") (0) (0) (0)

        forvalues k = 1/17 {
            lincom 1.lag_`k' + 1.lag_`k'#1.high
            if !_rc {
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

    gen ci_lo = b - 1.645 * se
    gen ci_hi = b + 1.645 * se

    twoway (rarea ci_lo ci_hi relative_year, color(gs12%40) cmissing(n)) ///
           (line b relative_year, lcolor(black) lwidth(medthick)), ///
           yline(0, lpattern(dash) lcolor(gs8)) ///
           xline(0, lpattern(dash) lcolor(gs8)) ///
           xline(2 7, lcolor(blue) lwidth(medthick)) ///
           ytitle("Change in ln(13-yr rolling avg PPE)") ///
           title("Event Study: High == `h'") legend(off)
    *graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\10_10_25\jack_spend_`h'.png", replace
}
