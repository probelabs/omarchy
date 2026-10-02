#!/bin/bash
# test/junit/live-session.sh <suite-id> <script>... -- run compositor-bound
# shell tests (test/shell.d/menu-compositor-test.sh, menu-acceptance-test.sh)
# inside a PRIVATE headless Wayland session (sway) and record one JUnit <testcase>
# per script through test/junit/junit.sh, so `proof audit` (tests_pass,
# project.checks.test_results) observes their outcomes.
#
# Each script gets its own fresh compositor (private XDG_RUNTIME_DIR, wlroots
# headless backend, pixman renderer, no GPU, no input devices). The user's own
# session is never touched.
#
# PREREQUISITES (checked before anything starts): sway ($PROOF_ENV_DIR/sysroot
# or PATH), quickshell, wtype and socat (bin/omarchy-shell's IPC client; on PATH
# or $PROOF_ENV_DIR/bin), jq, python3. When one is
# missing, every script is recorded as <skipped> with the missing tools named
# (for example on a macOS host) -- never as a pass.
#
# STRICT MODE. Once the session is up, a script that still skips (its own
# "no Wayland compositor" / "quickshell not installed" guards) is recorded as
# a FAILURE: the prerequisites were verified, so a skip means the session was
# not reachable and the outcome was not observed.
set -u

ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$ROOT" || exit 1
# shellcheck source=test/junit/junit.sh
. test/junit/junit.sh

suite=$1
shift
junit_begin "$suite"

# Optional helper toolchain for hosts whose system lacks some of the session
# tools (the lock-qml harness uses the same layout): $PROOF_ENV_DIR/bin for
# wtype/socat, $PROOF_ENV_DIR/sysroot for sway.
PROOF_ENV_DIR="${PROOF_ENV_DIR:-$HOME/proof-env}"
if [ -d "$PROOF_ENV_DIR/bin" ]; then
  PATH="$PATH:$PROOF_ENV_DIR/bin"
  export PATH
fi

missing=""
SWAY_BIN="$PROOF_ENV_DIR/sysroot/usr/bin/sway"
SWAY_LIB="$PROOF_ENV_DIR/sysroot/usr/lib"
if [ ! -x "$SWAY_BIN" ]; then
  SWAY_BIN=$(command -v sway || true)
  SWAY_LIB=""
fi
[ -n "$SWAY_BIN" ] || missing=" sway"
for tool in quickshell qs wtype socat jq python3 timeout md5sum; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  for s in "$@"; do
    junit_skip "$s" "requires a headless Wayland session (sway + quickshell + wtype); missing:$missing"
  done
  junit_end
  exit $?
fi

CONF="$ROOT/test/junit/sway-headless.conf"
LIVE_TIMEOUT="${LIVE_TIMEOUT:-900}"
RT=""
HP=""

stop_session() {
  if [ -n "$HP" ]; then
    kill "$HP" 2>/dev/null || true
    for _ in 1 2 3 4 5 6 7 8 9 10; do
      kill -0 "$HP" 2>/dev/null || break
      sleep 0.2
    done
    kill "$HP" 2>/dev/null || true
    wait "$HP" 2>/dev/null || true
  fi
  if [ -n "$RT" ] && [ -d "$RT" ]; then
    # Our own mktemp dir only (sway sockets, quickshell run state, logs).
    find "$RT" -mindepth 1 -depth -delete 2>/dev/null
    rmdir -- "$RT" 2>/dev/null || true
  fi
  HP="" RT=""
}
trap stop_session EXIT

# start_session: bring up a private headless sway (wlroots headless backend,
# pixman renderer: no GPU, no input devices -- the same compositor setup as the
# lock-qml harness); on success exports XDG_RUNTIME_DIR and WAYLAND_DISPLAY.
start_session() {
  RT=$(mktemp -d /tmp/omarchy-live.XXXXXX) || return 1
  chmod 700 "$RT"
  env -i \
    LD_LIBRARY_PATH="$SWAY_LIB" \
    XDG_RUNTIME_DIR="$RT" \
    HOME="$HOME" \
    WLR_BACKENDS=headless \
    WLR_RENDERER=pixman \
    WLR_LIBINPUT_NO_DEVICES=1 \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/bin" \
    "$SWAY_BIN" -c "$CONF" >"$RT/sway.log" 2>&1 &
  HP=$!
  local way="" i
  for ((i = 0; i < 120; i++)); do
    way=$(cd "$RT" && ls wayland-[0-9] 2>/dev/null | head -1)
    if [ -n "$way" ] && [ -S "$RT/$way" ] && ls "$RT"/sway-ipc.*.sock >/dev/null 2>&1; then
      unset HYPRLAND_INSTANCE_SIGNATURE
      # Software Qt Quick: the pixman compositor offers no GPU buffers (the
      # lock-qml harness runs quickshell the same way).
      export XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$way" QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software
      return 0
    fi
    kill -0 "$HP" 2>/dev/null || break
    sleep 0.25
  done
  return 1
}

session_failed() {
  echo "not ok - private headless sway did not start for $1"
  [ -n "$RT" ] && tail -n 20 "$RT/sway.log" 2>/dev/null
  return 1
}

# live_strict <script>: run one script; any skip line counts as a failure.
live_strict() {
  local out rc=0
  out=$(mktemp "${TMPDIR:-/tmp}/omarchy-live-out.XXXXXX")
  timeout "$LIVE_TIMEOUT" /usr/bin/env bash "$1" >"$out" 2>&1 || rc=$?
  cat "$out"
  if [ "$rc" -eq 0 ] && grep -qE '# SKIP|; skipping ' "$out"; then
    echo "not ok - $1 skipped inside a verified live session (outcome not observed)"
    rc=1
  fi
  rm -f "$out"
  return "$rc"
}

for s in "$@"; do
  if start_session; then
    junit_run live_strict "$s"
  else
    junit_run session_failed "$s"
  fi
  stop_session
done

junit_end
