# Evidence clips — upstream menu JSONC / navigation PRs

Recorded on the private headless sway harness (sysroot sway 1.12, WLR headless +
pixman): one full-screen alacritty terminal runs a narrative-only driver; the
orchestrator (wf-recorder + file staging) never appears on camera. Every
command shown is really executed against the shipped `shell/plugins/menu/`
code at the stated revision; `MenuModel.js` / `Menu.qml` are swapped between
takes off-camera so BEFORE and AFTER show the same commands on the same stage.
One-line captions are burned in; voiceover omitted (optional).

| File | GitHub item | BEFORE → AFTER revs | Caption (burned in) | How recorded | Reproducer (committed driver) |
|---|---|---|---|---|---|
| `menu-jsonc-comment-tail.mp4` | #13493 | `8b4eae66` (upstream quattro) → `ff77cd02` (consolidated fix, fork branch `prep/upstream-jsonc-consolidated-v3`) | JSONC // comment tail empties the menu (3→0) — fixed: parses 3 rows | real `node check-menu.js` against shipped `MenuModel.js.parseMenuJsonc`, headless-sway terminal capture | `pocs/reproducers/menu-jsonc-comment-tail/` (`check-menu.js` + `menu.jsonc`, `omarchy-menu.jsonc`) |
| `menu-jsonc-comma-in-string.mp4` | #13250 | `8b4eae66` → `ff77cd02` | Comma inside a string value is silently rewritten — fixed: string-aware strip | real `node check-menu.js` against shipped `MenuModel.js`, headless-sway terminal capture | `pocs/reproducers/menu-jsonc-comma-in-string/` (`check-menu.js` + `strings.jsonc`) |
| `menu-jsonc-array-root.mp4` | #13492 | `8b4eae66` → `ff77cd02` | Array root invents rows 0,1 — ids lost; fixed: rejected like scalar roots | real `node check-menu.js` against shipped `MenuModel.js`, headless-sway terminal capture | `pocs/reproducers/menu-jsonc-array-root/` (`check-menu.js` + `array.jsonc`) |
| `menu-back-from-search.mp4` | #13012 | `d3cfd53b` (PR base) → `7a7fb10c` (PR #13012 head) | Back after search lands on Theme (row 0) — fixed: returns to Font | real `node back-from-search.js`: shipped `MenuModel.js` search + `setActiveMenu`/`goBack`/`activateIndex` extracted verbatim from shipped `Menu.qml` (same extraction the menu test suite uses), driven with the shipped default menu data; model-level supplementary evidence — the on-screen menu UI clip is `menu-back-from-search-gui.mp4` | `pocs/reproducers/menu-back-from-search/` (`back-from-search.js`) |
| `menu-back-from-search-gui.mp4` | #13012 | `d3cfd53b` (PR base) → `7a7fb10c` (PR #13012 head) | BEFORE d3cfd53b (bug) - Back after search lands on Theme; AFTER 7a7fb10c (fix) - Back restores the Font row | real quickshell menu UI: full production `shell/shell.qml` (bar + all plugins) on the private headless sway harness, menu summoned over the shell's IPC (`omarchy-shell shell summon omarchy.menu {"menu":"style"}`), real keystrokes via wtype (search "font", Enter, Backspace), screen captured as timed `grim -o HEADLESS-1` stills assembled with ffmpeg (wf-recorder drops its buffered tail on this pixman headless setup — see deviations); `Menu.qml` swapped between revs off-camera | `pocs/reproducers/menu-back-from-search-gui/` (`gui-drive.sh`, reconstructed recipe) |

Each clip's driver, fixtures, and README live under `pocs/reproducers/<clip-name>/` (`menu-back-from-search-gui/gui-drive.sh` is a reconstruction; see its README). Drivers read the menu code of whatever revision they run against; `pocs/reproducers/run-at-rev.sh <sha> ...` runs them against explicit revisions. Every revision below is an explicit SHA:

- `8b4eae66`: upstream `quattro` tip at recording time. Its menu code is identical to `e332dc97`, the upstream code carried by this branch (`quattro-proof`).
- `ff77cd02`: our consolidated JSONC fix (parent `8b4eae66`). Not upstream.
- `d3cfd53b` / `7a7fb10c`: base / head of upstream PR #13012. Not merged upstream.

## Re-validation (2026-10-01)

Every driver was re-run on the audit box against each stated SHA with `run-at-rev.sh`; the per-SHA
output is in [`pocs/reproducers/README.md`](../../pocs/reproducers/README.md). All five clips' burned-in
BEFORE/AFTER labels match the actual output: upstream `8b4eae66` / `e332dc97` does show each bug, and
each AFTER revision shows the fix. No caption needed correcting. One scope note for #13493: the clip's
fixtures put the `//` note on the same line as the trailing comma. Upstream parses the other shape
(trailing comma, then a full-line `//` comment, then `}`) correctly, 3 rows; only the PR #13512 head
`f75205f9` breaks that shape (0 rows), and `ff77cd02` keeps it working (3 rows). The control fixture
`fullline-control.jsonc` records this; the clip does not claim otherwise.

## Verified deltas (read back from extracted frames)

- #13493: BEFORE `menu.jsonc: 0 rows` and `omarchy-menu.jsonc: 0 rows`; AFTER
  both files `3 rows` (`personal`, `personal.notes`, `personal.files`).
- #13250: BEFORE `label=Keep f{.bak}` / `desc=mv f{.bak} old/*.jpg` (commas
  silently eaten while the parse succeeds); AFTER `Keep f{.bak,}` /
  `mv f{.bak,}` verbatim.
- #13492: BEFORE `2 rows` with phantom `id=0` / `id=1`; AFTER `0 rows`.
- #13012: BEFORE `Back -> cursor row 0: style.theme (Theme)`; AFTER
  `Back -> cursor row 3: style.font (Font)`.

## Honest deviations from the requested script

- The bare uncommented sample (`config/omarchy/extensions/omarchy-menu.jsonc`
  with only the three example rows enabled) does NOT reproduce at `8b4eae66`:
  it parses to 3 rows both sides, because the old line-anchored comment strip
  removes the comment lines before the trailing-comma regex runs. The clip
  therefore shows the sample with one realistic user edit — an inline
  `// favorites` note after a row — which is exactly the #13493 mechanism
  (inline `//` after a trailing comma) and drops it to 0 rows BEFORE.
- For #13012 the task listed `7a7fb10c` as BEFORE, but that commit is the PR's
  fix itself ("Restore menu selection when navigating back"); the clip uses
  its parent `d3cfd53b` as BEFORE and the upstream PR head as AFTER.
- The searched-and-opened row is `style.font` (the Style ▸ Font row; the other
  "font" hit, `install.style.font`, is also shown on screen for honesty).
- GUI renditions (live menu plugin emptying, lock-screen fail-open
  #7072/#10299) were skipped: the JSONC findings are model-level (no GUI
  render changes), and the lock fail-open harness was not exercised in this
  session — not forced per the task's time-box.
- The #13012 GUI clip is captured at ~2.5 fps (one `grim` still every 0.4 s,
  assembled at 25 fps) rather than a wf-recorder take: wf-recorder runs on
  this pixman headless sway but its final 2-4 s of buffered frames are lost
  at SIGINT, which cut off the exact Back-landing moment; repeated takes
  (SIGINT after 3 s and 8 s holds, and the `-d` flag is a DRM device option,
  not duration) reproduced the loss, so the stills assembler is used instead.
  The first keystroke of each fresh wtype process also races seat focus and
  is dropped, so every wtype invocation is prefixed with a no-op Shift
  keypress; the burned-in captions are the only post-capture addition.
