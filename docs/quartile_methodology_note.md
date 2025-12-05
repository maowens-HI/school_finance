# Quartile Methodology: Within-State vs. National

**Date:** 2025-12-05
**Issue:** Winsorization creates duplicate values that cause problems with within-state quartile creation

---

## Problem Discovered

After winsorizing `county_exp` at the 1st and 99th percentiles by year, we found significant duplicate values:

```
duplicates report county_exp state_fips
```

Large clusters of duplicates appeared (up to 1,758 observations with identical values), primarily at the winsorized tail values.

## Impact on Within-State Quartiles

When creating quartiles within each state:

```stata
bysort state_fips: egen pre_q1971 = xtile(exp), n(4)
```

**Two problems emerged:**

### 1. Small States Can't Support Quartiles

After balancing to the event-study window, many states had too few counties:

| Counties | States Affected |
|----------|-----------------|
| 1 | DE, MT |
| 2 | ME, TN |
| 3 | MA, NH, ND, RI |
| 4 | VT |
| 5 | AR |

States with ≤4 counties cannot have meaningful quartiles. All observations end up in Q1, or quartiles have 0 observations.

### 2. Unequal Quartile Sizes

Total observations by quartile were highly uneven:

| Quartile | Observations |
|----------|--------------|
| Q1 | 14,168 |
| Q2 | 13,104 |
| Q3 | 13,384 |
| Q4 | 12,096 |

Q1 had 17% more observations than Q4.

## Solution: National Quartiles

Changed from within-state to national quartile assignment:

```stata
*--- National quartiles (stable sort for reproducibility)
sort exp county_id
xtile pre_q1971 = exp, nq(4)
```

### Why This Is Better

1. **Matches JJP 2016 methodology** — The original paper uses national baseline spending quartiles
2. **Answers the right policy question** — "Do reforms help the poorest districts nationally?"
3. **Statistical power** — ~166 counties per quartile (balanced panel) vs. as few as 1 with within-state
4. **Avoids small-state problem** — No states excluded or artificially grouped

### Reproducibility Note

Adding `county_id` as a secondary sort variable ensures deterministic tie-breaking when multiple counties have identical spending values after winsorization.

---

## Files Modified

- `code/06_A_county_balanced_figure1.do` — Sections 4a and 4b updated to use national quartiles
