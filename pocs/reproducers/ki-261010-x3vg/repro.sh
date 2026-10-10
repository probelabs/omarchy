#!/bin/bash
# Reproduces: KI-261010-X3VG
# Keybindings Lua bind scan never terminates when user config iterates an hl
# list getter. build_lua_bind_cache (bin/omarchy-menu-keybindings) re-evaluates
# ~/.config/hypr/hyprland.lua in a bare lua interpreter where hl is a stub
# whose catch-all __index answers every key with a truthy noop sentinel, so
# ipairs(hl.get_monitors()) never reaches nil, the lua subprocess spins
# forever, and the menu neither opens nor refuses.
# Correct behaviour (SW-REQ-260922-0W96, SYS-REQ-260922-6642): --print must
# end with the binding list or a loud, exit-coded refusal - never a hang.
#
# The trigger is the reported one line of user Lua in the user Hyprland Lua
# config, placed ahead of require("default.hypr.omarchy"): at this baseline
# that require reaches default/hypr/qconsole.lua, whose numeric comparison
# throws against the same stub and makes the pcall abort the scan before
# later user files load (the masking the issue thread documents), so the
# same loop in monitors.lua would never run. The defect is the stub's
# non-terminating ipairs; any user Lua the scan evaluates can reach it.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
SCRIPT="$ROOT/bin/omarchy-menu-keybindings"
KI="KI-261010-X3VG"
LIMIT=8

setup_fail() {
  echo "SETUP: $*"
  exit 2
}

command -v lua >/dev/null || setup_fail "lua is not on PATH"
command -v timeout >/dev/null || setup_fail "timeout is not on PATH"
[[ -x $SCRIPT ]] || setup_fail "keybindings script missing: $SCRIPT"

TMP=$(mktemp -d /tmp/ki-261010-x3vg.XXXXXX)
cleanup() { rm -rf "$TMP"; }
trap cleanup EXIT

# Stock user config tree, with the reported trigger added to the user
# Hyprland Lua config ahead of the default loads.
mkdir -p "$TMP/home/.config/hypr"
cp -r "$ROOT/default" "$TMP/home/.config/default"
cp "$ROOT"/config/hypr/*.lua "$TMP/home/.config/hypr/"
awk '
  $0 == "require(\"default.hypr.omarchy\")" {
    print "for _, monitor in ipairs(hl.get_monitors()) do end"
  }
  { print }
' "$ROOT/config/hypr/hyprland.lua" >"$TMP/home/.config/hypr/hyprland.lua"

export HOME="$TMP/home" OMARCHY_PATH="$ROOT" PATH="$ROOT/bin:$PATH" XDG_CACHE_HOME="$TMP/cache"

echo "running omarchy-menu-keybindings --print with the reported trigger in the user config"

set -m
timeout --kill-after=2 "$LIMIT" "$SCRIPT" --print >"$TMP/out" 2>"$TMP/err" &
pid=$!
( sleep $((LIMIT + 3)); kill -KILL -- "-$pid" 2>/dev/null ) &
wd=$!
wait "$pid"
status=$?
kill "$wd" 2>/dev/null
wait "$wd" 2>/dev/null

echo "exit=$status"
sed 's/^/stdout: /' "$TMP/out" | head -20
sed 's/^/stderr: /' "$TMP/err" | head -20

if [[ $status -eq 124 || $status -eq 137 ]]; then
  echo "PROOF-REPRODUCER: defect-present $KI"
  exit 1
fi
echo "PROOF-REPRODUCER: defect-absent $KI"
exit 0
