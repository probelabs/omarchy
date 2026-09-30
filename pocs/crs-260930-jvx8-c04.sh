#!/bin/bash
# PoC for claim CRS-260930-JVX8/C04 (spec SW-REQ-260922-0W96)
# Mechanism: dispatch_sendshortcut_binding commits on the down call (line
# 635), ignores the up call's failure (line 637) and returns unconditionally
# (line 638) - so down-accepted + up-refused leaves the synthetic key stuck
# down and skips the sendshortcut fallback (line 641), the exact state the
# clipboard helper's comment says must not happen.
# Both-ways: drives the REAL function with a stubbed dispatch_lua_expression
# outcome split (down ok / up refused); asserts neither the key-up nor the
# fallback chord runs (exit 0 = defect present). With a fix (propagate the up
# failure into the fallback, or send a compensating up), the fallback fires
# and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPT="$REPO/bin/omarchy-menu-keybindings"

FUNCS="$(sed '/^if \[\[ $1 == "--print"/,$d' "$SCRIPT")"
eval "$FUNCS"

HYPRCTL_CALLS=()
hyprctl() {
  HYPRCTL_CALLS+=("$*")
  # every hyprctl call is instrumented but never used for the down path
  return 0
}
DOWN_OK=0; UP_OK=1   # down accepted, up refused
dispatch_lua_expression() {
  if [[ $1 == *"state = \"down\""* ]]; then return $DOWN_OK; fi
  if [[ $1 == *"state = \"up\""* ]]; then return $UP_OK; fi
  return 1
}

dispatch_sendshortcut_binding "SHIFT ALT,L,window:abc"

echo "== calls made =="
printf '%s\n' "${HYPRCTL_CALLS[@]}"

FALLBACK=0
for c in "${HYPRCTL_CALLS[@]}"; do
  [[ $c == *"sendshortcut"* ]] && FALLBACK=1
done

if (( ! FALLBACK )); then
  echo "SYMPTOM: down accepted + up refused -> no key-up retry and sendshortcut fallback skipped; key left stuck down (defect present)"
  exit 0
else
  echo "PASS-REFUTED: fallback chord reached after the refused up - defect fixed"
  exit 1
fi
