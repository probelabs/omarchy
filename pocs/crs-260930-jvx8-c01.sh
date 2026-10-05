#!/bin/bash
# PoC for claim CRS-260930-JVX8/C01 (spec SW-REQ-260922-0W96)
# Mechanism: build_lua_bind_cache dofiles the whole hyprland.lua under one
# pcall. Any module that throws against the scanner's mock ends the scan, and
# hypr.bindings (required later, config/hypr/hyprland.lua:21) is never
# scanned - every user Lua bind silently vanishes from the menu cache.
# Two triggers, each its own arm:
#   A (shipped config): require("default.hypr.omarchy") loads qconsole whose
#     console_monitor() evaluates `mon.scale > 0` against the mock (a table);
#     the comparison throws.
#   B (a user module): with A's comparisons guarded, a monitors.lua that hands
#     a mock value to a library call that checks its argument type
#     (string.format("%d", ...)) throws the same way. hypr.monitors is required
#     before hypr.bindings.
# Refs: bin/omarchy-menu-keybindings (build_lua_bind_cache),
#       config/hypr/hyprland.lua:14-21, default/hypr/qconsole.lua:123
# Both-ways: exit 0 = the defect is present on at least one arm. A fix that
# keeps the binds loaded after a throwing module flips both arms and this
# exits 1. Each arm prints its own verdict, so a fix that removes only the
# shipped trigger shows as arm A fixed, arm B present.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"
PATH="$REPO/bin:$PATH"

TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# make_home <dir> <guard-qconsole:0|1> : the whole shipped user config (hyprland.lua
# also requires hypr.monitors and hypr.input before hypr.bindings, so a partial
# copy would end a fixed scan on a missing module and read as the defect), plus a
# user rebind and a new user bind.
make_home() {
  mkdir -p "$1/.config/hypr"
  cp -r "$REPO/default" "$1/.config/default"
  if [[ $2 == 1 ]]; then
    sed -e 's/if not monitor or not monitor.scale or monitor.scale <= 0 then/if not monitor or not monitor.scale or type(monitor.scale) ~= "number" or monitor.scale <= 0 then/' \
        -e 's/if mon and mon.scale and mon.scale > 0 then/if mon and mon.scale and type(mon.scale) == "number" and mon.scale > 0 then/' \
      "$REPO/default/hypr/qconsole.lua" > "$1/.config/default/hypr/qconsole.lua"
  fi
  cp "$REPO"/config/hypr/*.lua "$1/.config/hypr/"
  cat >> "$1/.config/hypr/bindings.lua" <<'LUA'
o.rebind("SUPER + RETURN", "Terminal", { launch = "alacritty" })
o.bind("SUPER + SHIFT + R", "SSH", { launch = "alacritty -e ssh your-server" })
LUA
}

# Load the real scanner functions (strip the trailing main dispatch block)
FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

# scan_has_ssh <home> <stderr-file> : one fresh scan (the cache maps are global,
# so they are cleared first); true when the user's SSH bind was cached.
scan_has_ssh() {
  local k
  LUA_BIND_DISPATCHER_MAP=(); LUA_BIND_KEY_MAP=(); LUA_BIND_ARG_MAP=()
  HOME="$1" OMARCHY_PATH="$REPO" DEBUG=1 build_lua_bind_cache 2>"$2"
  for k in "${!LUA_BIND_DISPATCHER_MAP[@]}"; do
    [[ $k == *,SSH,* ]] && return 0
  done
  return 1
}

defect=0

# Arm A: the shipped config as it is.
make_home "$TMP/home" 0
echo "== arm A (shipped config): scan stderr =="
if scan_has_ssh "$TMP/home" "$TMP/err"; then a=present; else a=absent; fi
cat "$TMP/err"
if [[ $a == absent ]]; then
  echo "arm A SYMPTOM: SSH bind absent from the scanned cache (defect present)"
  defect=1
else
  echo "arm A PASS-REFUTED: SSH bind cached through the shipped config (fixed)"
fi

# Arm B: shipped trigger guarded; the user's monitors.lua formats a mode string
# from the active monitor, the way a user would build a mode.
make_home "$TMP/homeB" 1
cat >> "$TMP/homeB/.config/hypr/monitors.lua" <<'LUA'
local m = hl.get_active_monitor()
local mode = string.format("%dx%d@%d", m.width, m.height, m.refresh_rate)
LUA
echo "== arm B (user monitors.lua with string.format): scan stderr =="
if scan_has_ssh "$TMP/homeB" "$TMP/errB"; then b=present; else b=absent; fi
cat "$TMP/errB"
if [[ $b == absent ]]; then
  echo "arm B SYMPTOM: SSH bind absent from the scanned cache (defect present)"
  defect=1
else
  echo "arm B PASS-REFUTED: SSH bind cached after a throwing user module (fixed)"
fi

# Negative control (PoC rules 3/10): the guarded shipped config with no extra
# user line caches the binds - the scan machinery is intact, so each arm's loss
# is attributable to its throwing line.
make_home "$TMP/home2" 1
if scan_has_ssh "$TMP/home2" "$TMP/err2"; then
  echo "control ok: with the throwing comparisons guarded, the SSH bind is cached (scan machinery intact)"
else
  echo "CONTROL FAILED: scan drops binds even with the throwing comparisons guarded; PoC inconclusive"
  cat "$TMP/err2"
  exit 2
fi

if [[ $defect == 1 ]]; then exit 0; fi
echo "PASS-REFUTED: every arm keeps the user's binds - defect fixed"
exit 1
