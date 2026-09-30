#!/bin/bash
# PoC for claims CRS-260930-G166/C01 + CRS-260930-G166/C13 (spec SW-REQ-260912-S154/Y0WT family)
# Mechanism: the fingerprint gate (bin/omarchy-apply-lock:47-48) greps the
# fprintd-list output for the substring "finger" with stderr discarded and no
# pipefail. Real fprintd empty-enrollment text ("User alice has no fingers
# enrolled ...") contains "fingers" -> the gate takes the ENROLLED branch and
# installs pam_fprintd for a user with zero prints; a daemon error banner
# ("Fingerprints" then non-zero exit) also passes because the pipeline status
# is grep's.
# Both-ways: evals the condition expression extracted VERBATIM from the live
# script (so a fix to line 48 changes what the PoC runs). The stub prints the
# real empty-enrollment text: exit 0 of the condition = defect present. A fix
# that requires actual enrollment (or probe success) makes the condition exit
# non-zero and this PoC exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# Stub standing in for /usr/bin/fprintd-list (the PoC rewrites the absolute
# path inside the extracted expression, nothing else).
cat > "$TMP/fprintd-list" <<'EOF'
#!/bin/bash
case "${FPRINTD_CASE:-empty}" in
  empty) echo "User $1 has no fingers enrolled for Synaptics Mets Sensors." ;;
  error) echo "Fingerprints"; echo "ListEnrolledFingers failed" ; exit 1 ;;
  enrolled) printf 'Fingerprints\n  right-index-finger: LFT\n' ;;
esac
EOF
chmod +x "$TMP/fprintd-list"

# Extract the live condition (lines 47-48), point the absolute path at the stub
COND="$(sed -n '47,48p' "$REPO/bin/omarchy-lock-does-not-exist" 2>/dev/null || sed -n '47,48p' "$REPO/bin/omarchy-apply-lock")"
COND="${COND//#usr#bin#fprintd-list/}"
COND="$(printf '%s\n' "$COND" | sed "s#/usr/bin/fprintd-list#$TMP/fprintd-list#")"
# drop the surrounding if/then so we get the bare condition for eval
COND="${COND#if }"; COND="${COND%; then}"

evaluate() {
  ( target_user="alice"; eval "$COND" )
}

FPRINTD_CASE=empty
if evaluate; then
  echo "case empty-enrollment: gate TRUE -> pam_fprintd installed for a user with no prints"
  C1=0
else
  echo "case empty-enrollment: gate FALSE (fix present?)"
  C1=1
fi

FPRINTD_CASE=error
if evaluate; then
  echo "case daemon-error:   gate TRUE -> pam_fprintd installed despite failed probe (fail-open)"
  C2=0
else
  echo "case daemon-error:   gate FALSE (fix present?)"
  C2=1
fi

# Negative control (PoC rules 3/10): a genuinely enrolled user takes the
# ENROLLED branch - the intended path the two fail-open cases abuse.
FPRINTD_CASE=enrolled
if evaluate; then
  echo "control enrolled: gate TRUE for a genuinely enrolled user (intended path intact)"
else
  echo "CONTROL FAILED: gate refused a genuinely enrolled user; PoC cannot distinguish defect from overcorrection"
  exit 2
fi

if (( C1 == 0 || C2 == 0 )); then
  echo "SYMPTOM: substring grep on fprintd-list output treats not-enrolled / failed probes as enrolled and installs fingerprint PAM (defect present)"
  exit 0
fi
echo "PASS-REFUTED: gate now requires real enrollment under a successful probe - defect fixed"
exit 1
