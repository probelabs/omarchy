#!/bin/bash
# MC/DC harness for the lock plugin QML (LockView.qml + Service.qml).
#
# Assembles quickshell config staging trees that mirror shell/ so the plugin's
# qs.* imports resolve against the instrumented sources, and runs two driver
# phases against one private headless sway (PanelWindow / WlrLayershell /
# WlSessionLock need a live Wayland compositor):
#
#   phase A — one output: the full decision walk (PAM transactions against a
#             private /etc/pam.d in a user+mount namespace, real session
#             lock, wtype keystrokes, PATH stubs for process branches)
#   phase B — output unplugged, USER/LOGNAME unset: the startup-binding and
#             no-real-screen arms
#
# Marker harvest reads stdout; the __REQPROOF_MCDC__ console lines pass
# through tee. The gate is the LOCK-QML-HARNESS-DONE marker from both phases.
set -u

# Optional helper toolchain (headless sway, wtype) for GUI acceptance runs.
# Override with PROOF_ENV_DIR; defaults to $HOME/proof-env so an existing
# per-host layout keeps working with nothing set.
PROOF_ENV_DIR="${PROOF_ENV_DIR:-$HOME/proof-env}"

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)
HARNESS=$ROOT/test/qml/lock
STUBS=$HARNESS/stubs
STAGE_A=$(mktemp -d /tmp/omarchy-lock-mcdc-a.XXXXXX)
STAGE_B=$(mktemp -d /tmp/omarchy-lock-mcdc-b.XXXXXX)
RT=$(mktemp -d /tmp/omarchy-lock-mcdc-rt.XXXXXX)
chmod 700 "$RT"
SWAY_PID=""
KBD_PID=""

cleanup() {
  if [[ -n ${MCDC_KEEP:-} ]]; then return; fi
  if [[ -n $KBD_PID ]]; then kill "$KBD_PID" 2>/dev/null || true; fi
  if [[ -n $SWAY_PID ]]; then kill "$SWAY_PID" 2>/dev/null || true; fi
  rm -rf "$STAGE_A" "$STAGE_B" "$RT"
}
trap cleanup EXIT

if [[ ! -d $ROOT/shell/plugins/lock ]]; then
  echo "harness: $ROOT/shell/plugins/lock not found" >&2
  exit 1
fi

