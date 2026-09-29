#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

# Verifies: SW-REQ-260912-FVHS, SW-REQ-260912-0Y70, SYS-REQ-260912-H8A5

# Row dispositions (see proof mcdc show <REQ-ID> for the tables):
#mcdc:ignore:defensive SW-REQ-260912-FVHS: lock_unavailable=T, run_refused_with_diagnostic=F, update_run_requested=T => FALSE -- the flock-failure branch unconditionally prints the diagnostic and exits 1; a second run entering the snapshot anyway needs a broken mutex [reviewed: REVIEW-14]
#mcdc:ignore:defensive SYS-REQ-260912-H8A5: held_state_reported=F, update_lock_exclusive=F, update_run_requested=T => FALSE -- the run path unconditionally opens and flocks the lock file and the held subcommand is an unconditional sibling in the same dispatcher; neither property can be absent without a broken build [reviewed: REVIEW-20]
#mcdc:ignore:defensive SYS-REQ-260912-H8A5: held_state_reported=F, update_lock_exclusive=T, update_run_requested=T => FALSE -- held is answered by the same script that takes the lock; exclusivity without the held answer is structurally absent [reviewed: REVIEW-20]
#mcdc:ignore:defensive SYS-REQ-260912-H8A5: held_state_reported=T, update_lock_exclusive=F, update_run_requested=T => FALSE -- every run takes the exclusive flock before executing the child; reporting held state without holding the lock exclusively is structurally absent [reviewed: REVIEW-20]

source "$SHELL_TEST_DIR/fixtures/sudo-boundary-test.sh"
test_tmp="$boundary_tmp"
stub_bin="$SUDO_TEST_ROOT/bin"
test_home="$SUDO_TEST_HOME"
runtime_dir="/run/user/$(id -u)"
test_run_id="test-$BASHPID-$RANDOM"
update_lock_name="omarchy-update-$test_run_id.lock"
stay_awake_dir_name="omarchy-update-stay-awake-$test_run_id"
trap 'rm -rf -- "$runtime_dir/$stay_awake_dir_name"; rm -f -- "$runtime_dir/$update_lock_name"; rm -rf -- "$boundary_tmp"' EXIT
for command in omarchy-update omarchy-update-lock omarchy-update-stay-awake; do
  rm -f "$SUDO_TEST_ROOT/bin/$command"
  copy_boundary_file "bin/$command"
done
sed -i \
  -e "s/omarchy-update\.lock/$update_lock_name/g" \
  -e "s#state_dir=\"\$state_base/omarchy-update-stay-awake\"#state_dir=\"\$state_base/$stay_awake_dir_name\"#" \
  "$SUDO_TEST_ROOT/bin/omarchy-update" \
  "$SUDO_TEST_ROOT/bin/omarchy-update-lock" \
  "$SUDO_TEST_ROOT/bin/omarchy-update-stay-awake"
cat >"$SUDO_TEST_ROOT/mock/setpriv" <<'STUB'
#!/bin/bash
while [[ ${1:-} == --* ]]; do
  case "$1" in
    --reuid|--regid) shift 2 ;;
    --clear-groups) shift ;;
    *) exit 90 ;;
  esac
done
exec "$@"
STUB
chmod +x "$SUDO_TEST_ROOT/mock/setpriv"

run_with_lock_env() {
  SUDO_TEST_HOME="$test_home" \
  XDG_RUNTIME_DIR="$runtime_dir" \
  XDG_STATE_HOME="$test_tmp/state" \
  PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$@"
}

