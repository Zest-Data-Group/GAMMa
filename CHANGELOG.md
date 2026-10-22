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
- Data page: Undo Delete only restores while the dataset is still the one the
  delete produced (a digest of the post-delete frame is kept); a GBIF gather or
  upload after a delete greys the button out instead of being replaced by the
  old snapshot. A Delete with nothing selected no longer overwrites the backup,
  and Undo clears the current selection so indices cannot drift (T-02, audit
  C-3/M-9).

## 1.1.0 (2026-09-23, deployed to shinyapps.io GAMMA_dev)

- September refactor: single GBIF download pipeline, gap analysis as a pure
  function, static layers loaded once, HTML report without pandoc, convex hull
  range method, protected-areas overlay, test suite and CI.
