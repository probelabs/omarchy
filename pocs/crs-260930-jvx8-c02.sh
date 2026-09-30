#!/bin/bash
# PoC for claim CRS-260930-JVX8/C02 (spec SW-REQ-260922-0W96)
# Mechanism: dynamic_bindings substitutes the dispatcher for __lua rows from
# LUA_BIND_DISPATCHER_MAP (bin/omarchy-menu-keybindings:309-312). Binds whose
# dispatcher is a raw Lua function never register in o.bind_commands, so the
# cache row carries kind=""/arg="" and the map lookup overwrites __lua with
# "". dispatch_binding's empty arm returns 1: the menu shows the row
# (Select all / Universal copy / paste / cut / Zoom in / Reset zoom) but
# dispatching it does nothing.
# Refs: bin/omarchy-menu-keybindings:308-312, dispatch_binding "" arm.
# Both-ways: asserts the defect symptom against CURRENT code (exit 0 = defect
# present). With a fix that keeps a dispatchable action for function binds,
# the assertion fails and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"

FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

# Feed the exact hyprctl binds records the shipped function binds produce:
# dispatcher __lua, empty arg, description set.
RECORDS="64,0,Select all,SUPER,A,__lua,
64,0,Universal copy,SUPER,C,__lua,
64,0,Reset zoom,SUPER,0,__lua,"

OUT="$(printf '%s\n' "$RECORDS" | dynamic_bindings)"

echo "== dynamic_bindings rows =="
echo "$OUT"

fail=0
# The row must not end with an empty dispatcher field
if echo "$OUT" | grep -qE ',__lua?,?$|,,($|[^,])'; then :; fi
EMPTY=$(echo "$OUT" | awk -F, '$4 == "" { c++ } END { print c+0 }')
if (( EMPTY > 0 )); then
  echo "SYMPTOM: $EMPTY shipped function bind row(s) have an empty dispatcher - menu shows them but dispatch is a no-op (defect present)"
else
  echo "PASS-REFUTED: every __lua row kept a dispatchable action - defect fixed"
  fail=1
fi
exit $fail
