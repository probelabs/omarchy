#!/usr/bin/env bash
# Reproducer for report cmupntnla003f49w4drywtcgj (omacom/omarchy#13954).
# Report: the lock screen never shows the fingerprint stack's PAM messages
# ("Remove your finger, and try touching the sensor again"): Service.qml's
# fingerprintPam handles onPamMessage only as a reached-the-reader signal, and
# LockView.qml has no fingerprint text element. This runs a private PAM stack
# that sends that message and checks whether the service or the view keeps it.
#
# Runs the QML fixture test/reports/report-cmupntnla003f49w4drywtcgj.qml against the REAL lock plugin
# sources of this tree (shell/plugins/lock) in quickshell, on a private headless
# sway (no GPU, no session, no input devices). Process-driven branches see no-op
# stubs for the display/keyboard brightness, wake and lock-probe helpers, so the
# run changes nothing on the host. The PAM stack is private to a user + mount
# namespace (unshare -Urm): the host's /etc/pam.d is never touched.
#   exit 1 + "AS-REPORTED:"     the reported behaviour is present at this commit
#   exit 0 + "NOT-AS-REPORTED:" it is not
#   exit 2 + "SETUP:"           the run could not be set up (quickshell, sway or jq
#                               missing, compositor or fixture failed) - decides nothing
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
FIXTURE="$ROOT/test/reports/report-cmupntnla003f49w4drywtcgj.qml"
PROOF_ENV_DIR=${PROOF_ENV_DIR:-$HOME/proof-env}
[ -f "$FIXTURE" ] || { echo "SETUP: $FIXTURE is missing"; exit 2; }
[ -d "$ROOT/shell/plugins/lock" ] || { echo "SETUP: shell/plugins/lock is missing"; exit 2; }
command -v quickshell >/dev/null 2>&1 || { echo "SETUP: quickshell is not on PATH"; exit 2; }
command -v jq >/dev/null 2>&1 || { echo "SETUP: jq is not on PATH"; exit 2; }
SWAY="$PROOF_ENV_DIR/sysroot/usr/bin/sway"; SWAYLIB="$PROOF_ENV_DIR/sysroot/usr/lib"
if [ ! -x "$SWAY" ]; then SWAY=$(command -v sway || true); SWAYLIB=""; fi
[ -n "$SWAY" ] || { echo "SETUP: no sway binary for the private headless compositor"; exit 2; }
RT=$(mktemp -d "${TMPDIR:-/tmp}/omarchy-report.XXXXXX") || { echo "SETUP: mktemp failed"; exit 2; }
chmod 700 "$RT"
SWAY_PID=""; QS_PID=""
cleanup() {
  [ -n "$QS_PID" ] && kill "$QS_PID" 2>/dev/null
  [ -n "$SWAY_PID" ] && kill "$SWAY_PID" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$RT"
}
trap cleanup EXIT
mkdir -p "$RT/home/.config" "$RT/home/.cache" "$RT/home/.local/state" "$RT/cfg" "$RT/stub"
# No-op helpers: blanking/waking the displays and the keyboard backlight, and the
# stranded-lock probe (exit 1 = "no stranded lock", so the service never takes a lock).
for c in omarchy-brightness-display omarchy-brightness-keyboard omarchy-system-wake hyprctl; do
  printf '#!/bin/sh\nexit 0\n' > "$RT/stub/$c"
done
printf '#!/bin/sh\nexit 1\n' > "$RT/stub/omarchy-hyprland-session-locked"
printf '#!/bin/sh\necho no\n' > "$RT/stub/fprintd-list"
chmod +x "$RT/stub/"*
env -i LD_LIBRARY_PATH="$SWAYLIB" XDG_RUNTIME_DIR="$RT" HOME="$RT/home" WLR_BACKENDS=headless \
  WLR_RENDERER=pixman WLR_LIBINPUT_NO_DEVICES=1 PATH="/usr/local/bin:/usr/bin" \
  "$SWAY" -c /dev/null > "$RT/sway.log" 2>&1 &
SWAY_PID=$!
WAY=""
for _ in $(seq 1 100); do
  WAY=$(cd "$RT" && ls wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)
  [ -n "$WAY" ] && break
  kill -0 "$SWAY_PID" 2>/dev/null || break
  sleep 0.2
done
[ -n "$WAY" ] || { echo "SETUP: the private headless sway did not start"; tail -5 "$RT/sway.log"; exit 2; }
cp "$FIXTURE" "$RT/cfg/shell.qml"
ln -s "$ROOT/shell/Ui" "$RT/cfg/Ui"
ln -s "$ROOT/shell/Commons" "$RT/cfg/Commons"
RESULT="$RT/result.json"
command -v unshare >/dev/null 2>&1 && unshare -Urm true 2>/dev/null || { echo "SETUP: unshare -Urm (an unprivileged user + mount namespace) is not available"; exit 2; }
# The private PAM stack: one info message (the text pam_fprintd sends for an
# unusable press, quoted in the report), then a failed attempt. It lives in a
# tmpfs mounted over /etc/pam.d inside the namespace only.
printf '%s\n' 'auth optional pam_echo.so Remove your finger, and try touching the sensor again' \
  'auth required pam_deny.so' 'account required pam_permit.so' > "$RT/pam-fingerprint"
env -i QT_QPA_PLATFORM=wayland QT_QUICK_BACKEND=software XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$WAY" \
  QT_WAYLAND_DISABLE_WINDOWDECORATION=1 OMARCHY_PATH="$ROOT" OMARCHY_QML_TEST_RESULT="$RESULT" \
  HOME="$RT/home" XDG_CONFIG_HOME="$RT/home/.config" XDG_CACHE_HOME="$RT/home/.cache" \
  XDG_STATE_HOME="$RT/home/.local/state" USER="${USER:-omarchy}" QML2_IMPORT_PATH="$ROOT/shell" \
  PATH="$RT/stub:/usr/local/bin:/usr/bin" \
  unshare -Urm sh -c 'mount -t tmpfs tmpfs /etc/pam.d && cp "$1" /etc/pam.d/omarchy-lock-fingerprint && exec quickshell -p "$2" --no-color' \
  _ "$RT/pam-fingerprint" "$RT/cfg" > "$RT/qs.log" 2>&1 &
QS_PID=$!
for _ in $(seq 1 300); do
  [ -s "$RESULT" ] && break
  kill -0 "$QS_PID" 2>/dev/null || break
  sleep 0.1
done
if [ ! -s "$RESULT" ]; then
  echo "SETUP: the fixture wrote no result (quickshell exited or timed out); quickshell log tail:"
  tail -15 "$RT/qs.log"
  exit 2
fi
sleep 0.2
if ! jq -e . "$RESULT" >/dev/null 2>&1; then echo "SETUP: unreadable fixture result"; cat "$RESULT"; exit 2; fi
SETUP_ERR=$(jq -r '.setup // empty' "$RESULT")
if [ -n "$SETUP_ERR" ]; then echo "SETUP: $SETUP_ERR"; tail -15 "$RT/qs.log"; exit 2; fi
echo "Observed on this tree (quickshell $(quickshell --version 2>/dev/null | head -1 | awk '{print $2}'), lock plugin shell/plugins/lock):"
jq -r '.observed[] | "  - " + .' "$RESULT"
if [ "$(jq -r '.asReported' "$RESULT")" = true ]; then
  echo "AS-REPORTED: $(jq -r '.summary' "$RESULT")"
  exit 1
fi
echo "NOT-AS-REPORTED: $(jq -r '.summary' "$RESULT")"
exit 0
