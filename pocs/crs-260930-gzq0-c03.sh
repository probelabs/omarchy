#!/bin/bash
# PoC for claim CRS-260930-GZQ0/C03 (spec SW-REQ-260912-FAWV)
# Mechanism: the argv budget guard (bin/omarchy-system-sleep-lock:45) matches
# ^[0-9]+$ then evaluates (( budget_ms < 1 )) - but bash arithmetic reads a
# leading zero as OCTAL, so "08"/"09" raise 'value too great for base', the
# guard's compound goes false, the heal never fires, and the script continues
# with the literal token as its budget. The deadline assignment at line 52
# then errors the same way (deadline unset), every lock_ipc fails its
# remaining guard, and the script exits via report_unsecured claiming
# "within 08ms" - with no lock request ever issued. "010" is silently octal 8.
# Both-ways: drives the REAL script with argv 08 and a healthy 5s window;
# asserts no lock attempt plus the nonsense report (exit 0 = defect present).
# A fix that forces 10# evaluation or rejects the token makes the script lock
# (or fail loudly) and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
LOG="$TMP/shell.log"

cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/bash
echo "t 5000000"
EOF
cat > "$TMP/bin/omarchy-shell" <<EOF
#!/bin/bash
echo "omarchy-shell \$*" >> "$LOG"
exit 0
EOF
cat > "$TMP/bin/omarchy-hyprland-monitor-clamshell" <<EOF
#!/bin/bash
exit 0
EOF
cat > "$TMP/bin/omarchy-notification-send" <<EOF
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/"*

OUT="$(PATH="$TMP/bin:$PATH" "$REPO/bin/omarchy-system-sleep-lock" 08 2>"$TMP/err")"
RC=$?

echo "exit=$RC"
echo "shell calls:"; cat "$LOG" 2>/dev/null
echo "stderr: $(cat "$TMP/err")"

if ! grep -q "omarchy-shell .* lock lock" "$LOG" 2>/dev/null && grep -q "within 08ms" "$TMP/err"; then
  echo "SYMPTOM: argv '08' skipped the guard via an octal arithmetic error, voided the deadline, and the script suspended with NO lock request while reporting 'within 08ms' (defect present)"
  exit 0
fi
echo "PASS-REFUTED: leading-zero budget handled as decimal or rejected - defect fixed"
exit 1
