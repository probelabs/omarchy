#!/bin/bash
# PoC for claim CRS-260930-GZQ0/C06 (spec SW-REQ-260912-H2YF)
# Mechanism: report_unsecured's notification send (bin/omarchy-system-sleep-lock:109-111)
# has no timeout wrapper - '|| true' only covers a non-zero exit. The
# underlying omarchy-notification-send busctl Notify call carries no
# --timeout, so the sd-bus default (~25s) applies. Against a stuck
# notification bus the unlocked-suspend warning the requirement promises may
# never be submitted, and the script lingers holding the delay inhibitor.
# Both-ways: drives the REAL script into the report path (missing-pam) with a
# notification-send stub that stalls 3s; asserts the run took >= 2.5s (the
# unbounded send - exit 0 = defect present). A fix wrapping the send in a
# short timeout keeps the run under ~1s and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/bash
echo "t 5000000"
EOF
# omarchy-shell lock: reply "missing-pam" on stdout -> report path
cat > "$TMP/bin/omarchy-shell" <<'EOF'
#!/bin/bash
if [[ $2 == lock && $3 == lock ]]; then
  echo "missing-pam"
fi
exit 0
EOF
cat > "$TMP/bin/omarchy-hyprland-monitor-clamshell" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$TMP/bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
# a stalled notification bus (the real send has no --timeout, so nothing
# bounds this wait at the script level)
sleep 3
exit 0
EOF
chmod +x "$TMP/bin/"*

START=$(date +%s%N)
PATH="$TMP/bin:$PATH" "$REPO/bin/omarchy-system-sleep-lock" 200 >/dev/null 2>"$TMP/err"
RC=$?
END=$(date +%s%N)
WALL_MS=$(( (END - START) / 1000000 ))
echo "exit=$RC wall_ms=$WALL_MS (budget 200ms)"
echo "stderr: $(cat "$TMP/err")"

if (( WALL_MS >= 2500 )); then
  echo "SYMPTOM: the unlocked-suspend notification send stalled ${WALL_MS}ms against a 200ms budget - unbounded send on the report path (defect present)"
  exit 0
fi
echo "PASS-REFUTED: notification send is timeout-bounded - defect fixed"
exit 1
