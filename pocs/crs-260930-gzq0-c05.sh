#!/bin/bash
# PoC for claim CRS-260930-GZQ0/C05 (spec SW-REQ-260912-FAWV)
# Mechanism: the deadline clock starts only AFTER derive_budget_ms returns
# (bin/omarchy-system-sleep-lock:52), but derive's busctl read is allowed a
# full 1s timeout (line 29). A logind reply that slow consumes exactly the
# 1000ms reserve the derive held back for logind, so on the default 5s window
# the script's inhibitor lifetime reaches ~5.1-5.2s (read 1.1s + wait 4.0s +
# poll overshoot) - the overrun the header calls "the failure this whole path
# exists to prevent".
# Both-ways: drives the REAL script with a busctl stub that burns its whole
# 1s timeout; asserts the script's total lifetime exceeds the 5s logind
# window (exit 0 = defect present). A fix that starts the clock before the
# read (or charges the read to the budget) keeps the lifetime under 5s and
# this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# busctl: reply slowly; logind's real InhibitDelayMaxUSec stays the 5s default
# (the timeout wrapper kills the stub at 1s+0.1s, derive falls back to 5s)
cat > "$TMP/bin/busctl" <<'EOF'
#!/bin/bash
if [[ $1 == get-property ]]; then
  sleep 1.5
  echo "t 5000000"
else
  echo "t 5000000"
fi
EOF
cat > "$TMP/bin/omarchy-shell" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$TMP/bin/omarchy-hyprland-monitor-clamshell" <<'EOF'
#!/bin/bash
exit 0
EOF
cat > "$TMP/bin/omarchy-notification-send" <<'EOF'
#!/bin/bash
exit 0
EOF
chmod +x "$TMP/bin/"*

START=$(date +%s%N)
PATH="$TMP/bin:$PATH" "$REPO/bin/omarchy-system-sleep-lock" >/dev/null 2>"$TMP/err"
RC=$?
END=$(date +%s%N)
WALL_MS=$(( (END - START) / 1000000 ))
echo "exit=$RC wall_ms=$WALL_MS (logind window is 5000ms)"
echo "stderr: $(cat "$TMP/err")"

if (( WALL_MS > 5000 )); then
  echo "SYMPTOM: slow busctl read (1.1s) plus the full 4000ms wait pushed the inhibitor lifetime to ${WALL_MS}ms - past logind's 5000ms window; the reserve held back for logind was consumed by the read (defect present)"
  exit 0
fi
echo "PASS-REFUTED: the read is charged against the budget / clock starts before the read - defect fixed"
exit 1
