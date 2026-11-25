# Changelog

Versions follow the `VERSION` file, which feeds the footer, the About-page
citation and the report filename. Tag releases in git as `vX.Y.Z`.

## Unreleased (dev)

- GBIF: a partial `eventDate` (year or year-month) no longer breaks a
  date-filtered download; "most recent first" sorts on the parsed date (#72).
- GBIF: advanced options grouped into "Download pool" and "Name checks", one
  tooltip per reference-selection choice, download flowchart on the About page
  (#65, #66).
- Gap map: layer control open by default and larger (#69).
- Version number flows into the About citation and the report filename (#71).
- Status banner with contact address and feedback-form link across every
  page; `CONTACT_EMAIL` and `FEEDBACK_URL` constants feed banner, footer and
  About page (#73).
- About page restyled into sections with images, a contents list and buttons
  to the working pages (#67, #70).
- Tests: GRS golden tolerance loosened to 1e-4 (GEOS/GDAL/PROJ drift, not app
  logic); hull test measures area with `terra::expanse()` instead of
  `sf::st_area()` so it no longer needs lwgeom; stale `n_buffers` fixture field
  removed. Suite is green again (T-00, audit L-11/L-12).
- Upload: rows whose Current Germplasm Type is not G or H are dropped at
  upload after confirmation; they no longer inflate GRS/ERS (#audit C-2).
  `run_gap_analysis()` also filters to G/H as a safeguard, so SRS record
  counts exclude such rows too. Cancelling the drop confirmation leaves an
  earlier upload and its status line untouched. Closes audit M-13 (report
  recoding blank types to H) by construction, since blanks never enter the
  dataset (T-01).
- Data page: Undo Delete only restores while the dataset is still the one the
  delete produced (the post-delete frame is kept for comparison); a GBIF gather or
  upload after a delete greys the button out instead of being replaced by the
  old snapshot. A Delete with nothing selected no longer overwrites the backup,
  and Undo clears the current selection so indices cannot drift (T-02, audit
  C-3/M-9).
- Gap analysis: the convex hull range now works for records straddling the
  antimeridian and for species in both hemispheres. Longitudes are unwrapped
  around the largest empty gap between records before hulling, and the land
  clip is re-wrapped to match, so a Fijian set no longer hulls the Pacific the
  wrong way round with G area 0 and GRS 0 (audit C-1, T-03). The hull is still
  drawn in lon/lat; a geodesic (projected) hull is a possible later
  improvement.
- Report: germplasm and reference buffers are drawn in their own colours (they
  were swapped against the legend); the gap-map palettes are now defined once
  and shared by the app and the report, which also stops the app painting a
  single-status ERS result in a blended colour. Uploaded text (taxon name,
  locality, collector, accession number) is escaped in the subtitle, the
  scores table, the popups and the records table. The priority cut-offs in
  the Definitions now match the categories the report prints (UP ≤ 25, HP ≤ 50,
  MP ≤ 75), and the report and About page describe the ERS denominator as the
  ecoregions containing at least one analysed record, which is what the
  score counts (T-05, audit M-11, M-12, M-14, L-9, L-10).
- GBIF: every request now times out (60 s, or 20 s without data) instead of
  hanging the app for all users. "Include taxonomic synonyms" works while the
  scientific-name check is on: a record filed under a synonym is kept when
  GBIF resolves it to the selected taxon (#52). A date filter no longer
  replaces the chosen reference-selection method; the records are ordered by
  the method and one per year is taken from that order. The sidebar summary
  shows records requested and retrieved separately, and Max Occurrences
  starts at 50 (T-06, audit M-3, M-4, M-5, L-5, L-6, L-13).
- Upload: CSV files saved by Excel on Windows (Windows-1252) load with their
  accented characters instead of disconnecting the session. Semicolon- and
  tab-delimited files load, including decimal commas in coordinates. Excel
  date cells in Collection Date show as dates, not serial numbers. Duplicate
  columns, an empty file, a workbook renamed .csv and a single-column file
  each get a message that says what is wrong (T-07, audit H-1, M-2, L-2, L-3,
  L-14).
- Data page: deleting records no longer re-zooms the map; the record counter
  clears with the dataset; the Gather button no longer stays live for a taxon
  that stopped resolving; cancelling a GBIF overwrite leaves the sidebar
  summary describing the records that are loaded. Gap page: record markers
  clear when the dataset empties, and Run Gap Analysis says so when there is
  nothing to analyse. Banner and footer icons now render (T-08, audit M-6,
  M-7, M-8, M-10, L-7, L-8).
- CI: tests also run on pushes to `dev`, and the runner is pinned to Ubuntu
  24.04. `ubuntu-latest` had moved to 26.04, where the locked s2 1.1.9 does
  not install, so the test step had not run since at least 2026-10-12.

## 1.1.0 (2026-09-23, deployed to shinyapps.io GAMMA_dev)

- September refactor: single GBIF download pipeline, gap analysis as a pure
  function, static layers loaded once, HTML report without pandoc, convex hull
  range method, protected-areas overlay, test suite and CI.
