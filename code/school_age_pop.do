
clear all
set more off
cd "$florida/data"

* 1)--------------------------------- Load county-level NHGIS enrollment file
use county_age,clear
	
	
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
*gen school_age_pop = c04003  + c04005 + c04007  + c04009 
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
keep county_code school_age_pop
gen state_fip = substr(county_code,1,2)
keep if state_fip == "12"
gen countyfip3 = substr(county_code,3,5)
drop state_fip county_code
save county_school_pop,replace

merge 1:m countyfip3 using sch_county_count_2000
keep if _merge == 3
save county_2000_fin,replace

use county_school_pop,clear 
merge 1:m countyfip3 using sch_county_count_1990
keep if _merge == 3
save county_1990_fin,replace
