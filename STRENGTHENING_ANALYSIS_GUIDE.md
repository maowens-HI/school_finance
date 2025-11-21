# Guide to Strengthening Your Figure 1 Analysis (Ethically)

**Author:** Myles Owens
**Date:** 2025-11-21
**Purpose:** Provide ethical framework for improving analysis power and precision

---

## ⚠️ CRITICAL: Ethics First

### What "Stronger" Should Mean

| ✅ Legitimate Goals | ❌ Red Flags |
|-------------------|-------------|
| Tighter confidence intervals (better precision) | Larger coefficients just to hit significance |
| Cleaner pre-trends (validate parallel trends) | Cherry-picking specifications that "work" |
| Better-matched control groups | Dropping observations until significant |
| Theoretically-motivated heterogeneity | Data-mining for significant subgroups |
| Addressing measurement error | Changing outcome definitions post-hoc |

### The Pre-Specification Principle

**BEFORE analyzing your data:**
1. Write down your hypotheses
2. Specify your main specification
3. List robustness checks you'll run
4. Commit to reporting ALL results (not just "significant" ones)

**WHY?** This prevents specification searching (p-hacking) and ensures your results are credible.

---

## Understanding Why Effects Might Be Weak

Before trying to "strengthen" effects, diagnose WHY they're weak:

### Potential Reasons

1. **True Effect is Small**
   - Not all reforms had large impacts
   - Effects may be heterogeneous (strong for some, weak for others)
   - **Implication:** Accept smaller effects, focus on precision and heterogeneity

2. **Measurement Error**
   - Spending data has noise (interpolation, aggregation)
   - Reform timing may be mis-coded
   - **Implication:** Improve measurement, use instrumental variables

3. **Poor Identification**
   - Parallel trends violated
   - Bad control group
   - **Implication:** Fix identification strategy, not effect size

4. **Low Statistical Power**
   - Small sample size
   - High variance in outcomes
   - **Implication:** Improve precision, not point estimates

5. **Specification Issues**
   - Wrong functional form
   - Missing control variables
   - **Implication:** Theory-driven specification improvements

---

## Legitimate Strategies to Improve Your Analysis

### Strategy 1: Improve Precision (Tighter Standard Errors)

**Goal:** Reduce confidence interval width WITHOUT changing point estimates

**Methods:**
- ✅ Control for pre-reform trends (if theoretically justified)
- ✅ Use optimal weighting (inverse variance, population weights)
- ✅ Longer smoothing windows to reduce noise in outcome
- ✅ More conservative clustering (may increase SEs, but more credible)
- ✅ Wild bootstrap for small cluster counts

**Code:** `code/precision_improvements.do`

**Ethical Check:**
- [ ] Pre-specified in analysis plan
- [ ] Point estimates don't change materially
- [ ] Not selectively reporting "best" specification

---

### Strategy 2: Theory-Driven Heterogeneity Analysis

**Goal:** Find WHERE effects are strongest (if theory predicts heterogeneity)

**Theoretically-Motivated Dimensions:**
1. **Baseline spending quartiles** - Equity channel predicts stronger effects for low-spending districts
2. **Reform type** - Equity vs adequacy reforms have different mechanisms
3. **State inequality** - Reforms should matter more in high-inequality states
4. **Treatment intensity** - Larger formula changes → larger effects

**Code:** `code/heterogeneity_prespecified.do`

**Ethical Check:**
- [ ] Heterogeneity dimensions are theory-motivated (not data-driven)
- [ ] Pre-specified before seeing results
- [ ] Report ALL subgroups (not just significant ones)
- [ ] Correct for multiple hypothesis testing if needed

---

### Strategy 3: Improve Control Group Quality

**Goal:** Better counterfactual = cleaner identification

**Methods:**
- ✅ Matched controls (Mahalanobis distance on pre-reform characteristics)
- ✅ Restrict to controls with parallel pre-trends
- ✅ Exclude outlier control states
- ✅ Synthetic controls (if appropriate)
- ✅ Callaway & Sant'Anna (2021) for staggered adoption

**Code:** `code/better_controls.do`

**Ethical Check:**
- [ ] Control group selection is pre-specified
- [ ] Show robustness to different control groups
- [ ] Pre-trends improve with better controls (validation check)

---

### Strategy 4: Address Staggered Treatment Timing

**Goal:** Account for heterogeneous treatment effects across cohorts

**Problem:**
Standard TWFE estimators with staggered adoption can be biased if:
- Treatment effects vary over time
- Treatment effects vary across states
- Already-treated units serve as controls for later-treated units

