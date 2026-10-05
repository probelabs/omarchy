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
# Fixture shape: Hyprland 0.56.2 reports every Lua bind as dispatcher __lua
# with a numeric registry ref in arg (hlBind stores luaL_ref; HyprCtl prints
# it), so the function bind row carries "arg: 264", not an empty arg. A fix
# may dispatch through that ref; an empty arg would hide such a fix.
# No `set -u` here on purpose: bin/omarchy-menu-keybindings itself runs without
# it, and the empty-dispatcher overwrite this PoC pins depends on the missing
# map lookup degrading to "" exactly as it does in production.
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"

FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

# Feed the `hyprctl binds` text Hyprland 0.56.2 prints for a shipped function
# bind: dispatcher __lua with its registry ref as arg, plus a launch bind for
# contrast.
hyprctl() {
  case $1 in
    binds)
      cat <<'EOF'
bind
	modmask: 64
	key: SUPER + A
	keycode: 0
	description: Select all
	dispatcher: __lua
	arg: 264

bind
	modmask: 64
	key: SUPER + RETURN
	keycode: 0
	description: Terminal
	dispatcher: exec
	arg: alacritty
EOF
      ;;
    *) return 1 ;;
  esac
}

OUT="$(dynamic_bindings)"

echo "== dynamic_bindings rows =="
printf '%s\n' "$OUT"

fail=0
# The __lua row must not end up with an empty dispatcher (CSV field 4).
EMPTY=$(printf '%s\n' "$OUT" | awk -F, 'NF >= 5 && $4 == "" { c++ } END { print c+0 }')
KEEP=$(printf '%s\n' "$OUT" | awk -F, 'NF >= 5 && $4 == "exec" { c++ } END { print c+0 }')

# Negative control (PoC rules 3/10): with a registered dispatchable action in
# the map - what o.bind_commands registration provides for non-function binds
# - the same __lua row keeps its dispatcher.
LUA_BIND_DISPATCHER_MAP["64,Select all,A"]="lua:console.selectAll"
COUT="$(dynamic_bindings)"
CKEEP=$(printf '%s\n' "$COUT" | awk -F, 'NF >= 5 && $4 == "lua:console.selectAll" { c++ } END { print c+0 }')
if (( CKEEP > 0 )); then
  echo "control ok: with a registered dispatcher the __lua row dispatches (map lookup intact)"
else
  echo "CONTROL FAILED: registered dispatcher did not reach the row; PoC inconclusive"
  exit 2
fi

if (( EMPTY > 0 && KEEP > 0 )); then
  echo "SYMPTOM: $EMPTY shipped function bind row(s) have an empty dispatcher while launch rows keep theirs - menu shows them but dispatch is a no-op (defect present)"
else
  echo "PASS-REFUTED: every __lua row kept a dispatchable action - defect fixed"
  fail=1
fi
exit $fail
