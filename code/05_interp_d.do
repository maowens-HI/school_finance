/*-------------------------------------------------------------------------------
File     : 05_interp_d
Purpose  : This file assigns district spending to tracts it imputes spending for
missing years. It then collapses tracts into countie and assingings treatments.
-------------------------------------------------------------------------------*/
*****************************************************************************
* I) Repeat Previous .do file steps but with interpolation
*****************************************************************************
*****************************************************************************
* A) Prep for Interpolation of district panel
*****************************************************************************
clear
set more off
cd "$SchoolSpending/data"

use f33_indfin_grf_canon,clear


* Convert string LEAID → numeric
encode LEAID, gen(LEAID_num) // LEAID is a string and needs to be changed for interpolation

* gap detector
bysort LEAID (year): gen gap_next = year[_n+1] - year // gap = next year - current year
gen too_far = gap_next > 3 // We don't want to impute gaps that are too big

* Ensure full county-year panel
tsset LEAID_num year4
tsfill, full // creates missing values to fill for the whole range of the panel



*--- 1. Fill identifiers ------------------------------------------------------

*Strings // adds back in stable variables for the gaps we created
foreach var in GOVID LEAID good_govid_baseline{
    bys LEAID_num: egen __fill_`var' = mode(`var'), maxmode
    replace `var' = __fill_`var' if missing(`var')
    drop __fill_`var'
}


bys LEAID_num (year4): replace too_far = too_far[_n-1] if missing(too_far)

*--- 2. Interpolate county expenditures --------------------------------------
bys LEAID_num: ipolate pp_exp year if too_far == 0, gen(exp2) 
// We create exp2 the imputed spending 
*****************************************************************************
* B) Save interpolated district panel
*****************************************************************************
replace exp2 = pp_exp if !missing(pp_exp)

drop pp_exp gap_next too_far

rename exp2 pp_exp

keep LEAID GOVID  year4 pp_exp LEAID_num
save interp_d, replace // This is a district level panel of interpolated spending



*****************************************************************************
* II) Build Tract Panel
*****************************************************************************
*****************************************************************************
* A) Assign one LEAID to each tract based on allocated population
*****************************************************************************
use "$SchoolSpending/data/grf_tract_canon", clear // list of all tracts
gen coc70 = substr(tract70,3,3)

* Guard against . sorting to the top
gen byte has_alloc = !missing(alloc_pop)

* Pick exactly one LEAID per (tract70 sdtc):
gsort tract70 sdtc -has_alloc -alloc_pop LEAID
by tract70 sdtc: keep if _n==1
drop if missing(tract70) // 0 obs deleted
drop if missing(sdtc)  // 1 case deleted
* Sanity
isid tract70 sdtc

* Save crosswalk
tempfile xwalk
save `xwalk', replace




***Merge panel to tracts
*District Year Spending
use "$SchoolSpending/data/interp_d.dta", clear


