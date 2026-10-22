# T-02: Undo Delete is valid only while the dataset is the one the delete produced

Status: todo
Branch: `fix/t02-undo-signature` (from `dev`)
Spec: `dev/specs/critical-fixes.md` section "T-02"
Audit: `BUG_AUDIT_2026-10-17.md` findings C-3 (critical), M-9 (medium)
Depends on: T-00

## Context

In `R/module_data_analysis.R` (lines 209-235) `analysis_data_backup` is written
only by Delete Selection and cleared only by Undo. The four writers of
`analysis_data()` in `module_controls.R` (GBIF gather, upload, their overwrite
confirms) never invalidate it, so:

- Load 8 rows, delete 2, gather 200 GBIF records, click Undo: the dataset
  reverts to the old 8 rows, the 200 GBIF rows are gone, the toast says
  "Successfully restored -192 records", and gap results are cleared.
- The backup is taken before the empty-selection check, so Delete with nothing
  selected overwrites the real backup; Undo then restores 0 records.
- Undo restores the pre-delete frame (old index values) without clearing
  `selected_points()`, so a selection made between delete and undo now points
  at a different record (M-9).

Decision (spec): store a digest of the post-delete frame; Undo is enabled only
while the live frame still matches it. Single-level undo stays. No toast when
Undo greys out. `digest` is already in renv.lock.

## Change

All in `R/module_data_analysis.R`, inside `dataAnalysisServer()`.

1. Add `backup_sig <- reactiveVal(NULL)` next to `analysis_data_backup`.
2. Add a helper `undo_available <- reactive({ nrow(analysis_data_backup()) > 0 &&
   !is.null(backup_sig()) && identical(digest::digest(analysis_data()), backup_sig()) })`.
3. `observeEvent(input$deleteSelection)`:
   - keep `req(nrow(analysis_data()) > 0)`;
   - move `analysis_data_backup(analysis_data())` to after the
     `length(current_selection) == 0` early return;
   - after `updated_data` is built: `backup_sig(digest::digest(updated_data))`
     then `analysis_data(updated_data)` as today.
4. Replace the toggleState observer with one that reads `undo_available()`; in
   the same observer, if the backup is non-empty but `undo_available()` is
   FALSE, clear `analysis_data_backup(data.frame())` and `backup_sig(NULL)` so
   a stale backup cannot linger.
5. `observeEvent(input$undoLastDelete)`:
   - `req(undo_available())`;
   - compute the restored count, restore, toast as today;
   - `selected_points(numeric(0))` (M-9);
   - clear backup and signature.
6. Update the NOTE comment above the observers to describe the signature rule.

Do not change `module_controls.R`.

## Acceptance criteria

New file `tests/testthat/test-module_data_analysis.R`, driven with
`shiny::testServer(dataAnalysisServer, args = list(analysis_data = analysis_data,
selected_points = selected_points), ...)`, using `load_fixture_dataset()` from
the helpers. Follow the patterns in `test-module_controls.R`. Read
`session$getReturned()`-free state through the reactiveVals passed in.

- [ ] Stale backup: load `Magnolia_acuminata_data_small.csv` (8 rows),
      `selected_points(c(1, 2))`, `setInputs(deleteSelection = 1)`: 6 rows and
      `undo_available()` TRUE (expose via `session$env` or test through the
      button's effect). Set `analysis_data()` to the 200-row
      `Magnolia_acuminata_data.csv` fixture; `setInputs(undoLastDelete = 1)`:
      `analysis_data()` still has 200 rows.
- [ ] Empty delete: 8 rows, delete 2, `selected_points(numeric(0))`,
      `setInputs(deleteSelection = 2)` (warning, no change), then
      `setInputs(undoLastDelete = 1)`: 8 rows restored.
- [ ] Selection cleared on undo: 10 rows (first 10 of the 200-row fixture),
      delete index 2, `selected_points(2)`, undo: `selected_points()` has
      length 0 and the frame has 10 rows.
- [ ] Normal path: delete 3 then undo restores all rows and the toast count is
      positive (capture with `shiny::showNotification` mocked, or assert on the
      row count only).
- [ ] `Rscript tests/testthat.R` reports FAIL 0.
- [ ] CHANGELOG.md line under Unreleased.

## Files

- `R/module_data_analysis.R`
- `tests/testthat/test-module_data_analysis.R` (new)
- `CHANGELOG.md`

## Notes

(append here while executing)