# Staging trees mirror shell/ so qs.Commons/qs.Ui resolve and the driver's
# relative import picks up the instrumented plugin sources in this workspace.
for pair in "$STAGE_A:$HARNESS/shell.qml" "$STAGE_B:$HARNESS/shell-noscreen.qml"; do
  stage=${pair%%:*}
  driver=${pair##*:}
  mkdir -p "$stage"
  cp -r "$ROOT/shell/Commons" "$ROOT/shell/Ui" "$stage/"
  cp -r "$ROOT/shell/plugins" "$stage/"
  cp "$driver" "$stage/shell.qml"
done

# Deterministic process-driven branches: the strand-check stub walks exit
# codes 2 (no answer yet), 0 (stranded), 1 (not stranded); the poster stub
# stands in for ffmpegthumbnailer; the fingerprint stub gates enrollment.
export MCDC_STUB_STATE="$RT/stub"
mkdir -p "$MCDC_STUB_STATE"
: > "$RT/fake-video.mp4"
printf 'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==\n' | base64 -d > "$RT/fake-image.png" 2>/dev/null

WTYPE=$(command -v wtype || true)
if [[ -z $WTYPE && -x ${PROOF_ENV_DIR}/bin/wtype ]]; then
  WTYPE=${PROOF_ENV_DIR}/bin/wtype
fi
if [[ -z $WTYPE ]]; then
  echo "harness: wtype not found for the keystroke path" >&2
  exit 1
fi
export MCDC_WTYPE="$WTYPE"

PATH="$STUBS:$PATH"
export PATH

# Private headless sway: headless wlroots needs no GPU or running session.
SWAY_BIN=${PROOF_ENV_DIR}/sysroot/usr/bin/sway
SWAYMSG_BIN=${PROOF_ENV_DIR}/sysroot/usr/bin/swaymsg
if [[ ! -x $SWAY_BIN ]]; then
  SWAY_BIN=$(command -v sway || true)
  SWAYMSG_BIN=$(command -v swaymsg || true)
fi
if [[ -z $SWAY_BIN ]]; then
  echo "harness: no sway binary for the Service PanelWindow path" >&2
  exit 1
fi

env -i \
  LD_LIBRARY_PATH=${PROOF_ENV_DIR}/sysroot/usr/lib \
  XDG_RUNTIME_DIR="$RT" \
  HOME="$HOME" \
  WLR_BACKENDS=headless \
  WLR_RENDERER=pixman \
  WLR_LIBINPUT_NO_DEVICES=1 \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/bin" \
  "$SWAY_BIN" -c "$HARNESS/sway-headless.conf" > "$RT/sway.log" 2>&1 &
SWAY_PID=$!
WAY=""
for (( i = 0; i < 100; i++ )); do
  WAY=$(cd "$RT" && ls wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)
  if [[ -n $WAY ]]; then break; fi
  if ! kill -0 "$SWAY_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
if [[ -z $WAY ]]; then
  echo "harness: private sway failed to start" >&2
  tail -20 "$RT/sway.log" >&2
  exit 1
fi

mkdir -p "$RT/pam.d"

# With no input devices the seat has a keyboard only while a virtual
# keyboard is connected. A short wtype run alone connects, types and leaves
# before the shell has bound the new wl_keyboard, so its keys go nowhere;
# an idle wtype kept open for the whole phase holds the capability up.
WAYLAND_DISPLAY="$WAY" XDG_RUNTIME_DIR="$RT" "$WTYPE" -s 600000 &
KBD_PID=$!

rc=0

# phase A: full decision walk under the private PAM namespace
MCDC_PAM_DIR="$RT/pam.d" \
MCDC_SWAYMSG="$SWAYMSG_BIN" \
MCDC_SWAYSOCK="$RT/$(cd "$RT" && ls sway-ipc.*.sock 2>/dev/null | head -1)" \
MCDC_FAKE_VIDEO="$RT/fake-video.mp4" \
MCDC_FAKE_IMAGE="$RT/fake-image.png" \
USER=${USER:-buger} \
unshare -Urm bash "$HARNESS/inner.sh" "$STAGE_A" "$RT" "$WAY" A | tee "$RT/out-a.log"
if (( ${PIPESTATUS[0]} != 0 )); then rc=1; fi

kill "$KBD_PID" 2>/dev/null || true
KBD_PID=""

# phase B: its own compositor with zero outputs — Quickshell then exposes a
# placeholder screen (empty name, zero extents), which covers the
# no-real-screen arms — and no USER/LOGNAME for the userName binding.
kill "$SWAY_PID" 2>/dev/null || true
SWAY_PID=""
sleep 1
env -i \
  LD_LIBRARY_PATH=${PROOF_ENV_DIR}/sysroot/usr/lib \
  XDG_RUNTIME_DIR="$RT" \
  HOME="$HOME" \
  WLR_BACKENDS=headless \
  WLR_RENDERER=pixman \
  WLR_LIBINPUT_NO_DEVICES=1 \
  WLR_HEADLESS_OUTPUTS=0 \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/bin" \
  "$SWAY_BIN" -c /dev/null > "$RT/sway-b.log" 2>&1 &
SWAY_PID=$!
WAY=""
for (( i = 0; i < 100; i++ )); do
  WAY=$(cd "$RT" && ls wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)
  if [[ -n $WAY ]]; then break; fi
  if ! kill -0 "$SWAY_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
if [[ -z $WAY ]]; then
  echo "harness: zero-output sway failed to start" >&2
  tail -20 "$RT/sway-b.log" >&2
  exit 1
fi
MCDC_FAKE_VIDEO="$RT/fake-video.mp4" \
MCDC_FAKE_IMAGE="$RT/fake-image.png" \
unshare -Urm bash "$HARNESS/inner.sh" "$STAGE_B" "$RT" "$WAY" B | tee "$RT/out-b.log"
if (( ${PIPESTATUS[0]} != 0 )); then rc=1; fi

# phase B2: as B but with LOGNAME set, for the userName fallback arm
MCDC_FAKE_VIDEO="$RT/fake-video.mp4" \
MCDC_FAKE_IMAGE="$RT/fake-image.png" \
unshare -Urm bash "$HARNESS/inner.sh" "$STAGE_B" "$RT" "$WAY" B2 | tee "$RT/out-b2.log"
if (( ${PIPESTATUS[0]} != 0 )); then rc=1; fi

# The drivers print DONE only after every scheduled step ran cleanly; the
# quickshell exit status is not a completion signal, so gate on the markers.
for out in "$RT/out-a.log" "$RT/out-b.log" "$RT/out-b2.log"; do
  if ! grep -q "LOCK-QML-HARNESS-DONE" "$out" || grep -q "LOCK-QML-HARNESS-FAIL" "$out"; then
    echo "harness: $out did not complete cleanly" >&2
    rc=1
  fi
done


# JUnit: test/junit/junit.sh reports this run as one <testcase> named run.sh,
# but the harness's Verifies annotations live in test/qml/lock/shell.qml. So
# under a proof test command (PROOF_PROJECT_ROOT set) this runner also records
# its verdict as a <testcase> for shell.qml, in a part of its own that
# test/junit/merge.mjs merges into the report, and proof joins the outcome
# to those annotations.
# Verifies: SW-REQ-261004-V813, SW-REQ-261004-296X, SW-REQ-261004-VVN2, SW-REQ-261009-RCPT
if [[ -n ${PROOF_PROJECT_ROOT:-} ]]; then
  JROOT=$(. "$ROOT/test/junit/junit.sh" && junit_root) || JROOT=""
  if [[ -n $JROOT && -d $JROOT/.proof/test-results/parts ]]; then
    {
      echo '<?xml version="1.0" encoding="UTF-8"?>'
      echo '<testsuites>'
      echo "  <testsuite name=\"lock-qml-harness\" tests=\"1\" failures=\"$rc\" errors=\"0\" skipped=\"0\">"
      if (( rc == 0 )); then
        echo '    <testcase name="shell.qml" classname="lock-qml-harness" file="test/qml/lock/shell.qml"/>'
      else
        echo '    <testcase name="shell.qml" classname="lock-qml-harness" file="test/qml/lock/shell.qml"><failure message="lock-qml harness did not complete cleanly"/></testcase>'
      fi
      echo '  </testsuite>'
      echo '</testsuites>'
    } >"$JROOT/.proof/test-results/parts/lock-qml-harness.xml"
  fi
fi

exit $rc
