# Headless GUI Testing

Read this before driving the Omarchy shell on a headless Linux box: reproducer
videos, PR evidence clips, quickshell-dependent UI checks, or any QML target
that needs a real Wayland compositor to render. This is the concrete recipe for
getting the production shell on screen and capturing what it actually drew when
there is no desktop session — it complements
[`agents/skills/visual-verification.md`](agents/skills/visual-verification.md)
(running-desktop verification) and
[`agents/skills/acceptance-tests.md`](agents/skills/acceptance-tests.md)
(disposable-VM acceptance suite), and everything here was proven on this box.

## When to use

- The box has no desktop session (SSH only) and the claim needs the real shell rendering, not a mockup or a model-level log.
- The change lives behind quickshell's plugin loader — menus, bar widgets, lock — which will not instantiate outside the production config.
- You are producing BEFORE/AFTER evidence clips for a PR or known issue.
- You are exercising QML decision paths against a live compositor, like the lock MC/DC harness does.
- You are producing recorded evidence under the `narrated-video-evidence` or `live-repro-evidence` proof roles (see Pointers).

## The recipe

### 1. Start a private headless sway

Headless wlroots needs no GPU and no running session. Give the compositor its
own `XDG_RUNTIME_DIR` so its sockets cannot collide with anything else, and
poll for the Wayland socket it creates. `test/qml/lock/run.sh` is the working
reference for all of this.

```bash
#!/bin/bash
RT=$(mktemp -d /tmp/headless-gui.XXXXXX)
chmod 700 "$RT"
SWAY_BIN=/home/buger/proof-env/sysroot/usr/bin/sway
env -i \
  LD_LIBRARY_PATH=/home/buger/proof-env/sysroot/usr/lib \
  XDG_RUNTIME_DIR="$RT" \
  HOME="$HOME" \
  WLR_BACKENDS=headless \
  WLR_RENDERER=pixman \
  WLR_LIBINPUT_NO_DEVICES=1 \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/bin" \
  "$SWAY_BIN" -c "$CONF" > "$RT/sway.log" 2>&1 &
SWAY_PID=$!
WAY=""
for (( i = 0; i < 100; i++ )); do
  WAY=$(cd "$RT" && ls wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)
  if [[ -n $WAY ]]; then break; fi
  if ! kill -0 "$SWAY_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
if [[ -z $WAY ]]; then
  echo "private sway failed to start" >&2
  tail -20 "$RT/sway.log" >&2
fi
export WAYLAND_DISPLAY=$WAY
export XDG_RUNTIME_DIR=$RT
```

- The config is minimal; `test/qml/lock/sway-headless.conf` is the pattern: `output HEADLESS-1 resolution 1920x1080`, `xwayland disable`, invisible bar. `HEADLESS-1` is the output name every later `grim -o` call uses.
- `WLR_RENDERER=pixman` is what makes this work without a DRM device — and it is also what breaks wf-recorder (step 5).
- On this box the sysroot binaries are not on PATH: sway/swaymsg/wtype live in `/home/buger/proof-env/sysroot/usr/bin` (sway needs `LD_LIBRARY_PATH=/home/buger/proof-env/sysroot/usr/lib`), and a standalone wtype build sits at `/home/buger/proof-env/bin/wtype`. Follow run.sh's pattern: probe `command -v` first, fall back to the sysroot path.
- The `env -i` minimal environment is deliberate — it keeps the harness deterministic and free of session leakage. Every later client call must get `WAYLAND_DISPLAY` and `XDG_RUNTIME_DIR` explicitly.
- For PAM-touching targets (lock), run the driver under `unshare -Urm` and mount a private tmpfs over `/etc/pam.d` — see run.sh phase A and `inner.sh`.

### 2. Launch the production shell

```bash
QT_QPA_PLATFORM=wayland \
QT_QUICK_BACKEND=software \
QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
OMARCHY_PATH=$PWD \
quickshell -p "$REPO/shell/shell.qml" &
```

- GOTCHA: plugin QML only instantiates inside the production quickshell plugin-loader context. Loading a plugin file directly fails two ways: offscreen it dies with "No PanelWindow backend loaded" (OverlayWindow cannot attach without a layer-shell backend), and on sway the external WlrLayershell attach fails ("Could not create attached properties object") or blocks the event loop after mapping. The fix is to always launch the real `shell/shell.qml` — the plugin loader inside it instantiates the plugins.
- `QT_QUICK_BACKEND=software` renders without a GPU; combined with pixman it is the only path that works headless here.
- If the target is plugin-internal code you need to instrument (the lock plugin), do what `test/qml/lock/run.sh` does: stage a mirror of `shell/` (`Commons`, `Ui`, `plugins`) into a temp config so `qs.*` imports resolve, and copy your instrumented plugin sources over the staged copies. Never edit `shell/` in place for a harness run.

