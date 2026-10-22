# Tickets

Local work items derived from `dev/specs/critical-fixes.md` (audit:
`BUG_AUDIT_2026-10-17.md`). Not mirrored to GitHub.

Execute in this order. Each ticket runs on its own branch cut from `dev` and is
merged back only when `Rscript tests/testthat.R` passes in full. Update the
Status line in the ticket file and append to its Notes section as you go.

| Ticket | Audit | Branch | Status |
|---|---|---|---|
| [T-00 Make the test suite green](T-00-tests-green.md) | L-11, L-12 | `fix/t00-tests-green` | todo |
| [T-01 Drop non-G/H rows at upload](T-01-germplasm-type-drop.md) | C-2 (+ makes M-13 moot) | `fix/t01-germplasm-type` | todo |
| [T-02 Undo Delete validity](T-02-undo-delete-signature.md) | C-3, M-9 | `fix/t02-undo-signature` | todo |
| [T-03 Antimeridian convex hull](T-03-antimeridian-hull.md) | C-1 | `fix/t03-antimeridian-hull` | todo |

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
