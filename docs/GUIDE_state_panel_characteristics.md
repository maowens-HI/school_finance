# Step-by-Step Guide: Understanding the State Panel Characteristics Code

**For Research Assistants with Limited Programming Experience**

This guide explains the Stata code in `08_state_panel_characteristics.do` line by line. Think of this code as a recipe that processes raw data ingredients into a useful summary table.

---

## Table of Contents
1. [What Does This Code Do?](#what-does-this-code-do)
2. [Before You Start](#before-you-start)
3. [Section-by-Section Walkthrough](#section-by-section-walkthrough)
4. [Understanding the Output](#understanding-the-output)
5. [Common Troubleshooting](#common-troubleshooting)
6. [How to Modify the Code](#how-to-modify-the-code)

---

## What Does This Code Do?

This code creates an Excel spreadsheet that documents every U.S. state's status in our school finance reform study. For each state, it tells us:

- **Is this state treated or a control?** (Did they have a court-ordered reform?)
- **When did reform happen?** (Treatment timing)
- **What type of reform was it?** (Equity vs. adequacy)
- **Is the state's data good enough to use?** (Balanced panel status)
- **What data is missing?** (Missing years, missing counties)
- **Why is a state excluded?** (Exclusion reasons)

Think of it as creating a "report card" for each state's data quality.

---

## Before You Start

### Prerequisites
1. **Stata must be installed** (version 14 or newer)
2. **Project files must exist** - run the earlier pipeline scripts (01-06) first
3. **Global path must be set** in your `run.do` file:
   ```stata
   global SchoolSpending "C:\Users\YOUR_NAME\path\to\project"
   ```

### How to Run This Code
```stata
do "$SchoolSpending/code/08_state_panel_characteristics.do"
```

---

## Section-by-Section Walkthrough

### SECTION 1: Setup and Load Data

```stata
clear all
set more off
cd "$SchoolSpending/data"
```

**What this does:**
- `clear all` - Erases everything in Stata's memory (like clearing a whiteboard)
- `set more off` - Tells Stata not to pause and wait when showing long output
- `cd "$SchoolSpending/data"` - Changes to the data folder (like navigating to a folder on your computer)

**Why we do this:** We always start fresh to avoid mixing old and new data.

---

### Section 1.1: Create State Master List

```stata
import delimited using "$SchoolSpending/data/state_fips_master.csv", clear
```

**What this does:** Loads a CSV file containing all U.S. states with their FIPS codes.

**FIPS codes explained:** These are standard numeric codes assigned to each state by the government:
- Alabama = 01
- Alaska = 02
- Arizona = 04
- ... and so on

```stata
gen str2 state_fips = string(state_fips_num, "%02.0f")
```

**What this does:** Converts the numeric FIPS code to a 2-character string with leading zeros.

**Why?** FIPS "01" and numeric 1 look different in data. We need consistency.

**Example:**
- Before: `1` (numeric)
- After: `"01"` (string with leading zero)

```stata
keep if inlist(state_abbr, "AL", "AK", "AZ", ...) | ...
```

**What this does:** Keeps only the 50 states plus DC, removing territories like Puerto Rico and Guam.

**The `inlist()` function:** Checks if a value is in a list. Much cleaner than writing:
```stata
keep if state_abbr == "AL" | state_abbr == "AK" | state_abbr == "AZ" ...
```

---

### SECTION 2: Load Reform Treatment Data

```stata
import excel using "$SchoolSpending/data/tabula-tabled2.xlsx", firstrow clear
```

**What this does:** Loads the Excel file from Jackson, Johnson, and Persico (2016) that contains all school finance reform information.

**`firstrow` option:** Tells Stata the first row contains variable names, not data.

#### Filling Down State Names

```stata
forvalues i = 2/`N' {
    if missing(state_name_raw[`i']) {
        replace state_name_raw = state_name_raw[`i'-1] in `i'
    }
}
```

**What this does:** The original Excel has "merged cells" where a state name appears once and subsequent rows are blank. This code fills in those blanks.

**Visual example:**

| Before | After |
|--------|-------|
| California | California |
| (blank) | California |
| (blank) | California |
| Texas | Texas |
| (blank) | Texas |

**How the loop works:**
1. Start at row 2 (row 1 has headers)
2. If the current row's state name is blank...
3. Copy the state name from the row above
4. Repeat for all rows

#### Creating Reform Type Indicators

```stata
gen byte reform_equity = regexm(reform_type_raw, "Equity")
```

**What this does:** Creates a 0/1 variable indicating if this was an "Equity" reform.

**`regexm()` explained:** This function searches for text patterns. It returns 1 if found, 0 if not.

**`byte` explained:** A tiny data type for 0/1 variables. Uses less memory than the default.

---

### SECTION 3: Compute Panel Balance and Missing Data

#### Section 3.2: Count Counties by State

```stata
preserve
keep state_fips county_id
duplicates drop
bysort state_fips: gen n_counties_total = _N
keep state_fips n_counties_total
duplicates drop
tempfile county_counts
save `county_counts', replace
restore
```

**What this does:** Counts how many unique counties each state has.

**Breaking it down:**

1. `preserve` - Saves current data to memory (like creating a restore point)
2. `keep state_fips county_id` - Keep only these two variables
3. `duplicates drop` - Remove duplicate rows
4. `bysort state_fips: gen n_counties_total = _N` - For each state, count rows (counties)
5. `keep state_fips n_counties_total` - Keep only summary info
6. `duplicates drop` - Now we have one row per state
7. `tempfile county_counts` - Create a name for a temporary file
8. `save `county_counts', replace` - Save to that temporary file
9. `restore` - Go back to the original data

**The `_N` special variable:** In Stata, `_N` means "total number of observations in the current group."

**Example:**
| state_fips | _N (n_counties) |
|------------|-----------------|
| 01 (Alabama) | 67 |
| 02 (Alaska) | 29 |
| 04 (Arizona) | 15 |

#### Section 3.3: Identify Missing Years

```stata
clear
set obs 53
gen year = 1966 + _n
```

**What this does:** Creates 53 observations (for years 1967-2019).

**The `_n` special variable:** This means "current row number."

| Row | year calculation | Result |
|-----|------------------|--------|
| 1 | 1966 + 1 | 1967 |
| 2 | 1966 + 2 | 1968 |
| 3 | 1966 + 3 | 1969 |
| ... | ... | ... |
| 53 | 1966 + 53 | 2019 |

```stata
cross using `states'
```

**What this does:** Creates every possible combination of states and years.

**Visual example:**
| Before cross | After cross |
|--------------|-------------|
| year 1967 | AL 1967, AK 1967, ... |
| year 1968 | AL 1968, AK 1968, ... |

If we have 51 states and 53 years, we get 51 × 53 = 2,703 rows.

#### Section 3.4: Compute Balanced Panel Status

```stata
gen byte balanced_county = (min_rel == -5 & max_rel == 17 & n_rel_years == 23 & n_nonmiss_spend >= 20)
```

**What this does:** A county is "balanced" if:
1. Its earliest relative year is -5 (5 years before reform)
2. Its latest relative year is +17 (17 years after reform)
3. It has all 23 years of data (-5 to +17 inclusive)
4. At least 20 of those years have non-missing spending data

**Why 23 years?** From -5 to +17, counting by 1:
- -5, -4, -3, -2, -1, 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 15, 16, 17
- That's 23 total years

---

### SECTION 5: Create Exclusion Reasons

This section assigns each state a reason for exclusion (or marks them as included).

```stata
replace exclusion_reason = "Fewer than 10 counties in state (n=" + string(n_counties_total) + ")" ///
    if !missing(n_counties_total) & n_counties_total < 10 & exclusion_reason == ""
```

**What this does:** If a state has fewer than 10 counties, we can't reliably estimate effects for that state.

**The `///` line continuation:** In Stata, `///` means "this command continues on the next line." It's just for readability.

**String concatenation with `+`:** Joins text together:
- `"n="` + `"15"` + `")"` → `"n=15)"`

**Exclusion hierarchy:** Notice the `& exclusion_reason == ""` condition. This ensures we only assign ONE reason per state (the first one that applies).

---

### SECTION 6: Validation Checks

```stata
count
local n_states = r(N)
if `n_states' == 51 {
    di as text "CHECK 1 PASSED: All 50 states + DC present (N=51)"
}
```

**What this does:** Verifies that our output has exactly 51 rows (50 states + DC).

**Understanding `r(N)`:** After most Stata commands, results are stored in `r()` values. `r(N)` contains the count.

**Local macros explained:** `local n_states = r(N)` stores the value in a temporary variable called `n_states`. We reference it as `` `n_states' `` (with backticks and apostrophe).

---

### SECTION 7: Save and Export

```stata
export excel using "$SchoolSpending/data/state_panel_characteristics.xlsx", ///
    firstrow(varlabels) replace sheet("State Characteristics")
```

**What this does:** Creates an Excel file with our summary table.

**Options explained:**
- `firstrow(varlabels)` - Use variable labels (not names) as column headers
- `replace` - Overwrite if file exists
- `sheet("State Characteristics")` - Name the Excel sheet

---

## Understanding the Output

### The Excel File Contains:

| Column | Description | Example |
|--------|-------------|---------|
| state_fips | 2-digit FIPS code | "01" |
| state_abbr | State abbreviation | "AL" |
| state_name | Full state name | "Alabama" |
| treated | 1 if had reform, 0 if control | 1 |
| reform_year | Year of court-ordered reform | 1993 |
| reform_types_str | Description of reform types | "equity MFP" |
| included_in_analysis | 1 if included, 0 if excluded | 1 |
| exclusion_reason | Why excluded (or "INCLUDED") | "INCLUDED - meets all criteria" |
| n_counties_total | Number of counties | 67 |
| n_balanced_counties | Counties with complete data | 45 |
| missing_years_str | List of years without data | "1968 1969" |

### How to Read the Output:

**Example 1 - California:**
```
treated = 1
reform_year = 1976
reform_types_str = "equity"
included_in_analysis = 1
exclusion_reason = "INCLUDED - meets all criteria"
```
*Interpretation: California had an equity-focused reform in 1976 and is included in our analysis.*

**Example 2 - Wyoming:**
```
treated = 0
reform_year = .
reform_types_str = "never treated (control)"
included_in_analysis = 1
exclusion_reason = "INCLUDED - meets all criteria"
```
*Interpretation: Wyoming never had a court-ordered reform and serves as a control state.*

**Example 3 - Hawaii:**
```
treated = 1
reform_year = 1973
included_in_analysis = 0
exclusion_reason = "Reform year 1973 is before 1972 (insufficient pre-period)"
```
*Interpretation: Hawaii's reform was too early - we can't observe enough years before it happened.*

---

## Common Troubleshooting

### Error: "File not found"

**Problem:** Stata can't find an input file.

**Solutions:**
1. Check that the global path is set:
   ```stata
   di "$SchoolSpending"
   ```
   Should show your project path.

2. Make sure earlier scripts ran successfully:
   ```stata
   dir "$SchoolSpending/data/*.dta"
   ```
   Should show `jjp_final.dta` or similar files.

### Error: "Variable not found"

**Problem:** A variable the code expects doesn't exist.

**Cause:** Usually means an earlier script didn't run or produced different output.

**Solution:** Check what variables exist:
```stata
describe
```

### Warning: "Not all states present"

**Problem:** Fewer than 51 states in output.

**Cause:** State FIPS crosswalk might be incomplete.

**Solution:** Check your `state_fips_master.csv` file.

### Output shows "." for many values

**Problem:** Missing data showing as dots.

**Cause:** The state might not be in the analysis dataset at all.

**This is expected for:** DC and some territories that don't have county-level education data.

---

## How to Modify the Code

### To Change the Event Window (e.g., -10 to +20 instead of -5 to +17):

Find this line:
```stata
keep if inrange(relative_year, -5, 17)
```

Change to:
```stata
keep if inrange(relative_year, -10, 20)
```

Also update the balance check:
```stata
gen byte balanced_county = (min_rel == -10 & max_rel == 20 & n_rel_years == 31 ...)
```

### To Add a New Exclusion Reason:

Add a new `replace` statement after the existing ones:
```stata
replace exclusion_reason = "Your new reason here" ///
    if YOUR_CONDITION & exclusion_reason == ""
```

**Important:** The `& exclusion_reason == ""` ensures it only applies if no earlier reason was assigned.

### To Export Different Variables:

Modify the `order` command to change which variables appear and in what order:
```stata
order state_fips state_abbr state_name ...
```

### To Filter the Export:

Add a `keep if` statement before exporting:
```stata
keep if treated == 1  // Only export treated states
export excel ...
```

---

## Key Stata Concepts Summary

| Concept | What It Does | Example |
|---------|--------------|---------|
| `preserve`/`restore` | Save and restore data state | Save before collapsing, restore after |
| `tempfile` | Create temporary file | `tempfile mytemp` creates name `mytemp` |
| `_N` | Total observations in group | `gen count = _N` counts rows |
| `_n` | Current row number | `gen row = _n` numbers rows 1, 2, 3... |
| `bysort` | Process data by group | `bysort state: ...` runs per state |
| `local` | Temporary variable | `` local x = 5 `` then use `` `x' `` |
| `///` | Line continuation | Splits long commands across lines |
| `r()` | Stored results | `r(N)` after `count` gives the count |

---

## Questions?

If you have questions about this code:
1. First, check the comments in the .do file itself
2. Look at similar patterns in other scripts (01-07)
3. Consult the main CLAUDE.md documentation
4. Contact: myles.owens@stanford.edu

---

*Last updated: 2026-01-06*
