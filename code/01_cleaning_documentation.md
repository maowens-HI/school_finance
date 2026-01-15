# Cleaning Documentation

## Data Sources

There are three primary data sources from which we construct our initial district level panel.

**1. NCES F-33 Finance Survey (1992-2019)**
The first is from the National Center of Education Statistics (NCES) Common Core of Data (CCD) Finance Survey (F-33). This contains spending data from 1992 onwards.

**2. Census INDFIN (1967, 1970-1991)**
The second is Census INDFIN. This contains spending data for 1967 and 1970-1991 (note: 1968 and 1969 are unavailable).

**3. Geographic Reference File (GRF 1969-70)**
The third is the 1969-70 Geographic Reference file (GRF). This links school districts to Census tracts.

---

## Panel Construction Overview

I first construct two panels:
- `indfin_panel.dta`
- `f33_panel.dta`

I then construct a district ID crosswalk called `f33_id.dta`. This crosswalk, which is constructed out of the same data used to create f33_panel, is needed to link the indfin_panel to the f33_panel. indfin_panel and f33_panel use two different ID systems. Luckily NCES provides both sets of IDs in the F-33 data. f33_panel uses Local Education Agency ID (LEAID) and INDFIN uses the Census of Governments ID (GOVID).

### Linking Logic

There are two things that must happen to form our desired dataset. We must link INDFIN to F-33 and we must link the panel formed out of those two to the GRF.

```
F33 (GOVID) → INDFIN = district_panel

district_panel (LEAID) → GRF = f33_indfin_grf_canon
```

This relationship implies that:
- A district must be dropped if it does not have a LEAID allocated to it; it could not link to the GRF data.

Now that we have gotten this out of the way we can go into specifics.

---

## Section I: Building the F-33 Panel (1992-2019)

### Step 1: Import SAS Files
The F-33 data comes as yearly SAS7BDAT files. Each file is converted to Stata .dta format.

### Step 2: Standardize Variables
Each yearly file has slightly different variable names for county. The code handles this:
- `FIPSCO` → `county_id`
- `CONUM` → `county_id`

County codes are standardized to 3 digits by taking the last 3 characters.

### Step 3: Append Years
All yearly files are appended into a single panel.

### Step 4: Reconstruct Full FIPS
After appending, the full 5-digit county FIPS is reconstructed by combining:
- State FIPS (first 2 digits of LEAID)
- 3-digit county code

### Step 5: Clean and Calculate Per-Pupil Expenditure
- **Flag anomalies**: Records with negative population (`bad_pop`) or negative expenditure (`bad_exp`) are flagged and dropped
- **Calculate spending**: `pp_exp = (TOTALEXP/1000) / V33` where V33 is enrollment
- **Extract GOVID**: The 9-digit GOVID is extracted from the 14-digit CENSUSID

**Output**: `f33_panel.dta`

---

## Section II: Building the INDFIN Panel (1967-1991)

### Step 1: Define Year Range
Years processed: 67, 70, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91

Note: 1968 and 1969 are skipped (data unavailable).

### Step 2: Filter to School Districts
Each yearly file is filtered to keep only school districts (`typecode == 5`).

### Step 3: Append Years
All cleaned yearly files are stacked into a single panel.

### Step 4: Create GOVID and Calculate Spending
- **Create GOVID**: Convert numeric ID to 9-character string with leading zeros
- **Calculate spending**: `pp_exp = totalexpenditure / population`

**Output**: `indfin_panel.dta`

---

## Section III: Building the ID Crosswalk

### Purpose
The F-33 data contains both LEAID and CENSUSID (which contains GOVID). This allows us to build a crosswalk linking the two ID systems.

### Step 1: Extract ID Pairs
From all F-33 yearly files, extract unique LEAID-GOVID pairs.

### Step 2: Classify Relationship Types
For each LEAID-GOVID pair, determine the relationship:

| rel_type | Description | Frequency | Percent |
|----------|-------------|-----------|---------|
| 1 | 1:1 | 14,466 | 51.21% |
| 2 | 1:M (LEAID→GOVID) | 3,364 | 11.91% |
| 3 | 1:M (GOVID→LEAID) | 6,931 | 24.54% |
| 4 | M:M | 3,487 | 12.34% |

### Step 3: Keep Only 1:1 Matches
**Critical Decision**: Only 1:1 matches are retained (51.21% of pairs).

**Rationale**: Authenticating 1:M and M:M relationships would require manual tracing of 10,000+ ID lineages. Some of these may be charter schools or administrative IDs. For simplicity, we use only verified 1:1 matches.

**Output**: `f33_id.dta` (crosswalk), `f33_1to1_map.dta` (strict 1:1 mapping)

---

## Section IV: Processing the Geographic Reference File (GRF)

### Purpose
The GRF links school districts (via LEAID) to Census tracts. This is essential for connecting school spending to geographic areas.

### Step 1: Read Fixed-Width ASCII File
The GRF is a fixed-width file with precise column positions for each field. Key fields include:
- `stc70` (cols 1-2): 1970 State code
- `coc70` (cols 5-7): 1970 County code
- `btc` (cols 77-80): Basic tract code
- `tsc` (cols 81-82): Tract suffix code
- `sdc` (cols 109-113): School district code
- `popc` (cols 101-108): Population count

### Step 2: Handle Missing Tract Codes
- Records without tract codes are flagged (`no_tract = 1`)
- Missing `btc` treated as 0000
- Missing `tsc` treated as 00

### Step 3: Drop Special Geographic Areas
The following non-standard areas are dropped:

