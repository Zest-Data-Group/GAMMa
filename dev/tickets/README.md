# Tickets

Local work items derived from `dev/specs/critical-fixes.md` (audit:
`BUG_AUDIT_2026-10-17.md`). Not mirrored to GitHub.

Execute in this order. Each ticket runs on its own branch cut from `dev` and is
merged back only when `Rscript tests/testthat.R` passes in full. Update the
Status line in the ticket file and append to its Notes section as you go.

| Ticket | Audit | Branch | Status |
|---|---|---|---|
| [T-00 Make the test suite green](T-00-tests-green.md) | L-11, L-12 | `fix/t00-tests-green` | done |
| [T-01 Drop non-G/H rows at upload](T-01-germplasm-type-drop.md) | C-2 (+ makes M-13 moot) | `fix/t01-germplasm-type` | done |
| [T-02 Undo Delete validity](T-02-undo-delete-signature.md) | C-3, M-9 | `fix/t02-undo-signature` | done |
| [T-03 Antimeridian convex hull](T-03-antimeridian-hull.md) | C-1 | `fix/t03-antimeridian-hull` | done |
| [T-04 Hull G area vs geodesic expanse](T-04-hull-geodesic-area.md) | found in T-03, not in audit | `fix/t04-hull-geodesic-area` | todo (needs grilling) |
| [T-05 Report correctness](T-05-report-correctness.md) | M-11, M-12, M-14, L-9, L-10 | `fix/t05-report-correctness` | done |
| [T-06 GBIF pipeline](T-06-gbif-pipeline.md) | M-3, M-4, M-5, L-5, L-6, L-13 | `fix/t06-gbif-pipeline` | done |
| [T-07 Upload robustness](T-07-upload-robustness.md) | H-1, M-2, L-2, L-3, L-14 | `fix/t07-upload-robustness` | done |

## Executing a ticket (for an agent)

1. `git checkout dev && git pull && git checkout -b <branch>`.
2. Read the ticket, then the spec section it points to, then the audit finding.
3. Set Status to `in progress`.
4. Write the tests listed under Acceptance criteria first; confirm they fail.
5. Make the change. Keep to the files listed; if another file must change,
   say why in Notes.
6. `Rscript tests/testthat.R` must report FAIL 0. Paste the summary line into Notes.
7. Add a CHANGELOG.md line under Unreleased.
8. Commit with a conventional message (`fix(gap): ...`, `fix(upload): ...`),
   set Status to `done`, and report back with the branch name. Do not merge;
   the owner merges.
