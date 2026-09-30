#!/bin/bash
# PoC for claim CRS-260930-JVX8/C07 (spec SW-REQ-260922-0W96)
# Mechanism: dispatch_lua_expression captures `hyprctl dispatch ... 2>&1`
# (line 605) and only accepts status 0 with an empty or exactly-"ok" body
# (line 608). A compositor that succeeds but warns on stderr fails that test,
# dispatch_lua_expression returns 1, and dispatch_exec_binding's
# `|| hyprctl dispatch exec "$command"` (line 620) runs the command a SECOND
# time.
# Both-ways: stubs hyprctl to succeed with a stderr warning; asserts the
# double dispatch (exit 0 = defect present). With a fix (status-only success
# or stderr stripped), a single dispatch runs and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"

FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

EXEC_COUNT=0
hyprctl() {
  if [[ $1 == dispatch && $2 == exec ]]; then
    (( EXEC_COUNT++ ))
    echo "ok"
    return 0
  fi
  # the hl.dsp.exec_cmd dispatch: accepted by the compositor, which also
  # writes a warning on stderr
  echo "warning: deprecated dispatcher form" >&2
  echo "ok"
  return 0
}

dispatch_exec_binding "omarchy-launch-terminal"

echo "== fallback hyprctl dispatch exec invocations: $EXEC_COUNT =="
# The first dispatch (hl.dsp.exec_cmd) was ACCEPTED by the compositor
# (status 0). Any fallback exec dispatch means the command ran a second time.
if (( EXEC_COUNT >= 1 )); then
  echo "SYMPTOM: accepted dispatch with a stderr warning treated as refusal; command dispatched by the accepted call AND by the fallback exec (double execution, defect present)"
  exit 0
else
  echo "PASS-REFUTED: single dispatch despite the warning - defect fixed"
  exit 1
fi
