Reproduces `review/media/menu-jsonc-comment-tail.mp4` (upstream issue #13493): a `//` note on the same line
as, and after, a trailing comma makes the menu parser fail and the menu shows no rows.

Fixtures:
- `menu.jsonc`: three rows; the last ends `}, // favorites`.
- `omarchy-menu.jsonc`: upstream's `config/omarchy/extensions/omarchy-menu.jsonc` (as of `8b4eae66`) with
  the three example rows uncommented and one inline `// favorites` note on the last. Shown in the clip.
- `fullline-control.jsonc`: control. Trailing comma, then a full-line `// favorites`, then `}`.

Run against one revision: `pocs/reproducers/run-at-rev.sh <sha>`; against the working tree:
`node check-menu.js menu.jsonc` (from this directory; `MENU_MODEL=<path>` overrides the parser file).

Actual results (`run-at-rev.sh`, 2026-10-01 on the audit box; `821ae589` and `b2dae8db` on 2026-10-02):

| Fixture | `8b4eae66` / `821ae589` (upstream) | `f75205f9` (PR #13512 head) | `ff77cd02` / `b2dae8db` (#13968 first commit / head) |
|---|---|---|---|
| `menu.jsonc` | 0 rows | 0 rows | 3 rows (`personal`, `personal.notes`, `personal.files`) |
| `omarchy-menu.jsonc` | 0 rows | 0 rows | 3 rows |
| `fullline-control.jsonc` | 3 rows | 0 rows | 3 rows |

The clip's BEFORE (`8b4eae66`, 0 rows) and AFTER (`ff77cd02`, 3 rows) match. On this branch
(`quattro-proof`, upstream code `821ae58`) the driver prints `0 rows` for both clip fixtures. The
full-line control shows that upstream does not break on every comment after a trailing comma; only the
inline form does.
