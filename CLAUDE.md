# CLAUDE.md - AI Assistant Guide for school_finance Repository

## Project Overview

This repository contains a **partial replication and extension** of Jackson, Johnson, and Persico (2016) "The Effects of School Spending on Educational and Economic Outcomes: Evidence from School Finance Reforms" published in the Quarterly Journal of Economics.

**Author:** Myles Owens
**Institution:** Hoover Institution, Stanford University
**Email:** myles.owens@stanford.edu
**Language:** Stata (all .do files)
**Data Period:** 1967, 1969-2019

### Research Question
How do court-ordered School Finance Reforms (SFRs) affect long-run educational attainment and adult economic outcomes, particularly for children from low-income families?

### Core Methodology
- **Identification Strategy:** Uses exogenous timing of court-ordered school finance reforms as quasi-experimental shocks
- **Treatment Variable:** Years of exposure to initial SFR
- **Approach:** Event-study and 2SLS models with fixed effects
- **Key Challenge:** Linking multiple historical datasets across different geographic identifiers

---

## Repository Structure

```
school_finance/
├── README.md                          # Project documentation
├── CLAUDE.md                          # This file - AI assistant guide
├── run.do                             # Master pipeline runner
└── code/                              # All Stata scripts
    ├── 00_cx.do                       # District crosswalks & panel construction
    ├── 01_tract.do                    # Tract-level panel construction
    ├── 03_infl.do                     # Inflation adjustment (CPI-U)
    ├── 04_cnty.do                     # County-level aggregation
    ├── 05_interp_d.do                 # Interpolate missing district spending
    ├── balance.do                     # Panel balance testing
    ├── district_only.do               # District-level analysis
    ├── test_reg.do                    # Regression specification testing
    ├── 11_4_25*.do                    # Event-study variants (Nov 4, 2025)
    ├── 11_5_25*.do                    # Figure reproduction & jackknife
    ├── 11_6_25_jk_reform.do           # Jackknife by reform type
    ├── 11_7_25*.do                    # Balanced panel restrictions
    ├── 11_12_25/                      # Latest analysis (Nov 12, 2025)
    │   ├── fig1_bal_wt_rest.do        # Figure 1 with balancing weights
    │   └── 11_12_25.txt               # Meeting notes and decisions
    └── Graph.png                      # Example output visualization
```

**Total Code:** ~7,500 lines across 22 Stata .do files

---

## Understanding .DO Files

### What are .do files?
- **Plain-text Stata script files** containing sequential commands for data analysis
- Equivalent to R scripts (.R) or Python scripts (.py), but for Stata statistical software
- Execute data cleaning, transformation, merging, statistical analysis, and visualization
- Comments start with `*` (line comment) or `//` (inline comment)
- Multi-line comments use `/* ... */`

### Common Stata Commands You'll See

| Command | Purpose | Example |
|---------|---------|---------|
| `use` | Load .dta file | `use "data/file.dta", clear` |
| `merge` | Join datasets | `merge m:1 state year using cpi` |
| `collapse` | Aggregate data | `collapse (mean) spending, by(county)` |
| `gen` | Create new variable | `gen log_exp = log(spending)` |
| `replace` | Modify existing variable | `replace x = 0 if missing(x)` |
| `tsset` | Declare panel data | `tsset district year` |
| `ipolate` | Interpolate missing values | `ipolate y x, gen(y_interp)` |
| `areg` | Absorbed regression (FE) | `areg y x, absorb(county)` |
| `bysort` | Group operations | `bysort state: egen mean_x = mean(x)` |

---

## Data Flow Pipeline

### Phase I: Data Construction

```
Raw Data Sources
├── F-33 (NCES Finance Survey, 1992-2019) ──┐
├── INDFIN (Historical Database, 1967-1991) ├──> 00_cx.do
└── GRF69 (1969 Geographic Reference File) ─┘
                                              │
                                              v
                        District-Year Panel with Quality Flags
                                              │
                                              v
                                         01_tract.do
                                              │
                                              v
                            Tract-Year Panel (tracts_panel_canon.dta)
```

**Key Operations in Phase I:**
- Import SAS7BDAT files and convert to Stata .dta format
- Build canonical 1:1 crosswalks between LEAID ↔ GOVID identifiers
- Parse fixed-width GRF file to link school districts to Census tracts
- Assign single LEAID per tract based on population weights
- Create quality flags for districts with complete baseline data (1967, 1970-1972)

### Phase II: Data Enhancement

