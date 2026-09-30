#!/bin/bash
# PoC for claims CRS-260930-GZQ0/C01 + C02 + C10 (spec SW-REQ-260912-FAWV)
# Mechanism: derive_budget_ms (bin/omarchy-system-sleep-lock:26-42) reserves
# max(window/5, 1000ms) with no floor, so a logind window of 1s yields budget
# 0 and any sub-second window yields a NEGATIVE budget. The line-45 heal
# guard re-derives instead of flooring, so it repeats the identical busctl
# read and reinstalls the same illegal value (C02). With budget <= 0 the
# deadline is already past: every lock_ipc hits the remaining<=0 guard and
# returns 1 with empty stdout, request_lock's case silently falls through,
# and the suspend proceeds with the lock never attempted (C10).
# Both-ways: drives the REAL script with stubbed externals; asserts the lock
# was never attempted and the report shows the degenerate budget (exit 0 =
# defect present). A floor fix (budget >= 1ms) makes the script attempt the
# lock and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
LOG="$TMP/shell.log"

# logind window: 1s (InhibitDelayMaxUSec=1000000)
cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/bash
echo "t 1000000"
EOF
# omarchy-shell: log every call, answer select/lock/status with no data
cat > "$TMP/bin/omarchy-shell" <<EOF
#!/bin/bash
echo "omarchy-shell \$*" >> "$LOG"
exit 0
EOF
cat > "$TMP/bin/omarchy-hyprland-monitor-clamshell" <<EOF
#!/bin/bash
echo clamshell >> "$LOG"
exit 0
EOF
cat > "$TMP/bin/omarchy-notification-send" <<EOF
#!/bin/bash
echo notify >> "$LOG"
exit 0
EOF
chmod +x "$TMP/bin/"*

OUT="$(PATH="$TMP/bin:$PATH" "$REPO/bin/omarchy-system-sleep-lock" 2>"$TMP/err")"
RC=$?

LOCKS=$(grep -c "lock lock" "$LOG" 2>/dev/null || true)
BUSCTL=$(grep -c busctl <(PATH="$TMP/bin:$PATH" true) 2>/dev/null || true)
echo "exit=$RC"
echo "shell call log:"; cat "$LOG" 2>/dev/null
echo "stderr: $(cat "$TMP/err")"

fail=0
if grep -qE "within (-?[0-9]*0|0)ms" "$TMP/err" && ! grep -q "^omarchy-shell .* lock lock" "$LOG" 2>/dev/null; then
  echo "SYMPTOM: 1s logind window -> degenerate budget carried past the heal guard (identical re-derive), lock_ipc refused silently and the lock was NEVER attempted before suspend (defect present)"
else
  echo "PASS-REFUTED: budget floored and the lock was attempted - defect fixed"
  fail=1
fi
exit $fail
