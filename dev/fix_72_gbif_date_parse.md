# Fix notes: GBIF date filter crash (#72)

Branch: `fix/gbif-date-parse` (cut from `main` on 2026-10-12)

## Symptom

A GBIF download with the date filter on failed with

```
GBIF download failed: character string is not in a standard unambiguous format
```

Reported for *Quercus alba*, 200 records, date filter 2018-11-27 to 2026-10-05,
exclude iNaturalist, require name match, spatially spread. The other options
were not the cause; any date-filtered download of an affected taxon fails.

## Root cause

GBIF's `eventDate` is a free-form ISO 8601 string. A pool can mix

| Shape | Example |
|---|---|
| full date | `2011-08-14` |
| timestamp | `2026-04-08T08:59:10` |
| range | `2018-11-27/2018-11-30` |
| partial date | `2023-07`, `2018` |

`gbif_apply_filters()` parsed the column with base `as.Date(df$eventDate)`.
That call tries two formats on the **first non-missing value only** and throws
the error above when that value is partial. The `suppressWarnings()` around it
did nothing because this is an error, not a warning. The saved test fixture
already contained a `2023-07` record; it never failed in tests only because a
full date came first.

## Reproduction (before the fix)

```r
source("global.R"); for (f in list.files("R", full.names = TRUE)) source(f)
pool <- readRDS("tests/testthat/fixtures/gbif_magnolia_fraseri.rds")
pool$eventDate[1] <- "2018"
gbif_apply_filters(pool, date_range = as.Date(c("2018-11-27", "2026-10-05")))
# Error: character string is not in a standard unambiguous format
```

## Change

`R/gbif_functions.R`

1. New helper `gbif_parse_date(x)`. Strips the time and the end of a range,
   pads partial dates to the first day of their period (`2018` becomes
   `2018-01-01`, `2023-07` becomes `2023-07-01`), then parses with an explicit
   `%Y-%m-%d` format. Unparseable values become `NA` instead of raising.
2. The date filter in `gbif_apply_filters()` uses the helper.
3. The two "most recent first" orderings (`select_spatially_spread()` and the
   `recent` method in `gbif_select_records()`) sort on the parsed date rather
   than the raw string, so partial dates sort sensibly and undated records go
   last. Ordering is at day precision.

`tests/testthat/test-gbif_functions.R`

- New test for the parser across every shape above.
- New test that plants a year-only date in row one of the fixture pool and runs
  the exact option set from the report through `gbif_gather()`.
- The existing "most recent first" assertion compares parsed dates instead of
  raw strings, since same-day records with different times now tie.

## Decision to be aware of

A partial date resolves to the earliest day it could mean. So a `2018` record
is excluded from a range starting 2018-11-27 but included in one starting
2018-01-01. GBIF's own server-side date filter is looser and returns such
records either way. If every partial-dated record GBIF returns should be kept,
relax the comparison to only the date parts that exist.

## Verification

```
Rscript -e 'testthat::test_file("tests/testthat/test-gbif_functions.R")'   # all pass
Rscript tests/testthat.R                                                   # 311 pass
```

Three failures in `test-gap_metrics.R` are pre-existing on `main` and unrelated:
two GRS golden values differ by about 1e-5 (geometry library drift on this
machine) and one test needs the `lwgeom` package, which is not installed.

## Commit and close

```bash
git add R/gbif_functions.R tests/testthat/test-gbif_functions.R dev/fix_72_gbif_date_parse.md
git commit -m "fix(gbif): tolerate partial eventDate values in the date filter and recent-first ordering (#72)"
git push -u origin fix/gbif-date-parse
```

Open a pull request into `main`. The CI workflow runs the unit tests. Reference
`#72` in the PR body; the remaining items on that issue (selection defaults,
the GBIF-order versus most-recent comparison) are handled with #65 and #66.
