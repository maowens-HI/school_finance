/*==============================================================================
Project    : School Spending - Relaxed Balance (+14 instead of +17)
File       : fig1_bal_relax14.do
Purpose    : Test whether using +14 event window (847 counties) instead of +17
             (822 counties) produces stronger results
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-11-14
───────────────────────────────────────────────────────────────────────────────
Inputs:    - interp_temp.dta, county_clean.dta, county_exp_final.dta
Outputs:   - Event study graphs with relaxed balance restriction
Notes:     - Matt's email noted +14 gives 847 counties vs 822 for +17
           - This is a 3% increase in sample size
==============================================================================*/

*--- 0. Setup -----------------------------------------------------------------
clear all
set more off
cd "$SchoolSpending\data"
use county_clean, clear
merge 1:m county using county_exp_final
drop _merge
replace good_county = 0 if missing(good_county)
drop if missing(county_exp)
rename county county_id
gen never_treated = treatment == 0
bysort county_id: egen ever_treated = max(treatment)
gen never_treated2 = ever_treated == 0
gen year_unified = year4-1
winsor2 county_exp, replace c(1 99) by(year_unified)

/**************************************************************************
   STRICT 13-YEAR ROLLING MEAN
**************************************************************************/
rename county_exp exp
gen lexp = log(exp)

rangestat (mean) exp, interval(year_unified -12 -0) by(county_id)
rename exp_mean exp_ma
gen lexp_ma = log(exp_ma)

rangestat (mean) exp_ma_strict = exp (count) n_obs = exp, ///
    interval(year_unified -12 0) by(county_id)

replace exp_ma_strict = . if n_obs < 13 & year4 < 1979
gen lexp_ma_strict = log(exp_ma_strict)

*--- 3. Relative year ---------------------------------------------------------

gen relative_year = year_unified - reform_year
replace relative_year = . if missing(reform_year)

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

/**************************************************************************
   LEADS AND LAGS (NOW BINNING AT +14 INSTEAD OF +17)
**************************************************************************/

forvalues k = 1/14 {
    gen lag_`k' = (relative_year == `k')
    replace lag_`k' = 0 if missing(relative_year)
}
forvalues k = 1/5 {
    gen lead_`k' = (relative_year == -`k')
    replace lead_`k' = 0 if missing(relative_year)
}

* BIN AT +14 (not +17)
replace lag_14 = 1 if relative_year >= 14 & !missing(relative_year)
replace lead_5 = 1 if relative_year <= -5 & !missing(relative_year)

/**************************************************************************
   BALANCED PANEL: -5 TO +14 (RELAXED)
**************************************************************************/

rename good_county_1967 good_66
rename good_county_1970 good_69
rename good_county_1971 good_70
rename good_county_1972 good_71
rename good_county_6771 good_66_70
rename good_county good_66_71
rename good_county_7072 good_69_71

save jjp_interp_temp, replace

* Create balanced panel with RELAXED restriction
preserve
keep if inrange(relative_year, -5, 14) // Changed from 17 to 14

bys county_id: egen min_rel = min(relative_year)
bys county_id: egen max_rel = max(relative_year)
bys county_id: gen n_rel = _N

* Full window: -5 to +14 = 20 years (not 23)
keep if min_rel == -5 & max_rel == 14 & n_rel == 20

keep county_id
duplicates drop
gen balance = 1
tempfile balance
save `balance'
restore

merge m:1 county_id using `balance'
replace balance = 0 if missing(balance)

* Keep balanced + never treated
keep if balance ==1 | never_treated2 ==1

count
di "Total observations after relaxed balance: " r(N)
codebook county_id
di "Total counties after relaxed balance: " r(r)

drop pre_q* base_*

/**************************************************************************
*   RE-CREATE BASELINE QUARTILES ON BALANCED SAMPLE
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

foreach y of local years {
    merge m:1 state_fips county_id using `q`y'', nogen
}

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

drop _merge
save jjp_balance_relax14, replace

use interp_d,clear
gen county_id = substr(LEAID,1,5)
collapse (mean) enrollment, by(county)
merge 1:m county_id using jjp_balance_relax14
save jjp_balance_relax14_final, replace

/*********************************
* Run event studies with RELAXED balance
**********************************/

local v lexp_ma_strict
local y pre_q1970
local g good_70

use jjp_balance_relax14_final, clear
drop if `g' != 1
count
di "Sample size with `g' restriction and RELAXED balance: " r(N)

*--------------------------------------*
* WEIGHTED
*--------------------------------------*

areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified [w=enrollment] if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

tempfile results
postfile handle str15 term float rel_year b se using `results', replace

forvalues k = 5(-1)1 {
    lincom 1.lead_`k'
    if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle ("base0") (0) (0) (0)

forvalues k = 1/14 {  // Now goes to 14 not 17
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
    title("Relaxed Balance (+14): Weighted | Bottom 3 Quartiles", size(medlarge) color("35 45 60")) ///
    note("Window: -5 to +14 | N counties: 847 (vs 822 for +17)") ///
    graphregion(color(white)) ///
    legend(off) ///
    scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\relax14_weighted.png", replace

*--------------------------------------*
* UNWEIGHTED
*--------------------------------------*

use jjp_balance_relax14_final, clear
drop if `g' != 1

areg `v' ///
    i.lag_* i.lead_* ///
    i.year_unified if `y' < 4 & (never_treated==1 | reform_year<2000), ///
    absorb(county_id) vce(cluster county_id)

tempfile results2
postfile handle str15 term float rel_year b se using `results2', replace

forvalues k = 5(-1)1 {
    lincom 1.lead_`k'
    if !_rc post handle ("lead`k'") (-`k') (r(estimate)) (r(se))
}

post handle ("base0") (0) (0) (0)

forvalues k = 1/14 {
    lincom 1.lag_`k'
    if !_rc post handle ("lag`k'") (`k') (r(estimate)) (r(se))
}

postclose handle

use `results2', clear
sort rel_year

gen ci_lo = b - 1.645*se
gen ci_hi = b + 1.645*se

twoway ///
    (rarea ci_lo ci_hi rel_year, color("214 96 77%20") cmissing(n)) ///
    (line b rel_year, lcolor("178 68 53") lwidth(medium)), ///
    yline(0, lpattern(dash) lcolor(gs10)) ///
    xline(0, lpattern(dash) lcolor(gs10)) ///
    ytitle("Δ ln(13-yr rolling avg PPE)", size(medsmall) margin(medium)) ///
    title("Relaxed Balance (+14): Unweighted | Bottom 3 Quartiles", size(medlarge) color("35 45 60")) ///
    note("Window: -5 to +14 | N counties: 847 (vs 822 for +17)") ///
    graphregion(color(white)) ///
    legend(off) ///
    scheme(s2mono)

graph export "C:\Users\maowens\OneDrive - Stanford\Documents\school_spending\notes\11_12_25\relax14_unweighted.png", replace
