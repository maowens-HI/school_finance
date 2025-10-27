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
* Phase I
********************************************************************************
do "`ProjectDir'/code/00_cx.do" // Build district panels
do "`ProjectDir'/code/01_tract.do" // Build tract panel

********************************************************************************
* Phase II - Repeats Phase I but with interpolation then restriction
********************************************************************************



********************************************************************************
* Phase III - Gets data into the format for first stage regressions
********************************************************************************



* --- 3. Analysis -------------------------------------------------------------------------



* --- 5. Wrap up --------------------------------------------------------------------------
local datetime2 = clock("$S_DATE $S_TIME", "DMYhms")
di "Runtime (hours): " %-12.2fc (`datetime2' - `datetime1')/(1000*60*60)
log close
