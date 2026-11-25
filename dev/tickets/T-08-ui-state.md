# T-08: Maps, counters and the Gather button follow the dataset

Status: done
Branch: `fix/t08-ui-state` (from `fix/t07-upload-robustness`)
Spec: none; the audit gives the fixes and no gap score changes. See
`dev/REVIEW_2026-11-25.md` section 2, task 6
Audit: `BUG_AUDIT_2026-10-17.md` findings M-6, M-7, M-8, M-10, L-7, L-8
Depends on: T-06 (same file, `R/module_controls.R`)

## Context

- M-6: `render_base_points()` re-fitted the map on every redraw, so deleting a
  record snapped the view back to the full extent.
- M-7: an incomplete taxon selection raised a silent error that cancelled the
  observer before it could disable the Gather button; the button stayed live
  and ignored clicks.
- M-8: cancelling the "Overwrite GBIF Data?" modal left the sidebar saying the
  cancelled download was loaded.
- M-10: when the dataset became empty, or lost all coordinates, the gap map
  kept the old markers and Run Gap Analysis did nothing, silently.
- L-7: the record counter on the data map kept the deleted dataset's numbers.
- L-8: the banner and footer used Bootstrap Icons classes, which the app does
  not load, so six icons rendered as empty elements.

## Change

1. `R/leaflet_maps.R`: remove the fit from `render_base_points()`.
   `module_map.R` already fits, with padding and a zoom cap, only when the
   row count grows.
2. `R/module_map.R`: remove the counter control before deciding whether to add
   a new one.
3. `R/module_gap_analysis.R`: clear the two record groups before the empty
   checks; Run with no records shows a notification.
4. `R/module_controls.R`:
   - `selected_taxon()` returns NULL for an incomplete selection;
   - a Gather click with no resolved taxon shows a notification;
   - `last_gather()` is set when records are loaded, not when they are
     downloaded; the result waits in `pending_gather` while the modal is open;
   - the modal's Cancel is a server button that clears the pending download.
5. `R/utils.R`: the six icons use `shiny::icon()`.

## Acceptance criteria

New file `tests/testthat/test-ui_state.R` captures leafletProxy calls by
replacing `leaflet:::invokeRemote`.

- [x] Loading records emits one `fitBounds` with `maxZoom` 10; deleting a
      record redraws the markers and emits none.
- [x] An empty dataset emits `removeControl("gbif_upload_counts")` and no
      `addControl`.
- [x] An empty dataset, and one with no coordinates, each clear both record
      groups on the gap map and add no markers.
- [x] An incomplete taxon selection gives NULL, and a click loads nothing.
- [x] Gather, gather again, Cancel: `last_gather()` and the dataset are
      unchanged and the pending download is gone. Confirm promotes it.
- [x] Banner and footer contain no `bi` classes and depend on Font Awesome.
- [x] `Rscript tests/testthat.R` FAIL 0.

## Files

- `R/leaflet_maps.R`, `R/module_map.R`, `R/module_gap_analysis.R`,
  `R/module_controls.R`, `R/utils.R`
- `tests/testthat/test-ui_state.R`, `tests/testthat/test-module_controls.R`
- `CHANGELOG.md`, `dev/tickets/README.md`

## Notes

- 2026-11-25: tests written and run red first (14 failing expectations), then
  green. `Rscript tests/testthat.R`:
  `[ FAIL 0 | WARN 3 | SKIP 1 | PASS 623 ]`.
- These are server-side checks of what is sent to the browser. Nothing here
  was looked at in a real browser: there is no Chrome on this machine and the
  browser test is skipped. Worth a two-minute click-through after merging:
  delete a point while zoomed in, cancel a GBIF overwrite, check the icons.
- The M-7 toggle itself runs through shinyjs, which testServer cannot
  observe; the test covers the cause (the reactive now returns NULL).
