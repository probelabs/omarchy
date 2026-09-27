# Threat-surface delta — fix/jsonc-trailing-comma-in-strings (package: menu)

Companion narrative to `proof/surfaces/threat-surface.yaml` (schema_version 1).
Synthesized 2026-09-27 by `agent:kimi-fix-jsonc-refresh` for checklist
`upstream_refresh_v1`, step `threat_surface_synthesis`.

## What the delta changed about the attack surface

The delta is our own fix, so the surface story runs backwards from the usual
refresh: the quattro baseline had a LIVE silent-mutation mode on the JSONC
config surface, and this branch closes it.

Pre-fix, `stripJsonc`'s string-blind regex `,(\s*[}\]]) → $1` deleted commas
inside string literals whenever the next byte (after optional whitespace —
including none) was `}` or `]`. Because `JSON.parse` accepts the stripped
text, the mutation was invisible: no error, no crash, just wrong data. Two
failure modes, both reproduced old-vs-new on 2026-09-27:

- **(a) display corruption** — `"x, ]y"` rendered as `"x ]y"`.
- **(b) command mutation (the realistic payload)** — an `action:` string like
  `mv f{.bak,}` became `mv f{.bak}` (brace expansion destroyed; `mv` then
  targets a literal filename) and `awk '{print $1, }'` became
  `awk '{print $1 }'` (output format silently changed for downstream
  pipelines). omarchy-menu executes action strings with the invoking user's
  full privileges, so the mutated command RUNS mutated. No privilege
  escalation — the user authors the config — but the
  explicit-configuration contract was violated invisibly.

Post-fix, the string-aware scanner (SW-REQ-260927-66FW) makes the mutation
class structurally unreachable, witnessed by all five MC/DC rows and a
20,000-case differential fuzz against an independent reference scanner.

## Ladder answers that carry weight

- **L1** — recover posture: parse failure degrades to an empty menu (3T3F
  catch). Crash oracles are dead here; the pre-fix danger was the opposite of
  a crash (silent success on mutated text), which is exactly the mode crash
  oracles can never see.
- **L4** — equivalence contract v1 was defined before the metamorphic and
  differential lanes armed: two configs are EQUAL when the parsed ordered item
  models match, normalizing whitespace, key order, full-line comments, and
  legal trailing commas outside strings.
- **L7** — the load-bearing metamorphic pair: inserting/removing comments and
  legal trailing commas outside strings must not change the model. This pair
  FAILED pre-fix for comma+closer inside strings — the DEFECT-260927-CMMA
  class — and holds post-fix.

## Degenerations, honestly

- L8/L10 are `na` with reasons (stateless pure parse).
- Live differential against a second production parser is blocked: verified
  that no `bin/` script parses the menu JSONC (the "mirrors the bash bin's jq
  pipeline" comment at Menu.qml:235 is stale prose — noted in the CRS-0020
  deliverable). The campaign substituted an independently written reference
  scanner for the fuzz lane.
- Two pre-existing edges survive as deferred claims with PoC
  (`review/poc-parse-edges.mjs`), NOT closed by this branch and deliberately
  out of the PR's scope: inline comment tails empty the whole menu
  (CRS-0017/C01), and top-level arrays of objects leak phantom rows
  (CRS-0019/C01).

## Vector

**V-MENU-JSONC-INPUT** (P1) covers the JSONC-input attack angle: user config
carrying comma-in-string payloads reaching display or execution mutated. The
campaign was executed statically this cycle (claims sessions + reproduction +
fuzz); exit recorded with the residual link in the residual step.
