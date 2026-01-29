/*==============================================================================
Project    : School Spending – County Quality Tagging
File       : 04_tag_county_quality.do
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
  - tract_panel_real.dta  (from 03_adjust_inflation.do)
      └─> Tract-year panel with pp_exp_real and good_tract flags
  - grf_id_tractlevel.dta
      └─> Tract-level metadata including no_tract indicator

OUTPUTS:
  - county_qual_flags.dta  ★ MAIN OUTPUT ★
      └─> County-year panel with quality flags:
          • county (5 chars: state+county FIPS)
          • good_county              (has complete 1967, 1970-1972 data)
          • good_county_6771         (has complete 1967, 1970-1971 data)
          • good_county_7072         (has complete 1970-1972 data)
          • good_county_1967/1970/1971/1972  (year-specific flags)
          • has_untracted            (county contains non-tracted areas)


DEPENDENCIES:
  • Requires: global SchoolSpending "C:\Users\...\path"
  • Requires: 03_adjust_inflation.do must run first (creates tract_panel_real.dta)
  • Stata packages: None (base Stata only)
  • Downstream: 05_create_county_panel.do uses good_county flags for sample restrictions

==============================================================================*/
*==============================================================*
* I) Load and clean tract panel
*==============================================================*

*--------------------------------------------------------------*
* A) Load tract panel and merge untracted flags
*--------------------------------------------------------------*

* 1)--------------------------------- Load inflation-adjusted tract panel
use tract_panel_real,clear

*** Rename county_code to county (already correctly defined in File 02)
rename county_code county


*==============================================================*
* II) Collapse to county level and tag quality
*==============================================================*

*--------------------------------------------------------------*
* A) Collapse tract-level quality flags to county level
*--------------------------------------------------------------*

* 1)--------------------------------- Aggregate using MIN (conservative approach)
* Weighting doesnt matter since we just care about good tags
preserve
collapse ///
         (min)  good_county              = good_tract ///
         (min)  good_county_6771         = good_tract_6771 ///
		 (min)  good_county_7072         = good_tract_7072 ///
         (min)  good_county_1967         = good_tract_1967 ///
         (min)  good_county_1970         = good_tract_1970 ///
         (min)  good_county_1971         = good_tract_1971 ///
         (min)  good_county_1972         = good_tract_1972, ///
         by(county)

* 2)--------------------------------- Clean and save county quality tags
gen state_fips = substr(county,1,2)
keep county good_county good_county_6771 good_county_7072 good_county_1967 ///
	good_county_1970 good_county_1971 good_county_1972

duplicates drop
drop if missing(county)
save county_qual_flags, replace // list of each county tagged

restore

preserve
use county_qual_flags,clear
keep if good_county_1970 == 1
restore