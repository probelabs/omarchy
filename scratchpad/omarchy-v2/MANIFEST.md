# Evidence clips — upstream menu JSONC / navigation PRs

Recorded on the private headless sway harness (sysroot sway 1.12, WLR headless +
pixman): one full-screen alacritty terminal runs a narrative-only driver; the
orchestrator (wf-recorder + file staging) never appears on camera. Every
command shown is really executed against the shipped `shell/plugins/menu/`
code at the stated revision; `MenuModel.js` / `Menu.qml` are swapped between
takes off-camera so BEFORE and AFTER show the same commands on the same stage.
One-line captions are burned in; voiceover omitted (optional).

| File | GitHub item | BEFORE → AFTER revs | Caption (burned in) | How recorded |
|---|---|---|---|---|
| `menu-jsonc-comment-tail.mp4` | #13493 | `8b4eae66` (upstream quattro) → `ff77cd02` (`prep/upstream-jsonc-consolidated-v3`) | JSONC // comment tail empties the menu (3→0) — fixed: parses 3 rows | real `node check-menu.js` against shipped `MenuModel.js.parseMenuJsonc`, headless-sway terminal capture |
| `menu-jsonc-comma-in-string.mp4` | #13250 | `8b4eae66` → `ff77cd02` | Comma inside a string value is silently rewritten — fixed: string-aware strip | real `node check-menu.js` against shipped `MenuModel.js`, headless-sway terminal capture |
| `menu-jsonc-array-root.mp4` | #13492 | `8b4eae66` → `ff77cd02` | Array root invents rows 0,1 — ids lost; fixed: rejected like scalar roots | real `node check-menu.js` against shipped `MenuModel.js`, headless-sway terminal capture |
| `menu-back-from-search.mp4` | #13012 | `d3cfd53b` (PR base) → `7a7fb10c` (PR #13012 head) | Back after search lands on Theme (row 0) — fixed: returns to Font | real `node back-from-search.js`: shipped `MenuModel.js` search + `setActiveMenu`/`goBack`/`activateIndex` extracted verbatim from shipped `Menu.qml` (same extraction the menu test suite uses), driven with the shipped default menu data |

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
