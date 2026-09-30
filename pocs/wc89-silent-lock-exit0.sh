#!/bin/bash
# Green tripwire for the SYS-REQ-260927-WC89 hazard (origin: hazard-analysis batch D).
#
# Mechanism: bin/omarchy-system-lock line 14 runs `omarchy-shell lock lock >/dev/null`
# with no status check and the script carries no `set -e`, so a refused engagement
# (omarchy-shell exits non-zero) or an absent binary (127) is swallowed: the script
# continues through its side-effect steps and exits 0. The menu Lock row
# (default/omarchy/omarchy-menu.jsonc:38) dismisses the menu on activation and only
# the runner's stderr sees the callee, so nothing reaches the user: the session stays
# unlocked while the user believes it locked.
#
# GREEN TRIPWIRE: pins the buggy behavior, so it PASSES while the defect is present.
# Arms 1-2 assert the failure arms still exit 0 (silent success); arm 3 is the
# negative control proving the harness exercises the real invocation wiring.
#
# tripwire_mutation: make bin/omarchy-system-lock propagate the engagement status -
# e.g. replace line 14 with `omarchy-shell lock lock >/dev/null || exit 1` (with the
# user-visible surfacing owned by the lock component, SYS-REQ-260912-T0XP family).
# Arms 1-2 then exit non-zero, the assertions below fail, and the tripwire flips red.
# The control arm is unaffected by that edit.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
LOG="$TMP/shell.log"
fail=0

# Stub every side-effect command the real script may reach after the engagement
# call, so the run is deterministic and touches nothing on this machine.
for cmd in hyprctl pgrep pkill timeout pidwait flock; do
  printf '#!/bin/bash\nexit 0\n' > "$TMP/bin/$cmd"
done
printf '#!/bin/bash\nexit 1\n' > "$TMP/bin/pgrep"   # 1password absent: skip that branch
chmod +x "$TMP/bin/"*

# omarchy-shell stub: logs its argv, exits 0 unless OC_FAIL=1
make_shell() {
  cat > "$TMP/bin/omarchy-shell" <<EOF
#!/bin/bash
echo "argc=\$# args=[\$*]" >> "$LOG"
[[ \${OC_FAIL:-0} == 1 ]] && exit 1
exit 0
EOF
  chmod +x "$TMP/bin/omarchy-shell"
}

check() { # name expected actual
  if [[ $2 == "$3" ]]; then
    echo "ok: $1 (exit $3)"
  else
    echo "FAIL: $1 expected exit $2, got $3"; fail=1
  fi
}

echo "== arm 1: engagement refused (omarchy-shell exits 1) =="
make_shell
: > "$LOG"
export PATH="$TMP/bin:$PATH"
OC_FAIL=1 "$REPO/bin/omarchy-system-lock" >/dev/null 2>&1
check "failed engagement still exits 0 (silent success)" 0 $?

echo "== arm 2: omarchy-shell absent (binary missing after partial sync) =="
rm -f "$TMP/bin/omarchy-shell"
"$REPO/bin/omarchy-system-lock" >/dev/null 2>&1
check "missing lock binary still exits 0 (silent success)" 0 $?

echo "== arm 3: control - healthy engagement =="
make_shell
: > "$LOG"
"$REPO/bin/omarchy-system-lock" >/dev/null 2>&1
check "healthy engagement exits 0" 0 $?
grep -q "argc=2 args=\[lock lock\]" "$LOG" \
  && echo "ok: control - lock verb invoked with exact args" \
  || { echo "FAIL: control - lock verb was not invoked as 'omarchy-shell lock lock'"; fail=1; }

if (( fail == 0 )); then
  echo "TRIPWIRE GREEN: exit 0 on every arm - the callee exit cannot distinguish a locked session from a failed one"
  exit 0
fi
echo "TRIPWIRE RED: failure arms no longer exit 0 - engagement status is surfaced"
exit 1