**Solutions:**
1. **Sun & Abraham (2021)** - Interaction-weighted estimator
2. **Callaway & Sant'Anna (2021)** - Cohort-specific ATTs
3. **Borusyak et al. (2024)** - Imputation estimator
4. **De Chaisemartin & D'Haultfoeuille (2020)** - Decomposition approach

**Stata Packages:**
```stata
ssc install eventstudyinteract  // Sun & Abraham
ssc install csdid                // Callaway & Sant'Anna
ssc install did_imputation       // Borusyak et al.
ssc install did_multiplegt       // De Chaisemartin
```

**Ethical Check:**
- [ ] These methods may give DIFFERENT estimates (not necessarily larger)
- [ ] Report all methods, explain differences
- [ ] Don't cherry-pick the "strongest" estimator

---

### Strategy 5: Better Measurement of Outcomes

**Goal:** Reduce noise in dependent variable

**Methods:**
- ✅ Alternative smoothing windows (5-yr, 7-yr, 13-yr, 17-yr)
- ✅ Weighted averages (weight by enrollment)
- ✅ Levels vs logs
- ✅ Per-pupil vs total spending
- ✅ Different expenditure categories (instructional vs total)

**Ethical Check:**
- [ ] Pre-specify which outcome is "primary"
- [ ] Report robustness to alternative measures
- [ ] Don't switch primary outcome post-hoc

---

### Strategy 6: Extended Event Windows

**Goal:** Show longer-run effects (if data allows)

**Currently:** -5 to +17 years
**Extension:** -10 to +25 years (if data permits)

**Benefits:**
- Longer post-period may show cumulative effects
- Longer pre-period validates parallel trends

**Ethical Check:**
- [ ] Balanced panel restriction may reduce sample size
- [ ] Be transparent about sample changes

---

## What NOT to Do (P-Hacking Red Flags)

### ❌ Don't Do This:

1. **Dropping observations until significant**
   - Example: "Let's drop the top 100 counties by weight" (without justification)
   - Red flag: You're doing this in your current code (lines 371, 432, 491, 552, 624, 743, 804)

2. **Selective reporting**
   - Running 20 specifications, only reporting the 2 that are significant
   - Not mentioning specifications that "didn't work"

3. **Post-hoc sample restrictions**
   - "Effects are only strong in states that start with 'M'"
   - Data-driven sample splits without theory

4. **Outcome switching**
   - "Let's try logs... no, levels... no, inverse hyperbolic sine..."
   - Changing outcome until you get significance

5. **Optional stopping**
   - "Let's add more control states until it's significant"
   - "Let's stop collecting data because it's now significant"

6. **HARKing** (Hypothesizing After Results are Known)
   - Finding a result, then writing theory to justify it
   - Presenting exploratory findings as confirmatory

---

## Recommended Workflow

### Phase 1: Diagnosis (Current Status)

1. **Run your baseline specification** (current code)
2. **Diagnose the "problem":**
   - Are effects small or imprecise?
   - Are pre-trends flat?
   - Is the sample appropriate?
   - Are there outliers driving results?

3. **Ask: Is this a real effect or methodological issue?**
   - Check JJP (2016) original results
   - Compare to other school finance reform papers
   - Consider if your extension has different context

### Phase 2: Pre-Specification

1. **Write an analysis plan** (BEFORE trying new specs)
2. **List all specifications you'll run:**
   - Primary specification
   - Robustness checks (at least 5)
   - Heterogeneity dimensions (pre-specified)
   - Control group variations

3. **Commit to reporting ALL results**
   - Create a table template
   - Register your plan (Open Science Framework, AEA RCT Registry)

### Phase 3: Implementation

1. **Run all pre-specified analyses** (use code files provided)
2. **Create a summary table** comparing all specifications
3. **Check for robustness:** Do effects persist across specs?

### Phase 4: Interpretation

1. **If effects are still weak:**
   - Accept them! Not all reforms had large effects
   - Focus on heterogeneity (who benefited?)
   - Emphasize precision and credibility over size

2. **If effects strengthen with better methods:**
   - Explain WHY (better measurement, better controls, etc.)
   - Show that it's not p-hacking (all specs in same direction)
   - Emphasize pre-specified nature of improvements

3. **If effects vary across specifications:**
   - Be transparent about sensitivity
   - Discuss what drives differences
   - Don't hide inconvenient results

---

## Decision Tree: Should I Strengthen My Analysis?

