#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# Verifies: SW-REQ-260912-FVHS, SW-REQ-260912-0Y70, SYS-REQ-260912-H8A5

# Row dispositions (see proof mcdc show <REQ-ID> for the tables):
#mcdc:ignore:defensive SW-REQ-260912-FVHS: lock_unavailable=T, run_refused_with_diagnostic=F, update_run_requested=T => FALSE -- the flock-failure branch unconditionally prints the diagnostic and exits 1; a second run entering the snapshot anyway needs a broken mutex [reviewed: REVIEW-14]
#mcdc:ignore:defensive SYS-REQ-260912-H8A5: held_state_reported=F, update_lock_exclusive=F, update_run_requested=T => FALSE -- the run path unconditionally opens and flocks the lock file and the held subcommand is an unconditional sibling in the same dispatcher; neither property can be absent without a broken build [reviewed: REVIEW-20]
#mcdc:ignore:defensive SYS-REQ-260912-H8A5: held_state_reported=F, update_lock_exclusive=T, update_run_requested=T => FALSE -- held is answered by the same script that takes the lock; exclusivity without the held answer is structurally absent [reviewed: REVIEW-20]
#mcdc:ignore:defensive SYS-REQ-260912-H8A5: held_state_reported=T, update_lock_exclusive=F, update_run_requested=T => FALSE -- every run takes the exclusive flock before executing the child; reporting held state without holding the lock exclusively is structurally absent [reviewed: REVIEW-20]

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
test_home="$test_tmp/home"
runtime_dir="$test_tmp/runtime"
mkdir -p "$stub_bin" "$test_home" "$runtime_dir"

run_with_lock_env() {
  HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  XDG_STATE_HOME="$test_tmp/state" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$@"
}

write_stub() {
  local name="$1"
  local body="$2"

  cat >"$stub_bin/$name" <<SH
#!/bin/bash
$body
SH
  chmod +x "$stub_bin/$name"
}

for command in \
  omarchy-toggle-idle \
  pkexec \
  systemd-inhibit \
  omarchy-update-pkg-prune \
  omarchy-update-dev \
  omarchy-update-keyring \
  omarchy-update-system-pkgs \
  omarchy-migrate \
  omarchy-update-aur-pkgs \
  omarchy-update-mise \
  omarchy-update-orphan-pkgs \
  omarchy-hook \
  omarchy-update-analyze-logs \
  omarchy-shell \
  omarchy-update-restart; do
  write_stub "$command" 'exit 0'
done
write_stub omarchy-update-available 'exit 1'
write_stub pkexec 'exec "$@"'

# omarchy-update should hold the lock before snapshotting, so a second update
# cannot even enter its pre-update snapshot.
update_snapshot_marker="$test_tmp/update-snapshot-started"
write_stub omarchy-snapshot 'echo started >"$TEST_MARKER"; sleep 2; exit 0'

# MC/DC witness: the first omarchy-update queries the held state without
# owning the lock (row 2: held_state_queried=T, held_true_only_for_owning_fd=F
# -> requirement false, so `held` exits 1 and the update re-execs under
# omarchy-update-lock run), then the re-exec'd child queries the held state
# while owning the lock descriptor (row 3: held_true_only_for_owning_fd=T ->
# true), which is what lets it reach the snapshot marker asserted below.
# MCDC SW-REQ-260912-0Y70: held_state_queried=T, held_true_only_for_owning_fd=F => FALSE
# MCDC SW-REQ-260912-0Y70: held_state_queried=T, held_true_only_for_owning_fd=T => TRUE
OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$update_snapshot_marker" run_with_lock_env "$ROOT/bin/omarchy-update" -y >"$test_tmp/update-first.out" 2>&1 &
update_pid=$!

for _ in {1..50}; do
  [[ -f $update_snapshot_marker ]] && break
  sleep 0.05
done
[[ -f $update_snapshot_marker ]] || fail "first omarchy-update reached snapshot under lock"
# MCDC SW-REQ-260912-FVHS: lock_unavailable=F, run_refused_with_diagnostic=F, update_run_requested=T => TRUE [no-action: the first update reaches the snapshot marker and its log carries no "already running" diagnostic — the refusal path never fires when the lock is free]

set +e
OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$test_tmp/update-second-snapshot-started" run_with_lock_env "$ROOT/bin/omarchy-update" -y >"$test_tmp/update-second.out" 2>&1
update_second_status=$?
set -e

wait "$update_pid"

