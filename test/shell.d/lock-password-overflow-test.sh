#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-WBS3

# Row dispositions (see proof mcdc show SW-REQ-260912-WBS3 for the table):
#mcdc:ignore:defensive SW-REQ-260912-WBS3: dots_scaled_within_field=F, password_text_overflows=T => FALSE -- the dot scale is a declarative binding on the width comparison; an overflowing row that stays unscaled needs a broken binding [reviewed: REVIEW-4]

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  if [[ -n $TMPDIR && -d $TMPDIR ]]; then
    rm -rf "$TMPDIR"
  fi
}
trap cleanup EXIT

require_compositor "lock password overflow test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping lock password overflow test"
  exit 0
fi

require_command jq

TMPDIR=$(mktemp -d)
result="$TMPDIR/result.json"
log="$TMPDIR/quickshell.log"
config_dir="$TMPDIR/lock-password-overflow"
mkdir -p "$config_dir" "$TMPDIR/home"
cp "$SHELL_TEST_DIR/fixtures/lock-password-overflow/shell.qml" "$config_dir/shell.qml"
ln -s "$ROOT/shell/Ui" "$config_dir/Ui"
ln -s "$ROOT/shell/Commons" "$config_dir/Commons"

OMARCHY_PATH="$ROOT" \
OMARCHY_QML_TEST_RESULT="$result" \
HOME="$TMPDIR/home" \
XDG_CONFIG_HOME="$TMPDIR/home/.config" \
XDG_CACHE_HOME="$TMPDIR/home/.cache" \
XDG_STATE_HOME="$TMPDIR/home/.local/state" \
QML2_IMPORT_PATH="$ROOT/shell${QML2_IMPORT_PATH:+:$QML2_IMPORT_PATH}" \
QML_IMPORT_PATH="$ROOT/shell${QML_IMPORT_PATH:+:$QML_IMPORT_PATH}" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$config_dir" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  [[ -s $result ]] && break
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    sed -n '1,220p' "$log" >&2
    fail "lock password overflow quickshell exited before writing result"
  fi
  sleep 0.1
done

[[ -s $result ]] || {
  sed -n '1,220p' "$log" >&2
  fail "lock password overflow test timed out"
}

if ! jq -e '.ok == true' "$result" >/dev/null; then
  printf 'Lock password overflow result:\n' >&2
  jq . "$result" >&2
  printf 'Lock password overflow log:\n' >&2
  sed -n '1,220p' "$log" >&2
  fail "lock password dots shrink to fit the field"
fi

# The fixture asserts both arms: short passwords keep passwordDotScale === 1,
# overflowing passwords shrink the dots (fixtures/lock-password-overflow/shell.qml).
# MCDC SW-REQ-260912-WBS3: dots_scaled_within_field=T, password_text_overflows=T => TRUE
# MCDC SW-REQ-260912-WBS3: dots_scaled_within_field=F, password_text_overflows=F => TRUE [no-action: the fixture's short-password arm asserts passwordDotScale === 1 — no scaling runs without an overflow]
pass "lock password dots shrink to fit the field"
