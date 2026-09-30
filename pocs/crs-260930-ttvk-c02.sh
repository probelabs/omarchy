#!/bin/bash
# PoC for claim CRS-260930-TTVK/C02 (spec SYS-REQ-260912-T0XP family)
# Mechanism: the lock service's fingerprint probe (embedded bash inside
# shell/plugins/lock/Service.qml, fingerprintCheckProc) is
#   fprintd-list "$USER" 2>/dev/null | grep -qi finger
# fprintd-list's stdout for an empty store is "User NAME has no fingers
# enrolled for ... Fingerprint Sensor" - grep -qi finger matches the
# substring "finger"/"Fingerprint", the probe echoes yes, and
# fingerprintConfigured becomes true: a zero-enrollment user is offered
# fingerprint auth on the lock screen (and on PAM, every attempt fails).
# Both-ways: extracts the probe command VERBATIM from the live Service.qml
# and runs it with a PATH-stubbed fprintd-list that emits the real
# zero-enrollment line. "yes" = defect present (exit 0); a fixed probe
# (enrollment-count anchored, error-exit aware) echoes "no" and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"

# real fprintd-list stdout for an empty fingerprint store
cat > "$TMP/bin/fprintd-list" <<'EOF'
#!/bin/bash
echo "User $(id -un) has no fingers enrolled for Synaptics Fingerprint Sensor."
EOF
chmod +x "$TMP/bin/fprintd-list"

# pull the live probe line out of Service.qml; stand in a stub PAM marker for
# the /etc/pam.d gate (root-only to create for real) and run it
PROBE="$(grep -o 'if \[\[ -f /etc/pam.d/omarchy-lock-fingerprint \]\].*then echo yes; else echo no; fi' \
  "$REPO/shell/plugins/lock/Service.qml" | head -1)"
[[ -n $PROBE ]] || { echo "probe line not found in Service.qml (file changed?)"; exit 2; }
touch "$TMP/omarchy-lock-fingerprint"
PROBE="${PROBE//\/etc\/pam.d\/omarchy-lock-fingerprint/$TMP/omarchy-lock-fingerprint}"

OUT="$(PATH="$TMP/bin:$PATH" bash -c "$PROBE")"
echo "probe said: [$OUT]"

# Negative control (PoC rules 3/10): a genuinely enrolled store reads as
# configured - the intended path the zero-enrollment case abuses.
mkdir -p "$TMP/bin-enrolled"
cat > "$TMP/bin-enrolled/fprintd-list" <<'EOF'
#!/bin/bash
printf 'Fingerprints\n  right-index-finger: LFT\n'
EOF
chmod +x "$TMP/bin-enrolled/fprintd-list"
COUT="$(PATH="$TMP/bin-enrolled:$PATH" bash -c "$PROBE")"
if [[ $COUT == yes ]]; then
  echo "control enrolled: probe reads a genuinely enrolled store as configured (intended path intact)"
else
  echo "CONTROL FAILED: probe refused an enrolled store; PoC cannot distinguish defect from overcorrection"
  exit 2
fi

if [[ $OUT == yes ]]; then
  echo "SYMPTOM: zero-enrollment user treated as fingerprintConfigured=true on the lock screen (defect present)"
  exit 0
elif [[ $OUT == no ]]; then
  echo "PASS-REFUTED: probe requires real enrollment - defect fixed"
  exit 1
else
  echo "UNEXPECTED probe output"; exit 2
fi