```
tracts_panel_canon.dta
        │
        v
    03_infl.do ──> Adjust for inflation using FRED CPI-U
        │
        v
    tracts_panel_real.dta (pp_exp_real in 2000 dollars)
        │
        v
    04_cnty.do ──> Aggregate tracts to counties
        │
        v
    county_clean.dta (with good_county flags)
        │
        v
    05_interp_d.do ──> Interpolate missing years (gaps ≤ 3 years)
        │
        v
    interp_d.dta (complete district-year panel)
```

### Phase III: Analysis

```
interp_d.dta + Reform Data (tabula-tabled2.xlsx)
        │
        v
    balance.do ──> Identify counties with complete event window (-5 to +17)
        │
        v
    Balanced Panel: 823 counties (from 1,087 total)
        │
        v
    Analysis Files (11_*.do)
        ├── Create lead/lag indicators
        ├── Generate baseline quartiles
        ├── Compute 13-year rolling means
        └── Run event-study regressions
```

---

## Key Geographic Identifiers

Understanding the ID systems is **critical** to working with this codebase:

| Identifier | Format | Length | Description | Example |
|------------|--------|--------|-------------|---------|
| **LEAID** | SSDDDDD | 7 chars | NCES Local Education Agency ID | 0100005 |
| **GOVID** | SS5CCCDDD | 9 chars | Government ID (State+Type+County+District) | 015000100 |
| **tract70** | SSCCCBTCTSC | 11 chars | 1970 Census tract code | 01001000100 |
| **gisjoin2** | SS0CCC0BTCTSC | 13 chars | GIS join format for NHGIS | 0100010000100 |
| **county** | SSCCC | 5 chars | State FIPS + County FIPS | 01001 |

**Where:**
- SS = State FIPS (2 digits)
- DDDDD = 5-digit district code
- CCC = County FIPS (3 digits)
- BTCTSC = Basic Tract + Tract Suffix Code

---

## Critical Variables

### Spending Variables
- `pp_exp` - Per-pupil expenditure (nominal dollars)
- `pp_exp_real` - Per-pupil expenditure in 2000 dollars
- `lexp` - Log per-pupil expenditure
- `lexp_ma` - Log spending with rolling mean
- `lexp_ma_strict` - Log spending with 13-year strict rolling mean (**primary outcome**)

### Treatment Variables
- `reform_year` - Year court-ordered reform took effect
- `relative_year` - Years since reform (year - reform_year)
- `lead_1` through `lead_5` - Indicators for pre-reform years
- `lag_1` through `lag_17` - Indicators for post-reform years
- `never_treated` - Indicator for states without SFR (control group)

### Quality Flags
- `good_govid` - District has complete baseline data (1967, 1970-1972)
- `good_tract` - Tract assigned to district with good_govid
- `good_county` - County contains only good tracts
- Individual year flags: `good_govid_1967`, `good_govid_1970`, etc.

### Baseline Characteristics
- `pre_q1969`, `pre_q1970`, `pre_q1971` - Quartile of baseline per-pupil spending
- `school_age_pop` - School-age population (**weighting variable**)

---

## Coding Conventions

### Global Path Configuration

**CRITICAL:** All scripts require this global to be set:

```stata
global SchoolSpending "C:\Users\<user>\OneDrive - Stanford\Documents\share_code"
```

- This is set in `run.do` at the top
- All file paths reference `$SchoolSpending/data/...` or `$SchoolSpending/code/...`
- **AI Assistants:** When modifying code, preserve this path structure

### Naming Conventions

**Variable Naming:**
- Use underscores for multi-word variables: `pp_exp`, `school_age_pop`
- Prefix transformations: `l` for log (lexp), `ln` for natural log
- Suffix for moving averages: `_ma`, `_ma_strict`
- Lead/lag indicators: `lead_1`, `lag_1` (NOT `lead1`, `lag1`)
- Quality flags: `good_*`, `bad_*`
- Temporary markers: `temp_*`, `flag_*`

**File Naming:**
- Sequential pipeline: `00_`, `01_`, `02_`, etc.
- Date-stamped iterations: `11_4_25`, `11_7_25` (MM_DD_YY format)
- Descriptive suffixes: `_wt` (weighted), `_no_wt` (unweighted), `_jk` (jackknife), `_restrict` (balanced panel)

### Code Structure Pattern

Every major .do file follows this structure:

