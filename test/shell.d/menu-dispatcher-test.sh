#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-T257, SW-REQ-260922-SNZG, SYS-REQ-260922-J0AN
#mcdc:ignore:defensive SW-REQ-260922-SNZG: diagnostic_printed=F, exit_two=F, verb_unknown=T => FALSE -- the unknown-verb arm unconditionally prints the diagnostic and exits 2; an unknown verb answered silently needs a broken case statement [reviewed: REVIEW-M1]
#mcdc:ignore:defensive SW-REQ-260922-SNZG: diagnostic_printed=F, exit_two=T, verb_unknown=T => FALSE -- the same arm echoes before it exits; exit 2 without the diagnostic is structurally absent [reviewed: REVIEW-M1]
#mcdc:ignore:defensive SW-REQ-260922-SNZG: diagnostic_printed=T, exit_two=F, verb_unknown=T => FALSE -- the same arm exits 2 right after the echo; a diagnostic without exit 2 is structurally absent [reviewed: REVIEW-M1]
# mcdc:witness-out-of-process

# Lock-style spy harness for the menu dispatcher: bin/omarchy-menu is a thin
# wrapper over `omarchy-shell` IPC, so a spy on omarchy-shell observes every
# presentation decision the dispatcher makes.
#
# The dispatcher runs out of process, so witness blocks carry
# `// mcdc:witness-out-of-process` for the drives-code check.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

cat >"$STUB_DIR/omarchy-shell" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SPY_LOG"
STUB
chmod +x "$STUB_DIR/omarchy-shell"

# Runs the dispatcher with the spy on PATH; leaves stdout in $OUT, stderr in
# $ERR, the exit status in $STATUS, and the spy log in $CALLS.
run_menu() {
  : >"$TMPDIR/calls"
  OUT=$(PATH="$STUB_DIR:$PATH" SPY_LOG="$TMPDIR/calls" "$ROOT/bin/omarchy-menu" "$@" 2>"$TMPDIR/err") && STATUS=0 || STATUS=$?
  ERR=$(cat "$TMPDIR/err")
  CALLS=$(cat "$TMPDIR/calls")
}

# A known verb reaches the omarchy.menu plugin over IPC with the route as a
# JSON payload. The default verb is toggle at root.
run_menu
[[ $STATUS -eq 0 ]] || fail "menu default invocation exits zero" "status: $STATUS err: $ERR"
[[ $CALLS == "shell toggle omarchy.menu {\"menu\":\"root\"}" ]] ||
  fail "menu default invocation toggles the menu plugin at root" "calls: $CALLS"
# MCDC SW-REQ-260922-T257: ipc_call_executed=T, verb_known=T => TRUE
# MCDC SYS-REQ-260922-J0AN: menu_invoked=T, menu_presented=T => TRUE
# MCDC SW-REQ-260922-SNZG: diagnostic_printed=F, exit_two=F, verb_unknown=F => TRUE [no-action: stderr is empty and the run exits zero -- no diagnostic is printed for a known verb]
pass "menu dispatcher toggles the menu at root by default"

run_menu summon style.theme
[[ $CALLS == "shell summon omarchy.menu {\"menu\":\"style.theme\"}" ]] ||
  fail "menu summon passes the route as JSON payload" "calls: $CALLS"
# MCDC SW-REQ-260922-T257: ipc_call_executed=T, verb_known=T => TRUE
pass "menu dispatcher summons a route as a JSON payload"

# close is a known verb, but nothing is presented: the IPC call hides the
# menu. That is the menu_presented=F arm of the lifecycle guarantee.
run_menu close
[[ $CALLS == "shell hide omarchy.menu" ]] ||
  fail "menu close hides the plugin over IPC" "calls: $CALLS"
# MCDC SYS-REQ-260922-J0AN: menu_invoked=T, menu_presented=F => FALSE
pass "menu dispatcher close presents nothing"

# help is also a known verb with no IPC at all: usage on stdout, zero calls.
run_menu help
[[ $STATUS -eq 0 && $OUT == *"Usage: omarchy menu"* && -z $CALLS ]] ||
  fail "menu help prints usage without touching IPC" "status: $STATUS out: $OUT calls: $CALLS"
# MCDC SW-REQ-260922-T257: ipc_call_executed=F, verb_known=T => FALSE
pass "menu dispatcher help reaches no IPC"

# An unknown verb is a diagnostic on stderr and exit 2, with zero IPC calls.
run_menu bogus-verb
[[ $STATUS -eq 2 ]] || fail "menu unknown verb exits two" "status: $STATUS"
[[ $ERR == "omarchy-menu: unknown verb 'bogus-verb'. Try 'omarchy menu --help'." ]] ||
  fail "menu unknown verb prints a diagnostic" "err: $ERR"
[[ -z $CALLS ]] || fail "menu unknown verb never touches IPC" "calls: $CALLS"
# MCDC SW-REQ-260922-SNZG: diagnostic_printed=T, exit_two=T, verb_unknown=T => TRUE
# MCDC SW-REQ-260922-T257: ipc_call_executed=F, verb_known=F => TRUE [no-action: the spy log is empty -- zero omarchy-shell calls for an unknown verb]
# MCDC SYS-REQ-260922-J0AN: menu_invoked=F, menu_presented=F => TRUE [no-action: the spy log is empty -- an unknown verb presents nothing]
pass "menu dispatcher rejects an unknown verb with a diagnostic and exit two"
