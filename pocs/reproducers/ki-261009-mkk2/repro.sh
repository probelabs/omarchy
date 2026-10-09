#!/bin/bash
# Reproduces: KI-261009-MKK2
# Lock the shell lock with two virtual keyboards attached, type on one,
# remove the other, then type again on the one that stayed.
# Correct behaviour: the second character reaches the password field.
# The defect: the field keeps only the first character.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
PROOF_ENV_DIR="${PROOF_ENV_DIR:-$HOME/proof-env}"
export PATH="$PATH:$PROOF_ENV_DIR/bin"

STAGE=$(mktemp -d /tmp/ki-261009-mkk2-stage.XXXXXX)
RT=$(mktemp -d /tmp/ki-261009-mkk2-rt.XXXXXX)
chmod 700 "$RT"
SWAY_PID=""
QS_PID=""
DROP_PID=""
HOLD_PID=""

cleanup() {
  if [[ -n $HOLD_PID ]]; then kill "$HOLD_PID" 2>/dev/null || true; fi
  if [[ -n $DROP_PID ]]; then kill "$DROP_PID" 2>/dev/null || true; fi
  if [[ -n $QS_PID ]]; then kill "$QS_PID" 2>/dev/null || true; fi
  if [[ -n $SWAY_PID ]]; then kill "$SWAY_PID" 2>/dev/null || true; fi
  rm -rf "$STAGE" "$RT"
}
trap cleanup EXIT

setup_fail() {
  echo "SETUP: $*"
  exit 2
}

command -v wtype >/dev/null || setup_fail "wtype not on PATH"
command -v quickshell >/dev/null || setup_fail "quickshell not on PATH"
command -v unshare >/dev/null || setup_fail "unshare not on PATH"

SWAY_BIN=${PROOF_ENV_DIR}/sysroot/usr/bin/sway
SWAY_LIB=${PROOF_ENV_DIR}/sysroot/usr/lib
if [[ ! -x $SWAY_BIN ]]; then
  SWAY_BIN=$(command -v sway || true)
  SWAY_LIB=""
fi
[[ -n $SWAY_BIN ]] || setup_fail "sway not found"
[[ -f $ROOT/shell/plugins/lock/Service.qml ]] || setup_fail "lock service missing"
[[ -f $ROOT/test/qml/lock/sway-headless.conf ]] || setup_fail "sway headless config missing"

mkdir -p "$STAGE"
cp -a "$ROOT/shell/Commons" "$ROOT/shell/Ui" "$ROOT/shell/plugins" "$STAGE/"
cp "$ROOT/pocs/reproducers/ki-261009-mkk2/driver.qml" "$STAGE/shell.qml"

env -i \
  LD_LIBRARY_PATH="$SWAY_LIB" \
  XDG_RUNTIME_DIR="$RT" \
  HOME="$HOME" \
  WLR_BACKENDS=headless \
  WLR_RENDERER=pixman \
  WLR_LIBINPUT_NO_DEVICES=1 \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/bin:/bin" \
  "$SWAY_BIN" -c "$ROOT/test/qml/lock/sway-headless.conf" >"$RT/sway.log" 2>&1 &
SWAY_PID=$!

WAY=""
for ((i = 0; i < 100; i++)); do
  WAY=$(cd "$RT" && ls wayland-* 2>/dev/null | grep -v '\.lock$' | head -1 || true)
  if [[ -n $WAY ]]; then break; fi
  if ! kill -0 "$SWAY_PID" 2>/dev/null; then break; fi
  sleep 0.2
done
[[ -n $WAY ]] || setup_fail "private sway did not start: $(tail -n 15 "$RT/sway.log" 2>/dev/null || true)"
echo "sway display=$WAY"

mkdir -p "$RT/pam.d"
printf 'auth required pam_deny.so\naccount required pam_permit.so\npassword required pam_deny.so\nsession required pam_permit.so\n' >"$RT/pam.d/omarchy-lock-password"

unshare -Urm bash -c "
  set -u
  mount -t tmpfs tmpfs /etc/pam.d
  cp '$RT/pam.d/omarchy-lock-password' /etc/pam.d/omarchy-lock-password
  exec timeout 40 env \
    QT_QPA_PLATFORM=wayland \
    QT_QUICK_BACKEND=software \
    XDG_RUNTIME_DIR='$RT' \
    WAYLAND_DISPLAY='$WAY' \
    QT_WAYLAND_DISABLE_WINDOWDECORATION=1 \
    HOME='$HOME' \
    USER='${USER:-buger}' \
    LOGNAME='${USER:-buger}' \
    PATH='$PATH' \
    quickshell -n -p '$STAGE'
" >"$RT/qs.log" 2>&1 &
QS_PID=$!

for ((i = 0; i < 80; i++)); do
  if grep -q 'event=secure=true' "$RT/qs.log" 2>/dev/null; then break; fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    setup_fail "quickshell exited before the lock was secure: $(tail -n 30 "$RT/qs.log")"
  fi
  sleep 0.25
done
grep -q 'event=secure=true' "$RT/qs.log" || setup_fail "lock did not become secure"
echo "lock secure"

# DROP is removed after the first character. HOLD types y while both exist,
# waits, then types x on the keyboard that stayed.
WAYLAND_DISPLAY="$WAY" XDG_RUNTIME_DIR="$RT" wtype -s 30000 >/dev/null 2>&1 &
DROP_PID=$!
WAYLAND_DISPLAY="$WAY" XDG_RUNTIME_DIR="$RT" wtype -s 2000 y -s 12000 x >"$RT/hold.log" 2>&1 &
HOLD_PID=$!
echo "keyboards drop=$DROP_PID hold=$HOLD_PID"

last_pw() {
  grep -o 'pw="[^"]*"' "$RT/qs.log" | tail -1 || true
}

seen_y=""
for ((i = 0; i < 48; i++)); do
  if [[ $(last_pw) == 'pw="y"' ]]; then seen_y=1; break; fi
  sleep 0.25
done
[[ -n $seen_y ]] || setup_fail "first key never reached the password field (last $(last_pw))"
echo "before removal password=$(last_pw)"

kill -0 "$DROP_PID" 2>/dev/null || setup_fail "the keyboard to remove was already gone"
kill "$DROP_PID" 2>/dev/null || true
wait "$DROP_PID" 2>/dev/null || true
DROP_PID=""
echo "removed one keyboard; remaining keyboard still held by $HOLD_PID"

seen_x=""
for ((i = 0; i < 60; i++)); do
  if [[ $(last_pw) == 'pw="yx"' ]]; then seen_x=1; break; fi
  sleep 0.25
done

echo "after removal password=$(last_pw)"
if [[ -n $seen_x ]]; then
  echo "PROOF-REPRODUCER: defect-absent KI-261009-MKK2"
  exit 0
fi
if [[ $(last_pw) == 'pw="y"' ]]; then
  echo "PROOF-REPRODUCER: defect-present KI-261009-MKK2"
  exit 1
fi
setup_fail "password field was neither y nor yx after removal (last $(last_pw))"