```stata
/*==============================================================================
Project    : School Spending – [Description]
File       : filename.do
Purpose    : [Clear description]
Author     : Myles Owens
Institution: Hoover Institution, Stanford University
Date       : YYYY-MM-DD
───────────────────────────────────────────────────────────────────────────────
Inputs:    - Input file 1
           - Input file 2
Outputs:   - Output file 1
Notes:     - Implementation details
==============================================================================*/

clear all
set more off
cd "$SchoolSpending/data"

*** ---------------------------------------------------------------------------
*** Section 1: Data Import
*** ---------------------------------------------------------------------------

[code here]

*** ---------------------------------------------------------------------------
*** Section 2: Data Cleaning
*** ---------------------------------------------------------------------------

[code here]

*** ---------------------------------------------------------------------------
*** Section 3: Save Output
*** ---------------------------------------------------------------------------

save "output.dta", replace
```

### Panel Data Operations

**Setting up time-series panel:**
```stata
encode LEAID, gen(LEAID_num)          // Convert string to numeric
tsset LEAID_num year4                  // Declare panel structure
tsfill, full                           // Fill in missing years
```

**Interpolation logic:**
```stata
bysort LEAID_num: gen gap_next = year[_n+1] - year
gen byte too_far = (gap_next > 3 & !missing(gap_next))
bysort LEAID_num: ipolate pp_exp year if too_far==0, gen(exp2)
replace exp2 = pp_exp if !missing(pp_exp)  // Keep originals
```

**Quality flags:**
```stata
gen byte good_govid = (has_1967==1 & has_1970==1 & has_1971==1 & has_1972==1)
keep if good_govid == 1
```

### Regression Specifications

**Standard event-study specification:**
```stata
areg lexp_ma_strict i.lag_1 i.lag_2 i.lag_3 ... i.lag_17 ///
                    i.lead_1 i.lead_2 i.lead_3 i.lead_4 i.lead_5 ///
                    i.year_unified##i.pre_q1970 ///
                    [weight=school_age_pop] ///
                    if (never_treated==1 | reform_year<2000), ///
     absorb(county_id) vce(cluster county_id)

eststo
```

**Key elements:**
- `areg` with `absorb()` - Fixed effects regression (faster than `xtreg`)
- `i.` prefix - Categorical variable (factor notation)
- `##` - Full interaction (main effects + interaction)
- `[weight=...]` - Analytical weights (AWEIGHTs)
- `vce(cluster ...)` - Clustered standard errors
- `eststo` - Store estimates for later table export

---

## Common Tasks for AI Assistants

### Task 1: Modify Analysis Specification

**Location:** Analysis files in `code/` (e.g., `11_7_25_restrict.do`)

**What to do:**
1. Read the existing file with the Read tool
2. Identify the regression specification section
3. Make modifications (e.g., change lead/lag bins, add controls, modify sample restrictions)
4. Use Edit tool to update the file
5. Describe changes clearly to the user

**Example modifications:**
- Change event-time window (e.g., -10 to +20 instead of -5 to +17)
- Add additional control variables
- Modify baseline period (use pre_q1969 instead of pre_q1970)
- Change clustering level (state instead of county)

### Task 2: Add New Quality Checks

**Location:** Data construction files (`00_cx.do`, `01_tract.do`)

**Pattern to follow:**
```stata
*--- Quality check: [description]
gen byte flag_name = (condition)
tab flag_name
list LEAID year if flag_name==1 & _n<=10  // Show examples
```

### Task 3: Create New Robustness Check

**Steps:**
1. Copy an existing analysis file (e.g., `11_7_25_restrict.do`)
2. Rename with new date and descriptive suffix
3. Modify the specification as needed
4. Update header comments to describe changes
5. Save output with descriptive name

**Example:**
```bash
# Copy existing file
cp code/11_7_25_restrict.do code/11_14_25_no_control.do
```

Then edit to remove control states from specification.

### Task 4: Debug Missing Data Issues

**Common causes:**
1. **Merge failures** - Check `_merge` variable after merge
2. **Quality flag restrictions** - Check how many obs dropped by `good_*` flags
3. **Interpolation gaps** - Check `too_far` flag in interpolation step
4. **Panel imbalance** - Run balance check similar to `balance.do`

**Debugging commands:**
```stata
tab _merge                              // After merge
count if good_govid==0                  // See dropped obs
tab year if missing(pp_exp)             // Find missing pattern
xtdescribe                              // Panel structure summary
```

### Task 5: Export Results to LaTeX

**Pattern:**
```stata
eststo clear                            // Clear previous estimates

*--- Run regressions and store
eststo: areg y x, absorb(fe) vce(cluster id)
eststo: areg y x controls, absorb(fe) vce(cluster id)

*--- Export table
esttab using "table1.tex", ///
    replace tex ///
    se star(* 0.10 ** 0.05 *** 0.01) ///
    keep(x controls) ///
    order(x controls) ///
    label nonotes ///
    title("Table 1: Main Results")
```

