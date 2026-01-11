# Data Processing Pipeline

This document outlines the data construction process for the School Finance Reform analysis, describing how raw district-level finance data is transformed into the county-year panel used for event-study regressions.

## Overview

The pipeline solves a core challenge: linking school district spending data from different eras (1967-2019) that use incompatible identifier systems, then aggregating to counties for analysis.

```
Raw Data Sources               Pipeline                    Final Output
─────────────────              ────────                    ────────────
F-33 (NCES, 1992-2019)    ┐
                          ├──> 01_build_district_panel.do
INDFIN (1967-1991)        ┘           │
                                      ▼
GRF 1969                  ───> 02_build_tract_panel.do
                                      │
                                      ▼
FRED CPI-U                ───> 03_adjust_inflation.do
                                      │
                                      ▼
                              04_tag_county_quality.do
                                      │
                                      ▼
Enrollment Data           ┐
                          ├──> 05_create_county_panel.do ──> interp_d.dta
Reform Treatment Data     ┘                                   (Analysis File)
```

---

## Step 1: Building the District Panel & ID Crosswalks

**File:** `01_build_district_panel.do`

### Data Sources

| Source | Years | ID System | Coverage |
|--------|-------|-----------|----------|
| **F-33 (NCES)** | 1992-2019 | LEAID (7-char) | ~15,000 districts/year |
| **INDFIN** | 1967, 1970-1991 | GOVID (9-char) | Historical finance data |
| **GRF 1969** | 1969 snapshot | LEAID + tract codes | District-to-tract linkage |

### The LEAID-GOVID Crosswalk Problem

The two major data sources use different identifier systems:

- **LEAID** (Local Education Agency ID): `SSDDDDD` - 2-digit state FIPS + 5-digit district code
- **GOVID** (Government ID): `SS5CCCDDD` - 2-digit state + type code + 3-digit county + 3-digit district

**Solution:** Extract both IDs from F-33 CENSUSID field and create 1:1 crosswalk.

**Key Restriction:** Only 1:1 LEAID↔GOVID matches are retained (~51% of raw mappings):

| Relationship Type | Count | Percent | Action |
|-------------------|-------|---------|--------|
| 1:1 | 14,466 | 51.2% | **Kept** |
| 1:M (LEAID→GOVID) | 3,364 | 11.9% | Dropped |
| 1:M (GOVID→LEAID) | 6,931 | 24.5% | Dropped |
| M:M | 3,487 | 12.3% | Dropped |

Many-to-many relationships arise from district consolidations, boundary changes, and charter school classifications. Manual authentication would require tracing 10,000+ individual ID histories.

### Baseline Quality Flags

Districts are tagged based on spending data availability in baseline years:

```
good_govid_baseline = 1 if district has non-missing pp_exp in ALL of:
                          1967, 1970, 1971, 1972
```

Alternative baseline periods are also tracked:
- `good_govid_6771`: 1967, 1970, 1971
- `good_govid_7072`: 1970, 1971, 1972

**Output:** `f33_indfin_grf_canon.dta` - Unified district-year panel (1967-2019) with quality flags

---

## Step 2: Linking Districts to Census Tracts

**File:** `02_build_tract_panel.do`

### The Geographic Linkage Challenge

Finance data exists at the **district** level, but we need **county** aggregates. The 1969 Geographic Reference File (GRF) provides the bridge:

```
GRF Structure: Block/ED → Tract → County
                 ↓
           School District Assignment
```

### Tract Identifier Construction

The 11-character `tract70` identifier encodes full geographic location:

```
tract70 = SS + CCC + BBBB + TT
          │    │     │      │
          │    │     │      └── Tract suffix code (2 digits)
          │    │     └── Basic tract code (4 digits)
          │    └── County FIPS (3 digits)
          └── State FIPS (2 digits)

Example: 01001000100 = Alabama (01) + Autauga County (001) + Tract 0001 + Suffix 00
```

### One LEAID Per Tract Assignment

**Problem:** Multiple districts can serve the same tract (e.g., separate elementary and secondary districts).

**Solution:** Assign single "dominant" LEAID based on allocated population:

```stata
* For each tract-district type combination:
gsort tract70 sdtc -alloc_pop LEAID
by tract70 sdtc: keep if _n==1    // Keep highest-population LEAID
```

### Special Geographies Excluded

- **Tract suffix 99:** Non-geographic areas (ships, etc.)
- **Tract suffix 70-98:** Tract revisions/slivers
- **Basic tract 9400-9499:** Native American lands
- **Basic tract 9800-9899:** Administrative codes
- **Basic tract 9900-9998:** Water bodies

### Quality Flag Propagation

Tract quality is determined by the quality of its assigned district:

```
good_tract = 1 if assigned LEAID has good_govid_baseline = 1
```

A tract is tagged "bad" if ANY of its serving districts lacks baseline data (conservative approach using MIN aggregation).

**Output:** `tracts_panel_canon.dta` - Tract-year panel with spending and quality flags

---

## Step 3: Inflation Adjustment

**File:** `03_adjust_inflation.do`

### State-Specific Fiscal Year CPI

States use different fiscal year calendars:
- New York: April - March
- California: July - June
- Federal: October - September

**Solution:** Calculate CPI-U averages specific to each state's 12-month fiscal period:

```stata
* fy_end_year is the calendar year when the fiscal year ends
gen fy_end_year = cal_y + (cal_m >= fy_start_month)

* Average CPI over each state's fiscal year months
collapse (mean) cpi_fy_avg, by(state_fips fy_end_year)
```

