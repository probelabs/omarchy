#!/bin/bash
# Reproduces: KI-261010-HY1B
# Empty ~/Pictures and ~/Videos make omarchy-menu-file pipe an empty find
# result into omarchy-menu-select. omarchy-menu-select cannot tell an empty
# piped list from "the caller passed no options", so it prints its own usage
# and exits 1. omarchy transcode then shows the user that internal usage
# string for a command the user never typed, and the menu's Transcode entry
# (no terminal) is a silent no-op.
#
# Correct behaviour (the sources of intent, R-1777 / omacom/omarchy#7114):
# "The right behaviour is 'nothing to transcode', not an internal usage
# string." The empty state is reported to the user and the picker's usage
# never leaks. The intended notice may be a desktop notification (the fix
# path), so a tiny stub records omarchy-notification-send instead of needing
# a notification daemon; the reported defect path never calls it.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
KI="KI-261010-HY1B"

setup_fail() {
  echo "SETUP: $*"
  exit 2
}

[[ -x $ROOT/bin/omarchy-transcode ]] || setup_fail "omarchy-transcode missing: $ROOT/bin/omarchy-transcode"
[[ -x $ROOT/bin/omarchy-menu-file ]] || setup_fail "omarchy-menu-file missing: $ROOT/bin/omarchy-menu-file"
[[ -x $ROOT/bin/omarchy-menu-select ]] || setup_fail "omarchy-menu-select missing: $ROOT/bin/omarchy-menu-select"
[[ -d $ROOT/bin ]] || setup_fail "bin directory missing: $ROOT/bin"

WORK=$(mktemp -d /tmp/ki-261010-hy1b.XXXXXX) || setup_fail "cannot create a work directory"
cleanup() { rm -rf "$WORK"; }
trap cleanup EXIT

mkdir -p "$WORK/home/Pictures" "$WORK/home/Videos" "$WORK/stub" ||
  setup_fail "cannot build the sandbox home"
[[ -z $(ls -A "$WORK/home/Pictures") && -z $(ls -A "$WORK/home/Videos") ]] ||
  setup_fail "the sandbox media directories are not empty"

NOTICE_LOG="$WORK/notices"
: >"$NOTICE_LOG"
export NOTICE_LOG
cat >"$WORK/stub/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$NOTICE_LOG"
STUB
chmod +x "$WORK/stub/omarchy-notification-send"

status=0
out=$(HOME="$WORK/home" PATH="$WORK/stub:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-transcode" 2>&1) || status=$?

echo "--- omarchy transcode with empty ~/Pictures and ~/Videos (exit $status) ---"
printf '%s\n' "$out"
echo "--- notifications recorded ---"
cat "$NOTICE_LOG"
echo "--- end ---"

if [[ $out == *"Usage: omarchy-menu-select"* ]]; then
  echo "the internal omarchy-menu-select usage reached the user of omarchy transcode"
  echo "PROOF-REPRODUCER: defect-present $KI"
  exit 1
fi

notice=$(cat "$NOTICE_LOG")
if [[ $out$'\n'$notice" " == *"nothing to transcode"* ||
  $out$'\n'$notice" " == *"No files found"* ||
  $out$'\n'$notice" " == *"nothing found"* ||
  $out$'\n'$notice" " == *"no media"* ]]; then
  echo "the empty state was reported to the user and the picker's usage did not leak"
  echo "PROOF-REPRODUCER: defect-absent $KI"
  exit 0
fi

echo "SETUP: no picker usage leak and no empty-state message, so nothing to judge (exit $status)"
exit 2
