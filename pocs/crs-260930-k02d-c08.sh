#!/bin/bash
# PoC for claim CRS-260930-K02D/C08 (spec SW-REQ-260922-Q6ZS)
# Mechanism: prepare_handshake_files creates selection_file=$(mktemp) at line
# 72 and done_file=$(mktemp) at line 73, but installs the cleanup EXIT trap
# only at line 75. If the second mktemp fails, set -e exits before the trap
# exists and the first temp file leaks in TMPDIR (0600, private content
# region for the selection).
# Both-ways: stubs mktemp to fail on the second call; asserts the script
# exits non-zero AND a leftover mktemp file remains (exit 0 = defect
# present). With a fix that installs the trap before the first mktemp (or
# cleans up on the failure path), no file remains and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
cat > "$TMP/bin/mktemp" <<EOF
#!/bin/bash
# fail on the second invocation
if [[ -f $TMP/first-done ]]; then
  echo "mktemp: forced failure" >&2
  exit 1
fi
touch "$TMP/first-done"
exec /usr/bin/mktemp "\$@"
EOF
chmod +x "$TMP/bin/mktemp"

TMPDIR="$TMP/home" PATH="$TMP/bin:$PATH" \
  "$REPO/bin/omarchy-menu-select" Pick one alpha beta >/dev/null 2>"$TMP/err"
RC=$?

LEFTOVER=$(find "$TMP/home" -name 'tmp.*' -type f 2>/dev/null | wc -l)

echo "exit=$RC leftover_temp_files=$LEFTOVER stderr=[$(cat "$TMP/err")]"

if (( RC != 0 && LEFTOVER > 0 )); then
  echo "SYMPTOM: script died on the second mktemp and leaked the selection temp file in TMPDIR (defect present)"
  exit 0
elif (( RC != 0 && LEFTOVER == 0 )); then
  echo "PASS-REFUTED: failure path cleaned up the first temp file - defect fixed"
  exit 1
else
  echo "UNEXPECTED: rc=$RC leftover=$LEFTOVER"; exit 2
fi
