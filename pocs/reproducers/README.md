# Clip reproducers

Drivers and fixtures behind the evidence clips in [`review/media/`](../../review/media/MANIFEST.md).
Each directory is named after its clip. The four model-level drivers run the menu code that ships in
`shell/plugins/menu/` (`MenuModel.js`, and for back-from-search the navigation functions extracted from
`Menu.qml`).

Run them against any revision without touching the working tree:

```sh
pocs/reproducers/run-at-rev.sh 8b4eae66 821ae589 ff77cd02 b2dae8db d3cfd53b 7a7fb10c
```

Revisions referenced below:

| SHA | What it is |
|---|---|
| `821ae589` | Upstream `quattro` (`821ae58`), the code this branch (`quattro-proof`) carries. |
| `8b4eae66` | Upstream `quattro` tip when the clips were recorded. Menu code identical to `821ae589`. |
| `f75205f9` | Head of upstream PR #13512 (inline-comment fix). |
| `ff77cd02` | The first commit of upstream PR #13968 (the JSONC fix; parent `8b4eae66`). The PR head is `b2dae8d`. Not merged upstream. |
| `b2dae8db` | Head of upstream PR #13968 (`b2dae8d`): `ff77cd02` plus the Unicode-whitespace follow-up. Not merged upstream. |
| `d3cfd53b` | Base of upstream PR #13012. |
| `7a7fb10c` | Head of upstream PR #13012 (restore selection on Back). Not merged upstream. |

Results below were produced by `run-at-rev.sh` (Node.js): on the audit box on 2026-10-01, and the
`821ae589` and `b2dae8db` columns on 2026-10-02. See each directory's README.

| Reproducer | `8b4eae66` | `821ae589` | `f75205f9` | `ff77cd02` | `b2dae8db` | `d3cfd53b` | `7a7fb10c` |
|---|---|---|---|---|---|---|---|
| comment-tail `menu.jsonc` (trailing comma + inline `//` on the same line) | 0 rows | 0 rows | 0 rows | 3 rows | 3 rows | 0 rows | 0 rows |
| comment-tail `omarchy-menu.jsonc` (upstream sample, examples enabled, one inline note) | 0 rows | 0 rows | 0 rows | 3 rows | 3 rows | 0 rows | 0 rows |
| comment-tail `fullline-control.jsonc` (trailing comma, then a full-line `//` comment, then `}`) | 3 rows | 3 rows | **0 rows** | 3 rows | 3 rows | 3 rows | 3 rows |
| comma-in-string `strings.jsonc` | `f{.bak}` (comma eaten) | `f{.bak}` | `f{.bak,}` | `f{.bak,}` | `f{.bak,}` | `f{.bak}` | `f{.bak}` |
| array-root `array.jsonc` | 2 rows, ids `0`/`1` | 2 rows, ids `0`/`1` | 2 rows, ids `0`/`1` | 0 rows | 0 rows | 2 rows, ids `0`/`1` | 2 rows, ids `0`/`1` |
| back-from-search | row 0 Theme | row 0 Theme | row 0 Theme | row 0 Theme | row 0 Theme | row 0 Theme | row 3 Font |

`fullline-control.jsonc` is a control, not a clip fixture: upstream parses it correctly; only the
#13512 PR head regresses it, and #13968 (both commits) keeps it working.

`menu-back-from-search-gui/` is a recipe for the live-UI clip, not a one-command rerun (see its README
and [`docs/proof/headless-gui-testing.md`](../../docs/proof/headless-gui-testing.md)).
