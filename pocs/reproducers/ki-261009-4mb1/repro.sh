#!/bin/bash
# Reproduces: KI-261009-4MB1
# Lock blank runs `omarchy-brightness-keyboard off` (brightnessctl -s set 0).
# A later blank runs off again while the LED is already 0, so -s overwrites
# the saved non-zero level with 0. Wake restore then applies that 0.
# Correct behaviour: restore brings back the level the first off saved.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCRIPT="$ROOT/bin/omarchy-brightness-keyboard"
KI="KI-261009-4MB1"
PRIOR=80

setup_fail() {
  echo "SETUP: $*"
  exit 2
}

command -v brightnessctl >/dev/null || setup_fail "brightnessctl is not on PATH"
command -v unshare >/dev/null || setup_fail "unshare is not on PATH"
[[ -x $SCRIPT ]] || setup_fail "keyboard brightness script missing: $SCRIPT"

FAKE=$(mktemp -d /tmp/ki-261009-4mb1-leds.XXXXXX)
RT=$(mktemp -d /tmp/ki-261009-4mb1-rt.XXXXXX)
chmod 700 "$RT"
cleanup() { rm -rf "$FAKE" "$RT"; }
trap cleanup EXIT

mkdir -p "$FAKE/fake::kbd_backlight"
echo 200 >"$FAKE/fake::kbd_backlight/max_brightness"
echo "$PRIOR" >"$FAKE/fake::kbd_backlight/brightness"

export FAKE ROOT SCRIPT PRIOR KI XDG_RUNTIME_DIR="$RT"

unshare --user --map-root-user --mount bash -s <<'EOF'
set -u
mount --bind "$FAKE" /sys/class/leds || { echo "SETUP: cannot bind a fake keyboard LED over /sys/class/leds"; exit 2; }
LED=/sys/class/leds/fake::kbd_backlight
SAVE="$XDG_RUNTIME_DIR/brightnessctl/leds/fake::kbd_backlight"
[[ -e $LED/brightness && -e $LED/max_brightness ]] || { echo "SETUP: fake LED nodes missing after mount"; exit 2; }

echo "$PRIOR" >"$LED/brightness" || { echo "SETUP: cannot write the fake LED"; exit 2; }

"$SCRIPT" off
status=$?
if [[ $status -ne 0 ]]; then
  echo "SETUP: first keyboard off exited $status"
  exit 2
fi
current=$(cat "$LED/brightness" 2>/dev/null || true)
saved=$(cat "$SAVE" 2>/dev/null || true)
echo "after-first-off current=$current saved=$saved"
if [[ $current != 0 || $saved != "$PRIOR" ]]; then
  echo "SETUP: first off did not save $PRIOR and set 0 (current=$current saved=${saved:-missing})"
  exit 2
fi

"$SCRIPT" off
status=$?
if [[ $status -ne 0 ]]; then
  echo "SETUP: second keyboard off exited $status"
  exit 2
fi
saved=$(cat "$SAVE" 2>/dev/null || true)
echo "after-second-off saved=$saved"

"$SCRIPT" restore
status=$?
if [[ $status -ne 0 ]]; then
  echo "SETUP: keyboard restore exited $status"
  exit 2
fi
got=$(cat "$LED/brightness" 2>/dev/null || true)
echo "after-restore brightness=$got expected=$PRIOR"

if [[ $got == "$PRIOR" ]]; then
  echo "PROOF-REPRODUCER: defect-absent $KI"
  exit 0
fi
if [[ $got == 0 ]]; then
  echo "PROOF-REPRODUCER: defect-present $KI"
  exit 1
fi
echo "SETUP: restore left brightness ${got:-missing}, neither $PRIOR nor 0"
exit 2
EOF
status=$?
exit "$status"
