Reproduces `review/media/menu-jsonc-array-root.mp4` (upstream issue #13492): an array root is walked by
index, so its elements become rows `id=0` / `id=1` and the real ids are lost. The fix rejects array roots
like scalar roots.

Run: `pocs/reproducers/run-at-rev.sh <sha>`, or from this directory `node check-menu.js array.jsonc`
(working tree; `MENU_MODEL=<path>` overrides the parser file).

Actual results (`run-at-rev.sh`, 2026-10-01 on the audit box; `821ae589` and `b2dae8db` on 2026-10-02):
- `8b4eae66` and `821ae589` (upstream; `821ae58` is this branch's code): 2 rows, `id=0 label=Personal`,
  `id=1 label=Notes`.
- `ff77cd02` (the first commit of #13968; the PR head `b2dae8db` gives the same): 0 rows.

The clip's BEFORE `8b4eae66` / AFTER `ff77cd02` captions match.
