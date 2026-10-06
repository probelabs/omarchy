#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP, SYS-REQ-260927-WC89

# Row dispositions (see proof mcdc show <REQ-ID> for the tables):
#mcdc:ignore:defensive SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=T => FALSE -- the lock path runs pkill -x ttfx and timeout 1s pidwait as unconditional sequence points; a run that reaches the path always attempts the signal and always waits bounded, so neither-fails is structural [reviewed: REVIEW-1]
#mcdc:ignore:defensive SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=T, ttfx_wait_bounded=F, user_lock_requested=T => FALSE -- the only wait is `timeout 1s pidwait`; there is no unbounded wait path in the file [reviewed: REVIEW-1]
#mcdc:ignore:defensive SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=F, session_lock_engaged=F, user_lock_requested=T => FALSE -- omarchy-system-lock unconditionally attempts the lock, the layout reset, and the screensaver stop in sequence; an all-three-failed run requires a broken build, not a reachable input [reviewed: REVIEW-16]


require_command jq

# Resolved before the mocks shadow it: the harness bounds the script with the
# real timeout, while the script under test sees the mock.
real_timeout=$(command -v timeout)

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

for command in hyprctl pkill timeout omarchy-notification-send; do
  cat >"$mock_bin/$command" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
MOCK
done

# Answers `lock status` the way the shell does. SECURE_AFTER is how many polls
# it takes to secure, so a lock that is still arming can be told apart from one
# that never will.
cat >"$mock_bin/omarchy-shell" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"

