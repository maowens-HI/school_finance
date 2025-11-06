
* Housekeeping
clear
set more off
cd "$SchoolSpending\data"


    use jjp_interp, clear

rename pre_q1971 pre_q

	tempfile reg_temp
	save `reg_temp'

**# Pred_spend
/*********************************
Construct Predicted Spending by Baseline Quartiles
**********************************/


*--- Load Regression-Ready Dataset ---
use `reg_temp',clear

*--- Estimate Event-Study Model ---
areg lexp_ma_strict ///
    i.lag_*##i.pre_q i.lead_*##i.pre_q ///
    i.year_unified##i.pre_q [w = school_age_pop]if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)
        

*-------------------------------------------------
* Extract Main (Baseline) Lag Coefficients
*-------------------------------------------------
forvalues t = 1/17{
        gen main_`t' = .
    }

* Fill placeholders
forvalues t = 1/17{
        scalar coeff_main = _b[1.lag_`t']
        replace main_`t' = coeff_main
    }



*-------------------------------------------------
* Extract Quartile-Specific Lag Coefficients
*-------------------------------------------------
forvalues t = 1/17{
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

*-------------------------------------------------
* Compute Mean Coefficients
*-------------------------------------------------

egen avg_main = rowmean(main_1 main_2 main_3 main_4 main_5 main_6 main_7 main_8 main_9 main_10 main_11 main_12 main_13 main_14 main_15 main_16 main_17)

forvalues q = 2/4 {
    egen avg_ppe_`q' = rowmean( ///
        ppe_1_`q' ppe_2_`q' ppe_3_`q' ppe_4_`q' ppe_5_`q' ppe_6_`q' ppe_7_`q' ///
        ppe_8_`q' ppe_9_`q' ppe_10_`q' ppe_11_`q' ppe_12_`q' ppe_13_`q' ///
        ppe_14_`q' ppe_15_`q' ppe_16_`q' ppe_17_`q')
}



*-------------------------------------------------
* Generate Predicted Spending by Quartile
*-------------------------------------------------

gen pred_spend = avg_main if !missing(pre_q)

forvalues q = 2/4 {
    replace pred_spend = avg_main + avg_ppe_`q' if pre_q == `q' & !missing(pre_q)
}



*-------------------------------------------------
* Define High-Spending Treatment Group
*-------------------------------------------------
gen high = 0 if !missing(pred_spend)
replace high = 1 if pred_spend > 0 & !missing(pred_spend)



tab pre_q high
tab pre_q high if never_treated==0
table pre_q high, ///
statistic(mean pred_spend) nformat(%9.3f)

*------------------------------------------
* Estimate event-study with interaction
*------------------------------------------


areg lexp_ma_strict ///
    i.lag_*##i.high i.lead_*##i.high ///
    i.year_unified##i.high [w = school_age_pop] if (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

*------------------------------------------
* Loop: 0 = main only, 1 = main + interaction
*------------------------------------------
forvalues h = 0/1 {

    if `h' == 1 {
        *** Main + Interaction (High group) ***
        tempfile results
        postfile handle str15 term float rel_year b se using `results'

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

        postclose handle
    }
    else {
        *** Main Only (Baseline group) ***
        tempfile results
        postfile handle str15 term float rel_year b se using `results'

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
    }

    *------------------------------------------
    * Plot and Export
    *------------------------------------------
    use `results', clear
    keep if rel_year >= -5 & rel_year <= 17
    sort rel_year

    gen ci_lo = b - 1.645 * se
    gen ci_hi = b + 1.645 * se



    twoway (rarea ci_lo ci_hi rel_year, color(gs12%40) cmissing(n)) ///
           (line b rel_year, lcolor(black) lwidth(medthick)), ///
           yline(0, lpattern(dash) lcolor(gs8)) ///
           xline(0, lpattern(dash) lcolor(gs8)) ///
           xline(1 17, lcolor(blue) lwidth(medthick)) ///
           ytitle("Change in ln(13-year rolling avg PPE)") ///
           title("Event Study: high = `h'") legend(off)

*graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\10_10_25\3_layer23_`h'.png", replace
}