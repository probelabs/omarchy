#!/bin/bash
# PoC for claims CRS-260930-G166/C05 + CRS-260930-G166/C06
# (KI-APPLY-LOCK-TARGET-USER-DEGRADES-ROOT; spec SW-REQ-260912-EKJP family).
#
# Mechanism: target_user resolution in bin/omarchy-apply-lock has no abort on a
# failed getent. With OMARCHY_INSTALL_USER and SUDO_USER unset and PKEXEC_UID
# mapping to nothing, cut yields the empty string and the helper falls back to
# $USER, which is root under pkexec or env -i. The fprintd enrollment probe then
# asks about root instead of the installing user.
#
# Method: runs a scratch copy of the REAL helper end to end, unprivileged. The
# copy differs from bin/omarchy-apply-lock only by retargeted absolute paths
# (/etc/pam.d/, /usr/bin/fprintd-list, /usr/lib/systemd/system-sleep/,
# /etc/systemd/system/), and a reverse substitution must reproduce the product
# file byte for byte. PATH stubs: getent (always fails, as for an unknown UID),
# sudo (runs the command unprivileged, drops install's -o/-g root, records
# systemctl), omarchy-shell (no running shell). The fprintd-list stub records
# the account it was asked about. The observable is that account.
#
# GREEN TRIPWIRE: exit 0 = an unmappable PKEXEC_UID made the probe ask about
# root (defect present); exit 1 = the helper no longer degrades to root (fix
# present); exit 2 = the control did not resolve the explicit install user.
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

printf '#!/bin/bash\nexit 2\n' >"$TMP/bin/getent"            # unknown UID / failing passwd db
cat >"$TMP/bin/sudo" <<EOF
#!/bin/bash
case \$1 in
  systemctl) exit 0 ;;
  install)
    args=(); skip=0
    for a in "\${@:2}"; do
      if (( skip )); then skip=0; continue; fi
      case \$a in -o|-g) skip=1 ;; *) args+=("\$a") ;; esac
    done
    exec install "\${args[@]}" ;;
esac
exec "\$@"
EOF
cat >"$TMP/fprintd-list" <<EOF
#!/bin/bash
echo "\$1" >>"$TMP/probed"
echo "Using device /net/reactivated/Fprint/Device/0"
if [[ \$1 == alice ]]; then
  echo "Fingerprints for user alice on Synaptics Sensors (press):"
  echo " - #0: right-index-finger"
else
  echo "User \$1 has no fingers enrolled for Synaptics Sensors."
fi
EOF
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/omarchy-shell"
chmod +x "$TMP/bin/getent" "$TMP/bin/sudo" "$TMP/fprintd-list" "$TMP/bin/omarchy-shell"

FP_STACK=$'#%PAM-1.0\nauth       required                    pam_fprintd.so\naccount    include                     system-local-login\n'

run_helper() { # env assignments... ; prints the account the probe asked about
  rm -f "$TMP/probed"
  printf '%s' "$FP_STACK" >"$TMP/pam.d/omarchy-lock-fingerprint"   # alice's working setup
  env -u OMARCHY_INSTALL_USER -u SUDO_USER -u PKEXEC_UID "$@" OMARCHY_PATH="$REPO" PATH="$TMP/bin:$PATH" \
    "$COPY" >/dev/null 2>&1
  head -1 "$TMP/probed" 2>/dev/null
}

echo "== case: pkexec UID maps to nothing, USER=root (alice installs, alice has a print) =="
T1=$(run_helper PKEXEC_UID=999999 USER=root)
echo "fingerprint probe asked about: [$T1]"
if [[ -f $TMP/pam.d/omarchy-lock-fingerprint ]]; then
  echo "    consequence: alice's fingerprint stack is still present"
else
  echo "    consequence: alice's fingerprint stack was removed (root has no prints)"
fi

echo "== control: an explicit OMARCHY_INSTALL_USER resolves to the installing user =="
T3=$(run_helper OMARCHY_INSTALL_USER=alice PKEXEC_UID=999999 USER=root)
echo "fingerprint probe asked about: [$T3]"
if [[ $T3 == alice ]]; then
  echo "control ok: explicit install user wins (intended mapping path intact)"
else
  echo "CONTROL FAILED: explicit OMARCHY_INSTALL_USER did not reach the probe; PoC cannot distinguish defect from broken mapping"
  exit 2
fi

if [[ $T1 == root ]]; then
  echo "SYMPTOM: an unmappable PKEXEC_UID silently degrades target_user to root; the fingerprint probe asks about the wrong account (defect present)"
  exit 0
fi
echo "PASS-REFUTED: mapping failure no longer degrades to root - defect fixed"
exit 1
