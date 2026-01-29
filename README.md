# **Partial Replication of Jackson, Johnson, and Persico (2016)**

### **Overview**
This repository supports a partial replication and extension of *“The Effects of School Spending on Educational and Economic Outcomes: Evidence from School Finance Reforms”* by **C. Kirabo Jackson, Rucker C. Johnson, and Claudia Persico (2016, QJE)**. The original study examines how increases in school spending, driven by exogenous timing of **court-ordered School Finance Reforms (SFRs)**, affect long-run educational attainment and adult labor market outcomes, particularly among children from low-income families.

Our work reconstructs the **district-level finance panel (F-33 and INDFIN)** used in the paper and extends it to county geographies to enable compatibility with proprietary Census data. This involves reprocessing the **1969 GRF (Geographic Reference File)** to link school districts with Census tracts and counties, addressing non-tract areas, and implementing aggregation logic for counties with both tract and non-tract zones.

---

### **Relation to the Original Paper**
The original JJP (2016) paper and its Online Appendix describe the following key data and methods:

- **Data Sources**:
  - *INDFIN Historical Database* (FY 1967,1969–1991) — standardized local government finances including school districts.
  - *Common COre of Data (CCD) NCES F-33 Finance Survey* (post-1992 annual continuation).
  - *1969–70 School District Geographic Reference File (GRF)* for linking Census tracts to pre-reform district geographies.

- **Identification Strategy**:
  - Court-ordered **School Finance Reforms (SFRs)** serve as exogenous shocks.
  - The number of **years of exposure** to initial SFR is the treatment variable.
  - Event-study and 2SLS models estimate causal impacts on spending and individual outcomes.
  - Data on court rulings comes from a preceding NBER working paper: https://www.nber.org/papers/w20118


Specifically, we aim to:
1. Develop crosswalks linking **F-33 (District) ↔ INDFIN (District) ↔ Tract (GRF) ↔ County (GRF)** identifiers.
2. Reconstruct consistent annual per-pupil spending at the county level.
3. Use this data to estimate event studies akin to figure 1 JJP 2016.
4. Extend the analysis with **jackknife regressions** to identify which counties experienced the largest spending increases from school finance reforms akin to figure 2 in JJP 2016.

---

### **Repository Structure**
```
school_finance/
├── README.md                          # Project documentation
├── CLAUDE.md                          # AI assistant guide
├── run.do                             # Master pipeline runner
├── data/                              # Data files (generated and raw)
│   ├── raw/                           # Source files: F-33, INDFIN, GRF, NHGIS, etc.
│   ├── dist_panel.dta                 # District-year panel with quality flags
│   ├── tract_panel.dta                # Tract-year panel with spending
│   ├── county_qual_flags.dta          # County-level quality flags
│   ├── county_panel.dta               # County-year panel with reform treatment
│   ├── analysis_panel_bal.dta         # Balanced analysis panel (lexp_ma_strict)
│   └── analysis_panel_bal_alt.dta     # Alternative balanced panel (lexp)
├── output/                            # Graphs and tables
└── code/                              # All Stata scripts
    ├── 01_build_district_panel.do     # Build district panels & ID crosswalks
    ├── 02_build_tract_panel_v2.do     # Build tract panel from GRF
    ├── 03_tag_county_quality.do       # Tag counties as good/bad (baseline data)
    ├── 05_create_county_panel.do      # Interpolate districts & create county panel
    ├── 06_build_jjp_final.do          # Build balanced analysis panel (lexp_ma_strict)
    ├── 06_jjp_alt.do                  # Build alternative balanced panel (lexp)
    ├── 07_figure1_event_study.do      # Figure 1 event-study regressions
    └── 08_figure2_event_study.do      # Figure 2 heterogeneity analysis
```

**Pipeline Organization:**
- **Core Pipeline (01–05):** Sequential data construction and preparation
  - 01: Build district panels & ID crosswalks
  - 02: Build tract panel from GRF
  - 03: Tag county quality (baseline data completeness)
  - 05: Interpolate districts, adjust for inflation, create county panel
- **Analysis Panel Construction (06):** Build balanced analysis datasets
  - 06_jjp_alt: Balance on `lexp` (alternative, includes more counties)
  - 06_build_jjp_final: Balance on `lexp_ma_strict` (13-year rolling mean)
- **Event-Study Analysis (07–08):** Main regressions and figures
  - 07: Figure 1 event-study regressions by baseline spending quartile
  - 08: Figure 2 heterogeneity analysis (High vs Low predicted spending, jackknife)

---

### **How to Reproduce**

#### **Step 1: Set Up Global Path**
In `run.do`, set the project path to your local directory:
```stata
global SchoolSpending "C:\Users\<user>\OneDrive - Stanford\school\git"
```