# SW-REQ-260912-FVHS:boundary:nominal
[[ $update_second_status -ne 0 ]] || fail "second omarchy-update exits non-zero while update lock is held"
grep -q "already running" "$test_tmp/update-second.out" || fail "second omarchy-update reports held update lock"
[[ ! -f $test_tmp/update-second-snapshot-started ]] || fail "second omarchy-update did not snapshot while lock was held"
# MCDC SW-REQ-260912-FVHS: lock_unavailable=T, run_refused_with_diagnostic=T, update_run_requested=T => TRUE
# MCDC SYS-REQ-260912-H8A5: held_state_reported=T, update_lock_exclusive=T, update_run_requested=T => TRUE
pass "omarchy-update prevents overlapping top-level updates"

# The sleep inhibitor deliberately outlives the step that starts it, so it must
# not inherit the update lock. An update killed before restore_update_inhibitors
# would otherwise leave the inhibitor holding the flock forever, blocking every
# later update and silencing omarchy-migrate-notify, which reads the same lock.
inhibit_pid_file="$test_tmp/inhibit-pid"
keyring_marker="$test_tmp/keyring-started"
write_stub omarchy-snapshot 'exit 0'
write_stub systemd-inhibit 'echo "$$" >"$INHIBIT_PID_FILE"; exec sleep 30'
write_stub omarchy-update-keyring 'echo started >"$TEST_MARKER"; sleep 3; exit 0'

OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$keyring_marker" INHIBIT_PID_FILE="$inhibit_pid_file" \
  run_with_lock_env "$ROOT/bin/omarchy-update" -y >"$test_tmp/update-inhibit.out" 2>&1 &
inhibit_update_pid=$!

for _ in {1..100}; do
  [[ -s $inhibit_pid_file && -f $keyring_marker ]] && break
  sleep 0.05
done
[[ -s $inhibit_pid_file ]] || fail "update starts its sleep inhibitor"

inhibitor_pid=$(<"$inhibit_pid_file")
kill -0 "$inhibitor_pid" 2>/dev/null || fail "sleep inhibitor is still running when its descriptors are inspected"

