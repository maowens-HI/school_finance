/*==============================================================================
Project    : School Spending – County Quality Tagging
File       : 03_tag_county_quality.do
Purpose    : V2 VERSION - Identify counties with complete baseline spending data
             (1967, 1970-1972) and tag as "good" or "bad" for event-study analysis.
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : 2025-01-21
───────────────────────────────────────────────────────────────────────────────

V2 CHANGES FROM ORIGINAL (04_tag_county_quality.do):
  1. Uses tract_panel.dta directly (no inflation adjustment required)
     - Inflation adjustment moved to later in pipeline (county collapse step)
  2. Removed unnecessary preserve/restore at end of file
  3. Simplified flow: single collapse operation

WHY INFLATION CAN WAIT:
  This file only needs quality FLAGS (good_tract_*), not actual spending values.
  Inflation adjustment is only needed when we actually use pp_exp for analysis,
  which happens at the county aggregation stage (step 05).

WHAT THIS FILE DOES (Summary):
  - Loads tract panel with quality flags from step 02
  - Collapses tract-level quality flags to county level using MIN logic
  - Tags counties as "good" if ALL their tracts link to good districts
  - Creates flags for different baseline periods

WHY THIS MATTERS (Workflow Context):
  The event-study design requires BASELINE spending data (pre-reform years
  1967-1972) to:
  - Construct spending quartiles (identifies which districts were initially poor/rich)
  - Test parallel trends assumption (pre-reform trends must be flat)
  - Control for differential trends by baseline characteristics

  Decision Rule: A county is "good" only if ALL its tracts are linked to districts
  with complete baseline data. This conservative approach ensures clean comparisons.

INPUTS:
  - $SchoolSpending/data/tract_panel.dta  (from 02_build_tract_panel_v2.do)
      └─> Tract-year panel with good_tract flags and county_code

OUTPUTS:
  - county_qual_flags.dta  ★ MAIN OUTPUT ★
      └─> County-level quality flags:
          • county (5 chars: state+county FIPS)
          • good_county              (has complete 1967, 1970-1972 data)
          • good_county_6771         (has complete 1967, 1970-1971 data)
          • good_county_7072         (has complete 1970-1972 data)
          • good_county_1967/1970/1971/1972  (year-specific flags)

DEPENDENCIES:
  • Requires: global SchoolSpending "C:\Users\...\path"
  • Requires: 02_build_tract_panel_v2.do must run first
  • Downstream: Used for sample restrictions in analysis
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*==============================================================*
* I) Load tract panel and collapse to county-level quality flags
*==============================================================*

use "tract_panel.dta", clear

* Rename for consistency with downstream code
rename county_code county

* Collapse tract-level quality flags to county level using MIN
* (A county is "good" only if ALL its tracts have good data)
collapse ///
    (min) good_county      = good_tract      ///
    (min) good_county_6771 = good_tract_6771 ///
    (min) good_county_7072 = good_tract_7072 ///
    (min) good_county_1967 = good_tract_1967 ///
    (min) good_county_1970 = good_tract_1970 ///
    (min) good_county_1971 = good_tract_1971 ///
    (min) good_county_1972 = good_tract_1972, ///
    by(county)

* Clean
drop if missing(county)

* Save county quality tags
save county_qual_flags, replace

* Summary
di as result "✓ County quality tagging complete: county_qual_flags.dta"
di as result "  Total counties: " _N
count if good_county == 1
di as result "  Good counties (complete 1967, 1970-1972): " r(N)
count if good_county_1972 == 1
di as result "  Good counties (complete 1972 only): " r(N)
