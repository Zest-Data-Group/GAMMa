# T-00: Make the test suite green

Status: todo
Branch: `fix/t00-tests-green` (from `dev`)
Spec: `dev/specs/critical-fixes.md` section "T-00"
Audit: `BUG_AUDIT_2026-10-17.md` findings L-11, L-12

## Context

`Rscript tests/testthat.R` on dev @ 8d03dd6 reports FAIL 3 | WARN 3 | SKIP 1 |
PASS 311. All three failures are in `tests/testthat/test-gap_metrics.R` and are
test-infrastructure problems, not app bugs. Every later ticket requires a green
suite, and T-03 needs the hull test to actually run.

- Two golden GRS values for `Magnolia_acuminata_data.csv` miss tolerance 1e-6 by
  1.2e-5 (10 km) and 6.8e-5 (50 km). The audit's verifier rebuilt terra 1.9-34
  and got identical numbers, so the drift is GEOS/GDAL/PROJ (unpinned by
  renv.lock), not app logic.
- The hull test at line 130 calls `sf::st_area()` on lon/lat geometry with s2
  off (`global.R:32`), which dispatches to lwgeom, which is not in renv.lock.
  It errors before any assertion runs.

## Change

Only `tests/testthat/test-gap_metrics.R`.

1. Line 22: `expect_equal(r$grs, case$grs, tolerance = 1e-4)`. Leave the SRS and
   ERS tolerances at 1e-6 (they are exact arithmetic on counts).
2. Line 130: replace
   `hull_area <- as.numeric(sum(sf::st_area(hull$sf_model))) / 1e6`
   with
   `hull_area <- sum(terra::expanse(terra::vect(hull$sf_model), unit = "km"))`.
   This was verified equal to `hull$grs$\`Area of model km2\`` (2,109,402).
3. Header comment: add the geometry-library versions the goldens were last
   verified against (GEOS 3.12.1, GDAL 3.8.4, PROJ 9.4.0, terra 1.9.50) and the
   reason for the 1e-4 GRS tolerance.
4. `gap_cases$n_buffers` values are stale and never asserted. Delete the field
   from the six cases and from `run_gap_pipeline_reference()` in
   `tests/testthat/helper-gap_pipeline.R` so nobody mistakes them for goldens.

Do not touch app code. Do not change any golden value.

## Acceptance criteria

- [ ] `Rscript tests/testthat.R` reports FAIL 0 (expected: PASS 314 or more,
      SKIP 1 for the browser test, warnings may remain).
- [ ] The hull test's assertions after line 130 now execute (temporarily break
      one to confirm, then restore).
- [ ] No golden number in `gap_cases` changed.

## Files

- `tests/testthat/test-gap_metrics.R`
- `tests/testthat/helper-gap_pipeline.R`

## Notes

(append here while executing)
