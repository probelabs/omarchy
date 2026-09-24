# Proof Re-Audit — omacom/omarchy#12223 (search ranking: apps above menu entries)

**Branch:** `review/pr-12223` (dogfood tree @ quattro `ce925cb` + PR diff)
**Diff source:** `https://github.com/omacom/omarchy/pull/12223.diff` (fetched 2026-09-24)
**Static audit:** `pr-12223-search-ranking.md` (verdict APPROVE-WITH-COMMENTS)
**Re-audit verdict: CONFIRMED** — the PR applies, every suite stays green, spec MC/DC stays 290/290, and the two spec contradictions the static audit mapped are confirmed against the executed tree.

---

## 1. Application

| File | Diff base blob | Dogfood blob | Result |
|---|---|---|---|
| `shell/plugins/menu/Menu.qml` | `aa879c188fd` | `82f86a90c5d` (annotated) | applied, hunk offset +45 |
| `shell/plugins/menu/MenuModel.js` | `28c995ea2bc` | `d43b038012a` (annotated) | applied, hunk offset +12 |
| `test/shell.d/menu-test.sh` | `a424379b1af` | `43dece78e3a` (annotated) | `git apply` fails on drift; `git apply --3way` merges cleanly |

Drift is the dogfood tree's own spec/MC/DC annotations; the PR's semantic payload is unchanged. Verified post-merge: `score -= 100` with the cross-tier policy comment (MenuModel.js:376), `rows = appRows.concat(currentRows).concat(deeperRows)` + divider-pair recompute (Menu.qml:705-707), flipped `font` assertion, new `vsc` cross-tier witness, new section-shape regex witness (menu-test.sh:174).

**Dogfood-side sync (not a PR defect):** `test/node/menumodel-replay.test.mjs` is a verbatim extraction of the menu-test.sh assertion body for the js MC/DC engine. The PR flips one assertion, so the mirror was re-extracted (same 3 hunks ported). Without the sync, menu-node fails with the *old* guarantee — which is exactly the tripwire the mirror exists to be.

## 2. Spec rows affected (verified against the applied diff, not copied from the audit)

| Req | Spec text (verbatim) | Re-audit finding |
|---|---|---|
| **SW-REQ-260922-SJ7P** | "…menus and links promote by 2, **apps demote by 5 within a tier**…" | **Contradicted, confirmed in execution.** The diff replaces the within-tier −5 with a cross-tier −100. The shipped `searchScore` executed under node: `vsc` → app `apps.code` −59968 beats menu entries 10026/10027; `font` → `apps.fontforge` −89966 now beats `style.font` −1971 (the disclosed tradeoff). Spec text + FRETish need revision in the same change. |
| **SW-REQ-260922-TKDP** | "Search lists **current-menu matches before deeper (drilldown) matches**, with a divider section exactly when both groups are non-empty." | **Contradicted, confirmed.** App rows are drilldown rows; pinning them above `currentRows` inverts the specified order whenever apps match. The divider clause survives: `rows.some(section==="drilldown") && rows.some(section!=="drilldown")` checked by enumeration over all emptiness combinations. |
| **SYS-REQ-260922-V7W6** | "…ranked by match quality." | Policy redefinition of "quality" to include launch intent; needs a stakeholder-visible note. |
| **SW-REQ-260922-PRNV** | "An exact id match wins over every alias; app rows are never routable…" | Unaffected — routing untouched; retained routing test still green. |

## 3. Suite results (branch)

| Suite | Result |
|---|---|
| `test/shell.d/menu-test.sh` | PASS (includes PR's flipped + new witnesses) |
| `test/shell.d/menu-guards-test.sh` | PASS |
| `test/shell.d/app-search-test.sh` | PASS |
| `test/shell.d/menu-compositor-test.sh` | PASS (live shell, wtype keys, full run) |
| `test/node/menumodel-replay.test.mjs` | PASS (after mirror sync, §1) |
| `proof audit` tests_pass (all evidence jobs, instrumented) | PASS — 118 s, all tests passed |

## 4. MC/DC delta (quattro `ce925cb` → branch)

| Measure | Before | After | Delta |
|---|---|---|---|
| Spec witness rows (78 reqs) | 290/290 covered, queue cleared | 290/290 covered, queue cleared | **no rows added, lost, or broken** |
| Code MC/DC aggregate | 40/102 decisions (39.2%), 63/147 conditions (42.9%) | 41/102 (40.2%), 64/147 (43.5%) | **+1 decision, +1 condition** — the new `vsc` witness drives one more `searchScore` branch each way |
| js engine (MenuModel.js) | 35/93 (37.6%), 56/132 (42.4%) | 36/93 (38.7%), 57/132 (43.2%) | +1/+1, denominators unchanged (no new branches in the diff) |

Audit checks: `tests_pass` ✓, `code_mcdc_measure` ✓, `code_mcdc_coverage` ✓ (floors met), `mcdc_coverage` ✓. **Errors: 0, Warnings: 0.**

The PR's test edits are witness-grade: they flip the SJ7P guarantee assertion loudly and add a cross-tier independence witness (`vsc`) plus a structural regex for the TKDP-shaped section order. No existing witness row was weakened or deleted silently.

## 5. Witness gaps (carried from the static audit, still open)

| Missing witness | Status on branch |
|---|---|
| Divider-count row: query yielding apps + current + deeper rows renders **exactly one** divider | still absent — the regex pins row order, not divider count |

## 6. Honesty caveats

- Blob drift vs the PR's base is dogfood annotation drift, not upstream movement; semantic context matched exactly (3-way clean, verified by grep of the merged payload).
- QML (`Menu.qml`) is not instrumentable by the js/bash MC/DC engines; the partition change is witnessed by the menu-test.sh regex + compositor suite, not by code-MC/DC counters.
- The `menu-compositor-test.sh` run requires the headless sway session and a `wtype` binary (built locally in `~/proof-env/bin`); it skips cleanly without them.
- The node replay mirror sync (§1) is a dogfood-tree maintenance step; upstream has no `test/node/`.

---
*Re-audit: proof 0.1.0-dev+gfbfdcd400b15 (Linux x86_64), dogfood quattro @ ce925cb, node v24.15.0 userland. Baseline log `reaudit-baseline-quattro.log`, branch log `reaudit-pr-12223.log`. Nothing pushed.*