---

## Data Quality and Validation

### Built-in Quality Checks

The codebase includes extensive quality validation:

1. **Baseline completeness** - Districts must have spending data in 1967, 1970, 1971, 1972
2. **ID uniqueness** - Ensures 1:1 LEAID ↔ GOVID mapping
3. **Geographic validity** - Drops special codes (water bodies, Native lands)
4. **Population validity** - Flags negative population values
5. **Panel balance** - Identifies counties with complete event windows

### When to Be Cautious

**⚠️ Warning Signs:**
- Large numbers of observations dropped (investigate why)
- _merge != 3 (unmatched records)
- Negative spending or population values
- Extreme outliers in spending (may need winsorization)
- Missing reform_year for treatment states

**Best practices:**
- Always check `tab _merge` after merges
- Use `count if missing(key_var)` to check completeness
- Generate and review summary statistics with `summarize, detail`
- Cross-check totals before and after aggregation

---

## File Dependencies

### Must Run in Order

**Phase I (Data Construction):**
1. `00_cx.do` - Creates F33 panel, INDFIN panel, crosswalks
2. `01_tract.do` - Creates tract panel (depends on output from 00_cx.do)

**Phase II (Enhancement):**
3. `03_infl.do` - Inflation adjustment (depends on tract panel)
4. `04_cnty.do` - County aggregation (depends on inflation-adjusted data)
5. `05_interp_d.do` - Interpolation (depends on county data)

**Phase III (Analysis):**
6. `balance.do` - Balance testing (optional but recommended)
7. Analysis files (`11_*.do`) - Can run in any order (independent)

### External Dependencies

**Data files** (not in repo, must be obtained separately):
- F-33 SAS files from NCES Common Core of Data
- INDFIN files from historical database
- GRF 1969 fixed-width file from ICPSR
- tabula-tabled2.xlsx from JJP 2016 online appendix
- State fiscal year start dates (fiscal_year.csv)
- State FIPS codes (state_fips_master.csv)

**Stata packages** (install with `ssc install`):
- winsor2
- rangestat
- eststo/esttab
- fred (for FRED API access)

---

## Working with Git

### Current Branch

This project uses the branch: `claude/claude-md-mhz4illyp6svafb7-01HcPogrY8AERupgjYGaEPmP`

