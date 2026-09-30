#!/bin/bash
# PoC for claims CRS-260930-G166/C05 + CRS-260930-G166/C06 (spec SW-REQ-260912-EKJP parent family)
# Mechanism: target_user resolution (bin/omarchy-apply-lock:18-22) has no
# pipefail and no abort on a failed getent: when OMARCHY_INSTALL_USER and
# SUDO_USER are unset and PKEXEC_UID maps to nothing (unknown UID, getent
# missing/failing), cut yields the empty string and line 22 falls back to
# $USER - which under pkexec/env -i as root is root. The fingerprint probe
# and both PAM files are then configured for the wrong account.
# Both-ways: evals the resolution block extracted VERBATIM from the live
# script with a failing getent stub; target_user=root = defect present. A fix
# that aborts (or keeps the mapping failure visible) makes the assertions
# fail.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
# getent stub: always fails (unknown uid / missing db)
printf '#!/bin/bash\nexit 2\n' > "$TMP/bin/getent"
chmod +x "$TMP/bin/getent"

BLOCK="$(sed -n '18,22p' "$REPO/bin/omarchy-apply-lock")"

run_block() {
  ( export PATH="$TMP/bin:/usr/bin:/bin"
    unset OMARCHY_INSTALL_USER SUDO_USER
    if [[ $1 == with-pkexec ]]; then export PKEXEC_UID=999999; else unset PKEXEC_UID; fi
    eval "$BLOCK"
    printf '%s' "$target_user" )
}

echo "== case 1: pkexec UID maps to nothing, USER=root =="
T1="$(USER=root run_block with-pkexec 2>/dev/null)"
echo "resolved target_user=[$T1]"

echo "== case 2: no install user, no SUDO_USER, no PKEXEC_UID at all, USER=root =="
T2="$(USER=root run_block 2>/dev/null)"
echo "resolved target_user=[$T2]"

if [[ $T1 == root || $T2 == root ]]; then
  echo "SYMPTOM: failed user mapping silently degrades to root; lock PAM + fingerprint probe configured for the wrong account (defect present)"
  exit 0
fi
echo "PASS-REFUTED: mapping failure no longer degrades to root - defect fixed"
exit 1
