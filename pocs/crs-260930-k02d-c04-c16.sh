#!/bin/bash
# PoC for claims CRS-260930-K02D/C04 + CRS-260930-K02D/C16 (spec SW-REQ-260922-Q6ZS)
# Mechanism: parse_arguments accepts any following word as a geometry value
# (no numeric or known-flag check), then encode_payload's Perl int() silently
# coerces non-integers (int("abc")==0, int("10.9")==10) and a value that is
# itself a flag ("--width --height 400") consumes --height as the width and
# drops the 400 as an unknown token. The summon still runs with corrupted
# geometry and no error.
# Refs: bin/omarchy-menu-select:42 (value assignment), :86 (int() cast).
# Both-ways: runs the REAL script with a stubbed omarchy-shell that captures
# the JSON payload; asserts width=0 from "abc" and --height eaten as a value
# (exit 0 = defect present). With a fix that rejects non-numeric / flag-like
# values, the script errors before summoning and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/omarchy-shell" <<'EOF'
#!/bin/bash
# capture the summon payload (argv[3]) and complete the handshake
printf '%s' "$4" > "${CAPTURE_FILE:?}"
python3 - "$4" <<'PY'
import json, sys
p = json.load(open("/dev/stdin")) if False else json.loads(sys.argv[1])
open(p["selectionFile"], "w").write("alpha")
open(p["doneFile"], "w").write("done")
PY
exit 0
EOF
chmod +x "$TMP/bin/omarchy-shell"

run_case() {
  CAPTURE_FILE="$TMP/payload" PATH="$TMP/bin:$PATH" \
    "$REPO/bin/omarchy-menu-select" "$@" >"$TMP/out" 2>"$TMP/err"
  echo "rc=$?" >"$TMP/rc"
}

echo "== case 1: --width abc =="
run_case Pick one alpha beta -- --width abc
W=$(python3 -c "import json;print(json.load(open('$TMP/payload')).get('width','<absent>'))" 2>/dev/null || echo "unparsable")
echo "summoned width=$W stderr=[$(cat "$TMP/err")]"

echo "== case 2: --width 10.9 =="
run_case Pick one alpha beta -- --width 10.9
W2=$(python3 -c "import json;print(json.load(open('$TMP/payload')).get('width','<absent>'))" 2>/dev/null || echo "unparsable")
echo "summoned width=$W2"

echo "== case 3: --width --height 400 =="
run_case Pick one alpha beta -- --width --height 400
python3 - "$TMP/payload" <<'PY'
import json, sys
p = json.load(open(sys.argv[1]))
print("summoned width=%r maxHeight=%r" % (p.get("width", "<absent>"), p.get("maxHeight", "<absent>")))
PY

fail=0
[[ $W == 0 ]] || { echo "case1: width abc not coerced to 0 (fix present?)"; fail=1; }
[[ $W2 == 10 ]] || { echo "case2: width 10.9 not truncated (fix present?)"; fail=1; }
if [[ $W == 0 && $W2 == 10 ]]; then
  # case 3 must also have silently eaten the flag
  MH=$(python3 -c "import json;print(json.load(open('$TMP/payload')).get('maxHeight','<absent>'))" 2>/dev/null)
  if [[ $MH == "<absent>" ]]; then
    echo "SYMPTOM: non-numeric/flag-like geometry values silently coerced (abc->0, 10.9->10) and a flag-like value swallowed the real --height 400 - all without any error (defect present)"
  else
    echo "PARTIAL: coercion reproduced but case 3 behaved unexpectedly (maxHeight=$MH)"
  fi
fi
exit $fail
