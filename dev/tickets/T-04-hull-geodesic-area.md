# T-04: Hull-method G area is wrong because hull edges are planar but areas are geodesic

Status: todo
Branch: `fix/t04-hull-geodesic-area` (from `dev`)
Spec: not yet grilled; found while executing T-03 (see its Notes)
Audit: not in `BUG_AUDIT_2026-10-17.md`; pre-existing, hull method only
Depends on: T-03

## Context

With `method = "hull"`, `GRSex()` derives the conserved G area as
`expanse(model) - expanse(erase(model, gBuff))`. `terra::expanse()` measures
every polygon edge as a geodesic, but the convex hull's edges are straight
lines in lon/lat. Erasing a G buffer that sits on a long hull edge splits that
edge into pieces whose geodesic bow differs from the original by roughly
L²/8R per edge, so the erased polygon can measure larger than the model and
the G area clamps to 0. The buffer method is unaffected (buffer polygons are
dense).

Reproductions from T-03 (terra 1.9.50, no antimeridian involvement):

| Case | model km² | erase km² | G reported | G true (buffer union) |
|---|---|---|---|---|
| Eastern US hull (lon -84,-80,-75,-90,-70; lat 35,40,38,33,42; G,H,G,H,G; 50 km) | 358,554 | 370,570 | 0 | 5,209 |
| Two-hemisphere fixture (T-03) | 2,265,686 | | 0 | 10,683 |
| Small Magnolia fixture, 50 km | 2,109,402 | | 7,307 | 10,658 |

Densifying the hull edges before clipping (`terra::densify(hull, 0.02, flat = TRUE)`)
makes every case agree within 0.2% and raises the small-Magnolia model area to
2,267,542 km² (the planar hull measured along geodesics is 7% low).

## Candidate fixes (decide in a grilling session)

1. Densify the hull in `convex_hull_range()` before clipping. Keeps the hull
   planar in lon/lat (consistent with the map) and fixes both the model area
   and the G area. Changes the hull-method numbers for every dataset; the
   existing hull test compares areas internally so it should still pass, but
   confirm and record new reference values.
2. Compute the G area directly as `expanse(aggregate(gBuff))` in the hull
   branch of `run_gap_analysis()`, leaving the model area as is. Smaller
   change, but the model area stays 7% low and GRS would mix two conventions.
3. Both.

## Acceptance (draft)

- [ ] Eastern US case above reports G within 1% of 5,209 km² and GRS > 0.
- [ ] Small Magnolia hull at 50 km reports G within 1% of 10,658 km².
- [ ] Buffer-method golden values unchanged.
- [ ] `Rscript tests/testthat.R` FAIL 0.

## Files

- `R/gap_analysis_functions.R`
- `tests/testthat/test-gap_metrics.R`
- `CHANGELOG.md`

## Notes

(append here while executing)
