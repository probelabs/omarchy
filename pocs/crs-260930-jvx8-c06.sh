#!/bin/bash
# PoC for claim CRS-260930-JVX8/C06 (spec SW-REQ-260922-0W96)
# Mechanism: dynamic_bindings prints its cache rows as raw comma-joined CSV
# (printf '%s,%s,%s,%s,%s\n', line 333) with no quoting; a description that
# itself contains a comma ("Save, quit") shifts every later field, and
# parse_binding_records (FS="," action=$3 dispatcher=$4) then shows a
# truncated label and dispatches the wrong dispatcher/arg - here the literal
# string " quit" as dispatcher, which dispatch_binding treats as unknown.
# Both-ways: runs the REAL parse_binding_records on the shifted record;
# asserts the field shift (exit 0 = defect present). With a fix (escaping or
# a non-ambiguous separator), the fields round-trip and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"

FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

# the exact record dynamic_bindings prints for description "Save, quit"
RECORDS='SUPER,Q,Save, quit,exec,alacritty'

OUT="$(printf '%s\n' "$RECORDS" | parse_binding_records)"
echo "== parse_binding_records output =="
echo "$OUT"

ACTION=$(printf '%s\n' "$OUT" | awk -F'\t' '{split($1,a,"→"); sub(/^ +/,"",a[2]); print a[2]}')
DISPATCHER=$(printf '%s\n' "$OUT" | awk -F'\t' '{print $2}')

if [[ $ACTION == "Save" && $DISPATCHER == " quit" ]]; then
  echo "SYMPTOM: action=[$ACTION] dispatcher=[$DISPATCHER] - comma in description shifted the CSV fields; menu shows a truncated label and dispatch fails (defect present)"
  exit 0
elif [[ $ACTION == "Save, quit" && $DISPATCHER == "exec" ]]; then
  echo "PASS-REFUTED: fields round-tripped correctly - defect fixed"
  exit 1
else
  echo "UNEXPECTED parse: action=[$ACTION] dispatcher=[$DISPATCHER]"; exit 2
fi
