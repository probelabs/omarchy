# Fix: issue #10340 — search ranking policy (apps buried below menu entries)

Branch: `fix/issue-10340-ranking-policy`
Base: quattro @ ce925cb (green baseline: 78 reqs / 290 witness rows / 0 uncovered)

## Root cause

The menu search scorer gave menu/drilldown entries a +2 in-tier promotion and no cross-tier
bias for installed apps, so a marginally better textual menu match outranked the app the user
wanted to launch. Separately, the search view rendered one flat list, so even correctly ranked
output mixed launch targets and configuration actions with no visual separation.

## Changes per layer

**Code**
- `shell/plugins/menu/MenuModel.js` — applied PR #12223's ranking fix, with the magic number
  replaced by a named constant: `APP_RANK_BIAS = 100` (line 357) with an INVARIANT comment
  (the bias must exceed every match tier; max tier is 80). App rows now get
  `score -= APP_RANK_BIAS` (line 381), so installed apps rank above menu entries across tiers.
- `shell/plugins/menu/Menu.qml` — PR #12223's divider rendering: the search list draws a
  section divider between the installed-app section and the menu/drilldown section.

**Spec tree**
- `SW-REQ-260922-SJ7P` (scoring) — description revised to state the tier ladder, the +2
  menu/link promotion, and the APP_RANK_BIAS cross-tier rule with its invariant.
- `SW-REQ-260922-TKDP` (search presentation) — description revised to require the divider
  section exactly when both section kinds (app matches, menu/drilldown matches) are non-empty.
- `STK-REQ-260922-XTNR` — stakeholder note appended: ranking prefers launch targets over
  configuration actions for ambiguous queries, because typing in the menu is overwhelmingly
  launch intent (issue #10340).
- Rationales on SJ7P/TKDP updated to quote the new code locations.

**Tests**
- `test/shell.d/menu-test.sh` — PR #12223's test hunks applied: flipped assertions that
  pinned the old buggy order now assert apps outrank menu entries.
- `test/node/menumodel-replay.test.mjs` — same assertion diff ported to the replay mirror
  (mechanical path-rewrite of the menu-test diff).
- `test/shell.d/menu-compositor-test.sh` — new live-compositor divider-count witness for
  SW-REQ-260922-TKDP: probe rows carry `section`, and a new block asserts rows[0] is an app,
  exactly one non-drilldown→drilldown boundary exists, and both sections are non-empty
  (MCDC row `matches_span_menus=T, sections_divided=T => TRUE`).

## Test results

- `proof audit --check tests_pass` — all suites green (118.7 s): menu-test rc=0,
  menumodel-replay 1/1, menu-compositor incl. new divider witness green.
- MC/DC delta: 290/290 witness rows → 290/290 (no new obligations; two descriptions
  revised, witnesses unchanged). `mcdc_coverage`: 78 requirements, 0 uncovered.
- `code_mcdc_coverage`: aggregate decisions 40.2%, conditions 43.5%, thresholds met.
- Audit: **0 errors, 0 warnings**.

## Evidence

Public evidence repo: https://github.com/buger/omarchy-proof-evidence
- Bug (before): `issue-10340-search-ranking-VO.mp4` / `issue-10340-search-ranking-VO.gif`
- Fixed (after): `pr-12223-search-ranking-VO.mp4` / `pr-12223-search-ranking-VO.gif`

## Deviations from the audit's recommendation

- The audit recommended adopting PR #12223's `score -= 100`; we kept the behavior but named
  the constant (`APP_RANK_BIAS`) and documented its invariant, per review comment 1 of the
  re-audit — the magic number's constraint (must exceed every tier) is now enforceable text.
- The divider-count MC/DC row is witnessed twice (regex witness in menu-test + live
  compositor witness in menu-compositor-test); both are kept intentionally.
