# T-01: Drop rows without a G/H germplasm type at upload, with consent

Status: todo
Branch: `fix/t01-germplasm-type` (from `dev`)
Spec: `dev/specs/critical-fixes.md` section "T-01"
Audit: `BUG_AUDIT_2026-10-17.md` finding C-2 (critical); makes M-13 moot
Depends on: T-00

## Context

The upload path keeps rows whose `Current Germplasm Type` is not G or H and
tells the user they "will be ignored by the gap analysis"
(`R/module_controls.R:613-622`). They are not ignored: `run_gap_analysis()`
(`R/gap_analysis_functions.R:355`) buffers every coordinate row, so those rows
inflate the range model, the ERS universe and GRS. On
`appData/Magnolia_acuminata_data_small.csv` at 50 km, blanking one H row's type
moves GRS from 61.92 to 77.67 and flips the priority from Medium to Low. The
report then recodes the blanks to H (M-13) and contradicts the app.

GBIF downloads always assign G or H (`R/gbif_functions.R:333`), so only uploads
introduce such rows.

Decision (spec): such rows are dropped at upload after the user confirms in a
modal. The pipeline filters to G/H as a safeguard. Nothing is kept "in grey".
Rule: after `trimws()` and `toupper()`, the value must be exactly "G" or "H".
Blank and unrecognised values are one rule, one message.

## Change

### 1. `R/fctn_read_upload_file.R` (pure function)

After step C (coordinates and metadata) and before the coordinate quality
check:

- normalise the column: `type <- toupper(trimws(data$\`Current Germplasm Type\`))`,
  treating NA as "".
- `keep <- type %in% c("G", "H")`; `n_dropped_type <- sum(!keep)`;
  `dropped_values <- head(unique(type[!keep]), 5)` (empty string shown as
  "blank" in messages).
- `data <- data[keep, ]` and recompute `index = dplyr::row_number()`.
- Add `n_dropped_type` and `dropped_values` to the returned list for the
  success case (0 and `character(0)` when nothing was dropped).
- Message text when `n_dropped_type > 0`: append to the existing message
  ". N record(s) with a blank or unrecognised Current Germplasm Type were
  dropped." and set `message_type = "warning"`. Keep the existing
  missing-coordinates note as well.
- If every row is dropped, return a `validation_error`: "Data not loaded. No
  rows have a Current Germplasm Type of G or H."

### 2. `R/utils.R`

- Delete `flag_invalid_germplasm()` and its call in `merge_and_index()`.
- Rewrite the comment above it: non-G/H rows are dropped at upload by
  `read_upload_file()`; `merge_and_index()` can assume G/H only.

### 3. `R/module_controls.R` (upload observer)

- Delete `warn_invalid_germplasm()` and its two call sites (lines 679, 698).
- Add `pendingTypeDrop <- reactiveVal(NULL)`.
- In `observeEvent(input$uploadData)`, after the validation/system error
  branches and before `upload_status(...)` is set:
  - if `res$n_dropped_type > 0`: `pendingTypeDrop(res)`, then `showModal()`:
    - title: "Records without a germplasm type"
    - body: "<N> of <total> records have a blank or unrecognised Current
      Germplasm Type (found: <values>). Only records typed G or H are analysed,
      so these records will be dropped. To include them, assign a type of G or
      H in your file and upload it again."
    - footer: `actionButton(ns("cancelTypeDrop"), "Cancel upload")` and
      `actionButton(ns("confirmTypeDrop"), "Drop them and continue", class = "btn-primary")`.
    - `return()` so nothing else happens before the click.
  - otherwise continue exactly as today.
- Factor the remainder of the current observer (set `upload_status`, overwrite
  check, merge, toast) into a local function `commit_upload(res)` so both the
  clean path and `confirmTypeDrop` call it.
- `observeEvent(input$confirmTypeDrop)`: `req(pendingTypeDrop())`; `res <-
  pendingTypeDrop()`; `pendingTypeDrop(NULL)`; `removeModal()`;
  `commit_upload(res)`. If upload data already exists this then shows the
  existing "Overwrite Upload Data?" modal, which is acceptable.