### 3. Summon surfaces over the shell IPC

The shell answers IPC without any keyboard focus dance, which makes it the
reliable way to open menus:

```bash
omarchy-shell shell summon omarchy.menu '{"menu":"style"}'
```

- `omarchy-shell` requires `OMARCHY_PATH` and resolves its socket from `OMARCHY_PATH` + `WAYLAND_DISPLAY`, so both must point at this private run, not the session.
- GOTCHA: once the shell's IPC socket file exists, `omarchy-shell` prefers its socat fast path, and that path can die on a stale socket left behind by a shell that exited since the last call. Fix: remove the socket before each call so `omarchy-shell` falls through to its `qs ipc` fallback:

```bash
socket_id=$(printf '%s\n%s' "$OMARCHY_PATH/shell" "$WAYLAND_DISPLAY" | md5sum)
socket="${XDG_RUNTIME_DIR:?}/omarchy-shell-${socket_id:0:16}.sock"
rm -f "$socket"
omarchy-shell shell summon omarchy.menu '{"menu":"style"}'
```

### 4. Drive it with wtype

For anything that needs real keystrokes (search fields, key navigation):

```bash
wtype -k Shift_Left; sleep 0.2
wtype font; sleep 1
wtype -k Return
```

- GOTCHA: the first keystroke of each fresh wtype process races seat focus and is silently dropped. Fix: prefix every wtype invocation with a no-op Shift press (shown above) so the racing key is a key that changes nothing.
- Sleep between steps: the shell has animation and search-debounce timing; a still taken 100 ms after a keystroke shows the previous state.

### 5. Capture with grim stills, not wf-recorder

- GOTCHA: wf-recorder runs on this pixman headless sway, but at SIGINT it drops its final 2–4 s of buffered frames — exactly the moment you are usually proving. Repeated takes (3 s and 8 s holds) reproduced the loss, and its `-d` flag is a DRM device option, not a duration. Fix: capture timed `grim` stills and assemble with ffmpeg:

```bash
still() { grim -o HEADLESS-1 "$OUT/$(printf '%04d' "$1").png"; }
# still after each step, then:
ffmpeg -y -framerate 25 -pattern_type glob -i "$OUT/[0-9]*.png" \
  -c:v libx264 -pix_fmt yuv420p "$OUT/clip.mp4"
```

- One still per UI step is enough; a loop at ~0.4 s intervals gives smooth-enough playback at 25 fps (the five committed clips were shot this way).

### 6. Before/after discipline

- Swap revs off-camera: `git -C "$REPO" checkout -q "$REV" -- shell/plugins/menu/Menu.qml` between takes, so both takes run identical on-camera commands on an identical stage and only the code under test differs.
- Captions are added post-capture only (burned-in or subtitle track); nothing is staged on screen.
- Real UI or none: the clip shows the production shell doing the real thing, or the evidence does not exist. Mockups, staged frames, and simulated output destroy the value of everything else in this recipe — and the harness itself (driver, git swaps, capture tooling) never appears on camera.

## Pointers

- Working references: `test/qml/lock/run.sh` + `test/qml/lock/inner.sh` (private headless sway, MC/DC lock harness with PAM namespacing) and `scratchpad/omarchy-v2/reproducers/menu-back-from-search-gui/gui-drive.sh` + its `README.md` (production-shell GUI drive: IPC summon, wtype, grim stills, ffmpeg assemble).
- Existing examples: `scratchpad/omarchy-v2/media/` with `scratchpad/omarchy-v2/MANIFEST.md` — five evidence clips produced this way, including the honest-deviations log recording the wf-recorder and wtype findings above.
- Recorded-evidence doctrine (stage discipline, narration, control-vs-patched delta) lives in the proof roles `narrated-video-evidence` and `live-repro-evidence` under `/home/buger/proof-env/reqproof-build/pkg/roles/builtin/` (proof-env, outside this repo).
- `docs/omarchy-shell.md` covers the IPC command used in step 3; `docs/testing.md` covers the automated suites that should already pass before you reach for this recipe.

## What this does NOT cover

- Verifying a change against a real desktop session — follow [`agents/skills/visual-verification.md`](agents/skills/visual-verification.md).
- The full graphical acceptance suite in a disposable VM — follow [`agents/skills/acceptance-tests.md`](agents/skills/acceptance-tests.md).