*ExplodeL one row per tract-year
joinby LEAID using `xwalk', unmatched(both) _merge(join_merge)
// This won't be a perfect join since some LEAIDs dissapear due to assignment

*** Clean and Save
sort tract70 year4
cd "$SchoolSpending/data"
keep if join_merge ==3
save interp_t_temp, replace


use grf_id_tractlevel, clear // this tells me if an area is non-tracted
keep no_tract tract70 county_code
duplicates drop  // want it on the tract level
merge 1:m tract70 using interp_t_temp // allows us to see non-t in tract panel
rename county_code county
* At this point every tract in the panel should have a label as to if it is an //
* ... untracted area or not.


/*******************************************************************************
B) Prep for sorting out untracted areas in the GRF
********************************************************************************/
* Count DISTINCT non-tracted areas per county–year

// Is a tract ever considered non-tracted?
bys county year4 tract70: egen byte any_untr = max(no_tract==1) 

// first row of every tract
bys county year4 tract70: gen  byte tag_tr   = _n==1 

// Is this the first row and is this untracted?
gen byte nt_tag = tag_tr & any_untr 

// Count of distinct non tracted areas in a county
bys county year4: egen n_nontr_uniq = total(nt_tag)
drop any_untr tag_tr nt_tag

* Count DISTINCT tracted areas per county–year (for the "no tracts" test)
bys county year4 tract70: egen byte any_tr = max(no_tract==0)
bys county year4 tract70: gen  byte tag_tr2 = _n==1
gen byte tr_tag = tag_tr2 & any_tr
bys county year4: egen n_tr_uniq = total(tr_tag)
drop any_tr tag_tr2 tr_tag


*A 4-type that splits based on Nicks's comments
gen byte county_type = .
replace county_type = 1 if n_nontr_uniq == 0 & n_tr_uniq > 0   // fully tracted
replace county_type = 2 if n_nontr_uniq == 1 & n_tr_uniq == 0  // fully untracted
replace county_type = 4 if n_nontr_uniq == 1 & n_tr_uniq > 0   // mixed: 1 untracted + some tracted
replace county_type = 3 if n_nontr_uniq >= 2     // ≥2 untracted (multi-untracted counties)


* Safety: if something weird sneaks through, mark it
replace county_type = . if n_nontr_uniq==. | n_tr_uniq==.

label define ctype ///
    1 "All tracted only" ///
    2 "Single untracted only (no tracts)" ///
    3 "Problematic: ≥2 untracted" ///
    4 "Mixed: 1 untracted + some tracted", replace
label values county_type ctype
save interp_t, replace // panel of interpolated tracts 


use interp_t,clear

/*******************************************************************************
C) Adjust for Inflation
********************************************************************************/
/*
*** Register FRED key once (no more nagging)
set fredkey 87d3478358d0f3e781d2657d1aefd1ff, permanently

*** Import MONTHLY CPI-U, grab 1966 so FY1967 is complete
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
use "$SchoolSpending/data/interp_t", clear

*** Standardize state_fips to str2
capture confirm string variable state_fips // Edit without capture 
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
gen str13 gisjoin2 = substr(tract70, 1, 2) + "0" + substr(tract70, 3, 3) + "0" + substr(tract70, 6, 6)
*** Save merged panel 
gen tract_merge = substr(tract70,1,9)
drop _merge
rename pp_exp pp_exp_real // remove later
save "$SchoolSpending/data/interp_t_real.dta", replace





/*******************************************************************************
III) Turn tract panel into county panel
********************************************************************************/
/*******************************************************************************
A) Import School Age Population for tracts
********************************************************************************/
*** Housekeeping
clear 
set more off 

*** Set working directory
cd "$SchoolSpending/data"

*** Load tract-level NHGIS school school_age_pop data
*import delimited "$SchoolSpending\data\school_level_1970.csv", clear
import delimited "$SchoolSpending/data/enroll_age_tract.csv", clear

*** Label variables from NHGIS 1970 "Age by school_age_pop Status" table (NT112)

label var gisjoin   "GIS Join Match Code"
label var year      "Data File Year"
label var regiona   "Region Code"
label var divisiona "Division Code"
label var state     "State Name"
label var statea    "State Code"
label var county    "County Name"
label var countya   "County Code"
label var cty_suba  "County Subdivision Code"
label var placea    "Place Code"
label var tracta    "Census Tract Code"
label var scsaa     "Standard Consolidated Statistical Area Code"
label var smsaa     "Standard Metropolitan Statistical Area Code"
label var urb_areaa "Urban Area Code"
label var areaname  "Area Name"
label var cencnty   "1970 Central County Code"
label var cbd       "Central Business District"
label var sea       "State Economic Area"

*** Table NT112: Age by school_age_pop Status (Persons 3–34 Years)
label var c04001 "3–4 years old — Enrolled"
label var c04002 "3–4 years old — Not enrolled"
label var c04003 "5–6 years old — Enrolled"
label var c04004 "5–6 years old — Not enrolled"
label var c04005 "7–13 years old — Enrolled"
label var c04006 "7–13 years old — Not enrolled"
label var c04007 "14–15 years old — Enrolled"
label var c04008 "14–15 years old — Not enrolled"
label var c04009 "16–17 years old — Enrolled"
label var c04010 "16–17 years old — Not enrolled"
label var c04011 "18–24 years old — Enrolled"
label var c04012 "18–24 years old — Not enrolled"
label var c04013 "25–34 years old — Enrolled"
label var c04014 "25–34 years old — Not enrolled"

*Note: This does not perfectly get the primary secondary split but approximates it.
***  total school-age population (approx ages 5–17)
gen school_age_pop = c04003 + c04004 + c04005 + c04006 + c04007 + c04008 + c04009 + c04010
label var school_age_pop "Estimated school-age population (5–17 years, enrolled + not enrolled)"

*****************************************************************************
*B) Clean School Age Population
*****************************************************************************

gen str2 state_str  = string(statea,  "%02.0f")
gen str3 county_str = string(countya, "%03.0f")

*** Build tract_str intelligently from numeric tracta
gen digits = floor(log10(tracta)) + 1 if tracta > 0 // no decimals
replace digits = 1 if tracta == 0 | tracta==.

gen str6 tract_str = ""
replace tract_str = string(tracta*100, "%06.0f") if digits <= 4    // 101 → 010100
replace tract_str = string(tracta, "%06.0f")      if digits == 5 | digits == 6   // 123456 → 123456


* Canonical 11-digit tract identifier
gen str11 tract70 = state_str + county_str + tract_str

gen tract_merge = substr(tract70,1,9)
label var tract70 "11-digit Census Tract FIPS (state+county+tract)"  // 


*** Create truncated GISJOIN for merging with tract panel
gen gisjoin2 = substr(gisjoin, 2, 14)

*****************************************************************************
* C) Merge into tract panel
*****************************************************************************
/* I get a better merge when I ingore tract suffixes. */
collapse (mean) school_age_pop, by(tract70)
summ school_age_pop
save school_age_pop,replace 

*** Merge NHGIS data to tract panel
merge 1:m tract70 using "interp_t_real.dta"

rename _merge good_merge
tempfile check_no_tract
rename county county_code
save `check_no_tract'

