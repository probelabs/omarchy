#!/bin/bash
# Green tripwire for the SYS-REQ-260927-WC89 hazard (origin: hazard-analysis batch D).
#
# Mechanism: bin/omarchy-system-lock runs `omarchy-shell lock lock >/dev/null` with no
# status check and the script carries no `set -e`. The shell answers a refused lock on
# stdout with exit 0 (Service.qml lock(): "ok" | "missing-pam" | "failed"), a stopped
# shell makes omarchy-shell exit 1, and an absent binary exits 127. All three are
# swallowed: the script continues through its side-effect steps and exits 0. The menu
# Lock row (default/omarchy/omarchy-menu.jsonc:38) dismisses the menu on activation and
# only the runner's stderr sees the callee, so nothing reaches the user: the session
# stays unlocked while the user believes it locked.
#
# GREEN TRIPWIRE: pins the buggy behavior, so it PASSES (exit 0) while the defect is
# present. Arms 1-3 assert the failure arms still exit 0 (silent success). Arm 4 is the
# negative control: a healthy shell that answers "ok" to `lock lock` and reports
# {"requested":true,"secure":true} to `lock status`, as the real shell does once the
# session is locked. A correct fix keeps the control at exit 0, so the tripwire flips
# red (exit 1) only through the failure arms. If the control itself breaks, the harness
# is not exercising the real wiring and the script exits 2 (neither green nor red).
#
# The omarchy-shell stub answers at the wrapper's interface the way bin/omarchy-shell
# and the lock plugin's IPC do: `lock lock` prints the lock() reply with exit 0;
# `lock status` prints the status() JSON (only the fields the scripts read); a stopped
# shell prints "omarchy-shell is not running" to stderr and exits 1.
#
# tripwire_mutation: make bin/omarchy-system-lock propagate the engagement status -
# e.g. replace the call with `omarchy-shell lock lock >/dev/null || exit 1` (with the
# user-visible surfacing owned by the lock component, SYS-REQ-260912-T0XP family).
# Arms 2-3 then exit non-zero, the assertions below fail, and the tripwire flips red.
# The control arm is unaffected by that edit.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/state"
LOG="$TMP/shell.log"
fail=0

# Stub every side-effect command the real script may reach after the engagement
# call, so the run is deterministic and touches nothing on this machine.
for cmd in hyprctl pkill timeout pidwait flock omarchy-notification-send omarchy-cmd-present; do
  printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/$cmd"
done
printf '#!/bin/bash\nexit 1\n' > "$TMP/bin/pgrep"   # 1password absent: skip that branch
chmod +x "$TMP/bin/"*

# omarchy-shell stub: logs its argv; OC_MODE selects the shell's behaviour:
#   ok (default) - `lock lock` answers ok and the session becomes secure
#   refused      - `lock lock` answers missing-pam (the real refusal shape), nothing locks
#   stopped      - the shell is not running: stderr message, exit 1
make_shell() {
  cat > "$TMP/bin/omarchy-shell" <<EOF
#!/bin/bash
echo "argc=\$# args=[\$*]" >> "$LOG"
case \${OC_MODE:-ok} in
  stopped) echo "omarchy-shell is not running" >&2; exit 1 ;;
esac
if [[ "\$1 \$2" == "lock lock" ]]; then
  if [[ \${OC_MODE:-ok} == refused ]]; then echo missing-pam; exit 0; fi
  : > "$TMP/state/requested"
  echo ok; exit 0
fi
if [[ "\$1 \$2" == "lock status" ]]; then
  if [[ -f "$TMP/state/requested" ]]; then
    printf '{"locked":true,"requested":true,"pending":false,"sessionLocked":true,"secure":true,"passwordPam":true}\n'
  else
    printf '{"locked":false,"requested":false,"pending":false,"sessionLocked":false,"secure":false,"passwordPam":true}\n'
  fi
  exit 0
fi
exit 0
EOF
  chmod +x "$TMP/bin/omarchy-shell"
  rm -f "$TMP/state/requested"
  : > "$LOG"
}

check() { # name expected actual
  if [[ $2 == "$3" ]]; then
    echo "ok: $1 (exit $3)"
  else
    echo "FAIL: $1 expected exit $2, got $3"; fail=1
  fi
}

export PATH="$TMP/bin:$PATH"

echo "== arm 1: engagement refused (the shell answers missing-pam, exit 0) =="
make_shell
OC_MODE=refused "$REPO/bin/omarchy-system-lock" >/dev/null 2>&1
check "refused engagement still exits 0 (silent success)" 0 $?

echo "== arm 2: shell not running (omarchy-shell exits 1) =="
make_shell
OC_MODE=stopped "$REPO/bin/omarchy-system-lock" >/dev/null 2>&1
check "failed engagement still exits 0 (silent success)" 0 $?

echo "== arm 3: omarchy-shell absent (binary missing after partial sync) =="
rm -f "$TMP/bin/omarchy-shell"
"$REPO/bin/omarchy-system-lock" >/dev/null 2>&1
check "missing lock binary still exits 0 (silent success)" 0 $?

echo "== arm 4: control - healthy engagement (ok, then secure) =="
make_shell
OC_MODE=ok "$REPO/bin/omarchy-system-lock" >/dev/null 2>&1
rc=$?
control=0
if [[ $rc == 0 ]]; then echo "ok: healthy engagement exits 0 (exit 0)"; else echo "CONTROL FAIL: healthy engagement expected exit 0, got $rc"; control=1; fi
grep -q "argc=2 args=\[lock lock\]" "$LOG" \
  && echo "ok: control - lock verb invoked with exact args" \
  || { echo "CONTROL FAIL: lock verb was not invoked as 'omarchy-shell lock lock'"; control=1; }

if (( control )); then
  echo "HARNESS BROKEN: the healthy control did not lock cleanly - the result says nothing about the defect"
  exit 2
fi
if (( fail == 0 )); then
  echo "TRIPWIRE GREEN: exit 0 on every arm - the callee exit cannot distinguish a locked session from a failed one"
  exit 0
fi
echo "TRIPWIRE RED: failure arms no longer exit 0 - engagement status is surfaced"
exit 1
