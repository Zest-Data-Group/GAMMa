# T-05: The downloaded report must agree with the app (colours, wording, escaping)

Status: done
Branch: `fix/t05-report-correctness` (from `dev`)
Spec: none; the audit gives the fixes and no decision changes a score. See
`dev/REVIEW_2026-11-25.md` section 2, task 2
Audit: `BUG_AUDIT_2026-10-17.md` findings M-11, M-12, M-14, L-9, L-10 (and the
leftover lines from M-13)
Depends on: T-01

## Context

The report is rendered from the same `run_gap_analysis()` result the app
draws, but it rebuilds the palettes and the explanatory text by hand:

- M-14: `reportTemplate.Rmd` builds the buffer palette with a named vector.
  `leaflet::colorFactor()` ignores names and sorts the levels, so G buffers
  are drawn in the H colour and vice versa, against the report's own legend.
- M-11: the app's ERS palette takes its levels from the data, so a result
  where every ecoregion has the same status is painted in a blend of the two
  colours.
- M-12: uploaded free text reaches the report as raw HTML in the records
  table, the subtitle, the popups and the scores table.
- L-10: the Definitions paragraph gives strict `<` cut-offs; `fcs_priority()`
  and its test use `<=`.
- L-9: the report and the About page say the ERS denominator is the
  ecoregions "occupied by the range"; `ERSex()` counts ecoregions containing
  at least one record.
- M-13: two `replace_na(..., "H")` lines are unreachable since T-01.

## Change

1. `R/leaflet_maps.R`: add `gap_type_palette()` and `gap_ers_palette()`, each a
   `colorFactor` with fixed `levels` and an unnamed palette. They are the only
   place these two palettes are defined.
2. `R/module_gap_analysis.R`: use the two helpers.
3. `reportTemplate.Rmd`:
   - use the two helpers for the buffer and ERS layers;
   - escape the subtitle, the popup Type and Source, and every text column of
     the records table (the GBIF accession link is built from escaped text);
   - delete the two `replace_na` lines;
   - Definitions: "UP when FCS ≤ 25, HP when 25 < FCS ≤ 50, MP when
     50 < FCS ≤ 75, LP when FCS > 75";
   - ERS wording: "ecoregions containing at least one analysed record".
4. `R/report_render.R`: `report_table()` writes its HTML with `cat()` so
   litedown passes it through instead of decoding the escaped cells.
5. `appData/about.md`: same ERS wording.

The wording in 3 and 5 describes the method as it is today. Issue #74 may
change the method later; that is a separate ticket.

Not in this ticket: a single `add_gap_layers()` shared by the app and the
report (review section 5.1). The two maps use different panes, group names
and geometry simplification, so merging them is a refactor of its own.

## Acceptance criteria

New file `tests/testthat/test-report.R`:

- [x] `gap_type_palette()` maps H to `combinedColor[1]` and G to
      `combinedColor[2]`; `gap_ers_palette()` returns `ersexColors[2]` for a
      vector holding only "Gap Ecoregion".
- [x] In a rendered report the Buffers layer's fill colours match the
      `processing_type` of each polygon.
- [x] A report rendered from data whose Taxon Name, Locality and Accession
      Number carry HTML contains none of it as live markup.
- [x] The report states the `≤` cut-offs and the record-based ERS wording.
- [x] `Rscript tests/testthat.R` FAIL 0.

## Files

- `R/leaflet_maps.R`, `R/module_gap_analysis.R`, `R/report_render.R`
- `reportTemplate.Rmd`, `appData/about.md`
- `tests/testthat/test-report.R`
- `CHANGELOG.md`, `dev/tickets/README.md`

## Notes

- 2026-11-25: tests written first; 11 expectations failed on `dev` @ 005c4f5
  and pass after the change. `Rscript tests/testthat.R`:
  `[ FAIL 0 | WARN 3 | SKIP 1 | PASS 500 ]` (was 478; the skip is the browser
  test, no Chrome on this machine).
- Checked a report rendered from a taxon name of
  `<img src=x onerror=alert(1)> Smith & Jones`: the subtitle, the scores
  table cell, the popups and the records table all carry the escaped text,
  with no double escaping (`&amp;lt;` count 0).
- The records table keeps `escape = FALSE` (the GBIF link needs it); every
  character column is escaped before the link is built, and the link target
  is URL-encoded.
- M-13: the two `replace_na(..., "H")` lines are removed. `library(tidyr)`
  stays in the template; the ecoregion table still uses `replace_na` for
  counts.
- L-4 (type shown unescaped in the app's hover label) was left alone: only G
  or H can reach it since T-01.
- The report's map is still built separately from the app's. Only the two
  palettes are shared; see "Not in this ticket".
