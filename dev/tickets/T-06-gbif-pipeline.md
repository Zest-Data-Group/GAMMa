# T-06: GBIF requests time out, and the advanced options do what they say

Status: done
Branch: `fix/t06-gbif-pipeline` (from `dev`)
Spec: none; the audit gives the fixes and no gap score changes. See
`dev/REVIEW_2026-11-25.md` section 2, task 5
Audit: `BUG_AUDIT_2026-10-17.md` findings M-3, M-4, M-5, L-5, L-6, L-13
GitHub: #52 (synonym toggle), part of #72
Depends on: nothing

## Context

- M-3: no GBIF request had a timeout. Shiny serves every session from one R
  process, so one stalled response froze all users.
- M-4: "Include taxonomic synonyms" did nothing while "Require scientific name
  match" was on (the default), because synonym records carry the synonym's own
  name and the name check removed them first.
- M-5: with a date filter on, every reference-selection method (random,
  spatial, most recent) returned GBIF order, because the one-per-year spread
  replaced the method instead of working with it.
- L-5: the standard-download summary labelled the number retrieved as
  "requested".
- L-6: the slider allowed 0, which produced "No records with coordinates
  found on GBIF".
- L-13: the date-filter test used a range holding no fixture record.

## Change

`R/gbif_functions.R`

1. `GBIF_CURLOPTS` (60 s per request, 10 s to connect, abort under 1 byte/s
   for 20 s) and `gbif_occ_search()`, the one place that calls
   `rgbif::occ_search()`. `gbif_counts()`, `gbif_fetch()` and
   `gbif_fetch_standard()` take it as their default `occ` argument.
2. `gbif_accepted_name_matches()`: does the record's accepted name belong to
   the selected taxon. `gbif_apply_filters()` keeps a row when the name check
   passes or, with synonyms included, when this does.
3. `gbif_select_records()`: with `yearly_spread`, order the reference records
   by the method first, take the first record of each year in that order,
   then fill in the same order. `spatial_spread_order()` supplies the full
   spatial ranking.
4. `gbif_gather()` returns `limit`.

`R/module_controls.R`

5. Slider minimum 50; a request of 0 or less is refused with a notification.
6. Summary reads "N records requested, M retrieved".
7. Synonym tooltip rewritten to say what the option now does.

## Acceptance criteria

- [x] Every GBIF request carries the timeout options; nothing but the wrapper
      calls `rgbif::occ_search`.
- [x] A timeout in `gbif_counts()` gives NA counts; in `gbif_fetch()` an error.
- [x] On the fixture, including synonyms with the name check on adds exactly
      the two synonym records; a synonym of a different taxon stays out.
- [x] With a date filter, spatial, recent and random each differ from GBIF
      order, random differs between runs, spatial is more dispersed, and every
      method still covers every year.
- [x] Slider minimum is 50 and a zero request loads nothing.
- [x] `Rscript tests/testthat.R` FAIL 0.

## Files

- `R/gbif_functions.R`, `R/module_controls.R`
- `tests/testthat/test-gbif_functions.R`, `tests/testthat/test-module_controls.R`
- `CHANGELOG.md`, `dev/tickets/README.md`

## Notes

- 2026-11-25: `Rscript tests/testthat.R`:
  `[ FAIL 0 | WARN 3 | SKIP 1 | PASS 553 ]`. The tests were written before the
  code but I did not run them red first; most call functions that did not
  exist yet.
- Live check against api.gbif.org through the wrapper: `gbif_counts(3153619)`
  returned 3,140 / 9 / 2,515 in 1.6 s and a 20-record standard fetch took 2
  requests, so rgbif accepts the options. Forcing `timeout_ms = 1` raised
  "Timeout was reached", which the existing handlers turn into NA counts or a
  "GBIF download failed" toast.
- One existing test changed. "the name-match filter is on by default" relied
  on the fixture's two synonym rows being the records the name check removes;
  those now come back when synonyms are included, so the test uses a record
  re-assigned to another genus instead.
- Behaviour change to be aware of: a download with a date filter and a method
  other than GBIF order now returns different records than before. That is
  the fix, but saved comparisons made with those settings will not reproduce.
- Not done: #72's question of whether "spatially spread" should be the
  default. That is a decision for the grilling session.
