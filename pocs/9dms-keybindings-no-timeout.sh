#!/bin/bash
# Green tripwire for SW-REQ-260922-9DMS external_call_timeout_bounded.
# Reproduces: KI-MENU-KEYBINDINGS-NO-TIMEOUT
#
# Mechanism: bin/omarchy-menu-keybindings builds its rows from two external
# calls with no timeout wrapper:
#   - `hyprctl binds` (keybindings_cache_key and dynamic_bindings), and
#   - `xkbcli compile-keymap </dev/null` (the keymap_cmd in parse_keycodes).
# A stalled Hyprland IPC or a wedged keymap compile therefore blocks the
# keybindings menu build for as long as the callee does; nothing bounds it.
#
# GREEN TRIPWIRE: pins the buggy behavior, so it PASSES while the defect is
# present. Each stall arm runs the REAL script in --print mode under an external
# watchdog and asserts it is still blocked when killed (rc=124). The control
# arm proves the harness drives the real build: healthy callees produce the
# stubbed bind row (with its keycode resolved through the stubbed keymap) well
# inside the same watchdog.
#
# Watchdog sizing: on a stalled hyprctl the --print path calls `hyprctl binds`
# three times in sequence (cache key, the cache refresh, then the uncached
# fallback once the refresh fails), so a fix that bounds each call at T seconds
# still takes about 3T. Arm A's watchdog is 10s so the declared 2s bound
# (about 6s total) finishes inside it; arm B's keymap compile runs once and
# keeps a 5s watchdog.
#
# tripwire_mutation: bound both calls in bin/omarchy-menu-keybindings, e.g.
#   `hyprctl binds` -> `timeout 2 hyprctl binds` (cache key and dynamic_bindings)
#   keymap_cmd = "xkbcli compile-keymap </dev/null"
#     -> keymap_cmd = "timeout 2 xkbcli compile-keymap </dev/null"
# The stall arms then finish (rc != 124) inside their watchdogs (arm A about 6s
# for three bounded calls, arm B about 2s), the assertions fail, and
# the tripwire flips red. Each arm flips on its own, so a partial fix (only one
# call bounded) still turns the tripwire red. The control arm is unaffected.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
MENU="$REPO/bin/omarchy-menu-keybindings"
[[ -x $MENU ]] || { echo "bin/omarchy-menu-keybindings missing"; exit 2; }
for c in timeout gawk jq; do
  command -v "$c" >/dev/null || { echo "$c required"; exit 2; }
done
awk --version 2>/dev/null | grep -q 'GNU Awk' || { echo "awk must be GNU awk (the script uses gawk match arrays)"; exit 2; }
TMP="$(mktemp -d)"
cleanup() {
  if [[ -f $TMP/stub.pids ]]; then
    while read -r pid; do kill -KILL "$pid" 2>/dev/null; done <"$TMP/stub.pids"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin"
fail=0

# hyprctl stub: `binds` answers one exec bind on code:38 (the "a" key,
# absent from the script fallback table) or stalls
# when HYPR_MODE=stall; `devices` answers a keymap line.
cat >"$TMP/bin/hyprctl" <<EOF
#!/bin/bash
echo "\$\$" >>"$TMP/stub.pids"
echo "hyprctl \$*" >>"$TMP/calls.log"
case "\$1" in
  binds)
    [[ \${HYPR_MODE:-} == stall ]] && exec sleep 300
    printf 'bind\n\tmodmask: 64\n\tsubmap: \n\tkey: \n\tkeycode: 38\n\tcatchall: false\n\tdescription: Tripwire workspace one\n\tdispatcher: workspace\n\targ: 1\n'
    ;;
  devices) echo "active keymap: English (US)" ;;
esac
EOF
# xkbcli stub: `compile-keymap` prints a minimal keymap mapping keycode 38 to
# the symbol "a", or stalls when XKB_MODE=stall.
cat >"$TMP/bin/xkbcli" <<EOF
#!/bin/bash
echo "\$\$" >>"$TMP/stub.pids"
echo "xkbcli \$*" >>"$TMP/calls.log"
[[ \${XKB_MODE:-} == stall ]] && exec sleep 300
cat <<'KEYMAP'
xkb_keymap {
xkb_keycodes "evdev" {
  <AC01> = 38;
};
xkb_symbols "pc" {
  key <AC01> { [ a, A ] };
};
};
KEYMAP
EOF
chmod +x "$TMP/bin/hyprctl" "$TMP/bin/xkbcli"

run_menu() { # $1 arm name, $2 watchdog seconds; watchdog-bounded --print run of the REAL script
  local home="$TMP/home-$1" start=$SECONDS rc
  mkdir -p "$home"
  HOME="$home" XDG_CACHE_HOME="$home/.cache" PATH="$TMP/bin:$REPO/bin:$PATH" \
    timeout -k 1 "$2" "$MENU" --print >"$TMP/out-$1" 2>/dev/null
  rc=$?
  echo "$rc $((SECONDS - start))"
}

echo "== control: hyprctl and xkbcli both answer =="
read -r rc t < <(run_menu control 5)
if [[ $rc == 0 ]] && grep -q 'SUPER + A' "$TMP/out-control" && grep -q 'Tripwire workspace one' "$TMP/out-control"; then
  echo "ok: control - menu built in ${t}s with the stubbed bind, keycode 38 resolved to A through the compiled keymap"
else
  echo "FAIL: control - rc=$rc output=[$(tr '\n' '|' <"$TMP/out-control")]"; fail=1
fi
grep -q '^hyprctl binds' "$TMP/calls.log" && grep -q '^xkbcli compile-keymap' "$TMP/calls.log" &&
  echo "ok: control - both external calls were reached (hyprctl binds, xkbcli compile-keymap)" ||
  { echo "FAIL: control - an external call was not reached"; fail=1; }

echo "== stall arm A: hyprctl binds never answers (stalled Hyprland IPC) =="
: >"$TMP/calls.log"
read -r rc t < <(HYPR_MODE=stall run_menu hypr 10)
if [[ $rc == 124 ]]; then
  echo "ok: menu build still blocked in hyprctl binds at the external 10s watchdog (${t}s, rc=124, $(grep -c '^hyprctl binds' "$TMP/calls.log") hyprctl binds call(s) started, none returned)"
else
  echo "FAIL: arm A expected rc=124, got rc=$rc after ${t}s with $(grep -c '^hyprctl binds' "$TMP/calls.log") hyprctl binds call(s) (hyprctl binds bounded?)"; fail=1
fi

echo "== stall arm B: xkbcli compile-keymap never answers (wedged keymap compile) =="
read -r rc t < <(XKB_MODE=stall run_menu xkb 5)
if [[ $rc == 124 ]]; then
  echo "ok: menu build still blocked in xkbcli compile-keymap at the external 5s watchdog (${t}s, rc=124)"
else
  echo "FAIL: arm B expected rc=124, got rc=$rc after ${t}s (xkbcli bounded?)"; fail=1
fi

if (( fail == 0 )); then
  echo "TRIPWIRE GREEN: neither hyprctl binds nor xkbcli compile-keymap carries a deadline - a stalled callee blocks the keybindings menu until killed from outside"
  exit 0
fi
echo "TRIPWIRE RED: a stall arm no longer hangs (or the control broke) - the external calls are bounded or the harness changed"
exit 1