#### **Step 2: Run the Full Pipeline**
Execute the master runner script:
```stata
do run.do
```

Or execute scripts individually in order:
```stata
* Phase I: Data Construction
do code/01_build_district_panel.do
do code/02_build_tract_panel_v2.do
do code/03_tag_county_quality.do
do code/05_create_county_panel.do

* Phase II: Analysis Panel Construction
do code/06_jjp_alt.do
do code/06_build_jjp_final.do

* Phase III: Event-Study Analysis
do code/07_figure1_event_study.do
do code/08_figure2_event_study.do
```

---

### **Key Geographic Identifiers**

Understanding the ID systems is critical for working with this codebase:

| Identifier | Format | Length | Description | Example |
|------------|--------|--------|-------------|---------|
| **LEAID** | SSDDDDD | 7 chars | NCES Local Education Agency ID | 0100005 |
| **GOVID** | SS5CCCDDD | 9 chars | Government ID (State+Type+County+District) | 015000100 |
| **tract70** | SSCCCBTCTSC | 11 chars | 1970 Census tract code | 01001000100 |
| **county** | SSCCC | 5 chars | State FIPS + County FIPS | 01001 |

Where: SS = State FIPS, CCC = County FIPS, DDDDD = District code, BTCTSC = Basic Tract + Tract Suffix Code

---

### **Data Notes**

**Coverage:**
- **Time Period:** 1967, 1969–2019 (F-33 and INDFIN harmonization)
- **Geographic Units:** 1970 Census tract definitions
- **Sample Restrictions:** Counties with non-missing 1972 baseline spending; balanced panel requires non-missing spending across the event window (-5 to +17 relative to reform); states with <10 balanced counties are dropped.

**Variable Dictionary (analysis_panel_bal.dta / analysis_panel_bal_alt.dta):**

*Identifiers:*
| Variable | Description |
|----------|-------------|
| `county_id` | 5-digit FIPS code (state + county) |
| `state_fips` | 2-digit state FIPS code |
| `year4` | Fiscal year end year |
| `year_unified` | School year (year4 - 1) |
| `relative_year` | Years since reform (missing for never-treated) |

*Outcome Variables:*
| Variable | Description |
|----------|-------------|
| `exp` | Per-pupil expenditure (2000 dollars, winsorized) |
| `lexp` | Log per-pupil expenditure |
| `lexp_ma` | Log PPE, 13-year rolling mean |
| `lexp_ma_strict` | Log PPE, 13-year strict rolling mean (primary outcome) |

*Baseline Characteristics:*
| Variable | Description |
|----------|-------------|
| `pre_q` | Baseline spending quartile (within-state) |
| `inc_q` | Income quartile (1970 Census, within-state) |
| `median_family_income` | Median family income (1970 Census) |
| `school_age_pop` | School-age population ages 5-17 (weight variable) |

*Treatment Variables:*
| Variable | Description |
|----------|-------------|
| `never_treated` | 1 = control state (no reform) |
| `reform_year` | Year court-ordered reform took effect |
| `reform_types` | Group indicator for reform type combination (via `egen group()`) |

*Binary Reform Type Indicators (from JJP Table D2):*
| Variable | Description |
|----------|-------------|
| `reform_eq` | 0 = Adequacy, 1 = Equity |
| `reform_mfp` | Minimum Foundation Plan |
| `reform_ep` | Equalization Plan |
| `reform_le` | Local Effort Equalization |
| `reform_sl` | Spending Limits |

*Quality Flags:*
| Variable | Description |
|----------|-------------|
| `good_county_1972` | 1 = non-missing 1972 baseline spending |
| `good_county` | 1 = complete baseline data (1967, 1970-1972) |

*Event-Study Indicators:*
| Variable | Description |
|----------|-------------|
| `lead_1` to `lead_5` | Pre-reform year dummies (`lead_5` binned at -5 and earlier) |
| `lag_1` to `lag_17` | Post-reform year dummies (`lag_17` binned at +17 and later) |

**Spatial Matching:**
- Uses 1970 tract definitions from 1969-70 GRF
- Untracted areas assigned residual county characteristics
- Single LEAID assigned per tract based on population weights
- Counties collapsed from tracts using school-age population weights

**Required Software:**
- Stata (tested with Stata 18+)
- Required Stata packages: `winsor2`, `rangestat`, `fred` (for CPI data)
- Install packages via: `ssc install [package_name]`

---

### **Data Flow Pipeline**

The pipeline follows a sequential process:

**Phase I: Data Construction**
1. **01_build_district_panel.do** — Imports F-33 SAS files (1992–2019) and INDFIN (1967–1991), builds 1:1 LEAID↔GOVID crosswalk, parses GRF for district-tract-county linkage, creates quality flags for baseline completeness
   - **Outputs:** `dist_panel.dta`, `f33_panel.dta`, `indfin_panel.dta`, `grf_id_tractlevel.dta`, `xwalk_leaid_govid.dta`
