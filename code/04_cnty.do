/*==============================================================================
Project    : School Spending – County Quality Tagging
File       : 04_cnty.do
Purpose    : Identify counties with complete baseline spending data (1967, 1970-1972)
             and tag as "good" or "bad" for inclusion in event-study analysis.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-10-27
───────────────────────────────────────────────────────────────────────────────

WHAT THIS FILE DOES (Summary):
  • Constructs 5-digit county identifiers (state FIPS + county FIPS)
  • Collapses tract-level quality flags to county level using MAX logic
  • Tags counties as "good" if ALL their tracts link to good districts
  • Creates flags for different baseline periods (1967-1972, 1967+1970-1971, 1970-1972)
  • Flags counties with untracted areas (rural/non-Census-defined zones)

WHY THIS MATTERS (Workflow Context):
  This is Step 4 of the core pipeline. The event-study design requires BASELINE
  spending data (pre-reform years 1967-1972) to:
  - Construct spending quartiles (identifies which districts were initially poor/rich)
  - Test parallel trends assumption (pre-reform trends must be flat)
  - Control for differential trends by baseline characteristics
  
  Problem: Counties aggregate multiple tracts, and tracts link to districts with
  varying data quality. We need COUNTY-LEVEL flags to determine which counties
  are suitable for analysis.
  
  Decision Rule: A county is "good" only if ALL its tracts are linked to districts
  with complete baseline data. This conservative approach ensures clean comparisons.

INPUTS:
  - tracts_panel_real.dta  (from 03_infl.do)
      └─> Tract-year panel with pp_exp_real and good_tract flags
  - grf_id_tractlevel.dta
      └─> Tract-level metadata including no_tract indicator

OUTPUTS:
  - county_clean.dta  ★ MAIN OUTPUT ★
      └─> County-year panel with quality flags:
          • county (5 chars: state+county FIPS)
          • good_county              (has complete 1967, 1970-1972 data)
          • good_county_6771         (has complete 1967, 1970-1971 data)
          • good_county_7072         (has complete 1970-1972 data)
          • good_county_1967/1970/1971/1972  (year-specific flags)
          • has_untracted            (county contains non-tracted areas)

KEY ASSUMPTIONS & SENSITIVE STEPS:
  1. Aggregation Logic - MAX Rule:
     - good_county = MAX(good_tract) across all tracts in county
     - This means: county is "good" only if AT LEAST ONE tract is good
     - The logic is: good_county = 1 if all tracts in county have good_tract = 1
     - This is CONSERVATIVE: one bad tract → entire county flagged as bad
  
  2. Baseline Period Options:
     - Main specification: 1967, 1970, 1971, 1972 (4 years)
     - Alternative 1: 1967, 1970, 1971 (3 years, if 1972 problematic)
     - Alternative 2: 1970, 1971, 1972 (3 years, if 1967 problematic)
     - Allows for experimentation with different baseline definitions

  3. Quality vs Coverage Trade-off:
     - Stricter baseline requirements → fewer "good" counties → smaller sample
     - But cleaner identification and better baseline controls
     - Typical result: ~75% of counties flagged as good with 1967+1970-1972 requirement

DEPENDENCIES:
  • Requires: global SchoolSpending "C:\Users\...\path"
  • Requires: 03_infl.do must run first (creates tracts_panel_real.dta)
  • Stata packages: None (base Stata only)
  • Downstream: 05_interp_d.do uses good_county flags for sample restrictions

VALIDATION CHECKS TO RUN:
  - County construction: assert length(county) == 5
  - Untracted share: summ has_untracted (mean = share of mixed counties)
  - Good county share: tab good_county (shows % counties with complete baseline)
  - Cross-check: compare good_county vs good_county_6771 vs good_county_7072
  - Geographic coverage: codebook county (should have ~3,100 counties)
==============================================================================*/
*****************************************************************************
*Build a list of good and bad counties
*****************************************************************************
*****************************************************************************
*A) Cleaning
*****************************************************************************
use tracts_panel_real,clear

*** Rename and construct county identifiers
rename county county_name
gen str5 county = state_fips + coc70

tempfile no_tract_fix
save `no_tract_fix',replace

use grf_id_tractlevel,clear
keep tract70 no_tract
duplicates drop tract70,force
merge 1:m tract70 using `no_tract_fix'

* 1. For each county, check if any of its tracts are untracted
bys county: egen has_untracted = max(no_tract)

* 2. Tabulate at the county level
bys county: keep if _n==1
tab has_untracted

* 3. Optionally, calculate share (explicitly)
summ has_untracted
display "Share of counties with untracted areas: " r(mean)
display "Share of counties fully tracted: " 1 - r(mean)



*****************************************************************************
*B) Collapse into counties
*****************************************************************************
* Weighting doesnt matter since we just care about good tags
preserve
collapse ///
         (max)  good_county              = good_tract ///
         (max)  good_county_6771         = good_tract_6771 ///
		 (max)  good_county_7072         = good_tract_7072 ///
         (max)  good_county_1967         = good_tract_1967 ///
         (max)  good_county_1970         = good_tract_1970 ///
         (max)  good_county_1971         = good_tract_1971 ///
         (max)  good_county_1972         = good_tract_1972, ///
         by(county year4)

		 
*Clean collapse 
gen state_fips = substr(county,1,2)
keep county good_county good_county_6771 good_county_7072 good_county_1967 ///
	good_county_1970 good_county_1971 good_county_1972

duplicates drop
drop if missing(county)
save county_clean, replace // list of each county tagged

restore

use county_clean,clear