**Important git practices:**
1. Always develop on the designated claude/* branch
2. Commit with clear, descriptive messages
3. Push with `-u` flag: `git push -u origin <branch-name>`
4. Never force push without explicit permission

### Typical Workflow

```bash
# Check status
git status

# Add modified files
git add code/new_file.do

# Commit with message
git commit -m "Add robustness check for alternative baseline period"

# Push to remote
git push -u origin claude/claude-md-mhz4illyp6svafb7-01HcPogrY8AERupgjYGaEPmP
```

---

## Interpreting Results

### Event-Study Coefficients

The primary output is an event-study plot showing:
- **X-axis:** Relative time (years since reform)
- **Y-axis:** Coefficient on lead/lag indicator
- **Interpretation:** Change in log spending relative to year -1 (omitted baseline)

**Expected pattern:**
- Flat pre-trends (lead coefficients near zero) → Parallel trends assumption
- Jump at reform (lag coefficients positive and increasing) → Treatment effect
- Persistent effects (coefficients remain elevated) → Long-run impact

### Heterogeneity Analysis

**By baseline spending quartile:**
- `pre_q1` - Lowest 25% baseline spending (poorest districts)
- `pre_q2` - 25th-50th percentile
- `pre_q3` - 50th-75th percentile
- `pre_q4` - Highest 25% baseline spending (richest districts)

**Interaction:** `i.year##i.pre_q` controls for differential trends by baseline wealth

### Reform Types

- **Equity reforms** - Focus on equalizing spending across districts
- **Adequacy reforms** - Set minimum spending thresholds
- Mixed reforms (both equity and adequacy elements)

---

## Troubleshooting Common Issues

### "File not found" errors

**Cause:** Global path not set correctly

**Fix:**
```stata
global SchoolSpending "/correct/path/to/project"
```

### "Variable not found" errors

**Cause:** Missing merge or incorrect variable name

**Fix:**
1. Check if previous script ran successfully
2. Verify merge was successful (`tab _merge`)
3. Check variable spelling (Stata is case-sensitive)

### "No observations" errors

**Cause:** Quality flag restrictions too stringent

**Fix:**
```stata
count                              // Before restriction
keep if good_govid==1
count                              // After restriction
```

If too many dropped, investigate with:
```stata
tab good_govid
list LEAID year if good_govid==0 & _n<=20
```

### Regression produces huge coefficients

**Cause:** Scale mismatch or missing log transformation

**Fix:**
- Ensure dependent variable is logged: `gen lexp = log(pp_exp)`
- Check for missing or zero values: `count if pp_exp<=0`
- Consider winsorization: `winsor2 pp_exp, replace cuts(1 99)`

---

## Best Practices for AI Assistants

### ✅ DO:
- **Read existing files** before making changes (use Read tool)
- **Preserve header comments** and update them if logic changes
- **Maintain consistent style** with existing code
- **Test incrementally** - run modified code on small samples first
- **Document changes** clearly in commit messages
- **Check data dimensions** before and after operations
- **Validate merges** with `tab _merge`
- **Comment non-obvious transformations**

### ❌ DON'T:
- **Don't modify global paths** without user confirmation
- **Don't delete quality checks** - they're there for a reason
- **Don't change variable names** used in downstream scripts
- **Don't commit large data files** (.dta files should be in .gitignore)
- **Don't skip header documentation** in new files
- **Don't use hardcoded paths** - always use `$SchoolSpending`
- **Don't remove seemingly redundant code** without checking dependencies

### When Uncertain:
1. **Ask the user** for clarification
2. **Check existing patterns** in similar files
3. **Read the README.md** for project context
4. **Review recent commits** to understand recent changes
5. **Examine meeting notes** (11_12_25.txt) for methodological decisions

---

## Quick Reference

### Most Important Files

| File | Purpose |
|------|---------|
| `run.do` | Master runner - start here to understand pipeline |
| `00_cx.do` | District ID crosswalks - critical for linking data |
| `05_interp_d.do` | Interpolation logic - handles missing years |
| `balance.do` | Panel balance - determines final sample |
| `11_7_25_restrict.do` | Main specification with balanced panel |

### Most Important Variables

| Variable | Description |
|----------|-------------|
| `lexp_ma_strict` | Primary outcome (log spending, 13-year rolling mean) |
| `relative_year` | Treatment timing (years since reform) |
| `good_govid` | Quality flag (complete baseline data) |
| `school_age_pop` | Weighting variable |
| `pre_q1970` | Baseline spending quartile (1970) |

### Most Important Commands

| Command | Purpose |
|---------|---------|
| `do code/run.do` | Run full pipeline |
| `use "file.dta", clear` | Load dataset |
| `merge m:1 id using other` | Join datasets |
| `areg y x, absorb(fe) vce(cluster id)` | Fixed effects regression |
| `eststo` | Store regression results |
| `esttab using "table.tex"` | Export to LaTeX |

---

## Additional Resources

### Original Paper
Jackson, C. K., Johnson, R. C., & Persico, C. (2016). *The Effects of School Spending on Educational and Economic Outcomes: Evidence from School Finance Reforms*. The Quarterly Journal of Economics, 131(1), 157–218.

**Online Appendix:** Contains detailed data description and reform coding

**NBER Working Paper:** https://www.nber.org/papers/w20118

### Data Sources
- **NCES Common Core of Data:** https://nces.ed.gov/ccd/
- **INDFIN Historical Database:** Individual government finance data
- **ICPSR GRF 1969:** Study #03515 (Geographic Reference Files)
- **FRED (Federal Reserve Economic Data):** https://fred.stlouisfed.org/ (CPI-U series)

### Stata Resources
- **Stata documentation:** https://www.stata.com/manuals/
- **Panel data commands:** `help tsset`, `help xtset`, `help areg`
- **Factor variables:** `help fvvarlist`

---

## Contact

**For questions about this codebase:**
- **Author:** Myles Owens
- **Email:** myles.owens@stanford.edu
- **GitHub:** https://github.com/maowens-HI/school_finance

**For AI assistance:**
- This CLAUDE.md file is your primary reference
- Check README.md for project overview
- Review code comments for implementation details
- Consult meeting notes (11_12_25.txt) for recent methodological decisions

---

## Version History

| Date | Update |
|------|--------|
| 2025-11-14 | Initial CLAUDE.md creation with comprehensive codebase documentation |

---

*This guide is maintained for AI assistants (like Claude) to effectively understand and work with the school_finance codebase. Keep it updated as the project evolves.*
