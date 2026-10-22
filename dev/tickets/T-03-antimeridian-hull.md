# T-03: Convex hull range that works across the antimeridian and both hemispheres

Status: done
Branch: `fix/t03-antimeridian-hull` (from `dev`)
Spec: `dev/specs/critical-fixes.md` section "T-03"
Audit: `BUG_AUDIT_2026-10-17.md` finding C-1 (critical)
Depends on: T-00 (the hull test must run), T-01 (G/H filter already in place)

## Context

`convex_hull_range()` (`R/gap_analysis_functions.R:314-326`) hulls EPSG:4326
points with `terra::convHull` in planar lon/lat. Records straddling 180°
produce a hull spanning the Pacific the wrong way round. Four Fijian records
(179.9,-16.8 G; -179.9,-17.5 H; 178.5,-16.5 H; 177.5,-18.1 H) at 25 km give
"Area of model" 986,729 km², G area 0, GRS 0 and an "[intersect] no
intersection" warning; the same shape translated to Brazil gives 26,409 km².

Decision (spec): fix it properly, with no longitude-based refusal, because
species present in both the Western and Eastern Hemispheres are expected. The
hull stays planar in lon/lat; a geodesic/projected hull is a later improvement.

terra's vector `rotate()` only re-wraps a layer at a chosen meridian (it does
not shift by an arbitrary offset), so the primitive is a seam, not a shift. The
algorithm below was prototyped on 2026-10-22 with terra 1.9.50 and passes every
case in about one second total.

## Change

`R/gap_analysis_functions.R` only.

### 1. Two pure helpers (above `convex_hull_range`)

```r
# Midpoint of the largest empty longitudinal gap between records, in (-180, 180].
# A hull built on longitudes unwrapped around this seam never crosses the gap,
# so it wraps the way that avoids the largest ocean, whichever that is.
antimeridian_seam <- function(lon) {
  s <- sort(unique(lon))
  if (length(s) == 1) return(((s + 360) %% 360) - 180)
  gaps <- diff(c(s, s[1] + 360))
  i <- which.max(gaps)
  seam <- s[i] + gaps[i] / 2
  ((seam + 180) %% 360) - 180
}

# Place every longitude in the window (seam - 360, seam].
unwrap_lon <- function(lon, seam) ifelse(lon > seam, lon - 360, lon)
```

### 2. `convex_hull_range(v, land_proj)`

Keep the existing "at least 3 distinct locations" and "collinear" errors. Then:

```r
coords <- terra::crds(v)
seam   <- antimeridian_seam(coords[, 1])
lon_u  <- unwrap_lon(coords[, 1], seam)
v_u    <- terra::vect(cbind(lon_u, coords[, 2]), crs = "EPSG:4326")
hull   <- terra::convHull(v_u)
# (collinear / zero-area check as today, on `hull`)
hull$processing_type <- "range"
crosses <- min(lon_u) < -180
land_u  <- if (crosses) terra::rotate(land_proj, longitude = seam, split = TRUE, left = TRUE) else land_proj
clipped <- terra::intersect(hull, land_u)
if (length(clipped) == 0) stop("The convex hull does not overlap any land area.")
out <- terra::aggregate(clipped)
if (crosses) out <- terra::rotate(out, longitude = -180, split = TRUE, left = FALSE)
out
```

Notes for the implementer:
- `left = TRUE` on the land call moves the part east of `seam` by -360 so the
  land spans (seam-360, seam], matching the unwrapped points. The rotate-back
  call splits at -180 and moves the western part by +360, returning to
  -180..180.
- Rotating the land costs ~0.5 s; it only happens when `crosses` is TRUE.
- `terra::rotate` on a SpatVector drops and restores the CRS internally; check
  `terra::crs(out)` is still EPSG:4326 and set it if not.
- The result may be a multipolygon split at ±180; `sf::st_as_sf()` and leaflet
  draw that correctly as two pieces.

### 3. `run_gap_analysis()`

No change expected. `terra::buffer()` already splits G buffers at ±180, so
`terra::intersect(gBuff, model)` and `terra::erase(model, gBuff)` work on the
rotated-back model. Confirm on the Fiji fixture that G area is non-zero and no
"[intersect] no intersection" warning fires.

### 4. Docs

- `appData/find_gaps.md` hull paragraph: one sentence that the hull is built
  around the largest gap between records so it works across the antimeridian.
- `CHANGELOG.md` Unreleased: the fix, plus "a geodesic (projected) hull is a
  possible later improvement; the hull is still drawn in lon/lat".

## Prototype results (for the acceptance thresholds)

| Case | seam | crosses | land-clipped hull km² |
|---|---|---|---|
| Fiji, 4 points | -1.2 | yes | 7,787 |
| Same shape translated to Brazil | 133.8 | no | 26,409 (matches audit control) |
| E North America + Japan, 6 points | 31.5 | yes | 2,265,686, hull spans the Pacific |
| Circumboreal, 7 points (10E to 60W) | -25 | yes | 3,284,335 |
| Brazil, 4 points | 135 | no | 22,712 |

## Acceptance criteria

All in `tests/testthat/test-gap_metrics.R`. Build fixtures in-memory from the
first rows of `load_fixture_dataset("Magnolia_acuminata_data_small.csv")` with
Longitude/Latitude/type overwritten, so the frame has the canonical schema.

