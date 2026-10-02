Reproduces `review/media/menu-back-from-search.mp4` (upstream PR #13012, model level): open Style, search
"font", open the Style > Font row, press Back. Without the PR the cursor lands on Theme (row 0); with it,
on Font (row 3).

The driver runs `MenuModel.js` search plus `setActiveMenu` / `goBack` / `activateIndex` extracted verbatim
from `Menu.qml` (the same extraction the menu test suite uses). `omarchy-menu-default.jsonc` is the
default menu as staged when the clip was recorded; `MENU_DATA=<file>` uses another.

Run: `pocs/reproducers/run-at-rev.sh <sha>`, or `node back-from-search.js` (working tree).

Actual results (audit box, 2026-10-01):
- `d3cfd53b` (PR base), `8b4eae66`, `e332dc97` (upstream; also this branch's code) and `ff77cd02`:
  `Back -> cursor row 0: style.theme (Theme)`.
- `7a7fb10c` (PR #13012 head): `Back -> cursor row 3: style.font (Font)`.

The clip's BEFORE `d3cfd53b` / AFTER `7a7fb10c` captions match. PR #13012 is not merged upstream, so
upstream `e332dc97` still shows the BEFORE line.

Scope: this is the common case, where the search result is a direct child of the current menu, and
#13012 restores the cursor correctly. The PR regresses a different case: when the search result sits
deeper than the menu being left (at root, search "font", open Install > Style > Font, then Back), the
#13012 head lands on an unrelated row (`learn`) where upstream lands on row 0 (`apps`). That case is
reproduced on the `pr/13012` mirror branch by the `KI-MENU-BACK-FILTERED-INDEX` green tripwire in
`test/shell.d/menu-pointer-lifecycle-test.sh`.