| Code Range | Description |
|------------|-------------|
| `tsc == 99` | Special areas (ships, etc.) |
| `tsc 70-98` | Tract revisions (slivers) |
| `btc >= 9500` | Various special codes |
| `btc 9400-9499` | Native American/Alaska Native lands |
| `btc 9800-9899` | Administrative codes |
| `btc 9900-9998` | Water bodies |

### Step 4: Construct Geographic Identifiers
- **tract70** (11 chars): `state(2) + county(3) + btc(4) + tsc(2)`
- **gisjoin2** (13 chars): GIS-compatible format with separator zeros
- **LEAID** (7 chars): `state(2) + sdc(5)`

### Step 5: Save GRF ID Files
- `grf_id_tractlevel.dta`: Tract-level IDs with county codes
- `sdtc.dta`: School district type codes
- `grf_id.dta`: Master list of all unique LEAIDs in the GRF

---

## Section V: Creating Quality Flags

### Purpose
For event-study analysis, we need districts with complete spending data in all baseline years (1967, 1970, 1971, 1972). Quality flags identify which districts meet this criterion.

### Baseline Year Definitions

| Flag | Years Required |
|------|----------------|
| `good_govid_baseline` | 1967, 1970, 1971, 1972 (all 4) |
| `good_govid_baseline_6771` | 1967, 1970, 1971 (all 3) |
| `good_govid_baseline_7072` | 1970, 1971, 1972 (all 3) |

### Step 1: Count Baseline Years Present
For each GOVID, count how many baseline years have non-missing spending data.

### Step 2: Create Binary Flags
- `good_govid_baseline = 1` if district has spending in all 4 baseline years
- `good_govid_YYYY = 1` if district has spending in that specific year

### Step 3: Tag Individual Years
Separate flags for each baseline year:
- `good_govid_1967`
- `good_govid_1970`
- `good_govid_1971`
- `good_govid_1972`

**Output**: `govtag` (tempfile with all quality flags by GOVID)

---

## Section VI: Building the Unified District Panel

### Step 1: Map INDFIN to LEAID via Crosswalk
Merge the quality-tagged GOVIDs with the 1:1 crosswalk to assign LEAIDs.

**Handling Unmapped Districts**:
- `mapped_1to1 = 1`: GOVID successfully linked to LEAID
- `fail_unmapped = 1`: GOVID had no 1:1 LEAID mapping (excluded)

Districts without a valid LEAID are dropped because they cannot link to the GRF.

### Step 2: Propagate County IDs from F-33
Extract county_id from the F-33 panel and merge it into the crosswalk. For districts with multiple county associations (rare boundary changes), the most common county is kept.

### Step 3: Merge Tags to INDFIN Panel
Spread quality indicators across all years of data for each district, creating a panel where every district-year observation is properly tagged.

**Output**: `indfin_panel_tagged.dta`

### Step 4: Merge F-33 and INDFIN
1. Use the 1:1 map to match F-33 records to valid LEAIDs
2. Append the tagged INDFIN panel
3. Propagate quality flags across all years within each district

**Output**: `district_panel_tagged.dta`

### Step 5: Merge with GRF
Final merge with the GRF master ID list. Only districts present in both:
- The combined F-33/INDFIN panel, AND
- The 1969 GRF

are retained.

**Output**: `f33_indfin_grf_canon.dta`

---

## Final Output Schema

### `f33_indfin_grf_canon.dta`

| Variable | Description |
|----------|-------------|
| `LEAID` | 7-char NCES Local Education Agency ID |
| `GOVID` | 9-char Census of Governments ID |
| `county_id` | 5-char FIPS county code |
| `year4` | 4-digit year |
| `pp_exp` | Per-pupil expenditure |
| `enrollment` | Student enrollment |
| `level` | School level code |
| `good_govid_baseline` | Has spending in all baseline years (1967, 70-72) |
| `good_govid_baseline_6771` | Has spending in 1967, 1970, 1971 |
| `good_govid_baseline_7072` | Has spending in 1970, 1971, 1972 |
| `good_govid_1967` | Has spending in 1967 |
| `good_govid_1970` | Has spending in 1970 |
| `good_govid_1971` | Has spending in 1971 |
| `good_govid_1972` | Has spending in 1972 |

---

## Data Loss Summary

### Records Dropped at Each Stage

1. **F-33 Panel**: Drop records with negative population or expenditure
2. **Crosswalk**: ~49% of LEAID-GOVID pairs dropped (non-1:1 relationships)
3. **GRF Special Areas**: Drop water bodies, Native lands, administrative codes, tract revisions
4. **Final Merge**: Drop districts not present in GRF

### Why Districts Are Dropped

| Reason | Implication |
|--------|-------------|
| No LEAID | Cannot link to GRF/Census tracts |
| Non-1:1 mapping | Ambiguous ID relationship |
| Not in GRF | Cannot assign to geographic area |
| Missing baseline spending | Cannot create baseline quartiles |

---

## Validation Checklist

After running this script, verify:

```stata
* Check crosswalk uniqueness
use f33_1to1_map, clear
isid LEAID

* Check final panel uniqueness
use f33_indfin_grf_canon, clear
isid LEAID year4

* Check baseline flag distribution
tab good_govid_baseline

* Check year coverage
tab year4

* Check missing spending
count if missing(pp_exp)
```

---

## Downstream Usage

This file (`f33_indfin_grf_canon.dta`) is the input for:
- `02_build_tract_panel.do`: Links districts to Census tracts
- `05_create_county_panel.do`: Interpolates and collapses to county level
