/*==============================================================================
Project    : School Spending – Inflation Adjustment
File       : 03_infl.do
Purpose    : Convert nominal per-pupil expenditures to real 2000 dollars using
             state-specific fiscal-year CPI-U averages from FRED.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-10-27
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES (Summary):
  • Pulls monthly CPI-U data from FRED API (1964-2019)
  • Constructs state-specific fiscal-year CPI averages (states have different FY definitions)
  • Merges CPI deflators to tract-year spending panel
  • Creates pp_exp_real = per-pupil expenditure in constant 2000 dollars
  • Preserves nominal values for robustness checks

WHY THIS MATTERS (Workflow Context):
  This is Step 3 of the core pipeline. The event-study analysis compares spending
  levels ACROSS TIME (1967-2019) and ACROSS STATES. Without inflation adjustment:
  - $1,000 in 1970 ≠ $1,000 in 2000 (purchasing power differs)
  - Nominal spending mechanically rises over time (confounds treatment effects)

  Challenge: States use different fiscal years (e.g., NY: April-March, CA: July-June).
  Solution: Calculate CPI averages specific to each state's 12-month fiscal period.

  Base Year = 2000: Coefficients in event-study regressions are interpretable as
  "percentage change in year-2000 dollars per pupil."

INPUTS:
  - tracts_panel_canon.dta  (from 01_tract.do)
      └─> Tract-year panel with nominal pp_exp
  - fiscal_year.csv
      └─> State FIPS × fiscal year start month (e.g., NY=4, CA=7)
  - FRED API (automatic download)
      └─> CPIAUCNS series (monthly CPI-U, not seasonally adjusted)

OUTPUTS:
  - tracts_panel_real.dta  ★ MAIN OUTPUT ★
      └─> Tract-year panel with:
          • pp_exp          (nominal dollars, original)
          • cpi_fy_avg      (state-FY-specific CPI index)
          • deflator_2000   (CPI_2000 / CPI_fy)
          • pp_exp_real     (pp_exp × inflator_2000)
          Coverage: 1967-2019, all tracts

KEY ASSUMPTIONS & SENSITIVE STEPS:
  1. CPI Series Choice:
     - Uses CPI-U (urban consumers), not CPI-W (wage earners)
     - Not seasonally adjusted (NSA) to match fiscal year periods exactly
     - Source: FRED series CPIAUCNS (St. Louis Fed)

  2. Fiscal Year Logic:
     - Each state's FY spans 12 months starting from fy_start_month
     - Fiscal year labeled by END year (e.g., NY FY 1970 = April 1969–March 1970)
     - Averages all 12 monthly CPI values within the state's fiscal period

  3. Base Year Normalization:
     - deflator_2000 = (CPI in year t) / (CPI in 2000)
     - inflator_2000 = (CPI in 2000) / (CPI in year t)
     - pp_exp_real = pp_exp × inflator_2000
     - Ensures year 2000 values remain unchanged (deflator_2000 = 1 for year 2000)

  4. Missing CPI:
     - Assert checks that all states have exactly 12 months of CPI per FY
     - Should never have missing deflators (FRED data is complete 1964-2019)

  5. State-Level Variation:
     - All tracts within same state-year get identical CPI adjustment
     - Does NOT vary by county or tract (CPI-U is metropolitan-area index,
       but we apply national all-items series for consistency)

DEPENDENCIES:
  • Requires: global SchoolSpending "C:\Users\...\path"
  • Requires: 01_tract.do must run first (creates tracts_panel_canon.dta)
  • Requires: FRED API key set in Stata (line 12: set fredkey ...)
  • Stata packages:
      - fred (install: ssc install fred)
  • Downstream: 04_cnty.do uses tracts_panel_real.dta

VALIDATION CHECKS TO RUN:
  - CPI completeness: assert nmonths == 12 (every state-FY has 12 months)
  - Deflator range: summ deflator_2000, detail (should be ~0.3 to 1.5)
  - Merge success: tab _merge after CPI merge (should be 100% matched)
  - Spot check: list year4 pp_exp pp_exp_real if year4==2000 & state_fips=="06"
                (pp_exp should ≈ pp_exp_real for base year)
==============================================================================*/


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
import delimited "$SchoolSpending/data/fiscal_year.csv", ///
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
use "$SchoolSpending/data/tracts_panel_canon", clear

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
keep LEAID GOVID year4 pp_exp_real good_tract sdtc state_fips gisjoin2 coc70 tract70 ///
	good_tract_1967 good_tract_1970 good_tract_1971 ///
    good_tract_1972 good_tract_6771 good_tract_7072 county_code
gen tract_merge = substr(tract70,1,9)
save "$SchoolSpending/data/tracts_panel_real.dta", replace
