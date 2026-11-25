# T-07: Uploads from Excel on Windows load correctly or fail with a useful message

Status: done
Branch: `fix/t07-upload-robustness` (from `fix/t06-gbif-pipeline`)
Spec: none; the audit gives the fixes and no gap score changes. See
`dev/REVIEW_2026-11-25.md` section 2, task 4
Audit: `BUG_AUDIT_2026-10-17.md` findings H-1, M-2, L-2, L-3, L-14
Depends on: T-01

## Context

- H-1: a Windows-1252 CSV (Excel's "CSV (Comma delimited)") passed validation
  with a success toast, then the session disconnected when the map built its
  labels from text that was not valid UTF-8.
- M-2: real Excel date cells arrived as serial numbers ("40769").
- L-2: "Latitude" plus "latitude" gave a sticky "Critical error ... duplicate
  names".
- L-3: a semicolon- or tab-delimited file, an empty file, or a workbook
  renamed .csv was reported as missing every required column.
- L-14: the fixture named "..._missing_lat.xlsx" lacks Longitude, so the
  missing-Latitude branch had no test.

## Change

All in `R/fctn_read_upload_file.R`.

1. `sniff_delimited_file()` reads the raw bytes before parsing and returns the
   encoding (UTF-8 if valid, otherwise Windows-1252) and the delimiter (comma,
   semicolon or tab, by count in the header outside quotes; ties go to the
   comma). It returns a message instead for an empty file, a zip/xlsx
   signature, NUL bytes (UTF-16) or a single-column header.
2. CSVs are read with `readr::read_delim()` using that encoding and delimiter;
   every text column is then forced to valid UTF-8.
3. Semicolon files accept a decimal comma in Latitude and Longitude.
4. `restore_excel_dates()` re-reads the sheet with typed cells and replaces
   date cells in Collection Date with `YYYY-MM-DD`. Other cells keep their
   text reading.
5. Known columns that appear twice after header normalisation are a
   validation error naming them.
6. `R/module_controls.R`: one line in the format modal about delimiters.

## Acceptance criteria

- [x] A Windows-1252 row with "Café Niño" loads as that text, valid UTF-8, and
      `point_labels()` does not error.
- [x] UTF-8 with and without a byte-order mark is unchanged.
- [x] The date-cell workbook gives "2011-08-14", "2011-08-03", "2011".
- [x] Duplicate-after-normalising headers: validation error naming the column.
- [x] Semicolon (with decimal commas) and tab files load; a comma file with
      semicolons inside quoted text is still read as comma.
- [x] Renamed workbook, empty file and single-column file each get their own
      message.
- [x] Missing Latitude and missing Longitude are each tested.
- [x] `Rscript tests/testthat.R` FAIL 0.

## Files

- `R/fctn_read_upload_file.R`, `R/module_controls.R`
- `tests/testthat/test-read_upload_file.R`
- `tests/testthat/fixtures/upload_excel_date_cells.xlsx` and
  `make_xlsx_date_fixture.py`, which builds it
- `CHANGELOG.md`, `dev/tickets/README.md`

## Notes

- 2026-11-25: tests written and run red first (10+ failures), then green.
  `Rscript tests/testthat.R`: `[ FAIL 0 | WARN 3 | SKIP 1 | PASS 590 ]`.
- Branch is cut from T-06, not `dev`: every ticket appends to the same lines
  of `CHANGELOG.md` and `dev/tickets/README.md`, so sibling branches would
  conflict on merge. Merge T-06 first, or merge this branch and get both.
- The encoding rule is deliberately simple: not valid UTF-8 means
  Windows-1252. A file in another legacy encoding (for example Mac Roman or
  Shift-JIS) will load with wrong accented characters rather than crash.
- UTF-16 "Unicode Text" exports are rejected with a message, not converted.
- No xlsx writer is installed, so the date fixture is assembled from XML by a
  short Python script (standard library only) kept beside it.
- The misnamed fixture was not renamed; it is referenced from
  `appData/.rscignore` and `.dockerignore` patterns. The test now asserts
  which column it lacks.
- I first wrote the sniffing with byte-wise regex calls, which failed on the
  Windows-1252 input itself ("input string is invalid UTF-8"). The text is now
  converted before any string handling. The H-1 test caught it.
