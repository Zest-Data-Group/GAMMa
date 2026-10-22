# Spec: fixes for the three critical findings of the 2026-10-17 bug audit

Source: `BUG_AUDIT_2026-10-17.md` (dev @ 8d03dd6), findings C-1, C-2, C-3.
Agreed in a grilling session on 2026-10-22. This document is the shared
understanding; the tickets in `dev/tickets/` are the executable units.

## Workflow

- Everything is local. No GitHub issues, labels or milestones.
- One ticket per unit of work in `dev/tickets/`, index in `dev/tickets/README.md`.
- Each ticket is executed on its own branch cut from `dev` and merged back to
  `dev` only when `Rscript tests/testthat.R` passes in full.
- Execution order: T-00, T-01, T-02, T-03. T-00 must land first because every
  later ticket's done-criterion is a green suite and the hull test (needed by
  T-03) cannot run today.
- Tickets are written so a fresh agent can execute one cold. The reasoning is
  stated so a human can disagree with it.
- Lower-priority audit findings are folded into a ticket when they touch the
  same lines (M-9 into T-02; L-11 and L-12 into T-00; M-13 becomes moot via T-01).

## T-00: make the test suite green (L-11, L-12)

The suite is red today for test-infrastructure reasons only.

- `tests/testthat/test-gap_metrics.R:22`: the two full-dataset GRS goldens miss
  the 1e-6 tolerance by 1.2e-5 and 6.8e-5. Cause is GEOS/GDAL/PROJ drift, which
  renv.lock does not pin. Loosen the GRS tolerance to 1e-4 and record the
  geometry-library versions in the header comment.
- `tests/testthat/test-gap_metrics.R:130`: the hull test computes area with
  `sf::st_area()` on lon/lat with s2 off, which needs lwgeom, which is not in
  renv.lock. Use `terra::expanse(terra::vect(hull$sf_model), unit = "km")`
  instead. The prototype confirmed this equals `Area of model km2`.
- Nothing else changes. No app code is touched.

## T-01: rows with a germplasm type other than G or H (C-2)

### Decision

Such rows are dropped at upload, with the user's explicit consent, and never
enter the working dataset. The analysis pipeline also filters to G/H as a
safeguard. Nothing is kept "in grey".

Blank and unrecognised values (for example "SEED", "X") are one rule with one
message. The rule is: after `trimws()` and `toupper()`, the value must be
exactly "G" or "H".

GBIF downloads always assign G (basisOfRecord LIVING_SPECIMEN) or H
(`R/gbif_functions.R:333`), so only uploads can introduce such rows.

### Behaviour

1. `read_upload_file()` (pure, `R/fctn_read_upload_file.R`) applies the rule
   and returns the kept frame plus `n_dropped_type` (count) and, if any,
   a short vector of the offending raw values for the message.
   The `invalid_germplasm` attribute set by `flag_invalid_germplasm()` in
   `R/utils.R` is removed, as is that function and the
   `warn_invalid_germplasm()` toast in `R/module_controls.R`.