*** Drop NHGIS-only records and clean merge variable
drop if good_merge == 1
drop good_merge

*** Save intermediate dataset // We split the data so we can assign county sch_pop
preserve 
keep if no_tract ==0
tempfile grf_tract_school_age_pop_v1
save `grf_tract_school_age_pop_v1'
summarize school_age_pop,d
restore
keep if no_tract ==1
tempfile grf_no_tract
save `grf_no_tract'

*****************************************************************************
*D) Import county level school age population data
*****************************************************************************
*** Load county-level school_age_pop file
import delimited "$SchoolSpending/data/enroll_age_county.csv", clear
	
	
* Labels (county-level NT112: Age by school_age_pop Status)
label var gisjoin   "GIS Join Match Code"
label var year      "Data File Year"
label var regiona   "Region Code"
label var divisiona "Division Code"
label var state     "State Name"
label var statea    "State Code"
label var county    "County Name"
label var countya   "County Code"
label var cty_suba  "County Subdivision Code"
label var placea    "Place Code"
label var tracta    "Census Tract Code"
label var scsaa     "Standard Consolidated Statistical Area Code"
label var smsaa     "Standard Metropolitan Statistical Area Code"
label var urb_areaa "Urban Area Code"
label var areaname  "Area Name"
label var cencnty   "1970 Central County Code"
label var cbd       "Central Business District"
label var sea       "State Economic Area"

label var c04001 "3–4 yrs — Enrolled"
label var c04002 "3–4 yrs — Not enrolled"
label var c04003 "5–6 yrs — Enrolled"
label var c04004 "5–6 yrs — Not enrolled"
label var c04005 "7–13 yrs — Enrolled"
label var c04006 "7–13 yrs — Not enrolled"
label var c04007 "14–15 yrs — Enrolled"
label var c04008 "14–15 yrs — Not enrolled"
label var c04009 "16–17 yrs — Enrolled"
label var c04010 "16–17 yrs — Not enrolled"
label var c04011 "18–24 yrs — Enrolled"
label var c04012 "18–24 yrs — Not enrolled"
label var c04013 "25–34 yrs — Enrolled"
label var c04014 "25–34 yrs — Not enrolled"

* County school-age total (5–17), and a clean 1970 county FIPS
gen school_age_pop = c04003 + c04004 + c04005 + c04006 + c04007 + c04008 + c04009 + c04010
label var school_age_pop "School-age population (5–17), 1970"

*** Construct county code using state and county numeric codes
gen str5 county_code = string(statea, "%02.0f") + string(countya, "%03.0f")

*Preserve a list of county codes and names
preserve
duplicates drop county_code,force
rename county county_name
keep county_code county_name
save cnames, replace
restore

save county_school_pop,replace

*** Merge county-level school_age_pop with non-tract dataset
merge 1:m county_code using `grf_no_tract'
keep if _merge==3
drop _merge
summarize school_age_pop,d
* Append back into the tract dataset
append using `grf_tract_school_age_pop_v1'

