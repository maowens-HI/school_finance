# **Partial Replication of Jackson, Johnson, and Persico (2016)**

### **Overview**
This repository supports a partial replication and extension of *“The Effects of School Spending on Educational and Economic Outcomes: Evidence from School Finance Reforms”* by **C. Kirabo Jackson, Rucker C. Johnson, and Claudia Persico (2016, QJE)**. The original study examines how increases in school spending—driven by exogenous timing of **court-ordered School Finance Reforms (SFRs)**—affect long-run educational attainment and adult labor market outcomes, particularly among children from low-income families.

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
1. Develop transparent crosswalks linking **F-33 (District) ↔ INDFIN (District) ↔ Tract (GRF) ↔ County (GRF) ** identifiers.
2. Handle **mixed counties** that contain both tracted and non-tracted areas by combining untracted units within each county.
3. Reconstruct consistent annual per-pupil spending at the county level.
4. Use this data to estimate event studies akin to figures 1 and 2 in JJP 2016.

---

### **Repository Structure**
```
├── data/
│ ├── raw/ # Source files: F‑33, INDFIN, GRF, IPUMS, etc.
├── code/
│ ├── 00_cx.do
│ ├── 01_tract.do
│ ├── 02_build_f33_panel.do
│ ├── 03_int.do
│ ├── 04_cnty.do
│ ├── 05_interp_d.do
├── run.do # Full pipeline runner
└── README.md
```

---

### **How to Reproduce**
1. In Stata, define the project path:
   ```stata
   global SchoolSpending "C:\Users\<user>\OneDrive - Stanford\school\git"
   ```
2. Execute the scripts in order:
   ```stata
   do code/00_cx.do
   do code/01_tracts.do
   do code/02_build_f33_panel.do
   do code/03_county_collapse.do
   ```

---

### **Data Notes**
- **Coverage:** 1967,1969-2019 (baseline) with F-33 and INDFIN harmonization.
- **Key Variables:** per-pupil spending (`pp_exp_real`), school-age population (`school_age_pop`), reform exposure (`reform_year`, `relative_year`).
- **Spatial Matching:** Uses 1970 tract definitions; untracted areas are given the residual of county characterstics and total tract charactersitics.
- **Weights:**  School age population when aggregating to the county level.

---


---

### **Outputs**
- County panels with harmonized spending and population data.

---

### **Citation**
If referencing the original study:
> Jackson, C. K., Johnson, R. C., & Persico, C. (2016). *The Effects of School Spending on Educational and Economic Outcomes: Evidence from School Finance Reforms*. The Quarterly Journal of Economics, 131(1), 157–218.
---

### **Contact**
**Author:** Myles Owens  
**Affiliation:** Hoover Institution, Stanford University  
**Email:** myles.owens@stanford.edu 
**GitHub:** [maowens-HI/school_finance](https://github.com/maowens-HI/school_finance)