2. In the upload observer (`R/module_controls.R`, `observeEvent(input$uploadData)`):
   - if `n_dropped_type == 0`, behave exactly as today (including the existing
     "Overwrite Upload Data?" modal when an upload is already loaded);
   - otherwise hold the result in a pending reactiveVal and show a modal:
     title "Records without a germplasm type", body stating the count, the
     rule (only G or H are analysed) and the instruction "To include these
     records, assign a type of G or H in your file and upload it again."
     Footer: `actionButton("cancelTypeDrop", "Cancel upload")` and
     `actionButton("confirmTypeDrop", "Drop them and continue", class = "btn-primary")`.
   - "Drop them and continue" commits the kept frame via the same path a
     clean upload uses (including the overwrite check if upload data already
     exists). "Cancel upload" clears the pending slot, resets the file input,
     and leaves both `analysis_data()` and `upload_status()` untouched (review
     change: the pending upload never wrote to the status box, so clearing it
     would erase a previous upload's line).
   - The dataset never changes before the click.
3. The persistent sidebar status box (`upload_status`) records the outcome
   after the modal, for example: "Loaded 197 records. 3 records with a blank or
   unrecognised Current Germplasm Type were dropped." Its type is `warning`
   when anything was dropped. The 10-second toast for the "ignored" case is
   removed; the existing success/warning toasts for a clean upload stay.
4. `run_gap_analysis()` (`R/gap_analysis_functions.R`) filters `all_data` to
   `Current Germplasm Type %in% c("G","H")` once at the top, before SRSex and
   `prep_lat_lon`, so SRS, the records table and the metrics all see the same
   rows (review change), and stops with "No G or H records to analyse." when
   nothing survives.
   SRSex, GRSex, ERSex are not modified. All existing fixtures are G/H-only, so
   golden values do not move.
5. Dead code removed: the `TRUE ~ "gray"` branch in `R/leaflet_maps.R:208`
   (keep a defensive fallback colour only if the case_when needs a default;
   note it can no longer be reached), the comment on `merge_and_index()` that
   says non-G/H rows are kept, and anything that reads the dropped attribute.
   The unlabelled grey buffer on the gap map (`R/module_gap_analysis.R:248`)
   disappears by construction; no code change is needed there beyond
   confirming it.
6. Documentation: the "Data Format Requirements" modal in `R/module_controls.R`
   gains a line under Current Germplasm Type: "Must be G or H. Rows with any
   other value are dropped at upload." `appData/gather_modal.md` and the upload
   section of `appData/about.md` say the same. `CHANGELOG.md` gets an entry
   under Unreleased.
7. Audit finding M-13 (report recodes blank types to H) becomes unreachable
   because blanks never enter the dataset. Note this in the ticket's Notes
   section; do not change `reportTemplate.Rmd` in this ticket.

### Tests

- `test-read_upload_file.R`: a new in-memory fixture (write a temp CSV from
  `appData/Magnolia_acuminata_data_small.csv` with one blank type and one
  "X" type added, 10 rows) asserting status success, `nrow == 8`,
  `n_dropped_type == 2`, and no row with a type outside G/H.
- `test-gap_metrics.R`: `run_gap_analysis()` on the 8-row small fixture plus a
  manually appended non-G/H row with coordinates returns GRS, ERS, area and
  priority identical to the 8-row result; and errors with "No G or H" on a
  frame whose rows are all non-G/H.
- `test-module_controls.R` (testServer): uploading the mixed fixture shows the
  modal and leaves `analysis_data()` empty; `confirmTypeDrop` loads 8 rows and
  the status box text contains "2 records"; `cancelTypeDrop` leaves
  `analysis_data()` empty and `upload_status()` NULL. A clean upload still
  loads without a modal.

## T-02: Undo Delete after the dataset was replaced (C-3, plus M-9)

### Decision

Undo is valid only while the live dataset is still the frame that the delete
produced. A reference to that frame, compared with `identical()`, is the proof
(the original plan used `digest::digest()`; the 2026-10-22 code review replaced
it to avoid hashing large frames on every flush and the extra dependency).

### Behaviour

In `R/module_data_analysis.R`:

1. `observeEvent(input$deleteSelection)`: move
   `analysis_data_backup(analysis_data())` below the
   `length(current_selection) == 0` early return, so an empty Delete does not
   overwrite a real backup. After computing `updated_data`, store
   `backup_sig(digest::digest(updated_data))` alongside the backup.
   `digest` is already in renv.lock (a shiny dependency).
2. The Undo button's state observer becomes
   `nrow(analysis_data_backup()) > 0 && identical(digest::digest(analysis_data()), backup_sig())`.
   When the condition is false because the data changed, clear the backup and
   the signature so the button greys silently. No toast.
3. `observeEvent(input$undoLastDelete)`: `req()` the same condition; restore;
   then `selected_points(numeric(0))` (M-9); then clear backup and signature.
   The "restored n records" toast stays and can no longer go negative.
4. Single-level undo stays. No behaviour change in `module_controls.R`.

### Tests

`tests/testthat/test-module_data_analysis.R` (new file, testServer on
`dataAnalysisServer`, args `analysis_data`, `selected_points`):

- load 8 rows, select 2, delete, assert 6 rows and Undo enabled; replace the
  dataset with 200 rows (simulating a GBIF gather by setting `analysis_data()`
  directly); assert Undo is disabled and `analysis_data()` still has 200 rows
  after triggering `undoLastDelete`.
- 8 rows, delete 2, clear selection, click Delete with nothing selected:
  assert the backup still restores to 8 rows.
- 10 rows, delete index 2, set `selected_points(2)`, undo: assert
  `selected_points()` is empty.
- Delete then Undo on an unchanged dataset still restores and shows the
  positive count (regression guard for the normal path).

## T-03: convex hull across the antimeridian (C-1)

### Decision

The hull must work for records that straddle 180° and for species present in
both the Western and Eastern Hemispheres. No longitude-based refusal. The hull
stays planar in lon/lat (a geodesic or projected hull would also need a
different base map and is a later improvement, noted in CHANGELOG as such).

### Algorithm (prototyped on 2026-10-22, terra 1.9.50, all cases pass in ~1 s)

In `R/gap_analysis_functions.R`, new pure helpers plus a change to
`convex_hull_range(v, land_proj)`:

1. `antimeridian_seam(lon)`: sort the unique longitudes, compute the gaps
   between consecutive values including the wrap-around gap, take the largest,
   return its midpoint normalised into (-180, 180]:
   `seam <- s[i] + gaps[i]/2; seam <- ((seam + 180) %% 360) - 180`.
2. `unwrap_lon(lon, seam)`: `ifelse(lon > seam, lon - 360, lon)`, placing every
   record in the window (seam - 360, seam]. The hull of the unwrapped points
   never crosses the seam, so it avoids the largest empty gap by construction.
3. In `convex_hull_range()`: build the hull from the unwrapped points. If every
   unwrapped longitude is <= -180 the whole set is east of the seam, so shift
   it back by +360 (review change: avoids rotating the land layer for any
   Eastern-hemisphere dataset). If `min(unwrapped) < -180` after that, the hull
   crosses the antimeridian: clip against
   `terra::rotate(land_proj, longitude = seam, split = TRUE, left = TRUE)`
   (land re-wrapped so its seam is at `seam`), then bring the result back with
   `terra::rotate(out, longitude = -180, split = TRUE, left = FALSE)`.
   Otherwise clip against `land_proj` unchanged, as today. Keep the existing
   "at least 3 distinct", "collinear" and "no land" errors.
   terra's vector `rotate()` only re-wraps at a meridian; it does not shift by
   an arbitrary offset, which is why the seam, not a shift, is the primitive.
4. Downstream in `run_gap_analysis()`: `terra::buffer()` already splits G
   buffers correctly at ±180, so `terra::intersect(gBuff, model)` and
   `terra::erase(model, gBuff)` need no change. Confirm on the Fiji fixture
   that G area is non-zero and no "[intersect] no intersection" warning fires.

Prototype results, for the acceptance tests:

| Case | seam | crosses | land-clipped hull km² |
|---|---|---|---|
| Fiji, 4 points (audit C-1) | -1.2 | yes | 7,787 |
| Same shape translated to Brazil | 133.8 | no | 26,409 (matches audit control) |
| E North America + Japan (6 points) | 31.5 | yes | 2,265,686, hull spans the Pacific |
| Circumboreal (7 points, 10E to 60W) | -25 | yes | 3,284,335 |
| Brazil 4 points | 135 | no | 22,712 |

### Tests (`test-gap_metrics.R`)

- Fiji fixture (179.9,-16.8 G; -179.9,-17.5 H; 178.5,-16.5 H; 177.5,-18.1 H),
  hull, 25 km: `Area of model km2` between 5,000 and 12,000; `G buffer areas
  in model km2 > 0`; GRS > 0; bbox xmin of `sf_model` >= 177 (no Pacific-wide
  hull); no warning.
- Two-hemisphere fixture (lon -84,-80,-75,138,140,142; lat 35,40,38,35,37,40,
  alternate G/H): hull succeeds; `sf_model` bbox does not include longitude 0
  (hull went across the Pacific, not the Atlantic); result is finite.
- Invariance: `antimeridian_seam()` and `unwrap_lon()` are pure, so assert that
  the unclipped `terra::convHull` expanse of the two-hemisphere points equals
  the expanse after adding 100° to every longitude (re-wrapped into -180..180),
  within 1e-6. Geodesic area of a lon/lat polygon is invariant to longitude
  shift, so any difference means the unwrap chose a different arc.
- Existing hull tests (small Magnolia fixture, degenerate inputs, ocean-only)
  unchanged and passing.

## Out of scope, recorded for later

- Geodesic or projected hull (T-03 keeps planar lon/lat).
- Multi-level undo.
- The remaining medium and low audit findings not named above.