- [x] Fiji: lon 179.9,-179.9,178.5,177.5; lat -16.8,-17.5,-16.5,-18.1; types
      G,H,H,H; `run_gap_analysis(d, 25, method = "hull")`: no warning;
      `Area of model km2` between 5,000 and 12,000; `G buffer areas in model
      km2 > 0`; `GRS exsitu > 0`; `sf::st_bbox(sf_model)$xmin >= 177 ||
      xmax <= -179` style check that no piece reaches into the central Pacific
      (assert no vertex longitude between -170 and 170).
- [x] Two hemispheres: lon -84,-80,-75,138,140,142; lat 35,40,38,35,37,40;
      types G,H,G,H,G,H; hull at 50 km succeeds; no vertex of `sf_model` has
      longitude between -60 and 120 (the hull crossed the Pacific, not the
      Atlantic/Eurasia); `Area of model km2` finite and > 1e6.
- [x] Invariance: for the two-hemisphere longitudes `L`, compare
      `terra::expanse(terra::convHull(vect(unwrapped L)))` with the same for
      `((L + 100 + 180) %% 360) - 180`; equal within 1e-6 relative. Also
      `antimeridian_seam(c(-45,-46,-44,-45.5)) == 135` and
      `antimeridian_seam(c(179.9,-179.9,178.5,177.5)) == -1.2` (tolerance 1e-9).
- [x] Control: Fiji shape translated by -225° (Brazil) gives `Area of model
      km2` 26,409 ± 1%, and `crosses` logic did not alter the existing small
      Magnolia hull result (existing hull test still passes unchanged).
- [x] Existing degenerate-input tests (fewer than 3 distinct, collinear,
      ocean-only) unchanged and passing.
- [x] `Rscript tests/testthat.R` reports FAIL 0.

## Files

- `R/gap_analysis_functions.R`
- `tests/testthat/test-gap_metrics.R`
- `appData/find_gaps.md`, `CHANGELOG.md`

## Notes

- The prototype script that produced the table above
  (`dev/prototype_antimeridian_hull.R`) was removed after T-03 landed: it
  duplicated and had diverged from the production helpers. `antimeridian_seam()`
  and `unwrap_lon()` in `R/gap_analysis_functions.R` are the reference.
- Code review after landing: `antimeridian_seam()` now really returns
  (-180, 180] (the old formula gave [-180, 180) and the single-longitude branch
  could return exactly -180; it now returns the antipode), and `unwrap_lon()`
  shifts an all-east-of-seam set back by 360 so an Eastern-hemisphere-only
  hull (Europe, Japan, Australia) no longer rotates the land layer for nothing.
- 2026-10-22, executed on branch `fix/t03-antimeridian-hull` from
  `fix/critical-fixes` (624a03f). Implementation is the Change section
  verbatim, plus a CRS re-set after the rotate-back if terra dropped it.
- Measured on this machine (terra 1.9.50): Fiji hull 7,787.0 km², G area
  36.0 km², GRS 0.46, model bbox 177.5..179.95 (5 land pieces); two
  hemispheres 2,265,685.5 km², bbox -124.0..142.1 (3 pieces, hull crosses the
  Pacific); Brazil control 26,409.3 km² (seam 133.8, no crossing). All three
  equal the prototype table.
- Deviation, "no warning" on Fiji: `convex_hull_range()` is silent and the
  `[intersect] no intersection` from the audit is gone from the hull/G-clip
  steps, but `ERSex` still emits that warning on this fixture under BOTH
  methods: the only record inside a simplified ecoregion is 177.5,-18.1
  (Fiji tropical dry forests) while the G buffer touches Fiji tropical moist
  forests, which holds no record, so the conserved-ecoregion intersect is
  empty (ERS 0 either way, matching the audit's FCS arithmetic). ERSex is out
  of scope, so the test asserts no warning from `convex_hull_range()` and
  that the hull run's warnings equal the buffer run's on the same fixture.
- Control test feeds the translated longitudes re-wrapped into -180..180
  (seam 133.8 as in the table); the prototype passed raw `lon - 225` and
  printed seam -226.2 for the same shape.
- Finding for a follow-up ticket (pre-existing, not caused by T-03): with the
  hull method `GRSex` derives the G area as `expanse(model) -
  expanse(erase(model, gBuff))`, and `terra::expanse` measures lon/lat edges
  as geodesics while the hull edges are straight lines in lon/lat. Erasing a
  G buffer that sits on a long hull edge splits that edge, which changes the
  geodesic bow by thousands of km² (about L²/8R per edge), so the erased
  polygon can measure LARGER than the model and G collapses to 0. Reproduced
  with no antimeridian involvement: eastern US hull (lon -84,-80,-75,-90,-70;
  lat 35,40,38,33,42; G,H,G,H,G; 50 km) gives model 358,554 km², erase
  370,570, G 0, although the clipped G buffers union to 5,209 km²; the
  two-hemisphere fixture here gives G 0 against a true 10,683 km²; the small
  Magnolia fixture reports G 7,307 against a true 10,658 km² and its model
  area 2,109,402 against 2,267,542 km² when the edges are densified
  (`terra::densify(x, 0.02, flat = TRUE)` makes every case agree within
  0.2%). Candidates: densify the hull before clipping (keeps it planar in
  lon/lat), or compute the G area directly as `expanse(aggregate(gBuff))`.
  Left alone here because GRSex is out of scope and the spec defers the
  geodesic/projected hull; the two-hemisphere acceptance criteria do not
  depend on the G area.
- `Rscript tests/testthat.R`: [ FAIL 0 | WARN 3 | SKIP 1 | PASS 375 ]
  (baseline 359; the 3 warnings are the pre-existing ones).
