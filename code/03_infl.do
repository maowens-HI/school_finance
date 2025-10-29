/*-------------------------------------------------------------------------------
File     : 03_infl.do
Purpose  : This do-file adjust for inflation
Inputs   : fiscal_year.csv, tracts_panel
Outputs  : tracts_panel_real.dta
Requires : 
Notes    : 
-------------------------------------------------------------------------------*/


*** Register FRED key once (no more nagging)
set fredkey 87d3478358d0f3e781d2657d1aefd1ff, permanently

*** Import MONTHLY CPI-U (NSA), grab 1966 so FY1967 is complete
tempfile cpi_monthly fy_tbl cpi_fy deflators
import fred CPIAUCNS, daterange(1964-01-01 2019-12-31) clear
gen m = mofd(daten)
format m %tm
rename CPIAUCNS cpi_u_all_nsa
keep m cpi_u_all_nsa
save `cpi_monthly'

*** Load fiscal-year lookup
import delimited "$SchoolSpending\data\fiscal_year.csv", ///
    varnames(1) clear

*** Make sure state_fips is str2
tostring state_fips, replace format("%02.0f")
keep state_fips fy_start_month
duplicates drop
save `fy_tbl', replace

*** Cross product of CPI months with states, assign fiscal year end-year
use `cpi_monthly', clear
cross using `fy_tbl'

gen cal_y = year(dofm(m))
gen cal_m = month(dofm(m))
gen fy_end_year = cal_y + (cal_m >= fy_start_month)

keep if inrange(fy_end_year, 1967,2019)


*** Collapse to fiscal-year averages
*This was messing stuff up
*collapse (mean) cpi_u_all_nsa (count) nmonths = m, by(state_fips fy_end_year)
collapse (mean) cpi_u_all_nsa (count) nmonths = cpi_u_all_nsa, by(state_fips fy_end_year)
assert nmonths == 12
rename fy_end_year year4
rename cpi_u_all_nsa cpi_fy_avg
label var cpi_fy_avg "CPI-U (NSA) averaged over state fiscal year"
save `cpi_fy', replace

*** Build 2000-dollar factors
bys state_fips: egen base2000 = max(cond(year4==2000, cpi_fy_avg, .))
gen deflator_2000 = cpi_fy_avg / base2000
gen inflator_2000 = base2000 / cpi_fy_avg

order state_fips year4 cpi_fy_avg deflator_2000 inflator_2000
save `deflators', replace

*** Merge to panel
use "$SchoolSpending\data\tracts_panel_canon", clear

*** Standardize state_fips to str2
capture confirm string variable state_fips
if _rc {
    tostring state_fips, gen(state_fips_str) force
    replace state_fips_str = substr("00"+state_fips_str, -2, 2)
    drop state_fips
    rename state_fips_str state_fips
}

merge m:1 state_fips year4 using `deflators', keep(match master) nogen

*** deflate per-pupil spending to 2000 dollars
gen pp_exp_real = pp_exp * inflator_2000
label var pp_exp_real "Per-pupil expenditure in 2000 dollars (state FY CPI-U avg)"
*/
*** Save merged panel 
keep LEAID GOVID year4 pp_exp_real good_tract sdtc state_fips gisjoin2 coc70 tract70
save "$SchoolSpending\data\tracts_panel_real.dta", replace
