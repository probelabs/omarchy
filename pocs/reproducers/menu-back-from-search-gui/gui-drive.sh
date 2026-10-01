#!/bin/bash
# GUI drive for menu-back-from-search-gui.mp4 (upstream PR #13012).
# RECONSTRUCTED 2026-10-01 from review/media/MANIFEST.md: the original
# orchestrator ran these steps as ad-hoc shell lines and no script file survived.
# Takes the two revs as args; the shell code (shell/plugins/menu/Menu.qml) is
# swapped off-camera between BEFORE and AFTER takes.
set -euo pipefail
BEFORE_REV=${1:?usage: gui-drive.sh <BEFORE-rev> <AFTER-rev> [repo-dir]}
AFTER_REV=${2:?usage: gui-drive.sh <BEFORE-rev> <AFTER-rev> [repo-dir]}
REPO=${3:-$PWD}
OUT=${OUT:-/tmp/menu-back-from-search-gui-stills}
HEADLESS_CONF=${HEADLESS_CONF:?path to sway-headless.conf (see test/qml/lock/sway-headless.conf for the pattern)}
# Tool locations: PATH first, then the private sysroot under PROOF_ENV_DIR
# (same convention as test/qml/lock/run.sh).
PROOF_ENV_DIR="${PROOF_ENV_DIR:-$HOME/proof-env}"
SWAY_BIN=$(command -v sway || echo "${PROOF_ENV_DIR}/sysroot/usr/bin/sway")
WTYPE=$(command -v wtype || echo "${PROOF_ENV_DIR}/bin/wtype")
export LD_LIBRARY_PATH="${PROOF_ENV_DIR}/sysroot/usr/lib${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
# Restore the working-tree Menu.qml when done (the takes swap it per rev).
trap 'git -C "$REPO" checkout -q HEAD -- shell/plugins/menu/Menu.qml' EXIT

mkdir -p "$OUT"
still() { grim -o HEADLESS-1 "$OUT/$(printf '%04d' "$1").png"; }

take() { # $1 = rev label
  local rev=$1 n=0
  git -C "$REPO" checkout -q "$rev" -- shell/plugins/menu/Menu.qml
  # headless sway + full production shell on output HEADLESS-1 (pixman)
  WLR_BACKENDS=headless WLR_LIBINPUT_NO_DEVICES=1 WLR_RENDERER=pixman \
    "$SWAY_BIN" -c "$HEADLESS_CONF" & SWAY_PID=$!
  sleep 2
  quickshell -p "$REPO/shell/shell.qml" & QS_PID=$!
  sleep 4
  still $((n++))
  # summon the Style submenu over the shell IPC
  omarchy-shell shell summon omarchy.menu '{"menu":"style"}'
  sleep 1; still $((n++))
  # wtype's first keystroke races seat focus; prime with a no-op Shift press
  "$WTYPE" -k Shift_Left; sleep 0.2
  "$WTYPE" font; sleep 1; still $((n++))          # search results
  "$WTYPE" -k Return; sleep 1; still $((n++))     # open Font row
  "$WTYPE" -k BackSpace; sleep 1; still $((n++))  # Back -> must land on Font, not Theme
  kill $QS_PID $SWAY_PID 2>/dev/null || true
  wait 2>/dev/null || true
}

take "$BEFORE_REV"
take "$AFTER_REV"
# assemble at 25 fps (wf-recorder loses its buffered tail on this pixman head,
# so timed grim stills are the capture medium)
ffmpeg -y -framerate 25 -pattern_type glob -i "$OUT/[0-9]*.png" -c:v libx264 -pix_fmt yuv420p "$OUT/menu-back-from-search-gui.mp4"
echo "assembled: $OUT/menu-back-from-search-gui.mp4"