*** Save updated dataset
tempfile grf_tract_school_age_pop_v2
save `grf_tract_school_age_pop_v2' , replace
drop if missing(sdtc) | sdtc==4

*** Generate school_age_pop measures
gen primary_age    = c04003 + c04004 + c04005 + c04006
gen secondary_age  = c04007 + c04008 + c04009 + c04010
gen age_total      = primary_age + secondary_age
gen share_primary   = primary_age   / age_total if age_total > 0
gen share_secondary = secondary_age / age_total if age_total > 0

*** Rename and construct county identifiers
rename county county_name
rename county_code county

*** Drop exact duplicates of tract-year-district observations
duplicates drop gisjoin2 year4 sdtc LEAID tract70, force

*** If multiple LEAIDs remain for same tract-year-type, keep first
by tract70 year4 sdtc (LEAID), sort: keep if _n == 1



/*******************************************************************************
E) Reshape dataset wide by district type
********************************************************************************/
keep LEAID gisjoin2 tract70 year4 sdtc pp_exp_real school_age_pop ///
share_primary share_secondary county_name county county_type no_tract
reshape wide LEAID pp_exp_real school_age_pop share_primary share_secondary county_name county, i(tract70 year4) j(sdtc)


/******************************************************************************
Assign tract-level per-pupil expenditure (PPE)
 Combine primary (sdtc==2) and secondary (sdtc==3) PPE weighted by shares.
*******************************************************************************/

*** Drop redundant share variables from reshape
drop share_primary3 share_secondary2

*** Initialize tract PPE variable
gen ppe_tract = .

*** Calculate weighted PPE for split-district cases
replace ppe_tract = pp_exp_real2*share_primary2 + ///
                    pp_exp_real3*share_secondary3 ///
                    if !missing(pp_exp_real2) & !missing(pp_exp_real3)

*** Sanity check distribution of tract PPE
summarize ppe_tract, detail

*** Fill missing tract PPE with available single-district values
replace ppe_tract = pp_exp_real1 if missing(ppe_tract) & !missing(pp_exp_real1)
replace ppe_tract = pp_exp_real2 if missing(ppe_tract) & !missing(pp_exp_real2)
replace ppe_tract = pp_exp_real3 if missing(ppe_tract) & !missing(pp_exp_real3)

*** Final rename for tract PPE
rename ppe_tract pp_exp_real

*** Reset working directory
cd "$SchoolSpending/data"

*** Clean school_age_pop variables
rename school_age_pop1 school_age_pop
replace school_age_pop = school_age_pop2 if missing(school_age_pop) 
drop school_age_pop2
replace school_age_pop = school_age_pop3 if missing(school_age_pop)
drop school_age_pop3

*** Clean county_name variables from reshape
rename county_name1 county_name
replace county_name = county_name2 if missing(county_name)
drop county_name2
replace county_name = county_name3 if missing(county_name)
drop county_name3

*** Clean county identifiers from reshape
rename county1 county
replace county = county2 if missing(county)
drop county2
replace county = county3 if missing(county)
drop county3

*** Clean LEAID variables
rename LEAID1 LEAID
replace LEAID = LEAID2 + LEAID3 if missing(LEAID)

*** Create county-level lookup for merging back later
preserve
keep county_name county
duplicates drop county county_name, force
save county_lookup,replace
restore

*****************************************************************************
*F) Collapse into counties
*****************************************************************************

save tract_b4_collapse,replace
use tract_b4_collapse, clear

/*******************************************************************************
Handle untracted populations in mixed/problematic counties
(Type 3 = ≥2 untracted; Type 4 = 1 untracted + some tracted)
*******************************************************************************/

use tract_b4_collapse, clear

********************************************************************************
* ---- TYPE 4: One untracted area + 1 or more tracted----
********************************************************************************
preserve
keep if county_type == 4
summ school_age_pop

* Step 0. county totals (from NHGIS/IPUMS)
gen county_school_age_pop = school_age_pop if no_tract==1
bys county year4: egen county_total = max(county_school_age_pop)

* Step 1. sum tract areas
bys county year4: egen tract_sum = total(cond(no_tract==0, school_age_pop, .))

* Step 2. residual = county total – tracted total
gen residual_pop = county_total - tract_sum

* Step 3. assign that residual to the untracted row
replace school_age_pop = residual_pop if no_tract==1

* clean
tempfile type4
save `type4'
summ school_age_pop
restore


<<<<<<< HEAD
/*******************************************************************************
 ---- TYPE 3: Two or more untracted areas ----
*******************************************************************************/
=======
********************************************************************************
* ---- TYPE 3: Two or more untracted areas ----
********************************************************************************
>>>>>>> 2048fe8d597ea3108320bca498875b6ca4b82bba
preserve
keep if county_type == 3
summ school_age_pop
* Step 0. county totals (from NHGIS/IPUMS)
gen county_school_age_pop = school_age_pop if no_tract==1
bys county year4: egen county_total = max(county_school_age_pop)