```
START: "My Figure 1 effect is weak"
│
├─> Is the effect SMALL or IMPRECISE?
│   ├─> SMALL → Accept it. Focus on:
│   │             - Heterogeneity (where is it strong?)
│   │             - Mechanisms (why might it be small?)
│   │             - Comparison to literature
│   │
│   └─> IMPRECISE → Legitimate precision improvements:
│                    - Control for pre-trends
│                    - Better weighting
│                    - Longer smoothing windows
│
├─> Are my PRE-TRENDS flat?
│   ├─> YES → Good! Proceed with analysis
│   │
│   └─> NO → Fix identification:
│             - Better control group
│             - Control for differential trends
│             - Consider different estimator
│
├─> Is my SAMPLE appropriate?
│   ├─> YES → Keep it
│   │
│   └─> NO/UNSURE → Pre-specify restrictions:
│                   - Theory-driven sample selection
│                   - Matched controls
│                   - Exclude outliers (pre-specified criteria)
│
└─> Is this THEORY-DRIVEN or DATA-DRIVEN?
    ├─> THEORY-DRIVEN → Proceed (with pre-specification)
    │
    └─> DATA-DRIVEN → STOP. This is p-hacking.
```

---

## Your Current Code: Analysis

Looking at your `06_A_county_balanced_figure1.do`, I see:

### ⚠️ Concerns:

1. **Lines 251, 371, 491:** You're restricting to `rank > 100`, `rank <= 100`, etc.
   - This looks like specification searching
   - What's the theoretical justification?

2. **Multiple specifications without clear pre-specification:**
   - Full sample
   - Top 100 counties
   - Bottom 100 counties
   - Top quartile only
   - Bottom 3 quartiles only

### ✅ Good Practices I See:

1. Balanced panel restriction (theoretically justified)
2. Within-state quartiles (equity channel motivation)
3. Weighted regressions (population weights)
4. 13-year rolling means (reduce noise)

### 🔧 Recommendations:

1. **Decide on ONE primary specification** (report in abstract/intro)
2. **Pre-specify robustness checks** (report in appendix)
3. **Remove ad-hoc sample restrictions** unless theory-justified
4. **Focus on heterogeneity analysis** (use `heterogeneity_prespecified.do`)
5. **Improve control group** (use `better_controls.do`)
6. **Improve precision** (use `precision_improvements.do`)

---

## Questions to Ask Yourself

1. **If I find stronger effects with specification X, will I report specifications Y and Z that showed weaker effects?**
   - If NO → You're p-hacking
   - If YES → You're doing robustness checks (good!)

2. **Did I decide on this specification BEFORE or AFTER seeing the results?**
   - BEFORE → Pre-specified (credible)
   - AFTER → Post-hoc (suspicious)

3. **Would I run this analysis if I knew it would make effects SMALLER?**
   - If NO → You're p-hacking
   - If YES → You're doing legitimate robustness

4. **Can I explain WHY this should strengthen effects, based on theory?**
   - If NO → Data-driven specification search
   - If YES → Theory-driven improvement (but still pre-specify!)

---

## Additional Resources

### Papers on Research Ethics:
- Simmons et al. (2011) "False-Positive Psychology: Undisclosed Flexibility in Data Collection and Analysis Allows Presenting Anything as Significant"
- Miguel et al. (2014) "Promoting Transparency in Social Science Research"
- Christensen & Miguel (2018) "Transparency, Reproducibility, and the Credibility of Economics Research"

### Methods Papers (Staggered DiD):
- Sun & Abraham (2021) "Estimating Dynamic Treatment Effects in Event Studies with Heterogeneous Treatment Effects"
- Callaway & Sant'Anna (2021) "Difference-in-Differences with Multiple Time Periods"
- Borusyak, Jaravel & Spiess (2024) "Revisiting Event Study Designs: Robust and Efficient Estimation"

### Pre-Registration:
- AEA RCT Registry: https://www.socialscienceregistry.org/
- Open Science Framework: https://osf.io/
- aspredicted.org: https://aspredicted.org/

---

## Summary: Path Forward

1. **Diagnose:** Understand WHY effects are weak
2. **Pre-Specify:** Write analysis plan BEFORE trying new specs
3. **Implement:** Use provided code files for legitimate improvements
4. **Report:** ALL results, not just "strongest" ones
5. **Interpret:** Accept results even if effects are small

**Remember:** Science is about discovering truth, not achieving significance. Small, precise, and credible effects are more valuable than large, imprecise, or suspicious ones.

---

**Questions? Email:** myles.owens@stanford.edu