### Conversion to 2000 Dollars

All spending is normalized to year-2000 purchasing power:

```stata
gen inflator_2000 = base2000 / cpi_fy_avg    // base2000 = CPI in year 2000
gen pp_exp_real = pp_exp * inflator_2000
```

**Output:** `tracts_panel_real.dta` - Tract-year panel with real spending (2000$)

---

## Step 4: County Quality Tagging

**File:** `04_tag_county_quality.do`

### Aggregating Quality to Counties

Counties are tagged as "good" only if ALL their constituent tracts are good:

```stata
collapse (min) good_county = good_tract, by(county)
```

This conservative rule ensures counties in the analysis sample have complete baseline data for constructing spending quartiles and testing parallel trends.

**Output:** `county_clean.dta` - County-level quality flags

---

## Step 5: District Interpolation & County Collapse

**File:** `05_create_county_panel.do`

### Interpolation of Missing Years

District spending is linearly interpolated for gaps ≤ 3 years:

```stata
bysort LEAID_num: gen gap_next = year[_n+1] - year
gen too_far = gap_next > 3    // Don't interpolate large gaps

bys LEAID_num: ipolate pp_exp year4 if too_far == 0, gen(exp2)
```

### Handling Untracted Areas

Some counties contain "untracted" rural areas without Census tract codes:

| County Type | Description | Handling |
|-------------|-------------|----------|
| Type 1 | All tracted | Standard collapse |
| Type 2 | Single untracted only | Use county enrollment directly |
| Type 3 | ≥2 untracted areas | Average untracted spending, assign residual population |
| Type 4 | 1 untracted + tracted | Assign residual population to untracted area |

### Weighted Collapse to Counties

Tracts are aggregated to counties using enrollment-weighted averages:

```stata
collapse (mean) pp_exp_real [w = school_age_pop], by(county year4)
```

School-age population (ages 5-17) from 1970 Census serves as the weighting variable.

### Reform Treatment Assignment

Court-ordered reform data from Jackson, Johnson, and Persico (2016) is merged:

- `reform_year`: Year court overturned state finance system
- `treatment`: 1 if state experienced reform, 0 otherwise
- `reform_eq`: 1 if equity reform, 0 if adequacy reform

**Output:** `interp_d.dta` - Final county-year analysis panel

---

## Sample Restrictions Summary

| Stage | Restriction | Observations Affected |
|-------|-------------|----------------------|
| Crosswalk | Keep only 1:1 LEAID-GOVID matches | ~49% of raw mappings dropped |
| GRF | Drop special geographies (water, Native lands, revisions) | ~5% of GRF records |
| Baseline | Require spending in 1967, 1970, 1971, 1972 | Districts without all 4 years flagged |
| Tract Assignment | Assign one LEAID per tract (max population) | Multi-district tracts simplified |
| Quality Propagation | County good only if ALL tracts good | Counties with any bad tract flagged |
| Interpolation | Max gap of 3 years | Larger gaps not interpolated |
| Event Window | Balance: require data for years -5 to +17 relative to reform | ~24% of counties dropped in balanced sample |

---

## Key Output Variables

| Variable | Description | Source |
|----------|-------------|--------|
| `county` | 5-character FIPS (state + county) | Constructed |
| `year4` | Fiscal year end year | Original data |
| `pp_exp_real` | Per-pupil expenditure (2000$, enrollment-weighted) | Constructed |
| `school_age_pop` | Ages 5-17 population (weighting variable) | 1970 Census |
| `reform_year` | Year of court-ordered reform | JJP 2016 |
| `good_county` | =1 if complete baseline data | Constructed |
| `treatment` | =1 if state had reform | JJP 2016 |

---

## Data Flow Diagram

```
                    ┌─────────────────┐
                    │   F-33 (NCES)   │ 1992-2019, LEAID
                    │   15k districts │
                    └────────┬────────┘
                             │
                    ┌────────▼────────┐
                    │     INDFIN      │ 1967-1991, GOVID
                    │   Historical    │
                    └────────┬────────┘
                             │
              ┌──────────────▼──────────────┐
              │   1:1 LEAID-GOVID Crosswalk │ 51% retained
              │   (14,466 districts)        │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │  District-Year Panel        │
              │  with quality flags         │
              └──────────────┬──────────────┘
                             │
                    ┌────────▼────────┐
                    │    GRF 1969     │ District-to-tract link
                    │  (population)   │
                    └────────┬────────┘
                             │
              ┌──────────────▼──────────────┐
              │   Tract-Year Panel          │ 1 LEAID per tract
              │   (spending expanded)       │
              └──────────────┬──────────────┘
                             │
                    ┌────────▼────────┐
                    │   FRED CPI-U    │ Inflation adjustment
                    │  (state fiscal) │
                    └────────┬────────┘
                             │
              ┌──────────────▼──────────────┐
              │   Real Tract Panel          │ 2000 dollars
              │   (quality tagged)          │
              └──────────────┬──────────────┘
                             │
              ┌──────────────▼──────────────┐
              │ County-Year Panel           │ Enrollment-weighted
              │ (interpolated, collapsed)   │ collapse
              └──────────────┬──────────────┘
                             │
                    ┌────────▼────────┐
                    │  JJP Reform     │ Treatment assignment
                    │  (1976-2006)    │
                    └────────┬────────┘
                             │
              ┌──────────────▼──────────────┐
              │     interp_d.dta            │
              │   FINAL ANALYSIS FILE       │
              │  ~50 years × ~3,000 counties│
              └─────────────────────────────┘
```
