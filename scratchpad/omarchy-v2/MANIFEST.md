# Evidence clips — upstream menu JSONC / navigation PRs

Recorded on the private headless sway harness (sysroot sway 1.12, WLR headless +
pixman): one full-screen alacritty terminal runs a narrative-only driver; the
orchestrator (wf-recorder + file staging) never appears on camera. Every
command shown is really executed against the shipped `shell/plugins/menu/`
code at the stated revision; `MenuModel.js` / `Menu.qml` are swapped between
takes off-camera so BEFORE and AFTER show the same commands on the same stage.
One-line captions are burned in; voiceover omitted (optional).

| File | GitHub item | BEFORE → AFTER revs | Caption (burned in) | How recorded | Reproducer (committed driver) |
|---|---|---|---|---|
| `menu-jsonc-comment-tail.mp4` | #13493 | `8b4eae66` (upstream quattro) → `ff77cd02` (`prep/upstream-jsonc-consolidated-v3`) | JSONC // comment tail empties the menu (3→0) — fixed: parses 3 rows | real `node check-menu.js` against shipped `MenuModel.js.parseMenuJsonc`, headless-sway terminal capture | `reproducers/menu-jsonc-comment-tail/` (`check-menu.js` + `menu.jsonc`) |
| `menu-jsonc-comma-in-string.mp4` | #13250 | `8b4eae66` → `ff77cd02` | Comma inside a string value is silently rewritten — fixed: string-aware strip | real `node check-menu.js` against shipped `MenuModel.js`, headless-sway terminal capture | `reproducers/menu-jsonc-comma-in-string/` (`check-menu.js` + `strings.jsonc`) |
| `menu-jsonc-array-root.mp4` | #13492 | `8b4eae66` → `ff77cd02` | Array root invents rows 0,1 — ids lost; fixed: rejected like scalar roots | real `node check-menu.js` against shipped `MenuModel.js`, headless-sway terminal capture | `reproducers/menu-jsonc-array-root/` (`check-menu.js` + `array.jsonc`) |
| `menu-back-from-search.mp4` | #13012 | `d3cfd53b` (PR base) → `7a7fb10c` (PR #13012 head) | Back after search lands on Theme (row 0) — fixed: returns to Font | real `node back-from-search.js`: shipped `MenuModel.js` search + `setActiveMenu`/`goBack`/`activateIndex` extracted verbatim from shipped `Menu.qml` (same extraction the menu test suite uses), driven with the shipped default menu data; model-level supplementary evidence — the on-screen menu UI clip is `menu-back-from-search-gui.mp4` | `reproducers/menu-back-from-search/` (`back-from-search.js`) |
| `menu-back-from-search-gui.mp4` | #13012 | `d3cfd53b` (PR base) → `7a7fb10c` (PR #13012 head) | BEFORE d3cfd53b (bug) - Back after search lands on Theme; AFTER 7a7fb10c (fix) - Back restores the Font row | real quickshell menu UI: full production `shell/shell.qml` (bar + all plugins) on the private headless sway harness, menu summoned over the shell's IPC (`omarchy-shell shell summon omarchy.menu {"menu":"style"}`), real keystrokes via wtype (search "font", Enter, Backspace), screen captured as timed `grim -o HEADLESS-1` stills assembled with ffmpeg (wf-recorder drops its buffered tail on this pixman headless setup — see deviations); `Menu.qml` swapped between revs off-camera | `reproducers/menu-back-from-search-gui/` (`gui-drive.sh`, reconstructed recipe) |

Each clip's driver, fixtures, and README now live in-repo under `reproducers/<clip-name>/` (landed 2026-10-01; `menu-back-from-search-gui/gui-drive.sh` is an honest reconstruction — see its README). Drivers are rev-dependent; each README states the verified BEFORE/AFTER output at quattro HEAD `7f7b5795`.

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

## Narrated variants (2026-10-01)