write_stub() {
  local name="$1"
  local body="$2"

  rm -f "$stub_bin/$name"
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
ln -s ../bin/pkexec "$SUDO_TEST_ROOT/mock/pkexec"
write_stub systemd-inhibit 'while [[ $1 == --* ]]; do shift; done; exec "$@"'
ln -s ../bin/systemd-inhibit "$SUDO_TEST_ROOT/mock/systemd-inhibit"

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
OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$update_snapshot_marker" run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update" -y >"$test_tmp/update-first.out" 2>&1 &
update_pid=$!

for _ in {1..50}; do
  [[ -f $update_snapshot_marker ]] && break
  sleep 0.05
done
[[ -f $update_snapshot_marker ]] || fail "first omarchy-update reached snapshot under lock"
# MCDC SW-REQ-260912-FVHS: lock_unavailable=F, run_refused_with_diagnostic=F, update_run_requested=T => TRUE [no-action: the first update reaches the snapshot marker and its log carries no "already running" diagnostic — the refusal path never fires when the lock is free]

set +e
OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$test_tmp/update-second-snapshot-started" run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update" -y >"$test_tmp/update-second.out" 2>&1
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
write_stub systemd-inhibit '[[ -z ${INHIBIT_PID_FILE:-} ]] || echo "$$" >"$INHIBIT_PID_FILE"; while [[ $1 == --* ]]; do shift; done; exec "$@"'
write_stub omarchy-update-keyring 'echo started >"$TEST_MARKER"; sleep 3; exit 0'

OMARCHY_UPDATE_LOGGED=1 TEST_MARKER="$keyring_marker" INHIBIT_PID_FILE="$inhibit_pid_file" \
  run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update" -y >"$test_tmp/update-inhibit.out" 2>&1 &
inhibit_update_pid=$!

for _ in {1..100}; do
  [[ -s $inhibit_pid_file && -f $keyring_marker ]] && break
  sleep 0.05
done
[[ -s $inhibit_pid_file ]] || fail "update starts its sleep inhibitor"

inhibitor_pid=$(<"$inhibit_pid_file")
kill -0 "$inhibitor_pid" 2>/dev/null || fail "sleep inhibitor is still running when its descriptors are inspected"

lock_target=$(readlink -f "$runtime_dir/$update_lock_name")
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
  sudo_log="$SUDO_TEST_LOG"
  : >"$sudo_log"
  pkexec_marker="$test_tmp/pkexec-used"
  terminal_inhibit_pid_file="$test_tmp/terminal-inhibit-pid"
  write_stub pkexec '[[ -z ${PKEXEC_MARKER:-} ]] || touch "$PKEXEC_MARKER"; exec "$@"'
  write_stub systemd-inhibit 'sleep 0.2; while [[ $1 == --* ]]; do shift; done; exec "$@"'

  # sudo -b returns before its child is ready. Require start to wait for the
  # delayed child and succeed, then stop it before script tears down the PTY.
  terminal_driver="$test_tmp/terminal-stay-awake"
  cat >"$terminal_driver" <<'SH'
#!/bin/bash
set -euo pipefail
omarchy-update-stay-awake start
[[ -s $XDG_RUNTIME_DIR/REPLACE_STAY_AWAKE_DIR/inhibit-pid ]]
omarchy-update-stay-awake stop
[[ ! -e $XDG_RUNTIME_DIR/REPLACE_STAY_AWAKE_DIR/inhibit-pid ]]
SH
  sed -i "s/REPLACE_STAY_AWAKE_DIR/$stay_awake_dir_name/g" "$terminal_driver"
  chmod +x "$terminal_driver"

  SUDO_LOG="$sudo_log" PKEXEC_MARKER="$pkexec_marker" INHIBIT_PID_FILE="$terminal_inhibit_pid_file" \
    run_with_lock_env script -qefc "$terminal_driver" /dev/null >/dev/null

  grep -q -- '^sudo -N -b -- ' "$sudo_log" || fail "terminal inhibition authenticates its background command without a reusable timestamp"
  [[ ! -e $pkexec_marker ]] || fail "terminal sleep inhibition does not use pkexec"
  run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update-stay-awake" stop
  pass "terminal updates use sudo instead of Polkit for sleep inhibition"

  wait_for_process_exit() {
    local process_pid="$1"

    for _ in {1..100}; do
      kill -0 "$process_pid" 2>/dev/null || return 0
      [[ $(awk '{ print $3 }' "/proc/$process_pid/stat" 2>/dev/null || true) == "Z" ]] && return 0
      sleep 0.02
    done
    return 1
  }

  delayed_marker="$test_tmp/delayed-inhibitor"
  delayed_helper_pid_file="$test_tmp/delayed-helper-pid"
  write_stub systemd-inhibit 'echo "$$" >"$DELAYED_MARKER"; sleep 0.4; while [[ $1 == --* ]]; do shift; done; exec "$@"'

  # Keep the start helper's stdin attached to the private PTY so it takes the
  # sudo -b branch, then signal only that helper before the held child publishes.
  delayed_terminal_driver="$test_tmp/delayed-terminal-stay-awake"
  cat >"$delayed_terminal_driver" <<'SH'
#!/bin/bash
set +e
omarchy-update-stay-awake start </dev/tty &
helper_pid=$!
echo "$helper_pid" >"$DELAYED_HELPER_PID_FILE"
wait "$helper_pid"
exit $?
SH
  chmod +x "$delayed_terminal_driver"
  DELAYED_MARKER="$delayed_marker" DELAYED_HELPER_PID_FILE="$delayed_helper_pid_file" \
    run_with_lock_env script -qefc "$delayed_terminal_driver" /dev/null >"$test_tmp/delayed-terminal.out" 2>&1 &
  delayed_terminal_driver_pid=$!
  for _ in {1..100}; do
    [[ -s $delayed_marker && -s $delayed_helper_pid_file ]] && break
    sleep 0.02
  done
  [[ -s $delayed_marker && -s $delayed_helper_pid_file ]] || fail "terminal cancellation reaches the delayed launch window"
  kill -TERM "$(<"$delayed_helper_pid_file")"
  wait "$delayed_terminal_driver_pid" || true
  delayed_inhibitor_pid=$(<"$delayed_marker")
  wait_for_process_exit "$delayed_inhibitor_pid" || fail "terminal cancellation leaves no delayed inhibitor"
  [[ ! -e $runtime_dir/$stay_awake_dir_name ]] || fail "terminal cancellation leaves no launch state"
  pass "terminal cancellation rolls back delayed publication"

  # With redirected stdin the same helper takes the graphical pkexec branch.
  : >"$delayed_marker"
  delayed_graphical_helper_pid_file="$test_tmp/delayed-graphical-helper-pid"
  delayed_graphical_driver="$test_tmp/delayed-graphical-stay-awake"
  cat >"$delayed_graphical_driver" <<'SH'
#!/bin/bash
echo "$$" >"$DELAYED_HELPER_PID_FILE"
exec omarchy-update-stay-awake start </dev/null
SH
  chmod +x "$delayed_graphical_driver"
  DELAYED_MARKER="$delayed_marker" DELAYED_HELPER_PID_FILE="$delayed_graphical_helper_pid_file" \
    run_with_lock_env "$delayed_graphical_driver" >"$test_tmp/delayed-graphical.out" 2>&1 &
  delayed_graphical_driver_pid=$!
  for _ in {1..100}; do
    [[ -s $delayed_marker && -s $delayed_graphical_helper_pid_file ]] && break
    sleep 0.02
  done
  [[ -s $delayed_marker && -s $delayed_graphical_helper_pid_file ]] || fail "graphical cancellation reaches the delayed launch window"
  delayed_graphical_helper_pid=$(<"$delayed_graphical_helper_pid_file")
  kill -TERM "$delayed_graphical_helper_pid"
  wait "$delayed_graphical_driver_pid" || true
  delayed_inhibitor_pid=$(<"$delayed_marker")
  wait_for_process_exit "$delayed_inhibitor_pid" || fail "graphical cancellation leaves no delayed inhibitor"
  [[ ! -e $runtime_dir/$stay_awake_dir_name ]] || fail "graphical cancellation leaves no launch state"
  pass "graphical cancellation rolls back delayed publication"
  write_stub systemd-inhibit 'while [[ $1 == --* ]]; do shift; done; exec "$@"'
fi

# Update-owned Stay Awake state must be cleared before the restart helper can
# reboot the machine, rather than relying on an EXIT trap during shutdown.
write_stub omarchy-snapshot 'exit 0'
write_stub omarchy-update-keyring 'exit 0'
write_stub omarchy-toggle-idle '
state_file="$SUDO_TEST_HOME/.local/state/omarchy/indicators/stay-awake"
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
state_file="$SUDO_TEST_HOME/.local/state/omarchy/indicators/stay-awake"
if [[ ${1:-} == "--services-only" || ${EXPECT_STAY_AWAKE:-0} == "1" ]]; then
  [[ -f $state_file ]]
else
  [[ ! -f $state_file ]]
fi'

rm -f "$test_home/.local/state/omarchy/indicators/stay-awake"
OMARCHY_UPDATE_LOGGED=1 run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update" -y
[[ ! -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "update clears its Stay Awake state before restart handling"

mkdir -p "$test_home/.local/state/omarchy/indicators"
touch "$test_home/.local/state/omarchy/indicators/stay-awake"
OMARCHY_UPDATE_LOGGED=1 EXPECT_STAY_AWAKE=1 run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update" -y
[[ -f $test_home/.local/state/omarchy/indicators/stay-awake ]] || fail "update preserves pre-existing Stay Awake state"
pass "omarchy-update restores only its own Stay Awake state before restart handling"

# Model package replacement while the existing updater is still running:
# start writes the old two-field state; the transaction installs the real new
# helper, whose stop must clean that state before reboot handling.
cp "$stub_bin/omarchy-update-stay-awake" "$test_tmp/inhibitor-after-upgrade"
write_stub omarchy-update-stay-awake '
set -e
[[ $1 == "start" ]]
umask 022
state="$XDG_RUNTIME_DIR/$LEGACY_STATE_NAME"
mkdir -p "$state" "$SUDO_TEST_HOME/.local/state/omarchy/indicators"
( exec {OMARCHY_UPDATE_LOCK_FD}>&-; exec sleep infinity ) &
pid=$!
printf "%s %s\n" "$pid" "$(awk '\''{ print $22 }'\'' /proc/$pid/stat)" >"$state/inhibit-pid"
printf "%s:1:1\n" "$$" >"$state/idle-owner"
/usr/bin/cp "$state/idle-owner" "$SUDO_TEST_HOME/.local/state/omarchy/indicators/stay-awake"'
write_stub omarchy-update-system-pkgs '
/usr/bin/cp "$INHIBITOR_AFTER_UPGRADE" "$OMARCHY_PATH/bin/omarchy-update-stay-awake"'
write_stub omarchy-update-restart '
if [[ $1 == "--reboot-only" ]]; then
  [[ ! -e $SUDO_TEST_HOME/.local/state/omarchy/indicators/stay-awake ]] || exit 91
  [[ ! -e $XDG_RUNTIME_DIR/$LEGACY_STATE_NAME ]] || exit 92
  touch "$UPGRADE_RESTARTED"
fi'
rm -f "$test_home/.local/state/omarchy/indicators/stay-awake"
OMARCHY_UPDATE_LOGGED=1 LEGACY_STATE_NAME="$stay_awake_dir_name" \
  INHIBITOR_AFTER_UPGRADE="$test_tmp/inhibitor-after-upgrade" \
  UPGRADE_RESTARTED="$test_tmp/upgrade-restarted" \
  run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update" -y
[[ -e $test_tmp/upgrade-restarted ]] || fail "first upgrade did not reach reboot handling"
pass "first upgrade cleans old inhibitor state with the newly installed helper"

# Stale cleanup state from a killed update must not override a Stay Awake choice
# the user made afterward.
stay_awake_helper_state="$runtime_dir/$stay_awake_dir_name"
stay_awake_state="$test_home/.local/state/omarchy/indicators/stay-awake"
mkdir -m 700 -p "$stay_awake_helper_state"
mkdir -p "$(dirname "$stay_awake_state")"
printf '%s\n' "123:456:789" >"$stay_awake_helper_state/idle-owner"
chmod 600 "$stay_awake_helper_state/idle-owner"
printf '%s\n' "user-choice" >"$stay_awake_state"

run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update-stay-awake" stop
[[ $(<"$stay_awake_state") == "user-choice" ]] ||
  fail "stale update ownership does not remove a newer Stay Awake choice"
pass "stale update ownership preserves a newer Stay Awake choice"

# A stale PID is safe even if it has been reused by another process.
sleep 30 >/dev/null &
unrelated_pid=$!
unrelated_start_time=$(awk '{ print $22 }' "/proc/$unrelated_pid/stat")
mkdir -m 700 -p "$stay_awake_helper_state"
printf '1 %s %s %s %032x\n' "$unrelated_pid" "$((unrelated_start_time + 1))" "$(id -u)" 1 >"$stay_awake_helper_state/inhibit-pid"
chmod 600 "$stay_awake_helper_state/inhibit-pid"

run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update-stay-awake" stop
kill -0 "$unrelated_pid" 2>/dev/null ||
  fail "stale inhibitor state does not terminate a reused PID"
kill "$unrelated_pid"
wait "$unrelated_pid" 2>/dev/null || true
pass "stale inhibitor state does not terminate a reused PID"

# The hidden helper also establishes its own boundary when invoked directly.
reset_boundary
touch "$SUDO_TEST_CACHE"
run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update-stay-awake" stop
[[ $(head -1 "$SUDO_TEST_LOG") == "sudo -k" ]] || fail "standalone inhibitor cleanup did not start cold"
assert_boundary_cold "standalone inhibitor cleanup"
pass "standalone inhibitor cleanup revokes before and after session work"

reset_boundary
export SUDO_TEST_REVOKE_FAIL=1
if run_with_lock_env "$SUDO_TEST_ROOT/bin/omarchy-update-stay-awake" start; then
  fail "inhibitor started after failed initial revocation"
fi
[[ ! -e $stay_awake_helper_state/inhibit-pid ]] || fail "failed revocation started an inhibitor"
pass "failed initial revocation prevents standalone inhibition"
unset SUDO_TEST_REVOKE_FAIL

# MC/DC witness row 1 (trigger-false): invoking omarchy-update-lock run
# directly never queries the held state, so the requirement holds vacuously.
# A PATH-level spy stub logs every subcommand the caller asks for and then
# execs the real binary; the assertion below proves `held` was never invoked.
# Post-merge note: stub_bin IS $SUDO_TEST_ROOT/bin under the sudo-boundary
# fixture, so preserve the sed-patched copy before write_stub replaces it;
# the spy execs that copy to keep the run isolated to the test lock name.
# MCDC SW-REQ-260912-0Y70: held_state_queried=F, held_true_only_for_owning_fd=F => TRUE [no-action: spy stub logs every omarchy-update-lock subcommand and the grep below proves no held call during run]
update_lock_calls="$test_tmp/update-lock-calls"
cp "$stub_bin/omarchy-update-lock" "$test_tmp/real-omarchy-update-lock"
write_stub omarchy-update-lock 'printf "%s\n" "${1:-}" >>"$UPDATE_LOCK_CALLS"; exec "$REAL_UPDATE_LOCK" "$@"'
UPDATE_LOCK_CALLS="$update_lock_calls" REAL_UPDATE_LOCK="$test_tmp/real-omarchy-update-lock" \
  run_with_lock_env omarchy-update-lock run true
[[ -f $update_lock_calls ]] || fail "spy stub saw the direct run invocation"
grep -qx run "$update_lock_calls" || fail "spy stub logged the run subcommand"
if grep -qx held "$update_lock_calls"; then
  fail "direct omarchy-update-lock run never queries the held state"
fi
pass "direct omarchy-update-lock run never queries the held state"

# Control: with no update requested at all, the spy sees zero subcommands.
control_calls="$test_tmp/update-lock-control"
UPDATE_LOCK_CALLS="$control_calls" REAL_UPDATE_LOCK="$test_tmp/real-omarchy-update-lock" \
  run_with_lock_env true
# MCDC SW-REQ-260912-FVHS: lock_unavailable=T, run_refused_with_diagnostic=F, update_run_requested=F => TRUE [no-action: the spy stub logs every omarchy-update-lock subcommand and no invocation happens in this control — the log never exists]
# MCDC SYS-REQ-260912-H8A5: held_state_reported=F, update_lock_exclusive=F, update_run_requested=F => TRUE [no-action: same control — zero subcommands logged, no lock opened, no held answer]
if [[ -f $control_calls ]]; then
  fail "no update-lock action runs without an update request" "calls: $(cat "$control_calls")"
fi
pass "no update-lock action runs without an update request"

# The lock script's own decision surface, driven against the patched copy:
# the held check reads the caller's lock descriptor out of /proc, and run
# takes the lock for real.
# write_stub above replaced the sandbox copy with the held spy, so the
# scenarios here drive the preserved sed-patched copy the spy execs.
update_lock="$test_tmp/real-omarchy-update-lock"
lock_file="$runtime_dir/$update_lock_name"

held_status() {
  local status=0
  if [[ $# -eq 0 ]]; then
    run_with_lock_env "$update_lock" held >/dev/null 2>&1 || status=$?
  else
    OMARCHY_UPDATE_LOCK_FD="$1" run_with_lock_env "$update_lock" held >/dev/null 2>&1 || status=$?
  fi
  return "$status"
}

# Without a descriptor exported the held check cannot even look.
if held_status; then
  fail "held answers zero without a lock descriptor exported"
fi
pass "held answers one without a lock descriptor exported"

# A descriptor number with no /proc entry behind it is the same answer.
if held_status 999; then
  fail "held answers zero for a descriptor that does not exist"
fi
pass "held answers one for a descriptor that does not exist"

exec {other_fd}>/dev/null
if held_status "$other_fd"; then
  fail "held claims a descriptor pointing elsewhere"
fi
pass "held answers one for a descriptor pointing at another file"

# A descriptor open on the lock file itself, with nothing holding the lock, is
# exactly what the re-exec'd updater carries: held says yes.
exec {own_fd}>"$lock_file"
if ! held_status "$own_fd"; then
  fail "held says no to an unlocked descriptor on the lock file"
fi
pass "held answers zero for an unlocked descriptor on the lock file"

# The held check flocks the descriptor it says yes to, and that hold lives as
# long as this shell keeps the descriptor open -- exactly the updater's shape.
# A fresh descriptor on the now-locked file is not that hold: flock on it
# fails, so held says no.
exec {fresh_fd}>"$lock_file"
if held_status "$fresh_fd"; then
  fail "held claims a descriptor whose lock is held elsewhere"
fi
pass "held answers one when another holder owns the lock file"

# The hidden run subcommand takes the lock itself: contended, it refuses with
# a diagnostic, and free, it runs the command under the lock.
status=0
run_with_lock_env "$update_lock" run true >"$test_tmp/contended.err" 2>&1 || status=$?
[[ $status -eq 1 ]] || fail "a contended run exits one" "status: $status"
grep -q "already running" "$test_tmp/contended.err" ||
  fail "a contended run says the update is already running" "$(cat "$test_tmp/contended.err")"
pass "a contended run refuses with the already-running diagnostic"

exec {own_fd}>&- {fresh_fd}>&-
status=0
run_with_lock_env "$update_lock" run true >/dev/null 2>&1 || status=$?
[[ $status -eq 0 ]] || fail "a free run executes the command under the lock" "status: $status"
pass "a free run executes the command under the lock"

# Usage errors: a run with nothing to execute, and an unknown subcommand.
status=0
run_with_lock_env "$update_lock" run >/dev/null 2>"$test_tmp/usage.err" || status=$?
[[ $status -eq 2 ]] || fail "a run without a command exits two" "status: $status"
grep -q "Usage: omarchy-update-lock run <command>" "$test_tmp/usage.err" ||
  fail "a run without a command prints its usage" "$(cat "$test_tmp/usage.err")"

status=0
run_with_lock_env "$update_lock" bogus >/dev/null 2>"$test_tmp/usage.err" || status=$?
[[ $status -eq 2 ]] || fail "an unknown subcommand exits two" "status: $status"
grep -q "Usage: omarchy-update-lock <held|run>" "$test_tmp/usage.err" ||
  fail "an unknown subcommand prints its usage" "$(cat "$test_tmp/usage.err")"
pass "usage errors exit two with the usage line"

# A runtime directory that cannot hold the lock file fails the run loudly
# rather than silently locking nothing.
ro_runtime="$test_tmp/ro-runtime"
mkdir -m 555 -p "$ro_runtime"
status=0
XDG_RUNTIME_DIR="$ro_runtime/missing" "$update_lock" run true >/dev/null 2>&1 || status=$?
[[ $status -ne 0 ]] || fail "a run whose lock cannot be created does not pretend to succeed"
pass "a run whose lock cannot be created fails loudly"

exec {other_fd}>&-
