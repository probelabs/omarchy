#!/bin/bash
# PoC for claims CRS-260930-G166/C07 + CRS-260930-G166/C09
# (KI-APPLY-LOCK-EXPORTED-FUNCTIONS-ROOT; spec SW-REQ-260912-EKJP, trusted_path_only).
#
# Mechanism: the EUID==0 branch of bin/omarchy-apply-lock replaces PATH but keeps
# the rest of the inherited environment. Bash imports exported functions
# (BASH_FUNC_grep%%, BASH_FUNC_command_not_found_handle%%, ...) and looks a name
# up as a function before it searches PATH. An imported grep therefore runs in
# place of the pinned grep inside the fingerprint gate, and an imported
# command_not_found_handle that returns 0 makes `if omarchy-shell lock status`
# true when the binary is absent (chroot install).
#
# Method: runs a scratch copy of the REAL helper end to end inside an
# unprivileged user namespace (unshare -r), so EUID is 0 and the helper takes its
# root branch: it pins PATH and as_root runs commands directly. The copy differs
# from bin/omarchy-apply-lock only by retargeted absolute paths (/etc/pam.d/,
# /usr/bin/fprintd-list, /usr/lib/systemd/system-sleep/, /etc/systemd/system/),
# and a reverse substitution must reproduce the product file byte for byte. The
# fprintd-list stub reports a failed probe, records EUID and PATH (proof that the
# root branch ran), and needs no systemd. The hostile functions are exported into
# the helper's environment, exactly as a caller would hand them over.
#
# GREEN TRIPWIRE: exit 0 = caller-supplied functions ran at a decision point of
# the root branch (defect present); exit 1 = neither function ran (fix present);
# exit 2 = the clean-environment control failed or user namespaces are missing.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO/bin/omarchy-apply-lock"
[[ -f $HELPER ]] || { echo "bin/omarchy-apply-lock missing"; exit 2; }
unshare -r true 2>/dev/null || { echo "unprivileged user namespaces unavailable (unshare -r); PoC cannot run"; exit 2; }
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
cleanup() { [[ -n ${TMP:-} && -d $TMP && $(basename "$TMP") == tmp.* ]] && find "$TMP" -depth -delete 2>/dev/null; }
trap cleanup EXIT
mkdir -p "$TMP/pam.d" "$TMP/sleep" "$TMP/units"
MARK="$TMP/HIJACK-MARKER"

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

cat >"$TMP/fprintd-list" <<EOF
#!/bin/bash
echo "euid=\$EUID path=\$PATH" >"$TMP/probe-env"
echo "Fingerprints for user \$1 on Synaptics Sensors (press):"
echo "ListEnrolledFingers failed: GDBus.Error:net.reactivated.Fprint.Error.Internal" >&2
exit 1
EOF
chmod +x "$TMP/fprintd-list"
PINNED=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin:/bin
for d in ${PINNED//:/ }; do
  [[ -x $d/omarchy-shell ]] && { echo "omarchy-shell exists at $d on this host; the absent-binary vector cannot be staged"; exit 2; }
done

run_root() { # $1 = hostile|clean ; output in $TMP/out.$1
  rm -f "$MARK" "$TMP/probe-env"
  if [[ $1 == hostile ]]; then
    # The function bodies carry the marker path literally: the helper gets the
    # functions through its environment, not this script's variables.
    ( eval "grep() { touch '$MARK.grep'; /usr/bin/grep \"\$@\"; }"
      eval "command_not_found_handle() { touch '$MARK.cnfh'; return 0; }"
      export -f grep command_not_found_handle
      OMARCHY_INSTALL_USER=alice OMARCHY_PATH="$REPO" unshare -r "$COPY" >"$TMP/out.$1" 2>&1 )
  else
    OMARCHY_INSTALL_USER=alice OMARCHY_PATH="$REPO" unshare -r "$COPY" >"$TMP/out.$1" 2>&1
  fi
}

# Negative control: a clean environment. The root branch must run (EUID 0 and the
# pinned PATH seen by the probe), no marker may appear, and with omarchy-shell
# absent the helper must not claim "Lock screen authentication configured."
rm -f "$MARK.grep" "$MARK.cnfh"
run_root clean
if grep -q "euid=0 path=$PINNED\$" "$TMP/probe-env" 2>/dev/null && [[ ! -e $MARK.grep && ! -e $MARK.cnfh ]] &&
   ! grep -q "Lock screen authentication configured." "$TMP/out.clean"; then
  echo "control clean-env: root branch ran ($(cat "$TMP/probe-env")), pinned commands only, no false 'configured' claim (intended path intact)"
else
  echo "CONTROL FAILED: clean-environment root run did not behave as intended; PoC inconclusive"
  sed 's/^/    /' "$TMP/out.clean"; cat "$TMP/probe-env" 2>/dev/null
  exit 2
fi

rm -f "$MARK.grep" "$MARK.cnfh"
run_root hostile
V=0
if [[ -e $MARK.grep ]]; then
  echo "vector grep: the imported grep() ran inside the fingerprint gate instead of the pinned grep"; V=1
else
  echo "vector grep: pinned grep used (fix present?)"
fi
if [[ -e $MARK.cnfh ]] && grep -q "Lock screen authentication configured." "$TMP/out.hostile"; then
  echo "vector cnfh: the imported command_not_found_handle ran for the missing omarchy-shell and returned 0 - the helper claimed 'Lock screen authentication configured.' with no shell binary"; V=1
else
  echo "vector cnfh: missing binary failed closed (fix present?)"
fi

if (( V )); then
  echo "SYMPTOM: exported bash functions execute inside the root helper's decision points despite the trusted-PATH replacement (defect present)"
  exit 0
fi
echo "PASS-REFUTED: exported functions no longer execute - defect fixed"
exit 1