The narrated-video-evidence role treatment was applied to all five clips: visuals
re-rendered by re-running the committed reproducers on the same headless-sway
harness (BEFORE/AFTER takes with off-camera rev swaps), captions re-burned
unchanged, plus a synchronized TTS voiceover per the role's Phase 5 doctrine
(local piper, storyboard-driven sync, `-c:v copy` mux). Narration states only
what the clip shows; fit logs land beside each output as
`<name>-narrated.mp4.fit.log`.

- TTS backend: piper 1.2.0 release binary + `en_US-lessac-medium` voice, already
  present in userland at `~/proof-env/tts/` (the role's sanctioned userland
  install; no cloud TTS, no sudo). Voiceover assembler: the role's
  `voiceover.sh` (deployed at `~/proof-env/gui/voiceover.sh`).

| Narrated file | Duration | Speech before / after | Narration (abridged) |
|---|---|---|---|
| `menu-jsonc-comment-tail-narrated.mp4` | 16.8s | 7.3s / 6.4s | A comment can blank the whole menu — trailing comma + inline comment parse to 0 rows on the shipped parser; the fixed scanner parses both files to 3 rows. |
| `menu-jsonc-comma-in-string-narrated.mp4` | 17.3s | 8.2s / 6.1s | A comma in a string gets rewritten — the old parser eats it while still succeeding; the string-aware strip round-trips values verbatim. |
| `menu-jsonc-array-root-narrated.mp4` | 17.3s | 7.4s / 5.5s | An array root invents rows 0,1 on the old parser; the fix rejects it like scalar roots — 0 rows, no phantom ids. |
| `menu-back-from-search-narrated.mp4` | 18.1s | 6.1s / 5.1s | Search font, open Font, press Back — old build lands on Theme row 0; fix restores the selection by id (Font, row 3). |
| `menu-back-from-search-gui-narrated.mp4` | 18.4s | 6.7s / 6.5s | Same flow on the live menu UI — old build lands on Theme; fix lands back on Font. |

The silent originals in this directory are untouched. Visuals of the narrated
variants come from fresh takes:

- Terminal clips (4): re-ran `record-take.sh` with the committed drivers,
  staging `git show <rev>:shell/plugins/menu/{MenuModel.js,Menu.qml}` into the
  demo dir per side, then re-assembled with the same confs. The pipeline is
  deterministic: all four re-assembled files match the committed silent clips'
  byte sizes and durations exactly (309215 / 177428 / 147111 / 169450 bytes).
- `menu-back-from-search-gui-narrated.mp4` deviations from the silent
  original: 18.4s vs 25.2s — the re-run capture is 23+23 stills at 2.5 fps
  (9.2 s per half) vs the original's 31/32, same steps and same revs
  (d3cfd53b / 7a7fb10c `Menu.qml` swap). The menu was summoned with the shell
  IPC call directly (`qs ipc -n -p <worktree>/shell call -- shell summon
  omarchy.menu '{"menu":"style"}'`) because omarchy-shell's socat path hung on
  this box today (its fallback is the same qs ipc call). Keystrokes used
  `wtype -k Shift_L` as the focus-race prime (the reconstructed recipe's
  `Shift_Left` keysym name is rejected by xkbcommon) with `-k Return` /
  `-k BackSpace` from the full wtype build at `~/proof-env/wtype-build` (the
  sysroot wtype is a text-only build). GUI captions render in JetBrains Mono
  rather than the original's sans (drawtext fontfile fallback); text,
  placement, and box style are unchanged.

Verification per narrated clip: AAC track present, no clipping (volumedetect
mean −16.6..−18.9 dB, max ≤ 0 dBFS), speech present in both the BEFORE and
AFTER halves (silencedetect per half), zero WARN-TOO-LONG storyboard lines in
the fit log, and 2 extracted frames per clip confirm the burned captions and
the on-screen deltas.
