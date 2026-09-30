#!/bin/bash
# PoC for claim CRS-260930-GZQ0/C04 (spec SW-REQ-260912-FAWV)
# Mechanism: sync_clamshell (bin/omarchy-system-sleep-lock:97-102) uses a
# fixed 'timeout --kill-after=0.1s 0.4s' bound. The script's own header
# invariant is "Every call below is bounded by what is left of the budget, so
# the deadline enforces itself" - but the clamshell sync never consults
# remaining_ms, so with a small argv budget it runs ~0.5s past a budget it
# should have clamped to, spending the reserve logind needs.
# Both-ways: drives the REAL script with budget 100ms and a clamshell helper
# that sleeps 1s; asserts total wall time >= 0.5s (the fixed bound) instead
# of the 100ms budget (exit 0 = defect present). A fix clamping the clamshell
# timeout to remaining_ms keeps the run under ~0.25s and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/bash
echo "t 5000000"
EOF
cat > "$TMP/bin/omarchy-shell" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$TMP/bin/omarchy-hyprland-monitor-clamshell" <<'EOF'
#!/bin/bash
sleep 1
EOF
cat > "$TMP/bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/"*

START=$(date +%s%N)
PATH="$TMP/bin:$PATH" "$REPO/bin/omarchy-system-sleep-lock" 100 >/dev/null 2>&1
RC=$?
END=$(date +%s%N)
WALL_MS=$(( (END - START) / 1000000 ))
echo "exit=$RC wall_ms=$WALL_MS (budget was 100ms)"

if (( WALL_MS >= 300 )); then
  echo "SYMPTOM: with a 100ms budget the fixed 0.4s clamshell bound ran the script ~${WALL_MS}ms - 4x the budget; the header invariant 'every call bounded by what is left of the budget' is not enforced (defect present)"
  exit 0
fi
echo "PASS-REFUTED: clamshell bound clamped to the remaining budget - defect fixed"
exit 1