- `observeEvent(input$cancelTypeDrop)`: `pendingTypeDrop(NULL)`;
  `shinyjs::reset("uploadData")`; `upload_status(NULL)`; `removeModal()`.
  `analysis_data()` is untouched.
- `upload_status` after a drop: type `warning`, text is `res$message` (which
  now carries "Loaded 197 records. 3 records with a blank or unrecognised
  Current Germplasm Type were dropped.").
- "Data Format Requirements" modal (line ~765): under Current Germplasm Type
  add " - Must be G or H. Rows with any other value are dropped at upload."

### 4. `R/gap_analysis_functions.R` (safeguard)

In `run_gap_analysis()` directly after `data <- prep_lat_lon(all_data)` and its
empty check:

```r
data <- data[data[[target_col]] %in% c("G", "H"), , drop = FALSE]
if (nrow(data) == 0) stop("No G or H records with valid coordinates to analyse.")
```

(`target_col` is defined one line later today; move its definition above.)
Do not modify `SRSex()`, `GRSex()` or `ERSex()`. No golden value moves: every
fixture is G/H-only (verified 2026-10-22).

### 5. Dead code and docs

- `R/leaflet_maps.R:208`: the `TRUE ~ "gray"` branch is unreachable. Keep a
  default in the `case_when` (it needs one) but change the comment to say it is
  defensive only.
- `R/module_gap_analysis.R:248`: confirm no non-G/H `processing_type` can reach
  `pal_type`; no code change expected.
- `appData/gather_modal.md` (line 7) and the upload paragraph in
  `appData/about.md`: state that rows typed other than G or H are dropped at
  upload with a confirmation.
- `CHANGELOG.md`, Unreleased: "Upload: rows whose Current Germplasm Type is
  not G or H are dropped at upload after confirmation; they no longer inflate
  GRS/ERS (#audit C-2)."

## Acceptance criteria

- [ ] `test-read_upload_file.R`: new test writes a temp CSV from
      `Magnolia_acuminata_data_small.csv` with two extra rows (one blank type,
      one "X", both with coordinates); asserts status success, `nrow == 8`,
      `n_dropped_type == 2`, `message_type == "warning"`, message matches
      "2 records", and all kept types are in G/H. A second case with "g" and
      " h " (lower case, padded) keeps both rows.
- [ ] `test-read_upload_file.R`: a CSV whose rows are all typed "X" returns a
      validation_error mentioning "G or H".
- [ ] `test-gap_metrics.R`: `run_gap_analysis()` on the 8-row small fixture plus
      one appended non-G/H row with coordinates returns GRS, ERS, `Area of model
      km2` and priority identical to the 8-row result (tolerance 1e-6); on an
      all-"X" frame it errors with "No G or H".
- [ ] `test-module_controls.R` (testServer, `controlsModuleServer`): uploading
      the mixed fixture leaves `analysis_data()` with 0 rows and `upload_status()`
      NULL until a button is clicked; `confirmTypeDrop` loads 8 rows and the
      status text contains "2 records"; `cancelTypeDrop` leaves 0 rows and
      status NULL. A clean upload loads with no modal (existing test at line 102
      still passes).
- [ ] `grep -rn "invalid_germplasm\|warn_invalid_germplasm" R/` returns nothing.
- [ ] `Rscript tests/testthat.R` reports FAIL 0.
- [ ] All six golden values in `test-gap_metrics.R` unchanged.

## Files

- `R/fctn_read_upload_file.R`
- `R/utils.R`
- `R/module_controls.R`
- `R/gap_analysis_functions.R`
- `R/leaflet_maps.R` (comment only)
- `appData/gather_modal.md`, `appData/about.md`, `CHANGELOG.md`
- `tests/testthat/test-read_upload_file.R`, `test-gap_metrics.R`, `test-module_controls.R`

## Notes

- Audit M-13 (`reportTemplate.Rmd:60,64` recodes NA types to H) becomes
  unreachable after this ticket because blanks never enter the dataset. Leave
  the report untouched here; record in CHANGELOG that M-13 is closed by this.
(append here while executing)
