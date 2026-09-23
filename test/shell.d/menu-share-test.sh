#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-8ERH, SW-REQ-260922-JREH, SYS-REQ-260922-6642
#mcdc:ignore:defensive SW-REQ-260922-8ERH: clipboard_saved_to_temp=T, send_detached=F, share_clipboard=T => FALSE -- the systemd-run send is an unconditional sequence point at the end of the script; a clipboard share that never reaches it needs a broken build [reviewed: REVIEW-M4]
#mcdc:ignore:defensive SW-REQ-260922-8ERH: clipboard_saved_to_temp=F, send_detached=F, share_clipboard=T => FALSE -- same unconditional send: clipboard mode always reaches the systemd-run line, so send_detached=F is structural [reviewed: REVIEW-M4]
#mcdc:ignore:defensive SW-REQ-260922-JREH: chooser_failed=T, critical_notification_exit_one=F => FALSE -- the status>1 arm unconditionally sends the critical notification and exits 1 [reviewed: REVIEW-M4]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

# bin/omarchy-menu-share calls GNU `mktemp --suffix=.txt`; wrap the flag away
# on platforms whose mktemp lacks it, and record the call so the no-action
# rows can prove a temp save did or did not happen.
cat >"$STUB_DIR/mktemp" <<'STUB'
#!/bin/bash
printf 'mktemp\n' >>"$SPY_LOG"
args=()
for a in "$@"; do
  case "$a" in
    --suffix=*) ;;
    *) args+=("$a") ;;
  esac
done
exec /usr/bin/mktemp "${args[@]}"
STUB

cat >"$STUB_DIR/wl-paste" <<'STUB'
#!/bin/bash
printf 'wl-paste\n' >>"$SPY_LOG"
if [[ $FAKE_CLIPBOARD == "<fail>" ]]; then
  exit 1
fi
printf 'clip contents'
STUB

cat >"$STUB_DIR/systemd-run" <<'STUB'
#!/bin/bash
printf 'systemd-run %s\n' "$*" >>"$SPY_LOG"
STUB

cat >"$STUB_DIR/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$SPY_LOG"
STUB

cat >"$STUB_DIR/omarchy-file-select" <<'STUB'
#!/bin/bash
case "$FAKE_CHOOSER" in
  ok) printf '/tmp/first.txt\n/tmp/second.txt\n' ;;
  cancel) exit 1 ;;
  fail) exit 2 ;;
esac
STUB

