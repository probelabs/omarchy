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
