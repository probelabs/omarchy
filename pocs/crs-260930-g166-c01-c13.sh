#!/bin/bash
# Regression reproducer for claims CRS-260930-G166/C01 + CRS-260930-G166/C13
# (KI-APPLY-LOCK-FPRINT-GATE-FAIL-OPEN; specs SW-REQ-260912-S154, SW-REQ-260912-Y0WT,
# SW-REQ-261004-SP65).
#
# Defect: the fingerprint gate in bin/omarchy-apply-lock decided "enrolled" with
# `fprintd-list "$target_user" 2>/dev/null | grep -qi finger`. fprintd's
# empty-enrollment text ("User alice has no fingers enrolled for ...") contains
# "fingers", and a failed probe that printed a "Fingerprints ..." banner before
# exiting non-zero also passed, because the pipeline status was grep's. Both
# cases installed pam_fprintd for an account with no usable print.
# Upstream omacom/omarchy#7158 (879d6583d, merged 2026-10-04) replaced the gate:
# it installs only on an enrolled "- #N:" row, removes the stack on an explicit
# empty enrollment, and keeps the existing configuration when the probe fails.
#
# Method: runs a scratch copy of the REAL helper end to end, unprivileged. The
# copy differs from bin/omarchy-apply-lock only by retargeted absolute paths
# (/etc/pam.d/, /usr/bin/fprintd-list, /usr/lib/systemd/system-sleep/,
# /etc/systemd/system/), and a reverse substitution must reproduce the product
# file byte for byte. PATH stubs: sudo (runs the command unprivileged, drops
# install's -o/-g root, records systemctl), omarchy-shell (no running shell).
# The fprintd-list stub prints the real daemon output shapes. Each arm starts
# with no fingerprint stack, as on a fresh install.
#
# RED REPRODUCER (asserts the correct behavior): exit 0 = neither fail-open
# input installs the fingerprint stack (fix present); exit 1 = a zero-enrollment
# or failed probe installed it (defect present); exit 2 = the enrolled control
# did not install the stack, so the harness cannot tell a fix from a broken run.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO/bin/omarchy-apply-lock"
[[ -f $HELPER ]] || { echo "bin/omarchy-apply-lock missing"; exit 2; }
(( EUID != 0 )) || { echo "run unprivileged: as root the helper bypasses sudo and resets PATH"; exit 2; }
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
cleanup() { [[ -n ${TMP:-} && -d $TMP && $(basename "$TMP") == tmp.* ]] && find "$TMP" -depth -delete 2>/dev/null; }
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/pam.d" "$TMP/sleep" "$TMP/units"

COPY="$TMP/omarchy-apply-lock"
sed -e "s|/etc/pam\.d/|$TMP/pam.d/|g" -e "s|/usr/bin/fprintd-list|$TMP/fprintd-list|g" \
    -e "s|/usr/lib/systemd/system-sleep/|$TMP/sleep/|g" -e "s|/etc/systemd/system/|$TMP/units/|g" "$HELPER" >"$COPY"
chmod +x "$COPY"
if sed -e "s|$TMP/pam.d/|/etc/pam.d/|g" -e "s|$TMP/fprintd-list|/usr/bin/fprintd-list|g" \
       -e "s|$TMP/sleep/|/usr/lib/systemd/system-sleep/|g" -e "s|$TMP/units/|/etc/systemd/system/|g" "$COPY" | cmp -s - "$HELPER"; then
  echo "ok: scratch copy differs from bin/omarchy-apply-lock only by the retargeted absolute paths"
else
  echo "HARNESS ERROR: retargeted copy differs from the product file beyond the path substitutions"; exit 2
fi

cat >"$TMP/bin/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$TMP/calls.log"
case \$1 in
  systemctl) exit 0 ;;                       # no system manager in the harness
  install)                                   # unprivileged: drop the root owner/group
    args=(); skip=0
    for a in "\${@:2}"; do
      if (( skip )); then skip=0; continue; fi
      case \$a in -o|-g) skip=1 ;; *) args+=("\$a") ;; esac
    done
    exec install "\${args[@]}" ;;
esac
exec "\$@"
EOF
cat >"$TMP/fprintd-list" <<'EOF'
#!/bin/bash
echo "Using device /net/reactivated/Fprint/Device/0"
case "${FPRINTD_CASE:-empty}" in
  empty) echo "User $1 has no fingers enrolled for Synaptics Sensors." ;;
  error) echo "Fingerprints for user $1 on Synaptics Sensors (press):"
         echo "ListEnrolledFingers failed: GDBus.Error:net.reactivated.Fprint.Error.Internal" >&2
         exit 1 ;;
  enrolled) echo "Fingerprints for user $1 on Synaptics Sensors (press):"
            echo " - #0: right-index-finger" ;;
esac
EOF
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/omarchy-shell"
chmod +x "$TMP/bin/sudo" "$TMP/fprintd-list" "$TMP/bin/omarchy-shell"

run_case() { # $1 fprintd case -> echoes installed|absent
  rm -f "$TMP/pam.d/"* "$TMP/sleep/"* 2>/dev/null
  FPRINTD_CASE=$1 OMARCHY_INSTALL_USER=alice OMARCHY_PATH="$REPO" PATH="$TMP/bin:$PATH" \
    "$COPY" >"$TMP/out.$1" 2>&1
  echo "rc=$?" >>"$TMP/out.$1"
  if [[ -f $TMP/pam.d/omarchy-lock-fingerprint ]] && grep -q pam_fprintd "$TMP/pam.d/omarchy-lock-fingerprint"; then
    echo installed
  else
    echo absent
  fi
}

fail=0
r=$(run_case empty)
if [[ $r == installed ]]; then
  echo "case empty-enrollment: fingerprint stack INSTALLED for a user with no prints (defect present)"; fail=1
else
  echo "case empty-enrollment: no fingerprint stack for a user with no prints (fix present)"
fi
r=$(run_case error)
if [[ $r == installed ]]; then
  echo "case daemon-error:     fingerprint stack INSTALLED although the probe failed (defect present)"; fail=1
else
  echo "case daemon-error:     failed probe installed nothing (fix present)"
fi

# Negative control: a genuinely enrolled user gets the stack through the same run.
r=$(run_case enrolled)
if [[ $r == installed ]]; then
  echo "control enrolled: fingerprint stack installed for an enrolled user (intended path intact)"
else
  echo "CONTROL FAILED: enrolled user got no fingerprint stack; harness cannot tell a fix from a broken run"
  sed 's/^/    /' "$TMP/out.enrolled"
  exit 2
fi

if (( fail )); then
  echo "SYMPTOM: the gate installs pam_fprintd for a zero-enrollment or failed fprintd-list probe (defect present)"
  exit 1
fi
echo "PASS: only an enrolled '- #N:' row installs the fingerprint stack; empty and failed probes do not (defect absent)"
exit 0