if [[ ${1:-} == "lock" && ${2:-} == "status" ]]; then
  polls=$(( $(cat "$POLL_COUNT" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$polls" >"$POLL_COUNT"
  if [[ ${SECURE_AFTER:-1} != never ]] && (( polls >= ${SECURE_AFTER:-1} )); then
    printf '{"secure":true,"requested":true}\n'
  else
    printf '{"secure":false,"requested":false}\n'
  fi
  exit 0
fi

if [[ ${1:-} == "lock" && ${2:-} == "lock" ]]; then
  [[ -n ${LOCK_REPLY:-} ]] && printf '%s\n' "$LOCK_REPLY"
  exit 0
fi
MOCK

cat >"$mock_bin/pgrep" <<'MOCK'
#!/bin/bash
exit 1
MOCK
chmod +x "$mock_bin"/*

# Verifies: SYS-REQ-260912-T0XP, SYS-REQ-260927-WC89 — runs the real script against the shell mock, bounded
run_lock() {
  local rc=0
  : >"$call_log"
  : >"$tmpdir/polls"
  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" POLL_COUNT="$tmpdir/polls" \
    SECURE_AFTER="${SECURE_AFTER:-1}" LOCK_REPLY="${LOCK_REPLY:-}" \
    "$real_timeout" -k 5s 40s "$ROOT/bin/omarchy-system-lock" 2>"$tmpdir/stderr" || rc=$?
  return "$rc"
}

rc=0
run_lock || rc=$?
# SYS-REQ-260927-WC89:error_handling:nominal
(( rc == 0 )) || fail "system lock succeeds once the session is secure" "exit $rc, $(<"$tmpdir/stderr")"
pass "system lock succeeds once the session is secure"

mapfile -t shutdown < <(rg '^(pkill|timeout) ' "$call_log")
[[ ${shutdown[0]} == "pkill -x ttfx" ]] ||
  fail "system lock stops ttfx before closing its terminal" "calls: ${shutdown[*]}"
[[ ${shutdown[1]} == "timeout 1s pidwait -x ttfx" ]] ||
  fail "system lock waits for ttfx to exit" "calls: ${shutdown[*]}"
[[ ${shutdown[2]} == "pkill -f [o]rg.omarchy.screensaver" ]] ||
  fail "system lock closes the screensaver terminal after ttfx exits" "calls: ${shutdown[*]}"
# SW-REQ-260912-MXQG:error_handling:nominal
# SYS-REQ-260912-T0XP:nominal:nominal
grep -q '^omarchy-shell lock lock$' "$call_log" ||
  fail "system lock engages the session lock through the shell IPC" "calls: $(cat "$call_log")"
grep -q '^hyprctl switchxkblayout all 0$' "$call_log" ||
  fail "system lock resets the keyboard layout to the default" "calls: $(cat "$call_log")"
# MCDC SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=T, ttfx_wait_bounded=T, user_lock_requested=T => TRUE
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=T, session_lock_engaged=T, user_lock_requested=T => TRUE
pass "system lock waits for ttfx before closing its terminal"

# The lock is secured after the request returns, so a session still arming must
# not be mistaken for one that failed.
rc=0
SECURE_AFTER=3 run_lock || rc=$?
(( rc == 0 )) || fail "system lock waits for a session that is still arming" "exit $rc"
pass "system lock waits for a session that is still arming"

# The shell reports a lock it can never perform on stdout, with a zero exit.
rc=0
LOCK_REPLY=missing-pam run_lock || rc=$?
(( rc == 1 )) || fail "system lock fails when no lock screen is configured" "exit $rc"
grep -q "no lock screen is configured" "$tmpdir/stderr" ||
  fail "system lock says why the session was not locked" "$(<"$tmpdir/stderr")"
# SYS-REQ-260927-WC89:error_handling:negative
# SYS-REQ-260912-T0XP:error_handling:negative
grep -q "^omarchy-notification-send .*Screen did not lock" "$call_log" ||
  fail "system lock warns on screen when it could not lock"
pass "system lock fails when no lock screen is configured"

# The earliest exit in the script, so the one most likely to strand the work
# that has to happen whether or not the session ends up secured.
rg -q '^pkill -f \[o\]rg\.omarchy\.screensaver$' "$call_log" ||
  fail "a lock the shell refuses still tears down the screensaver"
rg -q '^hyprctl switchxkblayout all 0$' "$call_log" ||
  fail "a lock the shell refuses still resets the keyboard layout"
pass "a lock the shell refuses still runs the rest of the lock sequence"

# The failure this exists to catch: the request is accepted, nothing secures,
# and the old script reported success anyway.
started=$SECONDS
rc=0
SECURE_AFTER=never run_lock || rc=$?
elapsed=$((SECONDS - started))

# SYS-REQ-260912-T0XP:error_handling:negative
(( rc == 1 )) || fail "system lock fails when the session never becomes secure" "exit $rc"
(( rc != 124 && rc != 137 )) || fail "system lock gives up on its own" "still running after ${elapsed}s"
pass "system lock fails when the session never becomes secure"

grep -q "did not secure the session" "$tmpdir/stderr" ||
  fail "system lock reports the deadline it gave up on" "$(<"$tmpdir/stderr")"
pass "system lock reports the deadline it gave up on"

(( $(grep -c '^omarchy-shell lock lock$' "$call_log") > 1 )) ||
  fail "system lock re-requests a lock the shell dropped" "$(grep -c '^omarchy-shell lock lock$' "$call_log") request(s)"
pass "system lock re-requests a lock the shell dropped"

# Locking 1Password and closing the screensaver still have to happen even when
# the session itself could not be secured.
rg -q '^pkill -f \[o\]rg\.omarchy\.screensaver$' "$call_log" ||
  fail "system lock still closes the screensaver when the lock fails"
pass "system lock still closes the screensaver when the lock fails"

# The variant blocks below start from the shell mock above (it answers
# `lock lock` and reports the session secure on the first `lock status`), then
# override one command. run_variant bounds the script the same way run_lock does
# and returns its exit status instead of aborting the test.
# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP — copies the shell mock for one variant
variant_bin() {
  mkdir -p "$1"
  cp "$mock_bin"/* "$1"/
}
# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP — runs the real script with one command overridden
run_variant() {
  local bin=$1 log=$2 rc=0
  : >"$tmpdir/polls"
  PATH="$bin:$PATH" CALL_LOG="$log" POLL_COUNT="$tmpdir/polls" SECURE_AFTER=1 LOCK_REPLY=ok \
    "$real_timeout" -k 5s 40s "$ROOT/bin/omarchy-system-lock" 2>"$tmpdir/stderr-variant" || rc=$?
  return "$rc"
}

# ttfx gone by the time the signal lands (pkill matches nothing, exit 1):
# the script must still complete, and the wait must stay inside the 1s bound.
# The same failing pkill arm is the no-action evidence for the
# ttfx_running=F row: zero SIGTERMs are delivered to ttfx.
mock_bin_pk="$tmpdir/bin-pk"
call_log_pk="$tmpdir/calls-pk"
variant_bin "$mock_bin_pk"
cat >"$mock_bin_pk/pkill" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
cat >"$mock_bin_pk/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin_pk"/*

rc=0
run_variant "$mock_bin_pk" "$call_log_pk" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds when ttfx cannot be signalled" "exit $rc"
# MCDC SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=T, user_lock_requested=T => FALSE
# MCDC SW-REQ-260912-MXQG: ttfx_running=F, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=T => TRUE [no-action: pkill spy exits 1 on -x ttfx so zero SIGTERMs are delivered; the wait degrades to the logged `timeout 1s pidwait` bound]
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=F, session_lock_engaged=T, user_lock_requested=T => FALSE
grep -q '^pkill -x ttfx$' "$call_log_pk" ||
  fail "system lock still attempts the ttfx stop when the signal cannot land" "calls: $(cat "$call_log_pk")"
# SW-REQ-260912-MXQG:error_handling:negative
grep -q '^timeout 1s pidwait -x ttfx$' "$call_log_pk" ||
  fail "system lock keeps the ttfx wait inside the 1s bound when the signal fails" "calls: $(cat "$call_log_pk")"
grep -q '^omarchy-shell lock lock$' "$call_log_pk" ||
  fail "system lock still engages the session lock when the ttfx stop fails" "calls: $(cat "$call_log_pk")"
pass "system lock completes with a bounded wait when ttfx cannot be signalled"

# Keyboard-layout reset failure must not abort the lock or the screensaver stop.
mock_bin_hy="$tmpdir/bin-hy"
call_log_hy="$tmpdir/calls-hy"
variant_bin "$mock_bin_hy"
for command in omarchy-cmd-present flock; do
  cat >"$mock_bin_hy/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_hy/hyprctl" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin_hy"/*

rc=0
run_variant "$mock_bin_hy" "$call_log_hy" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds when the layout reset fails" "exit $rc"
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=T, session_lock_engaged=T, user_lock_requested=T => FALSE
grep -q '^omarchy-shell lock lock$' "$call_log_hy" ||
  fail "system lock still engages the session lock when the layout reset fails" "calls: $(cat "$call_log_hy")"
grep -q '^pkill -x ttfx$' "$call_log_hy" ||
  fail "system lock still stops the screensaver when the layout reset fails" "calls: $(cat "$call_log_hy")"
pass "system lock completes when the keyboard layout reset fails"

# Session-lock IPC failure (the shell is not running, every call exits 1) must
# not skip the layout reset or the screensaver stop, and must end in a failure
# the user can see.
mock_bin_sh="$tmpdir/bin-sh"
call_log_sh="$tmpdir/calls-sh"
variant_bin "$mock_bin_sh"
for command in omarchy-cmd-present flock; do
  cat >"$mock_bin_sh/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_sh/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin_sh"/*

rc=0
run_variant "$mock_bin_sh" "$call_log_sh" || rc=$?
# SYS-REQ-260912-T0XP:error_handling:negative
(( rc == 1 )) || fail "system lock fails when the session-lock IPC fails" "exit $rc"
grep -q "^omarchy-notification-send .*Screen did not lock" "$call_log_sh" ||
  fail "system lock warns on screen when the session-lock IPC fails" "calls: $(cat "$call_log_sh")"
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=T, session_lock_engaged=F, user_lock_requested=T => FALSE
grep -q '^hyprctl switchxkblayout all 0$' "$call_log_sh" ||
  fail "system lock still resets the layout when the lock IPC fails" "calls: $(cat "$call_log_sh")"
grep -q '^pkill -x ttfx$' "$call_log_sh" ||
  fail "system lock still stops the screensaver when the lock IPC fails" "calls: $(cat "$call_log_sh")"
pass "system lock completes the sequence and fails visibly when the session-lock IPC fails"

# Control: without a lock request (script never invoked) no lock action runs.
control_log="$tmpdir/calls-control"
PATH="$mock_bin:$PATH" CALL_LOG="$control_log" true
# MCDC SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=F => TRUE [no-action: omarchy-system-lock is never invoked in this control, and the pkill/pidwait spy log stays empty — the signal path is unreachable without a lock request]
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=F, session_lock_engaged=F, user_lock_requested=F => TRUE [no-action: same control — with no invocation the spy log records zero omarchy-shell/hyprctl/pkill calls]
if [[ -f $control_log ]]; then
  fail "no lock action runs without a lock request" "calls: $(cat "$control_log")"
fi
pass "no lock action runs without a lock request"

# With 1password running and installed, the line-17 guard takes its true arm:
# the lock path fires under its own flock, through a bounded timeout. The
# helper block runs in the background, so poll the log instead of racing it.
mock_bin_1p="$tmpdir/bin-1p"
call_log_1p="$tmpdir/calls-1p"
variant_bin "$mock_bin_1p"
for command in flock omarchy-cmd-present; do
  cat >"$mock_bin_1p/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_1p/pgrep" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin_1p"/*

rc=0
run_variant "$mock_bin_1p" "$call_log_1p" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds on the 1password path" "exit $rc"
for _ in {1..50}; do
  [[ -f $call_log_1p ]] && grep -q '^timeout --kill-after=1s 3s 1password --lock' "$call_log_1p" && break
  sleep 0.05
done
[[ -f $call_log_1p ]] || fail "system lock logs its calls when 1password is running"
grep -q '^flock -n 9$' "$call_log_1p" ||
  fail "system lock serializes the 1password lock through its own flock" "calls: $(cat "$call_log_1p")"
grep -q '^timeout --kill-after=1s 3s 1password --lock' "$call_log_1p" ||
  fail "system lock locks 1password through a bounded timeout" "calls: $(cat "$call_log_1p")"
pass "system lock locks 1password when it is running"

# Running but not installed (the guard's second condition false) must skip the
# 1password path entirely.
mock_bin_np="$tmpdir/bin-np"
call_log_np="$tmpdir/calls-np"
variant_bin "$mock_bin_np"
for command in flock; do
  cat >"$mock_bin_np/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_np/pgrep" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin_np/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin_np"/*

rc=0
run_variant "$mock_bin_np" "$call_log_np" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds when 1password is not installed" "exit $rc"
sleep 0.2
if [[ -f $call_log_np ]] && grep -q '^flock -n 9$' "$call_log_np"; then
  fail "system lock skips the 1password lock path when 1password is not installed" \
    "calls: $(cat "$call_log_np")"
fi
pass "system lock skips the 1password lock path when 1password is not installed"

# A contended 1password lock must skip the lock attempt: the flock guard's
# exit-0 arm keeps a second system-lock from stacking Electron helper trees.
mock_bin_fc="$tmpdir/bin-fc"
call_log_fc="$tmpdir/calls-fc"
variant_bin "$mock_bin_fc"
for command in omarchy-cmd-present; do
  cat >"$mock_bin_fc/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_fc/pgrep" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin_fc/flock" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin_fc"/*

rc=0
run_variant "$mock_bin_fc" "$call_log_fc" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds while the 1password lock is contended" "exit $rc"
for _ in {1..50}; do
  [[ -f $call_log_fc ]] && grep -q '^flock -n 9$' "$call_log_fc" && break
  sleep 0.05
done
[[ -f $call_log_fc ]] && grep -q '^flock -n 9$' "$call_log_fc" ||
  fail "system lock attempts the 1password flock before giving up" "calls: ${call_log_fc:-missing}"
if grep -q '1password --lock' "$call_log_fc"; then
  fail "system lock does not lock 1password while its lock is contended" "calls: $(cat "$call_log_fc")"
fi
pass "system lock skips the 1password lock while its lock is contended"
