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
# The whole shipped user config, as the control arm below uses: hyprland.lua
# also requires hypr.monitors and hypr.input before hypr.bindings, so a partial
# copy would end a fixed scan on a missing module and read as the defect.
cp "$REPO"/config/hypr/*.lua "$TMP/home/.config/hypr/"
cat >> "$TMP/home/.config/hypr/bindings.lua" <<'LUA'
o.rebind("SUPER + RETURN", "Terminal", { launch = "alacritty" })
o.bind("SUPER + SHIFT + R", "SSH", { launch = "alacritty -e ssh your-server" })
LUA

# Load the real scanner functions (strip the trailing main dispatch block)
FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

cache_has_ssh() {
  local k
  for k in "${!LUA_BIND_DISPATCHER_MAP[@]}"; do
    [[ $k == *,SSH,* ]] && return 0
  done
  return 1
}

HOME="$TMP/home" OMARCHY_PATH="$REPO" DEBUG=1 build_lua_bind_cache 2>"$TMP/err"

echo "== scan stderr =="
cat "$TMP/err"
echo "== scanned SSH bind =="
if cache_has_ssh; then echo present; else echo absent; fi

fail=0
grep -q "lua bind scan failed" "$TMP/err" || { echo "FAIL: scan did not die on qconsole (fix present?)"; fail=1; }
if cache_has_ssh; then
  echo "PASS-REFUTED: SSH bind present in cache - defect fixed"
  fail=1
else
  echo "SYMPTOM: SSH bind absent from the scanned cache after the qconsole abort (defect present)"
fi

# Negative control (PoC rules 3/10): with the console module made tolerant of
# the scanner's mock (type-guards on the scale comparisons), the same scan
# caches the binds - the scan machinery is intact and the abort is
# attributable to the throwing comparison.
mkdir -p "$TMP/home2/.config/hypr"
cp -r "$REPO/default" "$TMP/home2/.config/default"
sed -e 's/if not monitor or not monitor.scale or monitor.scale <= 0 then/if not monitor or not monitor.scale or type(monitor.scale) ~= "number" or monitor.scale <= 0 then/' \
    -e 's/if mon and mon.scale and mon.scale > 0 then/if mon and mon.scale and type(mon.scale) == "number" and mon.scale > 0 then/' \
  "$REPO/default/hypr/qconsole.lua" > "$TMP/home2/.config/default/hypr/qconsole.lua"
cp "$REPO"/config/hypr/*.lua "$TMP/home2/.config/hypr/"
cat >> "$TMP/home2/.config/hypr/bindings.lua" <<'LUA'
o.rebind("SUPER + RETURN", "Terminal", { launch = "alacritty" })
o.bind("SUPER + SHIFT + R", "SSH", { launch = "alacritty -e ssh your-server" })
LUA
HOME="$TMP/home2" OMARCHY_PATH="$REPO" build_lua_bind_cache 2>/dev/null
if cache_has_ssh; then
  echo "control ok: with the throwing comparisons guarded, the SSH bind is cached (scan machinery intact)"
else
  echo "CONTROL FAILED: scan drops binds even with the throwing comparisons guarded; PoC inconclusive"
  fail=2
fi
exit $fail
