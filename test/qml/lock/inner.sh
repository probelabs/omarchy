#!/bin/bash
# Runs inside unshare -Urm: stages the PAM fixtures under suffixed names and
# runs quickshell. The driver swaps fixtures itself via pamSwap() so every
# phase transition lands on a script step instead of a wall-clock race.
# MODE=B/B2: no PAM fixtures at all; B2 keeps LOGNAME for the userName
# binding fallback.
set -u
STAGE=$1
RT=$2
WAY=$3
MODE=$4

extra_env=()
if [[ $MODE == A ]]; then
  mount -t tmpfs tmpfs /etc/pam.d
  printf 'auth required pam_unix.so\naccount required pam_permit.so\npassword required pam_deny.so\nsession required pam_permit.so\n' > "$MCDC_PAM_DIR/omarchy-lock-password-deny"
  printf 'auth sufficient pam_permit.so\naccount sufficient pam_permit.so\npassword sufficient pam_permit.so\nsession sufficient pam_permit.so\n' > "$MCDC_PAM_DIR/omarchy-lock-password-permit"
  printf 'auth required pam_exec.so /bin/sleep 60\naccount required pam_permit.so\nsession required pam_permit.so\n' > "$MCDC_PAM_DIR/omarchy-lock-password-hang"
  printf 'auth required pam_unix.so\naccount required pam_permit.so\nsession required pam_permit.so\n' > "$MCDC_PAM_DIR/omarchy-lock-fingerprint-hang"
  printf 'auth required pam_nosuchmod.so\n' > "$MCDC_PAM_DIR/omarchy-lock-fingerprint-broken"
  # A reader that prompts (pam_echo sends two non-error messages, as
  # pam_fprintd does before and during a scan) and then waits for a finger.
  printf 'auth optional pam_echo.so Place your finger on the fingerprint reader\nauth optional pam_echo.so Place your finger on the fingerprint reader again\nauth required pam_exec.so /bin/sleep 60\naccount required pam_permit.so\nsession required pam_permit.so\n' > "$MCDC_PAM_DIR/omarchy-lock-fingerprint-prompt"
  # A reader that never answers: no message, no result until aborted.
  printf 'auth required pam_exec.so /bin/sleep 60\naccount required pam_permit.so\nsession required pam_permit.so\n' > "$MCDC_PAM_DIR/omarchy-lock-fingerprint-silent"
  # A reader that never prompts: pam_nologin sends an error message and
  # fails the attempt, so it never reaches the device.
  printf 'Fingerprint reader is not available\n' > "$MCDC_PAM_DIR/nologin"
  printf 'auth requisite pam_nologin.so file=%s/nologin\nauth required pam_deny.so\naccount required pam_permit.so\nsession required pam_permit.so\n' "$MCDC_PAM_DIR" > "$MCDC_PAM_DIR/omarchy-lock-fingerprint-nologin"
  extra_env+=(MCDC_PAM_DIR="$MCDC_PAM_DIR")
elif [[ $MODE == B ]]; then
  extra_env+=(USER= LOGNAME=)
elif [[ $MODE == B2 ]]; then
  extra_env+=(USER= LOGNAME=buger)
fi

timeout 220 env \
  QT_QPA_PLATFORM=wayland \
  QT_QUICK_BACKEND=software \
  XDG_RUNTIME_DIR="$RT" \
  WAYLAND_DISPLAY="$WAY" \
  QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
  OMARCHY_PATH=$PWD \
  HOME="$HOME" \
  "${extra_env[@]}" \
  PATH="$PATH" \
  quickshell -n -p "$STAGE"
rc=$?
if (( rc == 124 )); then
  echo "harness: driver (mode $MODE) timed out" >&2
fi
exit $rc
