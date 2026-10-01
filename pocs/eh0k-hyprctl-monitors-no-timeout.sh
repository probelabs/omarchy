#!/bin/bash
# Green tripwire for SW-REQ-260912-EH0K external_call_timeout_bounded.
# Reproduces: KI-LOCK-PROBE-HYPRCTL-NO-TIMEOUT
#
# Mechanism: bin/omarchy-hyprland-session-locked runs
#   monitors=$(hyprctl -j monitors 2>/dev/null) || exit 2
# with no timeout wrapper. When the Hyprland IPC socket accepts the request
# but never answers (a stalled compositor), the probe blocks for as long as
# hyprctl does. Its callers (stranded-lock recovery) then wait on a probe that
# never reports locked / unlocked / undetermined.
#
# GREEN TRIPWIRE: pins the buggy behavior, so it PASSES while the defect is
# present. The stall arm asserts the REAL probe is still blocked when an
# external 5s watchdog kills it (rc=124). The control arms prove the harness
# drives the real probe: a healthy hyprctl answer yields exit 0 (LOCK) and
# exit 1 (readable, unlocked) within the same watchdog.
#
# tripwire_mutation: bound the IPC call in bin/omarchy-hyprland-session-locked,
#   monitors=$(timeout 2 hyprctl -j monitors 2>/dev/null) || exit 2
# The stall arm then returns exit 2 (undetermined) after ~2s instead of being
# killed at 5s, the rc=124 assertion fails, and the tripwire flips red. The
# control arms are unaffected.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
PROBE="$REPO/bin/omarchy-hyprland-session-locked"
[[ -x $PROBE ]] || { echo "probe missing: bin/omarchy-hyprland-session-locked"; exit 2; }
command -v jq >/dev/null || { echo "jq required (the probe parses with jq)"; exit 2; }
command -v timeout >/dev/null || { echo "timeout(1) required for the external watchdog"; exit 2; }
TMP="$(mktemp -d)"
cleanup() {
  # Kill any stalled stub the watchdog left behind, then drop the scratch dir.
  if [[ -f $TMP/stub.pids ]]; then
    while read -r pid; do kill -KILL "$pid" 2>/dev/null; done <"$TMP/stub.pids"
  fi
  rm -rf "$TMP"
}
trap cleanup EXIT
mkdir -p "$TMP/bin"
fail=0

# hyprctl stub. HYPR_MODE=stall: accept the request, never answer (a stalled
# IPC). Otherwise print the monitor JSON in HYPR_MONITORS.
cat >"$TMP/bin/hyprctl" <<EOF
#!/bin/bash
echo "\$\$" >>"$TMP/stub.pids"
echo "argv=[\$*]" >>"$TMP/hyprctl.log"
if [[ \${HYPR_MODE:-} == stall ]]; then
  exec sleep 300
fi
printf '%s\n' "\$HYPR_MONITORS"
EOF
chmod +x "$TMP/bin/hyprctl"

run_probe() { # watchdog-bounded run of the REAL probe; echoes rc and elapsed
  local start=$SECONDS rc
  PATH="$TMP/bin:$PATH" timeout -k 1 5 "$PROBE" >/dev/null 2>&1
  rc=$?
  echo "$rc $((SECONDS - start))"
}

check() { # name expected actual
  if [[ $2 == "$3" ]]; then echo "ok: $1 (rc=$3)"; else echo "FAIL: $1 expected rc=$2, got rc=$3"; fail=1; fi
}

echo "== control 1: compositor answers, a monitor holds LOCK =="
read -r rc t < <(HYPR_MONITORS='[{"name":"eDP-1","solitaryBlockedBy":["LOCK"]}]' run_probe)
check "locked session reported as exit 0 within ${t}s" 0 "$rc"
grep -q 'argv=\[-j monitors\]' "$TMP/hyprctl.log" &&
  echo "ok: control - probe invoked 'hyprctl -j monitors'" ||
  { echo "FAIL: control - probe did not invoke 'hyprctl -j monitors'"; fail=1; }

echo "== control 2: compositor answers, readable and unlocked =="
read -r rc t < <(HYPR_MONITORS='[{"name":"eDP-1","solitaryBlockedBy":["CANDIDATE"]}]' run_probe)
check "unlocked session reported as exit 1 within ${t}s" 1 "$rc"

echo "== stall arm: Hyprland IPC accepts the request but never answers =="
read -r rc t < <(HYPR_MODE=stall run_probe)
check "probe still blocked in hyprctl at the external 5s watchdog (${t}s, no internal bound)" 124 "$rc"

if (( fail == 0 )); then
  echo "TRIPWIRE GREEN: the lock-state probe has no deadline on hyprctl -j monitors - a stalled IPC blocks it until killed from outside (controls answer 0/1 normally)"
  exit 0
fi
echo "TRIPWIRE RED: the stall arm no longer hangs (or a control broke) - the hyprctl call is bounded or the harness changed"
exit 1