* Step 1. total tracted population
bys county year4: egen tract_sum = total(cond(no_tract==0, school_age_pop, .))

* Step 2. residual population = county total – tracted total
bys county year4: gen residual_pop = county_total - tract_sum

* Step 3. average untracted spending (unweighted)
bys county year4: egen untr_pp_avg = mean(cond(no_tract==1, pp_exp_real, .))

* Step 4. pick one representative untracted row per county-year
gen keep_flag = 0
bys county year4 (tract70): replace keep_flag = 1 if no_tract==1 & keep_flag==0
keep if no_tract==0 | keep_flag==1

* Step 5. assign the averaged spending + residual population
replace pp_exp_real = untr_pp_avg if no_tract==1
replace school_age_pop = residual_pop if no_tract==1

* clean
*drop county_school_age_pop county_total tract_sum residual_pop untr_pp_avg keep_flag
tempfile type3
save `type3'
summ school_age_pop
restore
<<<<<<< HEAD
=======

********************************************************************************
* ---- Combine all types back together ----
********************************************************************************
drop if inlist(county_type,3,4)
*append using `type3'
append using `type4'
>>>>>>> 2048fe8d597ea3108320bca498875b6ca4b82bba

/*******************************************************************************
 ---- Combine all types back together ----
*******************************************************************************/
drop if inlist(county_type,3,4)
append using `type3'
append using `type4'
*keep if county_type == 1 // WARNING test do not keep
save tract_b4_collapse_fixed, replace



* 0) Build county-year totals of school_age_pop once
preserve
collapse (sum) school_age_pop, by(county year4)
tempfile totpop
save `totpop'
restore


preserve
collapse (mean) pp_exp_real [w = school_age_pop], by(county year4) // WARNING add weight back in
tempfile tracted
save `tracted', replace
restore


* 3) Stack the two views
use `tracted', clear


* 4) Merge total school-age population back in
merge m:1 county year4 using `totpop', nogen

* Now you have:
* - one row per county-year for tracted 
* - one row per county-year for untracted 
* - total county-year school_age_pop from the full data
save county_panel_temp2, replace


use county_panel_temp2,clear
duplicates tag county year4, gen(dup)
*** Rename collapsed variables for clarity
rename pp_exp_real county_exp   
gen state_fips = substr(county,1,2)
gen year_unified = year4 - 1

*** Save county-year panel temporarily
tempfile mytemp2
save `mytemp2'

