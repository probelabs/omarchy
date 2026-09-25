# PR #9056 research-delta — summon answers in-flight request as cancelled

Base: ce925cb1 (quattro) · Head: baf7aaf0 · Delta: `shell/plugins/menu/Menu.qml` +8 (open() summon handler)

## Summon handler flow (Menu.qml `open(payloadJson)`)
1. Parse payload JSON.
2. **NEW (delta):** `if (root.requestActive) root.finishRequest(null)` — before any new
   open path, an in-flight select/input request is answered as cancelled.
3. Apply `fontFamily` override.
4. `payload.mode === "select" | "input"` → `openDmenu(payload)`; else `openRoute(...)`.

## requestActive lifecycle
- `openDmenu` sets `requestActive = !!doneFile` (Menu.qml ~line 935) and stashes
  `selectionFile`/`doneFile`.
- `openExistingMenu` unconditionally clears `requestActive = false` and both file paths
  (Menu.qml ~line 905) — **pre-delta this silently abandoned the caller's doneFile**.
- `finishRequest(selection)` (Menu.qml lines 131–149): if `!requestActive || !doneFile`
  → close only (SW-REQ-260922-3VTN); else clears state, then:
  - `selection == null/undefined` → create done file only (SW-REQ-260922-C8HX);
  - else → write selection file + done file (SW-REQ-260922-FGZQ).
- `cancel()` calls `finishRequest(null)` when `dmenuActive`.

## finishRequest(null) semantics (cancelled answer)
Creates (truncates) only the done file. The polling caller observes an empty selection
file and exits 1 (cancelled) — the same observable outcome as the user pressing Escape.

## Who polls doneFile
- `bin/omarchy-menu-select` lines 93–95: `while [[ ! -e $done_file ]]; do sleep 0.05; done`
  — unbounded poll (KI-MENU-SELECT-POLL-DEADLOCK). Same pattern in `bin/omarchy-menu-input`.

## Pre-delta defect path this mitigates
Summons are single-instance: any `omarchy-shell shell summon omarchy.menu ...` while a
select/input request is in flight (repeated trigger key, second script, keybind) routed
through `openDmenu` (overwrites file paths) or `openRoute`→`openExistingMenu` (clears
them). The first caller's doneFile was then never written → infinite poll →
KI-MENU-SELECT-POLL-DEADLOCK. Post-delta, every summon resolves the prior request as
cancelled before opening, so the poll always terminates.

## Remaining gap (out of delta scope)
The poll is still unbounded for true peer death (Quickshell crash with no further
summon). The delta mitigates the *abandoned-request* trigger only; the bounded-wait
spec gap called out in KI-MENU-SELECT-POLL-DEADLOCK remains open.

## spec-review-delta findings (step 6)
Delta-related findings, all fixed:
- changed_requirements_reviewed: 7 changed specs still draft (the 5 SW + 2 SYS this refresh
  touched) -> promoted to review with grounded spec_conformance ReviewRecords REVIEW-21..25
  (citation-backed, per-branch judgments) and verification.review in_review stamps matching
  the baseline agent:kimi-dogfood precedent.
- spec_lint_status_vs_review: 7 issues caused by the promotion -> fixed via review stamps.
- spec_lint_spec_conformance_review_grounded: 5 issues (new at review status) -> fixed by
  REVIEW-21..25.

Pre-existing baseline debt (documented, NOT fixed — out of delta scope):
- gaps_clean: 6 unconstrained output variables in specs/system/menu (dismissal_signalled,
  rows_hidden_or_marked_per_results, lifecycle_answered, +3).
- variable_orphans_clean: 12 declared-unused variables in specs/system/menu.
- interface_coverage: lock and menu components have no INT interface specs.
- spec_lint_prose_ste100: 11 prose issues, mostly proof/known-issues/KI-MENU-SELECT-POLL-DEADLOCK.yaml.
- code_predicates_modeled: 2 unmodeled predicate sites (Menu.qml charCodeAt, MenuModel.js isVisible).
- Trace quirk: 4 derived implemented_by links to Menu.qml:requestDeleteSelected mis-attribute
  annotations (function-boundary detection); derived links cannot be removed via trace remove.
- orphan_code_clean: 2 unmodeled upstream menu keybindings scripts
  (bin/omarchy-menu-herdr-keybindings, bin/omarchy-menu-tmux-keybindings; post-quattro
  upstream additions 03b825f5 / 3edf254a) surfaced when the box proof binary moved
  gfbfdcd400 -> gec4c02971 (merged main detects subshell-style `name() ( ... )`
  functions). No requirement coverage exists for either script; parked via lint.exclude
  in proof.yaml pending the baseline-debt modeling track.
