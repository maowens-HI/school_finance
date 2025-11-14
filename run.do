/****************************************************************************************
* MASTER SCRIPT: run.do
* PROJECT: School Spending Reforms (Replication of JJP 2016)
* AUTHOR: Myles Owens
* PURPOSE:
*   - Run entire workflow from raw data → cleaned panels → analysis → outputs
****************************************************************************************/

* --- 0. Define project root ---
* Change global to where the share_code file is located on your device
global SchoolSpending "C:/Users/maowens/OneDrive - Stanford/Documents/share_code"
local ProjectDir "$SchoolSpending"
cd "`ProjectDir'"


cap assert !mi("`ProjectDir'")
if _rc {
    noi di as error "Error: must define global SchoolSpending in run.do"
    error 9
}

* --- 1. Initialize environment -----------------------------------------------------------
local datetime1 = clock("$S_DATE $S_TIME", "DMYhms")
clear all
set more off

cap mkdir "`ProjectDir'/logs"
cap log close
local logdate : di %tcCCYY.NN.DD!_HH.MM.SS `datetime1'
local logfile "`ProjectDir'/logs/`logdate'.log.txt"
log using "`logfile'", text


* --- 2. Build datasets -------------------------------------------------------------------


********************************************************************************
* Phase I: Build District and Tract Panels
********************************************************************************
do "`ProjectDir'/code/01_build_district_panel.do"  // Build district panels & ID crosswalks
do "`ProjectDir'/code/02_build_tract_panel.do"     // Build tract panel from GRF
do "`ProjectDir'/code/03_adjust_inflation.do"      // Adjust tract spending for inflation
do "`ProjectDir'/code/04_tag_county_quality.do"    // Tag counties as good/bad
do "`ProjectDir'/code/05_create_county_panel.do"   // Interpolate districts & create county panel

********************************************************************************
* Phase II: Analysis (add analysis scripts here)
********************************************************************************



* --- 3. Analysis -------------------------------------------------------------------------



* --- 5. Wrap up --------------------------------------------------------------------------
local datetime2 = clock("$S_DATE $S_TIME", "DMYhms")
di "Runtime (hours): " %-12.2fc (`datetime2' - `datetime1')/(1000*60*60)
log close
