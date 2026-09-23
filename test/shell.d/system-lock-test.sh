#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP

# Row dispositions (see proof mcdc show <REQ-ID> for the tables):
#mcdc:ignore:defensive SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=T => FALSE -- the lock path runs pkill -x ttfx and timeout 1s pidwait as unconditional sequence points; a run that reaches the path always attempts the signal and always waits bounded, so neither-fails is structural [reviewed: REVIEW-1]
#mcdc:ignore:defensive SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=T, ttfx_wait_bounded=F, user_lock_requested=T => FALSE -- the only wait is `timeout 1s pidwait`; there is no unbounded wait path in the file [reviewed: REVIEW-1]
#mcdc:ignore:defensive SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=F, session_lock_engaged=F, user_lock_requested=T => FALSE -- omarchy-system-lock unconditionally attempts the lock, the layout reset, and the screensaver stop in sequence; an all-three-failed run requires a broken build, not a reachable input [reviewed: REVIEW-16]

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

for command in omarchy-shell hyprctl pkill timeout; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin"/*

PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$ROOT/bin/omarchy-system-lock"
mapfile -t shutdown < <(grep -E '^(pkill|timeout) ' "$call_log")

[[ ${shutdown[0]} == "pkill -x ttfx" ]] ||
  fail "system lock stops ttfx before closing its terminal" "calls: ${shutdown[*]}"
[[ ${shutdown[1]} == "timeout 1s pidwait -x ttfx" ]] ||
  fail "system lock waits for ttfx to exit" "calls: ${shutdown[*]}"
[[ ${shutdown[2]} == "pkill -f [o]rg.omarchy.screensaver" ]] ||
  fail "system lock closes the screensaver terminal after ttfx exits" "calls: ${shutdown[*]}"
# SW-REQ-260912-MXQG:error_handling:nominal
grep -q '^omarchy-shell lock lock$' "$call_log" ||
  fail "system lock engages the session lock through the shell IPC" "calls: $(cat "$call_log")"
grep -q '^hyprctl switchxkblayout all 0$' "$call_log" ||
  fail "system lock resets the keyboard layout to the default" "calls: $(cat "$call_log")"
# MCDC SW-REQ-260912-MXQG: ttfx_running=T, ttfx_signalled=T, ttfx_wait_bounded=T, user_lock_requested=T => TRUE
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=T, session_lock_engaged=T, user_lock_requested=T => TRUE
pass "system lock waits for ttfx before closing its terminal"

# ttfx gone by the time the signal lands (pkill matches nothing, exit 1):
# the script must still complete, and the wait must stay inside the 1s bound.
# The same failing pkill arm is the no-action evidence for the
# ttfx_running=F row: zero SIGTERMs are delivered to ttfx.
mock_bin_pk="$tmpdir/bin-pk"
call_log_pk="$tmpdir/calls-pk"
mkdir -p "$mock_bin_pk"
for command in omarchy-shell hyprctl timeout; do
  cat >"$mock_bin_pk/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
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

PATH="$mock_bin_pk:$PATH" CALL_LOG="$call_log_pk" "$ROOT/bin/omarchy-system-lock"
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
mkdir -p "$mock_bin_hy"
for command in omarchy-shell omarchy-cmd-present flock pkill timeout pgrep; do
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

PATH="$mock_bin_hy:$PATH" CALL_LOG="$call_log_hy" "$ROOT/bin/omarchy-system-lock"
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=T, session_lock_engaged=T, user_lock_requested=T => FALSE
grep -q '^omarchy-shell lock lock$' "$call_log_hy" ||
  fail "system lock still engages the session lock when the layout reset fails" "calls: $(cat "$call_log_hy")"
grep -q '^pkill -x ttfx$' "$call_log_hy" ||
  fail "system lock still stops the screensaver when the layout reset fails" "calls: $(cat "$call_log_hy")"
pass "system lock completes when the keyboard layout reset fails"

# Session-lock IPC failure must not abort the layout reset or screensaver stop.
mock_bin_sh="$tmpdir/bin-sh"
call_log_sh="$tmpdir/calls-sh"
mkdir -p "$mock_bin_sh"
for command in hyprctl omarchy-cmd-present flock pkill timeout pgrep; do
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

PATH="$mock_bin_sh:$PATH" CALL_LOG="$call_log_sh" "$ROOT/bin/omarchy-system-lock"
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=T, session_lock_engaged=F, user_lock_requested=T => FALSE
grep -q '^hyprctl switchxkblayout all 0$' "$call_log_sh" ||
  fail "system lock still resets the layout when the lock IPC fails" "calls: $(cat "$call_log_sh")"
grep -q '^pkill -x ttfx$' "$call_log_sh" ||
  fail "system lock still stops the screensaver when the lock IPC fails" "calls: $(cat "$call_log_sh")"
pass "system lock completes when the session-lock IPC fails"

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
mkdir -p "$mock_bin_1p"
for command in omarchy-shell hyprctl pkill timeout flock omarchy-cmd-present; do
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

PATH="$mock_bin_1p:$PATH" CALL_LOG="$call_log_1p" "$ROOT/bin/omarchy-system-lock"
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
mkdir -p "$mock_bin_np"
for command in omarchy-shell hyprctl pkill timeout flock; do
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

PATH="$mock_bin_np:$PATH" CALL_LOG="$call_log_np" "$ROOT/bin/omarchy-system-lock"
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
mkdir -p "$mock_bin_fc"
for command in omarchy-shell hyprctl pkill timeout omarchy-cmd-present; do
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

PATH="$mock_bin_fc:$PATH" CALL_LOG="$call_log_fc" "$ROOT/bin/omarchy-system-lock"
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
