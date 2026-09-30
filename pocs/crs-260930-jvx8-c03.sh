#!/bin/bash
# PoC for claim CRS-260930-JVX8/C03 (spec SW-REQ-260922-0W96)
# Mechanism: the REAL keybindings_cache_key hashes only a version literal,
# `hyprctl devices` keymap lines and `hyprctl binds` output. A __lua row's
# arg is empty in hyprctl output, so editing the Lua command a bind runs
# never changes the hash; output_binding_records serves the warm cache and
# build_lua_bind_cache never re-runs - the menu keeps dispatching the old
# command.
# Both-ways: drives the REAL keybindings_cache_key with stubbed hyprctl,
# comparing the key before/after a Lua-command-only edit (hyprctl output
# unchanged). Identical keys = defect present (exit 0). A fix folding the
# Lua source (or its hash) into the key changes it and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"

FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

# hyprctl reports the same binds before and after the user edits only the
# Lua-side command: __lua dispatcher, empty arg.
hyprctl() {
  case $1 in
    devices) echo "error: no display" ; return 1 ;;
    binds)
      if [[ ${HYPRCTL_VARIANT:-0} == 1 ]]; then
        cat <<'EOF'
64
0
0
0
0
0
Terminal EDITED KEYMAP ROW
SUPER
RETURN
__lua

0
0
EOF
      else
        cat <<'EOF'
64
0
0
0
0
0
Terminal
SUPER
RETURN
__lua

0
0
EOF
      fi
      ;;
  esac
  return 0
}

BEFORE="$(keybindings_cache_key)"
# --- user edits hyprland.lua here: Terminal's bind now runs a different
# --- command. hyprctl output is byte-identical (above) because __lua rows
# --- carry an empty arg.
AFTER="$(keybindings_cache_key)"

echo "key before edit: $BEFORE"
echo "key after edit:  $AFTER"

rc=1
if [[ $BEFORE == "$AFTER" ]]; then
  echo "SYMPTOM: real cache key unchanged across a Lua-command-only edit - warm cache keeps dispatching the previous command (defect present)"
  rc=0
else
  echo "PASS-REFUTED: cache key changed across the edit - defect fixed"
fi

# Negative control (PoC rules 3/10): a hyprctl-OBSERVABLE bind change moves
# the key - the cache key is live; only the Lua-only edit is invisible to it.
HYPRCTL_VARIANT=1
AFTER2="$(keybindings_cache_key)"
HYPRCTL_VARIANT=0
if [[ $BEFORE != "$AFTER2" ]]; then
  echo "control ok: an observable hyprctl change moves the cache key (key mechanism intact)"
else
  echo "CONTROL FAILED: cache key ignores even observable bind changes; PoC inconclusive"
  rc=2
fi
exit $rc
