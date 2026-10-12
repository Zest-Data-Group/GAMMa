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
- Status banner with contact address across every page; one `CONTACT_EMAIL`
  constant feeds banner, footer and About page (#73).
- About page restyled into sections with images, a contents list and buttons
  to the working pages (#67, #70).

## 1.1.0 (2026-09-23, deployed to shinyapps.io GAMMA_dev)

- September refactor: single GBIF download pipeline, gap analysis as a pure
  function, static layers loaded once, HTML report without pandoc, convex hull
  range method, protected-areas overlay, test suite and CI.
