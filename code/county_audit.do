* housekeeping
cd "$SchoolSpending/data"
clear 
set more off

*==============================================================================
* STAGE 1: Raw INDFIN - unique counties by state
*==============================================================================

* INDIFN
use indfin_panel,clear
gen indfin_st = substr(GOVID, 1,2)
gen cty_indfin = substr(GOVID,4,3)

keep indfin_st cty_indfin
duplicates drop
* Create a count variable that shows how many counties per state
bysort indfin_st: egen indfin_counties = count(cty_indfin)
keep indfin_st indfin_counties
duplicates drop
save indfin_counties, replace
list


*==============================================================================
* STAGE 1: Raw F33 - unique counties by state
*==============================================================================

* F33
use f33_panel,clear
gen f33_st = substr(LEAID, 1,2)
rename county_id cty_f33

keep f33_st cty_f33
duplicates drop
* Create a count variable that shows how many counties per state
bysort f33_st: egen f33_counties = count(cty_f33)
keep f33_st f33_counties
duplicates drop
drop if inlist(f33_st, "N", "M", ".")
save f33_counties, replace
list

*==============================================================================
* STAGE 1: District Panel Tagged (Districts Before GRF Merge) (After 1:1 Filter)
*==============================================================================

* F33
use district_panel_tagged,clear
gen f33_st = substr(LEAID, 1,2)
rename county_id cty_f33

keep f33_st cty_f33
duplicates drop
* Create a count variable that shows how many counties per state
bysort f33_st: egen dist_tag_counties = count(cty_f33)
keep f33_st dist_tag_counties
duplicates drop
drop if inlist(f33_st, "N", "M", ".")
save 1_to_1_counties, replace
list

*==============================================================================
* STAGE 1: District Panel (After GRF Merge)
*==============================================================================

use dist_panel,clear
gen f33_st = substr(LEAID, 1,2)
rename county_id cty_f33

keep f33_st cty_f33
duplicates drop
* Create a count variable that shows how many counties per state
bysort f33_st: egen dist_counties = count(cty_f33)
keep f33_st dist_counties
duplicates drop
drop if inlist(f33_st, "N", "M", ".")
save dist_grf_counties, replace
list

*==============================================================================
* STAGE 2: Tract Panel 
*==============================================================================

use tract_panel,clear
gen f33_st = substr(LEAID, 1,2)
rename county_code cty_f33

keep f33_st cty_f33
duplicates drop
* Create a count variable that shows how many counties per state
bysort f33_st: egen tract_counties = count(cty_f33)
keep f33_st tract_counties
duplicates drop
drop if inlist(f33_st, "N", "M", ".")
save tract_counties, replace
list

*==============================================================================
* STAGE 4: Coutny Panel 
*==============================================================================

use county_panel,clear
gen f33_st = substr(county, 1,2)
rename county cty_f33

keep f33_st cty_f33
duplicates drop
* Create a count variable that shows how many counties per state
bysort f33_st: egen tract_counties = count(cty_f33)
keep f33_st tract_counties
duplicates drop
drop if inlist(f33_st, "N", "M", ".")
save county_counties, replace
list




*==============================================================================
* STAGE 5: Alternative Balance
*==============================================================================

use analysis_panel_bal, clear
gen f33_st = substr(county_id, 1,2)
rename county_id cty_f33

keep f33_st cty_f33
duplicates drop
* Create a count variable that shows how many counties per state
bysort f33_st: egen dist_counties = count(cty_f33)
keep f33_st dist_counties
duplicates drop
drop if inlist(f33_st, "N", "M", ".")
save alt_bal_counties, replace
list