# Threat-surface delta — PR #9056 upstream refresh (package: menu)

Companion narrative to `proof/surfaces/threat-surface.yaml` (schema_version 1).
Synthesized 2026-09-25 by `agent:kimi-upstream-refresh` for checklist
`upstream_refresh_v1`, step `threat_surface_synthesis`.

## What the delta changed about the attack surface

Base `ce925cb1` → head `baf7aaf0` adds one guard in
`shell/plugins/menu/Menu.qml:32`: when `open()` runs while
`root.requestActive`, the in-flight dmenu request is first answered as
cancelled (`finishRequest(null)` — done file only, empty selection) before
the new summon dispatches.

Before the hunk, a second summon while a caller was still polling its done
file silently hijacked the shared request state: the first caller was
abandoned and — because `bin/omarchy-menu-select` polls the done file with
no timeout — could wait forever. That is the abandoned-request trigger of
`KI-MENU-SELECT-POLL-DEADLOCK`. After the hunk, the same interleaving is a
defined recovery: the prior caller always observes a cancelled answer.

So the delta does not add a new input surface; it **re-postures an existing
one**. The summon-while-request-active interleaving moves from "undefined
behavior feeding a known deadlock" to "recover, with a spec guarantee"
(SW-REQ-260925-XTGG, hazard classes `scenario/concurrent` +
`property/atomicity`).

## Surface rows and why

### `dmenu-select-ipc` (kind: protocol) — the delta surface

L1 error posture is **recover**, not reject: the mitigation's entire
semantics is graceful cancellation. Crash oracles are therefore dead on
this surface by construction — arming one would be the classic L1
mismatch.

The hard L4 gate is satisfied by an explicit equivalence contract (v1):
two runs are EQUAL when the done-file answer kind (selection text vs
cancelled-empty) and the menu model content match for a fixed summon/input
sequence, normalizing poll timing, pid-dependent paths, and compositor
focus-event ordering. No relational oracle (differential/metamorphic
compare) is armed against live runs until Phase 2 executes the contract on
a Linux shell — recorded expectations in `test/shell.d/` are the only L5
material that exists.

Armed families follow from the lifecycle: sequence fuzzing over the
`idle → active → answered` state machine (L8), a conservation ledger —
exactly one answer per issued request, zero abandoned callers (L3) — and
metamorphic pairs around cancel/summon repetition (L7).

The candidate vector for this surface is **V-MENU-SUMMON-WHILE-ACTIVE**
(P1): repeated or hostile summon IPC interleaved with an in-flight
request, hunting for any path that still abandons a caller or answers
twice. The claims campaign (CRS-0017..0018) already hunted it statically;
one residual race survived as a deferred claim — `resultProc` busy drops a
`finishRequest` answer mid-write (QML `Process` ignores command changes
while running, Menu.qml:1067-1072) — which needs a live-harness PoC in
Phase 2 before it can be promoted (KI) or killed (residual).

### `menu-jsonc-config` (kind: parser) — pre-existing, recorded not re-hunted

Untouched by the delta, but defect-review session CRS-0025 surfaced two
real `stripJsonc` edges (comma-inside-string corruption; inline comments
emptying the whole menu), reproduced by `review/poc-jsonc-strip-edges.mjs`
and deferred. The row exists so the next campaign starts from the artifact
instead of rediscovering the edges. Posture is recover (parse failure →
empty menu, never crash); the L7 metamorphic pair "comments/trailing
commas outside strings must not change the model" is exactly the pair that
fails on the deferred edges. Candidate vector
**V-MENU-JSONC-STRIP-EDGES** (P2).

## Degenerations, honestly

- L12 is `na` on both rows with reasons (no rendering oracle; config parse
  is spec-regulated). Several parser-row questions (`L3/L5/L8/L10/L11`)
  are `na` with reasons rather than silently skipped.
- Differential compare is **blocked, not armed**, on both rows — there is
  no second implementation to diff against. This is recorded under
  `oracle_families_blocked` so a future campaign does not mistake absence
  for oversight.
- The compositor peer-death gap of `KI-MENU-SELECT-POLL-DEADLOCK` remains
  open and is this surface's L11 boundary case (unbounded poll at the
  limit); it is out of delta scope and tracked in the KI ledger, not
  re-filed here.