2. **02_build_tract_panel_v2.do** — Links districts to 1970 Census tracts via GRF allocated population weights, assigns one LEAID per tract, propagates quality flags from districts to tracts
   - **Outputs:** `tract_panel.dta`, `xwalk_tract_dist.dta`
3. **03_tag_county_quality.do** — Collapses tract-level quality flags to counties using MIN logic (county is "good" only if all its tracts link to districts with complete baseline data)
   - **Outputs:** `county_qual_flags.dta`
4. **05_create_county_panel.do** — Interpolates district spending (gaps ≤ 3 years), adjusts for inflation (CPI-U, 2000 dollars), imports NHGIS enrollment data, handles untracted areas (residual population method), collapses to enrollment-weighted county averages, merges JJP reform treatment data and median family income
   - **Outputs:** `county_panel.dta`, `dist_panel_interp.dta`, `tract_panel_interp_real.dta`

**Phase II: Analysis Panel Construction**
5. **06_jjp_alt.do** — Merges quality flags, applies balanced panel restriction on `lexp` (event window -5 to +17), drops states with <10 balanced counties
   - **Outputs:** `analysis_panel_bal_alt.dta`, `analysis_panel_unrestricted_alt.dta`
6. **06_build_jjp_final.do** — Same pipeline but balances on `lexp_ma_strict` (13-year strict rolling mean)
   - **Outputs:** `analysis_panel_bal.dta`, `analysis_panel_unrestricted.dta`

**Phase III: Event-Study Analysis**
7. **07_figure1_event_study.do** — Event-study regressions by baseline spending quartile
   - **Part A:** Individual quartile regressions (Q1, Q2, Q3, Q4)
   - **Part B:** Bottom 3 quartiles pooled (Q1–Q3)
   - **Specification:** County and year FE, clustered SEs, school-age population weights
   - **Outcomes:** `lexp`, `lexp_ma`, `lexp_ma_strict`
   - **Outputs:** Coefficient plots with 90% CIs (PNG)
8. **08_figure2_event_study.do** — Heterogeneity analysis (JJP Figure 2)
   - **Spec A:** Baseline spending quartile interactions
   - **Spec B:** Baseline spending + income × reform type interactions
   - **Approach:** Full-sample and leave-one-state-out jackknife predictions
   - **Classification:** Counties split into High vs Low predicted spending increase
   - **Outputs:** High/Low and quartile event-study graphs (PNG)

---

### **Key Outputs**

**Intermediate Datasets:**
- `dist_panel.dta` — District-year panel with quality flags (from 01)
- `tract_panel.dta` — Tract-year panel with assigned LEAIDs (from 02)
- `county_qual_flags.dta` — County-level quality flags (from 03)
- `county_panel.dta` — County-year panel with reform treatment data (from 05)

**Final Analysis Datasets:**
- `analysis_panel_unrestricted.dta` / `analysis_panel_unrestricted_alt.dta` — Full county panels before balance restriction (from 06)
- `analysis_panel_bal.dta` — Balanced panel (balanced on `lexp_ma_strict`) with state filter applied (from 06):
  - Counties with complete event windows (-5 to +17)
  - States with ≥10 balanced counties
  - Ready for event-study analysis
- `analysis_panel_bal_alt.dta` — Alternative balanced panel (balanced on `lexp`, includes more counties)

**Analysis Outputs:**
- Figure 1: Event-study coefficient plots by baseline spending quartile (from 07)
- Figure 2: High vs Low predicted spending increase, with jackknife robustness (from 08)

---

### **Citation**
If referencing the original study:
> Jackson, C. K., Johnson, R. C., & Persico, C. (2016). *The Effects of School Spending on Educational and Economic Outcomes: Evidence from School Finance Reforms*. The Quarterly Journal of Economics, 131(1), 157–218.
---

### **Contact**

**Research Analyst:** Myles Owens

**Affiliation:** Hoover Institution, Stanford University

**Email:** myles.owens@stanford.edu

**GitHub:** [maowens-HI/school_finance](https://github.com/maowens-HI/school_finance)

---

### **Additional Resources**

**For detailed documentation:**
- See `CLAUDE.md` for comprehensive AI assistant guide and coding conventions
- Review individual .do file headers for specific implementation details

**Original paper and data sources:**
- JJP (2016) Online Appendix: Detailed data description and reform coding
- NCES Common Core of Data: https://nces.ed.gov/ccd/
- FRED CPI-U Data: https://fred.stlouisfed.org/
- ICPSR GRF 1969: Study #03515 (Geographic Reference Files)

---

*For AI assistants working with this codebase: Please refer to CLAUDE.md for comprehensive project documentation, coding conventions, and task-specific guidance.*