*** Merge county names back into collapsed panel
use county_lookup
duplicates drop county,force
merge 1:m county using `mytemp2'
keep if _merge==3
drop _merge

*** Clean county names for consistency
replace county_name = lower(county_name)
gen county_name2 = regexr(county_name, "(County|Census|Parish|Borough|city|City).*", "")
drop county_name 
rename county_name2 county_name
replace county_name = trim(county_name)

*** Save final county-level per-pupil expenditure panel
gen interp = 0

save interp_c,replace








/*******************************************************************************
Use JJP reform table instead of Hanushek logic
*******************************************************************************/

*** Housekeeping
clear
set more off
cd "$SchoolSpending/data"
*** Load JJP reform mapping (first sheet assumed)
import excel using "$SchoolSpending/data/tabula-tabled2.xlsx", firstrow


rename CaseNameLegislationwithout case_name
rename Constitutionalityoffinancesys const
rename TypeofReform reform_type
rename FundingFormulaafterReform form_post
rename FundingFormulabeforeReform form_pre
rename Year reform_year
rename State state_name



* create a local with the number of rows
local N = _N  

forvalues i = 2/`N' {
    if missing(state_name[`i']) {
        replace state_name = state_name[`i'-1] in `i'
    }
    else {
        replace state_name = state_name[`i'] in `i'
    }
}

replace state_name = itrim(lower(strtrim(state_name)))
* replace line feeds with a space
replace state_name = subinstr(state_name, char(10), " ", .)
replace state_name = subinstr(state_name, char(13), " ", .)
* now clean up any double spaces
replace state_name = itrim(strtrim(state_name))

replace state_name = "massachusetts" if state_name == "massachuset ts"

drop if missing(case_name)
keep if const == "Overturned"
bysort state_name: keep if _n == 1

gen mfp_pre = "MFP" if regexm(form_pre, "MFP")
gen ep_pre  = "EP"  if regexm(form_pre, "EP")
gen le_pre  = "LE"  if regexm(form_pre, "LE")
gen sl_pre  = "SL"  if regexm(form_pre, "SL")

gen mfp_post = "MFP" if regexm(form_post, "MFP")
gen ep_post  = "EP"  if regexm(form_post, "EP")
gen le_post  = "LE"  if regexm(form_post, "LE")
gen sl_post  = "SL"  if regexm(form_post, "SL")

gen reform = 0
replace reform = 1 if regexm(reform_type, "Equity")
drop reform_type
label define reform_lbl 0 "Adequacy" 1 "Equity"
label values reform reform_lbl
label variable reform "School finance reform type"
gen treatment = 1

* Generate flags
gen mfp_flag = (mfp_post != "" & mfp_pre == "")
gen ep_flag  = (ep_post  != "" & ep_pre  == "")
gen le_flag  = (le_post  != "" & le_pre  == "")
gen sl_flag  = (sl_post  != "" & sl_pre  == "")

* Encode into a single numeric variable
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

import delimited using state_fips_master, clear
replace state_name = itrim(lower(strtrim(state_name)))

merge 1:m state_name using `temp'
drop _merge
tostring fips, gen(state_fips) format(%02.0f)

drop fips

*** Save final panel with JJP treatment
merge 1:m state_fips using interp_c
replace treatment = 0 if missing(treatment)
keep if _merge ==3
drop _merge
drop long_name sumlev region division state division_name region_name
keep state_fips reform_year reform_* year4 county_name county_exp county  treatment school_age_pop

save "$SchoolSpending/data/interp_c_treat", replace



use cnames, clear
rename county_code county
merge 1:m county using interp_c_treat
keep if _merge ==3
drop _merge
replace county_name = lower(county_name)
save interp_c_treat,replace


/*******************************************************************************
Include median family income
*******************************************************************************/
*** Housekeeping
clear

set more off

*** Import raw county income data
import delimited using "$SchoolSpending/data/county2.csv", varnames(1)

*** Rename column and drop junk rows
rename v2 median_family_income
drop in 3271/3279
drop if missing(county)

*** Clean county names and extract state abbreviation
gen county_name = regexr(county, "(County|Census|Parish|Borough|city|City).*", "")
gen state_abbr = ""
replace state_abbr = regexs(1) if regexm(county, " ([A-Za-z]+)$")

/*
replace state_abbr = "ND" if state_abbr == "Dakota"
replace state_abbr = "NC" if state_abbr == "Carolina"
replace state_abbr = "NH" if state_abbr == "Hampshire"
*/
*** Save as a temporary dataset
tempfile temp
save `temp'

*** Import master FIPS state crosswalk
import delimited using "$SchoolSpending/data/state_fips_master.csv", clear

*** Merge in the county income data by state abbreviation
merge 1:m state_abbr using `temp'
keep if _merge==3
drop _merge

*** Standardize state FIPS (zero-padded string) and handle duplicate counties
gen state_fips = string(fips, "%02.0f")
duplicates tag county_name state_fips, gen(dup_tag)
gen tag_county = strpos(county, "County") > 0

drop if regexm(county, "(?i)\bcensus\b")
drop if regexm(county, "(?i)\bcity\b") & county!= "Carson City, NV" ///
& county!= "St. Louis city, MO" 

replace county_name = "carson city" if county == "Carson City, NV"
replace county_name = "st. louis city" if county == "St. Louis city, MO"

keep county_name state_fips median_family_income

*** Truncate county name, standardize case, trim spaces
gen county_name2 = substr(county_name, 1, 25)
drop county_name
rename county_name2 county_name
replace county_name = lower(county_name)
replace county_name = trim(county_name)

*** Individual county-specific fixes
replace county_name = subinstr(county_name, "debaca", "de baca", .)
replace county_name = subinstr(county_name, "de kalb", "dekalb", .)
replace county_name = subinstr(county_name, "laplata", "la plata", .)
replace county_name = subinstr(county_name, "la porte", "laporte", .)
replace county_name = subinstr(county_name, "mc kean", "mckean", .)
replace county_name = subinstr(county_name, "o'brien", "o brien", .)
replace county_name = subinstr(county_name, ".", "", .)

duplicates tag county_name state_fips, gen(dup_tag) // No duplicates

*** Set working directory 
cd "$SchoolSpending/data"


*** Merge with county expenditure panel
merge 1:m county_name state_fips using interp_c_treat
keep if _merge==3
drop _merge


*** Save final cleaned dataset
save county_exp_final, replace
