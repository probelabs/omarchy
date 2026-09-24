# Fix: issue #10601 — quadratic menu open (visibleRowsHeight re-walks the model per append)

Branch: `fix/issue-10601-layoutserial-invariant`
Base: quattro @ ce925cb (green baseline: 78 reqs / 290 witness rows / 0 uncovered)

## Root cause

`visibleRowsHeight` bound to `displayModel.count` (and filter/divider state), but rebuild
appends rows one at a time — so every append re-ran the full row walk: opening a 231-row
menu walked 26,796 row-visits (the triangular sum) instead of 231. `layoutSerial` already
marked a finished model; the height binding just didn't use it as its only trigger.

## Changes per layer

**Code** (`shell/plugins/menu/Menu.qml`, PR #10631 applied via `git apply --3way`)
- `visibleRowsHeight` (line 120) now binds only to `layoutSerial`:
  `root.dmenuActive ? dmenuRowListHeight(layoutSerial) : rowListHeight(layoutSerial)`,
  with the O(n²) hazard comment (lines 117-119).
- `rowListHeight` / `dmenuRowListHeight` signatures narrowed to `(_serial)` (lines 196,
  216) — the serial is a binding dependency only; the walk always reads the model.
  The `// Implements: SW-REQ-260922-B757` comments were kept during conflict resolution.
- `rebuildDisplay`'s `if (!root.rowsLoaded)` early return (line 664) now bumps
  `layoutSerial` before returning, so an empty model still collapses the card instead of
  keeping the prior height (comment at 662-663).

**Spec tree**
- New `SW-REQ-260924-8PWV` (parent SYS-REQ-260922-J0AN): "when display_model_mutated the
  menu_layout shall always satisfy layout_serial_bumped_before_exit" — the durable
  invariant: every displayModel mutation path (both append loops, both early returns)
  exits through a layoutSerial bump. Rationale pins all four bump sites.
- New `SW-REQ-260924-84E4` (parent SYS-REQ-260922-J0AN): "when rows_presented the
  menu_layout shall always satisfy open_cost_linear_in_row_count" — the performance
  obligation: one walk per finished model, binding never depends on displayModel.count.
- `SW-REQ-260922-B757` rationale refreshed to current line numbers and gains the
  linear-cost note pointing at SW-REQ-260924-84E4.

**Tests** (`test/shell.d/menu-height-quadratic-test.sh`, PR #10631's suite, wired into the
proof.yaml menu-shell job)
- Structural witnesses: binding shape (serial-only), no `displayModel.count` anywhere in
  the binding or helper call sites, narrowed signatures, all four bump sites, empty-model
  early return.
- Arithmetic witnesses mirroring the video harness: `simulate(231, true)` walks 26,796
  (pre-fix triangular sum) vs `simulate(231, false)` walks 231 with exactly 1 height call;
  400-row case stays linear.
- MC/DC: 6 new witness rows (3 per new requirement). Violation rows dispositioned as
  defensive ignores (`[reviewed: REVIEW-M2]`): post-fix the un-bumped exit and the
  per-append re-walk are structurally absent. No-action rows carry caller-level
  justifications (serial-only binding; empty-model early return).

## Test results

- `menu-height-quadratic-test.sh`: 14/14 assertions green (13 PR assertions + 1 added
  empty-model witness).
- `proof audit --check tests_pass` — all suites green (121.0 s), including the rewired
  menu-shell job.
- MC/DC delta: 290/290 → **296/296** witness rows (78 → 80 requirements, 0 uncovered).
- `code_mcdc_coverage`: aggregate decisions 39.2%, conditions 42.9%, thresholds met.
- Audit: **0 errors, 0 warnings**.

## Evidence

Public evidence repo: https://github.com/buger/omarchy-proof-evidence
- Bug (before): `issue-10601-quadratic-menu-open-VO.mp4` / `issue-10601-quadratic-menu-open-VO.gif`
  (narrated open of a 231-row menu; the quadratic stall is visible)
- Fixed behavior is witnessed by the arithmetic + structural suite above; no post-fix
  video was recorded for this branch.

## Deviations from the audit's recommendation

- None on the code: PR #10631's diff applied verbatim (fetched live from GitHub this
  session; earlier 503s did not recur). Conflict resolution only preserved our
  `// Implements: SW-REQ-260922-B757` annotations.
- The audit suggested the cost note could live on B757's family; we made it a full
  obligation (SW-REQ-260924-84E4) with MC/DC rows, because the arithmetic witnesses
  (26,796 vs 231) are claims that deserve their own coverage rather than a prose note.
  B757's rationale still carries the cross-reference.
- The PR test suite was extended with one extra assertion (empty-model early return) to
  back the 84E4 no-action row, plus the six MC/DC witness/ignore annotations.
