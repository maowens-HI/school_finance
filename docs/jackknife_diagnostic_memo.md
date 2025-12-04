# Diagnostic Memo: Jackknife Classification Instability in Approach II

**Date:** December 4, 2025
**Author:** Analysis Session with Claude
**File Under Investigation:** `08_jackknife_approach_ii.do`
**Specification:** Spec A (Spending Quartile Only)

---

## Executive Summary

Investigation into why the jackknife event-study graph shows a compressed "high predicted" trend compared to the baseline revealed a fundamental issue: **two states (Ohio and Texas) have below-average spending growth for their high-baseline-spending counties, causing them to be misclassified as "high predicted" in the jackknife procedure.**

This is not a coding bug—the jackknife is mechanically correct. Rather, it is an artifact of the leave-one-state-out methodology interacting with influential outlier states, creating contamination in the treatment heterogeneity classification.

---

## 1. Initial Problem

### Observation
The baseline (full-sample) event-study showed clear separation between "high predicted" and "low predicted" spending groups. The jackknife version showed compressed, overlapping trends with the "high" group performing worse than expected.

### Quantification
Tabulating `pre_q × high_def_A` (baseline spending quartile × high/low classification) revealed:

| Quartile | Baseline High | Jackknife High | Difference |
|----------|---------------|----------------|------------|
| pre_q 1 | 3,080 | 3,080 | 0 |
| pre_q 2 | 3,136 | 3,136 | 0 |
| pre_q 3 | 0 | 504 | **+504** |
| pre_q 4 | 0 | 336 | **+336** |
| **Total** | 6,216 | 7,056 | **+840** |

**Finding:** 840 observations from pre_q 3/4 (high-baseline-spending counties) flipped from "low" to "high" in the jackknife—counties that theoretically should have *lower* predicted spending increases.

---

## 2. Diagnostic Approach

### Step 1: Identify Which States Contributed the Flipped Observations

Tabulated `state_fips × high_def_A` for pre_q ≥ 3 counties in both baseline and jackknife datasets.

**Result:** All 840 flipped observations came from exactly **two states**:
- Ohio (FIPS 39): 336 observations
- Texas (FIPS 48): 504 observations

No other state had any pre_q 3/4 counties flip classification.

### Step 2: Examine Within-State Prediction Patterns

Tabulated `pre_q × pred_q` (baseline quartile × predicted quartile) for Ohio and Texas separately.

**Ohio:**
| pre_q | pred_q (national) | Count | high_def_A |
|-------|-------------------|-------|------------|
| 3 | 1 (lowest) | 392 | 0 |
| 4 | 2 | 336 | **1** |

**Texas:**
| pre_q | pred_q (national) | Count | high_def_A |
|-------|-------------------|-------|------------|
| 3 | 3 | 504 | **1** |
| 4 | 1 (lowest) | 280 | 0 |

**Finding:** Ohio and Texas exhibit **opposite coefficient orderings**:
- Ohio: pre_q 4 predicted higher than pre_q 3
- Texas: pre_q 3 predicted higher than pre_q 4

The 840 flipped observations are:
- 336 Ohio pre_q 4 counties
- 504 Texas pre_q 3 counties

### Step 3: Compare Leave-Out Coefficients

Extracted key coefficients from three models using lag 4 as representative:

```
Full Sample:   main = 0.0179   ppe3 = -0.0199   ppe4 = -0.0298
Leave-Ohio:    main = 0.0124   ppe3 = -0.0157   ppe4 = -0.0112
Leave-Texas:   main = 0.0217   ppe3 = -0.0075   ppe4 = -0.0303
```

**Computed Predictions:**

| Model | pred(q=3) | pred(q=4) |
|-------|-----------|-----------|
| Full Sample | -0.0020 | -0.0119 |
| Leave-Ohio | -0.0033 | **+0.0012** |
| Leave-Texas | **+0.0142** | -0.0086 |

**Finding:**
- When Ohio is excluded, `ppe4` jumps from -0.030 to -0.011 (Δ = +0.019), pushing Ohio's pre_q 4 predictions above zero
- When Texas is excluded, `ppe3` jumps from -0.020 to -0.008 (Δ = +0.012), pushing Texas's pre_q 3 predictions above zero

### Step 4: Examine Actual Spending Trajectories

Collapsed mean `lexp_ma_strict` by state group (Ohio/Texas/Other) for pre_q ≥ 3 counties over relative years 2-7 (the averaging window).

| State Group | t=2 | t=7 | Change |
|-------------|-----|-----|--------|
| Ohio | 2.001 | 2.122 | +0.120 |
| Other States | 1.875 | 2.012 | **+0.137** |
| Texas | 1.622 | 1.735 | +0.113 |

**Finding:** Ohio and Texas pre_q 3/4 counties have **flatter spending growth** than other states:
- Ohio: 1.7 percentage points less growth than national average
- Texas: 2.4 percentage points less growth than national average

---

## 3. Root Cause Analysis

### The Mechanism

1. **In the full sample:** Ohio and Texas pre_q 3/4 counties drag down the `ppe3` and `ppe4` interaction coefficients because their spending growth is below the national average for those quartiles.

2. **In the jackknife:** Each state's counties receive predictions from a model that *excludes* that state:
   - Ohio counties get predictions from the "leave-Ohio" model
   - Texas counties get predictions from the "leave-Texas" model

3. **The perverse result:** When Ohio/Texas are excluded from estimation, the remaining states' pre_q 3/4 spending growth looks *better* (because the below-average performers are removed). This makes the interaction coefficients less negative, pushing predictions above zero.

