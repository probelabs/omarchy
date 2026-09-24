# Proof Re-Audit — omacom/omarchy#13012 (restore selection on Back)

**Branch:** `review/pr-13012` (dogfood tree @ quattro `ce925cb` + PR diff)
**Diff source:** `https://github.com/omacom/omarchy/pull/13012.diff` (fetched 2026-09-24)
**Static audit:** `pr-13012-restore-selection-on-back.md` (verdict APPROVE-WITH-COMMENTS)
**Re-audit verdict: CONFIRMED — and the static audit's fragility prediction fired on first contact.** The PR's own new test crashes on an annotated tree (regex null-deref, exactly as review comment 1 warned), and the PR silently changes the navStack payload shape out from under an existing live witness. Both fixed on this branch with the review's recommended changes; tree then returns to 290/290 green.

---

## 1. Application

| File | Diff base blob | Dogfood blob | Result |
|---|---|---|---|
| `shell/plugins/menu/Menu.qml` | `aa879c188fd` | `82f86a90c5d` (annotated) | 3-way merge, **one conflict**: dogfood's `// Implements: SW-REQ-260922-DE93` line vs the new 4-arg signature — resolved keeping both |
| `test/shell.d/menu-test.sh` | `a424379b1af` | `43dece78e3a` (annotated) | 3-way clean |

Verified post-merge: `{menu, index, itemId}` push before `activeMenu` reassignment, `selectedIndex = restoreSelection ? … : 0`, id-scan with `rowSelectable` guard after `rebuildDisplay()`, `goBack` passing `previous` as the 4th arg (Menu.qml:778-815).

## 2. Breakage found by running the PR against a proof tree (the re-audit's new data)

| # | Failure | Root cause | Disposition on this branch |
|---|---|---|---|
| 1 | `menu-test.sh` **crashes** (`TypeError: null[0]`, rc=1) at the PR's new vm test | The extraction regex `/function setActiveMenu\([\s\S]*?\n  \}\n\n  function goBack/` requires the two functions to be adjacent with exactly one blank line; the dogfood tree carries a one-line `// Implements:` annotation between them. **This is the exact failure mode the static audit's review comment 1 predicted** ("silently breaks if reordered, re-indented, or separated… failure mode is a regex null deref"). | Applied the review's recommended fix: extract each function independently with a loud `assert(m !== null, …)` (marked REVIEW-FIX in the file). Suite then passes, including both new vm witnesses (plain restore; reorder-following by id). |
| 2 | `menu-compositor-test.sh` live witness **fails**: `drill-in pushes the path` | The witness asserted `.navStack[0] == "root"`; the PR changes the payload from string to `{menu, index, itemId}`. State dump at failure: `navStack:[{"menu":"root","index":2,"itemId":"nav"}]`. DE93's push/pop *semantics* hold; the shape assertion was collateral. | Witness updated to the record shape (`.navStack[0].menu/itemId/index`), and the same live run now **additionally observes the PR's new behavior**: after Back, `.selectedIndex == 2 and .rows[2].itemId == "nav"` — cursor restored to the drilled-from row by id, on a real shell with real key events. |
| 3 | `test/node/menumodel-replay.test.mjs` fails (dogfood mirror) | Replay body is a verbatim extraction of menu-test.sh; the PR's updated pointer-gate regex (4-arg signature) had to be ported. Same maintenance step as PR 12223; upstream has no `test/node/`. | Mirror re-extracted; passes. |

Without fixes 1-3 the branch stands at: tests_pass ✗, code_mcdc_measure ✗, code_mcdc_coverage ⚠ (js evidence partial). With them: all green (§4).

## 3. Spec rows (verified against the applied diff)

| Req | Spec text (verbatim) | Re-audit finding |
|---|---|---|
| **SW-REQ-260922-DE93** | "Drilling in pushes the previous menu on the navigation stack; Backspace/Left pops it, or falls back to the parent menu when the stack is empty; entering a menu clears the filter." | **Semantically preserved** — push/pop/fallback/filter-clear all verified in the diff and live. Payload shape changed (string → record); grep confirms the only navStack consumers are the push, the pop, and the two resets (openDmenu/openExistingMenu), so the shape change cannot leak. |
| **SW-REQ-260922-Z48F** | "Cursor movement lands on the next selectable row… disabled rows are stepped over." | Preserved — restore scan keeps the `rowSelectable(i)` guard. |
| **SW-REQ-260922-3JG5** | "When every row is disabled the menu shows no cursor at all…" | Preserved — `settleCursor`/`nextSelectable` still normalize the restored index. |

**Untracked behavior change (additive), confirmed:** "Back restores the previously selected row, following it by id across reorders" has **no governing requirement** — DE93 covers retracing the *menu*, not the *cursor*. In a proof tree this PR must add a child of SYS-REQ-260922-P708 (suggested FRETish in the static audit §2). This branch's live compositor run demonstrates the behavior exists and is observable; it just has no contract.

## 4. Suite & audit results (branch, after §2 fixes)

| Suite | Result |
|---|---|
| `menu-test.sh` | PASS — incl. PR's vm witnesses: restore `selectedIndex == 2`; reorder-follow to index 0 |
| `menu-guards-test.sh` | PASS |
| `menu-dmenu-test.sh` | PASS (navStack resets in the dmenu path unaffected) |
| `menu-compositor-test.sh` | PASS — live shell, wtype keys; restore now positively witnessed |
| `menumodel-replay.test.mjs` | PASS (mirror sync, §2.3) |

`proof audit --check tests_pass,code_mcdc_measure,code_mcdc_coverage,mcdc_coverage`: **all ✓, 0 errors, 0 warnings.**

## 5. MC/DC delta (quattro `ce925cb` → branch)

| Measure | Before | After | Delta |
|---|---|---|---|
| Spec witness rows (78 reqs) | 290/290, queue cleared | 290/290, queue cleared | none added/lost/broken — **after** witness-shape repair; as-applied the PR breaks one live witness (§2.2) |
| Code MC/DC aggregate | 40/102 decisions (39.2%), 63/147 conditions (42.9%) | identical | no movement — QML-only production change; QML is not instrumentable by the js/bash engines |

The PR's vm test is a genuine behavioral witness (drives the real extracted functions), but extraction-style tests are only as strong as the regex — demonstrated.

## 6. Witness gaps (carried from the static audit, still open)

| Missing witness | Status on branch |
|---|---|
| Restore when the remembered row is now **disabled** → settle on nearest selectable, never the disabled one (Z48F/3JG5 cross-guard) | absent |
| Restore when the remembered **id is absent** → clamped old index, not 0, not crash | absent |
| `goBack` with **empty navStack** falls back to parent with `selectedIndex = 0` under the new record shape | absent |

## 7. Honesty caveats

- The two REVIEW-FIX/witness edits on this branch are review-recommended changes, not PR content; they are marked in-file and itemized in §2. The "green" claim applies to PR + these fixes.
- The live restore observation uses the compositor suite's read-only, test-injected probe (shipped tree untouched); keys are real virtual-keyboard events via wtype on headless sway.
- QML code paths changed by the PR contribute no code-MC/DC counters; coverage claims rest on the vm test and the live compositor witnesses.

---
*Re-audit: proof 0.1.0-dev+gfbfdcd400b15 (Linux x86_64), dogfood quattro @ ce925cb, node v24.15.0 userland. Branch log `reaudit-pr-13012.log`. Nothing pushed.*
