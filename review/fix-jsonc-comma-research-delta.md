# Research delta — fix/jsonc-trailing-comma-in-strings (quattro → 1832b66a)

Campaign: upstream_refresh_v1 on the fix worktree (2026-09-27, agent:kimi-fix-jsonc-refresh).
Delta is OUR fix, not upstream churn: 4 commits, 8 files, +199/−7.

## What changed

`shell/plugins/menu/MenuModel.js stripJsonc`: the string-blind trailing-comma
regex `,(\s*[}\]]) → $1` is replaced by a string-aware single-pass scanner
(lines 1–35). A comma is dropped iff it sits outside every string literal AND
the next non-whitespace byte is `}` or `]` (or EOF). `\"` escapes inside
strings are skipped verbatim. Full-line comment stripping (the
`^\s*//…` regex) is unchanged. Decision variables
`comma_in_string` / `next_char_closes_json` / `trailing_comma_dropped` are
declared in `specs/software/variables/menu.vars.yaml`; the equivalence is
speced as SW-REQ-260927-66FW (parent SYS-REQ-260922-PPDW).

## Verification performed this campaign (macOS, node-only surface)

- `node --test test/node/menumodel-replay.test.mjs` → 1/1 pass (the replay
  suite agent-25 extended; covers all 5 table rows of the 66FW decision).
- Targeted adversarial cases, old-vs-new comparison: pre-fix code SILENTLY MUTATES
  strings while JSON.parse still succeeds:
  - label `"x, ]y"` → `"x ]y"` (display corruption — failure mode a)
  - action `"mv f{.bak,}"` → `"mv f{.bak}"` (brace expansion destroyed → mv
    targets a literal filename `f{.bak}` — failure mode b)
  - action `"awk '{print $1, }' f"` → `"awk '{print $1 }' f"` (output format
    silently changed — failure mode b)
  All three parse successfully under the old stripper, so the corruption was
  invisible to the 3T3F error path. The new scanner preserves all three.
- 20,000-case differential fuzz of stripJsonc against an independently
  written reference scanner over an adversarial alphabet
  (`{}[], "\` whitespace): 0 mismatches.
- Unterminated string → copied verbatim → JSON.parse throws → 3T3F catch →
  empty item set. No crash path.

## Residual edges (pre-existing, NOT introduced or worsened by the delta)

- Comment stripping remains line-anchored: inline trailing comments
  (`{"a": 1} // note`) are not stripped and fail the parse → empty menu via
  3T3F. Unchanged from quattro; tracked for defect-review disposition.
- EOF-terminated comma (`…,` with no closing byte) is dropped — lenient,
  matches the spec formula's boundary row (next>=len ⇒ drop), witnessed.

## Out-of-delta context

The dmenu request lifecycle (Menu.qml) is untouched here; the
KI-MENU-SELECT-POLL-DEADLOCK ledger entry is refresh-branch scope, not this
campaign's delta.
