# Fix — issue #9057 / KI-MENU-SELECT-POLL-DEADLOCK: orphaned omarchy-menu-select processes

**Branch:** `fix/issue-9057-menu-select-poll` (dogfood @ quattro `ce925cb`)
**Upstream:** [issue #9057](https://github.com/omacom/omarchy/issues/9057), [PR #9056](https://github.com/omacom/omarchy/pull/9056) (summon-side only)
**Evidence videos:** [ki-menu-select-poll-deadlock-NARRATED-VO.mp4 / .gif](https://github.com/buger/omarchy-proof-evidence) (control vs fixed, live)

## Root cause (2 lines)

`bin/omarchy-menu-select` polls its `done_file` with no deadline (`while [[ ! -e $done_file ]]; do sleep 0.05; done`), and `Menu.qml open()` replaces an in-flight select/input request without answering it — so on supersession (#9057) or peer death (KI) nothing ever writes the file and the caller spins forever.

## What changed, per layer

**Code**
- `bin/omarchy-menu-select`: bounded poll — deadline `OMARCHY_MENU_SELECT_TIMEOUT` (default 30 s), stderr diagnostic, exit 1 on expiry. Adopted from the GREEN-video reference (`omarchy-menu-select.fixed`), diagnostic text widened to name both triggers. Covers peer death, which #9056 does not.
- `shell/plugins/menu/Menu.qml`: `if (root.requestActive) root.finishRequest(null)` at the top of `open()` (the #9056 summon-side fix) — a superseded request is answered as cancelled (done-only, per C8HX) before replacement; conditional per 3VTN.

**Spec (the class, not the trigger)**
- `SW-REQ-260924-CV8S` (new, parent X6Z5): *"when summon_supersedes_active_request the dmenu_protocol shall eventually satisfy prior_request_answered_as_cancelled."*
- `SW-REQ-260924-AK4Z` (new, parent X6Z5): *"when peer_unresponsive the dmenu_protocol shall eventually satisfy caller_exits_bounded."* Both carry rationale with file:line pins.

**Tests / MC/DC witnesses**
- `test/shell.d/menu-select-poll-deadlock-repro.sh`: the KI's bound red reproducer **flipped green** (short-deadline env, asserts bounded exit 1 + diagnostic); wired into the `menu-shell` evidence job. Row: `caller_exits_bounded=T, peer_unresponsive=T => TRUE`.
- `test/shell.d/menu-compositor-test.sh` (live shell, real wtype keys): new supersession witness — summon select B while select A is unanswered → A's done file appears with no selection, B answers normally; plus the 3VTN regression guard (open() with nothing active writes no done file). Rows: CV8S T,T => TRUE + F,F no-action.
- Defensive ignores with stated reasons for the two guarantee-violation rows (post-fix structurally unreachable).
- KI ledger: `KI-MENU-SELECT-POLL-DEADLOCK` → `status: fixed` with remediation; evidence recaptured with `--accept-flip` (`known_issue_not_reproduced`, reproducer passes).

## Test results

- `menu-dmenu-test.sh` PASS, `menu-compositor-test.sh` PASS (incl. 2 new witnesses), `menu-select-poll-deadlock-repro.sh` PASS (green flip), full `tests_pass` PASS (~120 s).
- `proof audit --check tests_pass,code_mcdc_measure,code_mcdc_coverage,mcdc_coverage`: **0 errors, 0 warnings**.

## MC/DC delta

| Measure | quattro | this branch |
|---|---|---|
| Requirements checked | 78 | 80 (+2 new obligations) |
| Spec witness rows | 290/290 covered | **296/296 covered** |
| Code MC/DC aggregate | 39.2% decisions / 42.9% conditions | unchanged (poll guard adds one bash decision; `omarchy-menu-select` instrumentation target not enabled) |

## Deviations from the audit's recommendation

- Poll deadline uses `SECONDS`-arithmetic (not a peer-liveness `kill -0` probe): the audit allowed either; the deadline alone covers every shell-side failure mode including a *live* shell that never answers, which a PID probe would miss. The supersession half is covered by the Menu.qml change instead.
- The reproducer was kept as the green witness (not replaced): it is the KI's bound evidence, and the ledger now records the flip.

---
*proof 0.1.0-dev+gfbfdcd400b15, Linux x86_64, node v24.15.0 userland. Audit log: `fix-9057-audit.log`. Nothing pushed.*
