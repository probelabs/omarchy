#!/bin/bash
# PoC for claim CRS-260930-JVX8/C01 (spec SW-REQ-260922-0W96)
# Mechanism: build_lua_bind_cache dofiles the whole hyprland.lua under one
# pcall. require("default.hypr.omarchy") loads qconsole whose
# console_monitor() evaluates `mon.scale > 0` against the scanner's noop mock
# (a table), the comparison throws, the pcall aborts, and hypr.bindings
# (required later, config/hypr/hyprland.lua:21) is never scanned - every user
# Lua bind silently vanishes from the menu cache.
# Refs: bin/omarchy-menu-keybindings:241, config/hypr/hyprland.lua:14,
#       default/hypr/qconsole.lua:123
# Both-ways: asserts the defect symptom against CURRENT code (exit 0 = defect
# present). With a fix that recovers binds despite a throwing require, the
# assertions fail and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"
PATH="$REPO/bin:$PATH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/home/.config"
cp -r "$REPO/default" "$TMP/home/.config/default"
mkdir -p "$TMP/home/.config/hypr"
cp "$REPO/config/hypr/hyprland.lua" "$TMP/home/.config/hypr/hyprland.lua"
cp "$REPO/config/hypr/bindings.lua" "$TMP/home/.config/hypr/bindings.lua"
cat >> "$TMP/home/.config/hypr/bindings.lua" <<'LUA'
o.rebind("SUPER + RETURN", "Terminal", { launch = "alacritty" })
o.bind("SUPER + SHIFT + R", "SSH", { launch = "alacritty -e ssh your-server" })
LUA

# Load the real scanner functions (strip the trailing main dispatch block)
FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

OUT="$(HOME="$TMP/home" OMARCHY_PATH="$REPO" DEBUG=1 build_lua_bind_cache 2>"$TMP/err")"
RC=$?

echo "== scan stderr =="
cat "$TMP/err"
echo "== scan rows =="
echo "$OUT"

fail=0
grep -q "lua bind scan failed" "$TMP/err" || { echo "FAIL: scan did not die on qconsole (fix present?)"; fail=1; }
echo "$OUT" | grep -q "SSH" || echo "SYMPTOM: SSH bind absent from cache (defect present)"
if echo "$OUT" | grep -q "SSH"; then
  echo "PASS-REFUTED: SSH bind present in cache - defect fixed"
  fail=1
fi
exit $fail
