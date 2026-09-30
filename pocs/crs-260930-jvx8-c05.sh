#!/bin/bash
# PoC for claim CRS-260930-JVX8/C05 (spec SW-REQ-260922-0W96)
# Mechanism: parse_keycodes' awk matches /code:([0-9]+)/ and /mouse:([0-9]+)/
# against the WHOLE comma-joined record ($0, lines 54/59) and sub() rewrites
# the first occurrence in place - not just the key field. A description or
# command containing code:N / mouse:N text is corrupted: "Count code:10
# items" -> "Count 1 items", "echo code:20" -> "echo MINUS",
# "notify-send mouse:272" -> "notify-send LEFT MOUSE BUTTON".
# Both-ways: runs the REAL parse_keycodes on corrupted-input records; asserts
# the description/command is rewritten (exit 0 = defect present). With a fix
# that confines the rewrite to the key field, the text survives and this
# exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"

FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

RECORDS='SUPER,Q,Count code:10 items,exec,true
SUPER,Q,Run a script,exec,echo code:20
SUPER,W,Move,exec,notify-send mouse:272'

OUT="$(printf '%s\n' "$RECORDS" | parse_keycodes)"
echo "== parse_keycodes output =="
echo "$OUT"

fail=0
echo "$OUT" | grep -q "Count 1 items" || { echo "description 'Count code:10 items' not corrupted (fix present?)"; fail=1; }
echo "$OUT" | grep -q "echo MINUS" || { echo "command 'echo code:20' not corrupted (fix present?)"; fail=1; }
echo "$OUT" | grep -q "notify-send LEFT MOUSE BUTTON" || { echo "command 'notify-send mouse:272' not corrupted (fix present?)"; fail=1; }
if (( ! fail )); then
  echo "SYMPTOM: description and command text rewritten by the keycode/mouse substitution (defect present)"
fi
exit $fail
