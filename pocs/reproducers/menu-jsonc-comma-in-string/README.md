Reproduces `review/media/menu-jsonc-comma-in-string.mp4` (upstream issue #13250): the old trailing-comma
regex is not string-aware, so `Keep f{.bak,}` is silently rewritten to `Keep f{.bak}` while the parse
still succeeds.

Run: `pocs/reproducers/run-at-rev.sh <sha>`, or from this directory `node check-menu.js strings.jsonc`
(working tree; `MENU_MODEL=<path>` overrides the parser file).

Actual results (audit box, 2026-10-01):
- `8b4eae66` and `e332dc97` (upstream; also this branch's code): 2 rows, `label=Keep f{.bak}`,
  `desc=mv f{.bak} old/*.jpg` (commas eaten).
- `ff77cd02` (consolidated fix): 2 rows, `label=Keep f{.bak,}`, `desc=mv f{.bak,} old/*.jpg` (verbatim).
- `f75205f9` (PR #13512 head) also keeps the commas.

The clip's BEFORE `8b4eae66` / AFTER `ff77cd02` captions match.
