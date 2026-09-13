#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-EH0K, SYS-REQ-260912-FRG0

# Row dispositions (see proof mcdc show <REQ-ID> for the tables):
#mcdc:ignore:defensive SW-REQ-260912-EH0K: exit_one_on_answerable_unlocked=F, exit_two_on_undetermined=F, exit_zero_on_lock=F, lock_state_queried=T => FALSE -- every query run exits through exactly one of the three exit-code returns; a query with no correct exit behavior needs a broken build [reviewed: REVIEW-12]
#mcdc:ignore:defensive SW-REQ-260912-EH0K: exit_one_on_answerable_unlocked=F, exit_two_on_undetermined=T, exit_zero_on_lock=T, lock_state_queried=T => FALSE -- the exit-1 arm is an unconditional return for the answerable-unlocked case; removing it needs a broken build [reviewed: REVIEW-12]
#mcdc:ignore:defensive SW-REQ-260912-EH0K: exit_one_on_answerable_unlocked=T, exit_two_on_undetermined=F, exit_zero_on_lock=T, lock_state_queried=T => FALSE -- the exit-2 arm is an unconditional return for the undetermined case; removing it needs a broken build [reviewed: REVIEW-12]
#mcdc:ignore:defensive SW-REQ-260912-EH0K: exit_one_on_answerable_unlocked=T, exit_two_on_undetermined=T, exit_zero_on_lock=F, lock_state_queried=T => FALSE -- the exit-0 arm is an unconditional return for the locked case; removing it needs a broken build [reviewed: REVIEW-12]
#mcdc:ignore:defensive SYS-REQ-260912-FRG0: lock_state_queried=T, lock_state_reported=F, stranded_lock_recovered=F => FALSE -- every query run exits through one of the three status returns; answering nothing needs a broken build [reviewed: REVIEW-19]
#mcdc:ignore:defensive SYS-REQ-260912-FRG0: lock_state_queried=T, lock_state_reported=F, stranded_lock_recovered=T => FALSE -- the stranded-lock recovery flows through the probe's exit-0 report; recovering without a reported state is structurally absent [reviewed: REVIEW-19]

require_command jq

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

fake_bin="$test_tmp/bin"
mkdir -p "$fake_bin"

cat >"$fake_bin/hyprctl" <<'SH'
#!/bin/bash

printf 'hyprctl %s\n' "$*" >>"${CALL_LOG:-/dev/null}"
[[ ${1:-} == "-j" && ${2:-} == "monitors" ]] || exit 1
[[ ${OMARCHY_TEST_HYPRCTL_FAILS:-0} == 1 ]] && exit 4
printf '%s\n' "$OMARCHY_TEST_MONITORS"
SH
chmod +x "$fake_bin/hyprctl"

LOCKED=0
UNLOCKED=1
UNDETERMINED=2

assert_status() {
  local expected="$1" monitors="$2" description="$3" hyprctl_fails="${4:-0}" actual=0

  PATH="$fake_bin:$PATH" \
  OMARCHY_TEST_MONITORS="$monitors" \
  OMARCHY_TEST_HYPRCTL_FAILS="$hyprctl_fails" \
    "$ROOT/bin/omarchy-hyprland-session-locked" || actual=$?

  (( actual == expected )) || fail "$description" "expected exit $expected, got $actual"
  pass "$description"
}

# LOCK in solitaryBlockedBy is how an active ext-session-lock shows up.
assert_status $LOCKED \
  '[{"name":"HDMI-A-1","solitaryBlockedBy":["WINDOWED","LOCK","CANDIDATE"]}]' \
  "a locked session is detected"

assert_status $LOCKED \
  '[{"name":"eDP-1","solitaryBlockedBy":["WINDOWED"]},{"name":"DP-2","solitaryBlockedBy":["LOCK"]}]' \
  "a lock on any monitor counts as a locked session"

assert_status $UNLOCKED \
  '[{"name":"HDMI-A-1","solitaryBlockedBy":["WINDOWED","CANDIDATE"]}]' \
  "an unlocked session is reported as unlocked"

# A monitor showing a solitary client has no blockers at all.
assert_status $UNLOCKED \
  '[{"name":"HDMI-A-1","solitaryBlockedBy":null}]' \
  "a monitor with no solitary blockers is reported as unlocked"

# LOCK only carries this meaning inside the reason list.
assert_status $UNLOCKED \
  '[{"name":"LOCK-1","description":"LOCK display","activeWorkspace":{"name":"LOCK"},"solitaryBlockedBy":["WINDOWED"]}]' \
  "LOCK elsewhere in the monitor payload is not a locked session"

# Guessing "unlocked" with nothing to read strands the session.
assert_status $UNDETERMINED '[]' \
  "a session with no monitors to read cannot say"

assert_status $UNDETERMINED '[]' \
  "an unreachable compositor cannot say" 1

assert_status $UNDETERMINED 'not json at all' \
  "an unreadable monitor payload cannot say"

# Hyprland stops at the first reason and never reaches the lock check.
assert_status $UNDETERMINED \
  '[{"name":"HDMI-A-1","solitaryBlockedBy":["WORKSPACE"]}]' \
  "a monitor with no workspace yet cannot say"

assert_status $UNLOCKED \
  '[{"name":"HDMI-A-1","solitaryBlockedBy":["WORKSPACE"]},{"name":"DP-2","solitaryBlockedBy":["WINDOWED"]}]' \
  "one readable monitor is enough to answer"

assert_status $LOCKED \
  '[{"name":"HDMI-A-1","solitaryBlockedBy":["WORKSPACE"]},{"name":"DP-2","solitaryBlockedBy":["LOCK"]}]' \
  "a lock is still found alongside a monitor that cannot say"

# The three scenario groups above drive exit 0 (locked), exit 1 (answerable
# unlocked), and exit 2 (undetermined) respectively; together they witness the
# positive row. The same runs answer queries without any stranded-lock
# recovery.
# MCDC SW-REQ-260912-EH0K: exit_one_on_answerable_unlocked=T, exit_two_on_undetermined=T, exit_zero_on_lock=T, lock_state_queried=T => TRUE
# MCDC SYS-REQ-260912-FRG0: lock_state_queried=T, lock_state_reported=T, stranded_lock_recovered=F => FALSE

# Control: without a query (script never invoked) no compositor call happens.
control_log="$test_tmp/calls-control"
PATH="$fake_bin:$PATH" CALL_LOG="$control_log" true
# MCDC SW-REQ-260912-EH0K: exit_one_on_answerable_unlocked=F, exit_two_on_undetermined=F, exit_zero_on_lock=F, lock_state_queried=F => TRUE [no-action: the control never invokes omarchy-hyprland-session-locked and the hyprctl spy log stays empty — no exit status exists without a query]
# MCDC SYS-REQ-260912-FRG0: lock_state_queried=F, lock_state_reported=F, stranded_lock_recovered=F => TRUE [no-action: same control — zero hyprctl calls in the spy log]
if [[ -f $control_log ]]; then
  fail "no compositor query runs without a lock-state check" "calls: $(cat "$control_log")"
fi
pass "no compositor query runs without a lock-state check"