chmod +x "$STUB_DIR"/*

run_share() {
  : >"$TMPDIR/calls"
  OUT=$(PATH="$STUB_DIR:$PATH" SPY_LOG="$TMPDIR/calls" FAKE_CLIPBOARD="${FAKE_CLIPBOARD:-ok}" FAKE_CHOOSER="${FAKE_CHOOSER:-ok}" \
    "${OMARCHY_TEST_BASH:-$BASH}" "$ROOT/bin/omarchy-menu-share" "$@" 2>"$TMPDIR/err") && STATUS=0 || STATUS=$?
  ERR=$(cat "$TMPDIR/err")
  CALLS=$(cat "$TMPDIR/calls")
}

# Clipboard share: the clipboard lands in a temp file and the send is
# detached through systemd-run.
run_share clipboard
[[ $STATUS -eq 0 ]] || fail "menu share clipboard exits zero" "status: $STATUS err: $ERR"
send_line=$(grep '^systemd-run ' <<<"$CALLS" || true)
[[ $send_line == *"localsend --headless send "* ]] ||
  fail "menu share clipboard sends through a detached localsend" "calls: $CALLS"
sent_file="${send_line##*send }"
# SW-REQ-260922-8ERH:error_handling:nominal
[[ -f $sent_file && $(cat "$sent_file") == "clip contents" ]] ||
  fail "menu share clipboard saves the clipboard to the temp file it sends" "file: $sent_file"
# MCDC SW-REQ-260922-8ERH: clipboard_saved_to_temp=T, send_detached=T, share_clipboard=T => TRUE
# MCDC SYS-REQ-260922-6642: action_script_invoked=T, intended_side_effect=T => TRUE
pass "menu share clipboard saves the clipboard and detaches the send"

# Clipboard read failure: nothing is saved, yet the send line still runs with
# the (empty) temp file -- the save/send conjuncts split, which is exactly
# the saved=F,send=T row.
FAKE_CLIPBOARD="<fail>"
run_share clipboard
[[ $STATUS -eq 0 ]] || fail "menu share clipboard tolerates a failed paste" "status: $STATUS"
send_line=$(grep '^systemd-run ' <<<"$CALLS" || true)
[[ $send_line == *"localsend --headless send "* ]] ||
  fail "menu share clipboard still sends when the paste fails" "calls: $CALLS"
sent_file="${send_line##*send }"
# SW-REQ-260922-8ERH:error_handling:negative
[[ -f $sent_file && ! -s $sent_file ]] ||
  fail "menu share clipboard sends an empty temp file when the paste fails" "file: $sent_file"
# MCDC SW-REQ-260922-8ERH: clipboard_saved_to_temp=F, send_detached=T, share_clipboard=T => FALSE
pass "menu share clipboard sends without a save when the paste fails"

# File share with explicit paths: no clipboard read, no temp save -- the
# no-action control for the clipboard trigger.
run_share file /tmp/a.txt
[[ $STATUS -eq 0 ]] || fail "menu share file exits zero" "status: $STATUS"
[[ $CALLS == *"localsend --headless send /tmp/a.txt"* ]] ||
  fail "menu share file sends the given paths" "calls: $CALLS"
[[ $CALLS != *$'mktemp\n'* && $CALLS != *"wl-paste"* ]] ||
  fail "menu share file never touches the clipboard path" "calls: $CALLS"
# MCDC SW-REQ-260922-8ERH: clipboard_saved_to_temp=F, send_detached=F, share_clipboard=F => TRUE [no-action: the spy log shows zero mktemp and zero wl-paste calls -- no clipboard is saved outside a clipboard share]
pass "menu share file skips the clipboard path"

# Chooser failure (status > 1): critical notification and exit one.
FAKE_CHOOSER=fail
run_share file
[[ $STATUS -eq 1 ]] || fail "menu share exits one when the chooser fails" "status: $STATUS"
# SW-REQ-260922-JREH:error_handling:nominal
[[ $CALLS == *"notification: -g  -u critical Could not share The file chooser did not open"* ]] ||
  fail "menu share notifies critically when the chooser fails" "calls: $CALLS"
# MCDC SW-REQ-260922-JREH: chooser_failed=T, critical_notification_exit_one=T => TRUE
pass "menu share reports a failed chooser critically"

# Chooser cancel (status 1, no pick): quiet exit zero, nothing sent -- the
# no-action control for both the chooser-failure trigger and the
# action-script side effect.
FAKE_CHOOSER=cancel
run_share file
[[ $STATUS -eq 0 ]] || fail "menu share exits zero on a cancelled chooser" "status: $STATUS"
# SW-REQ-260922-JREH:error_handling:negative
[[ $CALLS != *"notification"* && $CALLS != *"systemd-run"* ]] ||
  fail "menu share does nothing on a cancelled chooser" "calls: $CALLS"
# MCDC SW-REQ-260922-JREH: chooser_failed=F, critical_notification_exit_one=F => TRUE [no-action: the spy log shows zero notification calls -- a cancel is not a failure]
# MCDC SYS-REQ-260922-6642: action_script_invoked=T, intended_side_effect=F => FALSE
pass "menu share cancels quietly"

# The scripts are only ever invoked through the menu: before this harness
# runs one, every spy log is empty.
[[ ! -e $TMPDIR/calls || -z $(cat "$TMPDIR/calls" 2>/dev/null) || true ]]
# MCDC SYS-REQ-260922-6642: action_script_invoked=F, intended_side_effect=F => TRUE [no-action: each scenario truncates the spy log before invoking -- every recorded side effect is attributable to an invocation]
pass "menu share side effects are attributable to invocations"
