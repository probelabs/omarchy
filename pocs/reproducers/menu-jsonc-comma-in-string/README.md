Reproduces `review/media/menu-jsonc-comma-in-string.mp4` (upstream issue #13250): the old trailing-comma
regex is not string-aware, so `Keep f{.bak,}` is silently rewritten to `Keep f{.bak}` while the parse
still succeeds.

Run: `pocs/reproducers/run-at-rev.sh <sha>`, or from this directory `node check-menu.js strings.jsonc`
(working tree; `MENU_MODEL=<path>` overrides the parser file).

Actual results (`run-at-rev.sh`, 2026-10-01 on the audit box; `821ae589` and `b2dae8db` on 2026-10-02):
- `8b4eae66` and `821ae589` (upstream; `821ae58` is this branch's code): 2 rows, `label=Keep f{.bak}`,
  `desc=mv f{.bak} old/*.jpg` (commas eaten).
- `ff77cd02` (the first commit of #13968; the PR head `b2dae8db` gives the same): 2 rows, `label=Keep f{.bak,}`, `desc=mv f{.bak,} old/*.jpg` (verbatim).
- `f75205f9` (PR #13512 head) also keeps the commas.

The clip's BEFORE `8b4eae66` / AFTER `ff77cd02` captions match.