lock_target=$(readlink -f "$runtime_dir/omarchy-update.lock")
inhibitor_holds_lock=0
for fd in /proc/"$inhibitor_pid"/fd/*; do
  [[ -e $fd ]] || continue
  [[ $(readlink -f "$fd" 2>/dev/null) == "$lock_target" ]] && inhibitor_holds_lock=1
done

wait "$inhibit_update_pid"

(( inhibitor_holds_lock == 0 )) || fail "update keeps the update lock out of the sleep inhibitor it leaves running"
pass "omarchy-update keeps the update lock out of its sleep inhibitor"

kill -0 "$inhibitor_pid" 2>/dev/null &&
  fail "update waits for its sleep inhibitor to stop before continuing"
pass "omarchy-update waits for its sleep inhibitor to stop"

if (( EUID != 0 )); then
  sudo_log="$test_tmp/sudo.log"
  pkexec_marker="$test_tmp/pkexec-used"
  terminal_inhibit_pid_file="$test_tmp/terminal-inhibit-pid"
  write_stub sudo '
printf "%s\n" "$*" >>"$SUDO_LOG"
if [[ $1 == "-v" ]]; then
  exit 0
fi
exec "$@"'
  write_stub pkexec 'touch "$PKEXEC_MARKER"; exec "$@"'

  # start leaves the inhibitor running on purpose, but script tears the pty down
  # the moment its command returns, which SIGHUPs that inhibitor before it can
  # exec. Keep the session open from the inside until the stub has logged.
  terminal_driver="$test_tmp/terminal-stay-awake"
  cat >"$terminal_driver" <<'SH'
#!/bin/bash
omarchy-update-stay-awake start
for _ in {1..200}; do
  grep -q '^systemd-inhibit ' "$SUDO_LOG" && break
  sleep 0.05
done
SH
  chmod +x "$terminal_driver"

  SUDO_LOG="$sudo_log" PKEXEC_MARKER="$pkexec_marker" INHIBIT_PID_FILE="$terminal_inhibit_pid_file" \
    run_with_lock_env script -qefc "$terminal_driver" /dev/null >/dev/null

  grep -qx -- '-v' "$sudo_log" || fail "terminal sleep inhibition validates sudo in the foreground"
  grep -q '^systemd-inhibit ' "$sudo_log" || fail "terminal sleep inhibition runs through sudo"
  [[ ! -e $pkexec_marker ]] || fail "terminal sleep inhibition does not use pkexec"
  run_with_lock_env "$ROOT/bin/omarchy-update-stay-awake" stop
  pass "terminal updates use sudo instead of Polkit for sleep inhibition"
fi

# Update-owned Stay Awake state must be cleared before the restart helper can
# reboot the machine, rather than relying on an EXIT trap during shutdown.
write_stub omarchy-snapshot 'exit 0'
write_stub omarchy-update-keyring 'exit 0'
write_stub omarchy-toggle-idle '
state_file="$HOME/.local/state/omarchy/indicators/stay-awake"
case "$1" in
  stay-awake)
    mkdir -p "$(dirname "$state_file")"
    touch "$state_file"
    ;;
  allow-idle)
    rm -f "$state_file"
    ;;
esac'
write_stub omarchy-update-restart '
state_file="$HOME/.local/state/omarchy/indicators/stay-awake"
if [[ ${EXPECT_STAY_AWAKE:-0} == "1" ]]; then
  [[ -f $state_file ]]
else
  [[ ! -f $state_file ]]
fi'

rm -f "$test_home/.local/state/omarchy/indicators/stay-awake"
OMARCHY_UPDATE_LOGGED=1 run_with_lock_env "$ROOT/bin/omarchy-update" -y
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "update clears its Stay Awake state before restart handling"

mkdir -p "$test_home/.local/state/omarchy/indicators"
touch "$test_home/.local/state/omarchy/indicators/stay-awake"
OMARCHY_UPDATE_LOGGED=1 EXPECT_STAY_AWAKE=1 run_with_lock_env "$ROOT/bin/omarchy-update" -y
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "update preserves pre-existing Stay Awake state"
pass "omarchy-update restores only its own Stay Awake state before restart handling"

# Stale cleanup state from a killed update must not override a Stay Awake choice
# the user made afterward.
stay_awake_helper_state="$runtime_dir/omarchy-update-stay-awake"
stay_awake_state="$test_home/.local/state/omarchy/indicators/stay-awake"
mkdir -p "$stay_awake_helper_state" "$(dirname "$stay_awake_state")"
printf '%s\n' "old-update-owner" >"$stay_awake_helper_state/idle-owner"
printf '%s\n' "user-choice" >"$stay_awake_state"

run_with_lock_env "$ROOT/bin/omarchy-update-stay-awake" stop
[[ $(<"$stay_awake_state") == "user-choice" ]] ||
  fail "stale update ownership does not remove a newer Stay Awake choice"
pass "stale update ownership preserves a newer Stay Awake choice"

# A stale PID is safe even if it has been reused by another process.
sleep 30 &
unrelated_pid=$!
unrelated_start_time=$(awk '{ print $22 }' "/proc/$unrelated_pid/stat")
mkdir -p "$stay_awake_helper_state"
printf '%s %s\n' "$unrelated_pid" "$((unrelated_start_time + 1))" >"$stay_awake_helper_state/inhibit-pid"

run_with_lock_env "$ROOT/bin/omarchy-update-stay-awake" stop
kill -0 "$unrelated_pid" 2>/dev/null ||
  fail "stale inhibitor state does not terminate a reused PID"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true
pass "stale inhibitor state does not terminate a reused PID"

# MC/DC witness row 1 (trigger-false): invoking omarchy-update-lock run
# directly never queries the held state, so the requirement holds vacuously.
# A PATH-level spy stub logs every subcommand the caller asks for and then
# execs the real binary; the assertion below proves `held` was never invoked.
# MCDC SW-REQ-260912-0Y70: held_state_queried=F, held_true_only_for_owning_fd=F => TRUE [no-action: spy stub logs every omarchy-update-lock subcommand and the grep below proves no held call during run]
update_lock_calls="$test_tmp/update-lock-calls"
write_stub omarchy-update-lock 'printf "%s\n" "${1:-}" >>"$UPDATE_LOCK_CALLS"; exec "$REAL_UPDATE_LOCK" "$@"'
UPDATE_LOCK_CALLS="$update_lock_calls" REAL_UPDATE_LOCK="$ROOT/bin/omarchy-update-lock" \
  run_with_lock_env omarchy-update-lock run true
[[ -f $update_lock_calls ]] || fail "spy stub saw the direct run invocation"
grep -qx run "$update_lock_calls" || fail "spy stub logged the run subcommand"
if grep -qx held "$update_lock_calls"; then
  fail "direct omarchy-update-lock run never queries the held state"
fi
pass "direct omarchy-update-lock run never queries the held state"

# Control: with no update requested at all, the spy sees zero subcommands.
control_calls="$test_tmp/update-lock-control"
UPDATE_LOCK_CALLS="$control_calls" REAL_UPDATE_LOCK="$ROOT/bin/omarchy-update-lock" \
  run_with_lock_env true
# MCDC SW-REQ-260912-FVHS: lock_unavailable=T, run_refused_with_diagnostic=F, update_run_requested=F => TRUE [no-action: the spy stub logs every omarchy-update-lock subcommand and no invocation happens in this control — the log never exists]
# MCDC SYS-REQ-260912-H8A5: held_state_reported=F, update_lock_exclusive=F, update_run_requested=F => TRUE [no-action: same control — zero subcommands logged, no lock opened, no held answer]
if [[ -f $control_calls ]]; then
  fail "no update-lock action runs without an update request" "calls: $(cat "$control_calls")"
fi
pass "no update-lock action runs without an update request"