4. **Classification flip:** Ohio's pre_q 4 counties and Texas's pre_q 3 counties cross the `pred_spend > 0` threshold and are classified as "high predicted."

### The Irony

Counties are classified as "high predicted" precisely *because* their own below-average performance is removed from the model that predicts them. The jackknife correctly uses out-of-sample predictions, but those predictions reflect what happened in *other* states—not what actually happened in Ohio/Texas.

---

## 4. Why This Matters

### Contamination of the "High" Group

The "high predicted" group in the jackknife now contains:
- Counties that genuinely had high predicted spending increases (correct)
- Ohio pre_q 4 and Texas pre_q 3 counties that actually had *below-average* spending growth (contamination)

This contamination drags down the "high" group's average trajectory, compressing the difference between high and low groups in the event-study plot.

### Quantifying the Contamination

- Total "high" in jackknife: 7,056 observations
- Contaminated observations: 840 (Ohio pre_q 4 + Texas pre_q 3)
- Contamination rate: **11.9%** of the "high" group

---

## 5. Implications and Options

### Is This a Bug?

**No.** The code correctly implements leave-one-state-out predictions. Each state's counties receive predictions from a model excluding that state. The predictions are stored and assigned correctly.

### Is This Expected Behavior?

**Technically yes, but problematically so.** The jackknife is designed to create out-of-sample predictions to avoid overfitting. However, when individual states are highly influential (as Ohio and Texas are for pre_q 3/4), the leave-out predictions can diverge substantially from actual outcomes.

### Potential Solutions

1. **Use Definition B (quartile-based) instead of Definition A (threshold-based)**
   - Less sensitive to small coefficient changes crossing zero
   - But the Ohio/Texas swap pattern suggests quartile rankings may also be unstable

2. **Examine robustness to excluding Ohio and Texas entirely**
   - Run analysis without these influential states
   - Compare results to full-sample and jackknife versions

3. **Use state-level clustering in the threshold**
   - Instead of national `pred_spend > 0`, use within-state classifications
   - Ensures each state's counties are compared to similar counties

4. **Report both baseline and jackknife results**
   - Acknowledge the instability as a limitation
   - Jackknife may be overly conservative due to this contamination

5. **Investigate why Ohio and Texas are different**
   - Are there policy or demographic factors explaining their below-average growth?
   - Could inform the heterogeneity analysis itself

---

## 6. Technical Details

### Files Examined
- `08_jackknife_approach_ii.do` (main analysis file)
- `baseline_reg_A.dta` (baseline predictions)
- `jk_reg_A.dta` (jackknife predictions)
- `model_baseline_A.ster` (full-sample estimates)
- `jackknife_A_state_39.ster` (leave-Ohio estimates)
- `jackknife_A_state_48.ster` (leave-Texas estimates)

### Key Variables
- `pre_q`: Baseline spending quartile (1971)
- `pred_spend`: Predicted spending increase (average of lags 2-7)
- `pred_q`: National quartile of predicted spending
- `high_def_A`: Binary classification (pred_spend > 0)
- `lexp_ma_strict`: Log per-pupil expenditure (13-year rolling mean)

### Prediction Formula (Spec A)
```
pred_spend = avg_main                    if pre_q == 1
pred_spend = avg_main + avg_ppe_2        if pre_q == 2
pred_spend = avg_main + avg_ppe_3        if pre_q == 3
pred_spend = avg_main + avg_ppe_4        if pre_q == 4

where avg_* = mean of coefficients across lags 2-7
```

---

## 7. Conclusion

The jackknife classification instability is driven by two influential states (Ohio and Texas) whose pre_q 3/4 counties have below-average spending growth. The leave-one-state-out methodology causes these counties to be classified as "high predicted" based on other states' patterns, contaminating the high group with counties that actually underperformed.

This represents a limitation of the Approach II methodology when applied to samples with influential outlier states, rather than a coding error. The finding suggests caution in interpreting the jackknife heterogeneity results and motivates robustness checks excluding or separately examining Ohio and Texas.

---

## Appendix: Diagnostic Code

```stata
* Compare leave-out coefficients
estimates use model_baseline_A
scalar full_main = _b[1.lag_4]
scalar full_ppe3 = _b[1.lag_4#3.pre_q]
scalar full_ppe4 = _b[1.lag_4#4.pre_q]

estimates use jackknife_A_state_39
scalar oh_main = _b[1.lag_4]
scalar oh_ppe3 = _b[1.lag_4#3.pre_q]
scalar oh_ppe4 = _b[1.lag_4#4.pre_q]

estimates use jackknife_A_state_48
scalar tx_main = _b[1.lag_4]
scalar tx_ppe3 = _b[1.lag_4#3.pre_q]
scalar tx_ppe4 = _b[1.lag_4#4.pre_q]

di "Full:  main=" full_main " ppe3=" full_ppe3 " ppe4=" full_ppe4
di "No-OH: main=" oh_main   " ppe3=" oh_ppe3   " ppe4=" oh_ppe4
di "No-TX: main=" tx_main   " ppe3=" tx_ppe3   " ppe4=" tx_ppe4

* Compare spending trajectories
use jjp_jackknife_prep, clear
keep if pre_q >= 3 & inrange(relative_year, 2, 7)
gen state_group = cond(state_fips == "39", "Ohio", ///
                  cond(state_fips == "48", "Texas", "Other"))
collapse (mean) lexp_ma_strict [aw=school_age_pop], by(state_group relative_year)
list, sepby(state_group)
```
