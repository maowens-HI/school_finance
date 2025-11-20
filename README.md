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
1. Develop crosswalks linking **F-33 (District) ↔ INDFIN (District) ↔ Tract (GRF) ↔ County (GRF) ** identifiers.
2. Reconstruct consistent annual per-pupil spending at the county level.
3. Use this data to estimate event studies akin to figures 1 and 2 in JJP 2016.

---

### **Repository Structure**
```
school_finance/
├── README.md                          # Project documentation
├── CLAUDE.md                          # AI assistant guide
├── run.do                             # Master pipeline runner
└── code/                              # All Stata scripts
    ├── 01_build_district_panel.do     # Build district panels & ID crosswalks
    ├── 02_build_tract_panel.do        # Build tract panel from GRF
    ├── 03_adjust_inflation.do         # Adjust tract spending for inflation
    ├── 04_tag_county_quality.do       # Tag counties as good/bad (baseline data)
    ├── 05_create_county_panel.do      # Interpolate districts & create county panel
    ├── 06_A_county_balanced_figure1.do    # County-level balanced panel Figure 1
    ├── 06_B_district_balanced_figure1.do  # District-level balanced panel Figure 1
    ├── 07_jackknife_heterogeneity.do      # Full jackknife heterogeneity analysis
    └── experimental_archive/          # Archived experimental analysis files
```

**Pipeline Organization:**
- **Core Pipeline (01-05):** Sequential data construction and preparation
  - 01: Build district panels & ID crosswalks
  - 02: Build tract panel from GRF
  - 03: Adjust tract spending for inflation
  - 04: Tag county quality (baseline data completeness)
  - 05: Interpolate districts & create county panel
- **Analysis Scripts (06-07):** Main event-study specifications and robustness checks
  - 06_A: County-level balanced panel analysis (Figure 1 replication)
  - 06_B: District-level balanced panel analysis (Figure 1 replication)
  - 07: Full jackknife heterogeneity analysis (treatment effect heterogeneity)
- **Experimental Archive:** Historical analysis files, robustness checks, and alternative specifications

---

### **How to Reproduce**

#### **Step 1: Set Up Global Path**
In Stata run.do , define the project path:
```stata
global SchoolSpending "[your file path]"
```

#### **Step 2: Run the Full Pipeline**
Execute the master runner script:
```stata
do run.do
```

Or run the core pipeline scripts individually in order:
```stata
do code/01_build_district_panel.do
do code/02_build_tract_panel.do
do code/03_adjust_inflation.do
do code/04_tag_county_quality.do
do code/05_create_county_panel.do
```

#### **Step 3: Run Analysis**
Execute main analysis scripts:
```stata
do code/06_A_county_balanced_figure1.do
do code/06_B_district_balanced_figure1.do
do code/07_jackknife_heterogeneity.do
```

Or explore archived experimental specifications in `code/experimental_archive/`

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
- **Time Period:** 1967, 1969-2019 (F-33 and INDFIN harmonization)
- **Geographic Units:** 1970 Census tract definitions
- **Sample Restrictions:** Counties with complete baseline data (1967, 1970-1972) for quality analysis

**Key Variables:**
- **Spending:** `pp_exp` (nominal), `pp_exp_real` (2000 dollars), `lexp_ma_strict` (log spending with 13-year rolling mean)
- **Population:** `school_age_pop` (used for weighting in aggregation)
- **Treatment:** `reform_year` (year of court-ordered SFR), `relative_year` (years since reform)
- **Quality Flags:** `good_govid`, `good_tract`, `good_county` (baseline data completeness)
- **Baseline Quartiles:** `pre_q1969`, `pre_q1970`, `pre_q1971` (pre-reform spending distribution)

**Spatial Matching:**
- Uses 1970 tract definitions from 1969-70 GRF
- Untracted areas assigned residual county characteristics
- Single LEAID assigned per tract based on population weights
- Counties collapsed from tracts using school-age population weights

**Required Software:**
- Stata (tested with Stata 16+)
- Required Stata packages: `winsor2`, `rangestat`, `eststo/esttab`, `fred` (for CPI data)
- Install packages via: `ssc install [package_name]`

---

### **Data Flow Pipeline**

The pipeline follows a sequential process:

**Phase I: Data Construction**
1. **01_build_district_panel.do** - Builds district-year panels from F-33 and INDFIN, creates canonical LEAID ↔ GOVID crosswalks
2. **02_build_tract_panel.do** - Parses 1969 GRF to link districts to Census tracts, assigns single LEAID per tract
3. **03_adjust_inflation.do** - Adjusts tract-level spending for inflation using FRED CPI-U data
4. **04_tag_county_quality.do** - Tags counties as "good" or "bad" based on baseline year data completeness (1967, 1970-1972)
5. **05_create_county_panel.do** - Interpolates district panel, re-assigns to tracts, imports enrollment data, collapses to county-year panel

**Phase II: Main Analysis**
6. **06_A_county_balanced_figure1.do** - County-level event-study analysis (Figure 1 replication)
7. **06_B_district_balanced_figure1.do** - District-level event-study analysis (Figure 1 replication)

**Phase III: Archived Experiments**
- `experimental_archive/` contains historical robustness checks, alternative specifications, and exploratory analyses

---

### **Key Outputs**

**Intermediate Datasets:**
- `districts_panel_canon.dta` - District-year panel with quality flags (from 01)
- `tracts_panel_canon.dta` - Tract-year panel with assigned LEAIDs (from 02)
- `tracts_panel_real.dta` - Inflation-adjusted tract panel (from 03)
- `county_clean.dta` - County quality flags (from 04)

**Final Analysis Dataset:**
- `interp_d.dta` - County-year panel (1967, 1969-2019) with:
  - Per-pupil spending (nominal and real 2000 dollars)
  - School-age population weights
  - Reform exposure variables
  - Baseline spending quartiles
  - Quality flags for balanced event-study samples

**Analysis Outputs:**
- Event-study regression estimates 
- Event-study plots showing dynamic treatment effects

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
