#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-Q6ZS, SW-REQ-260922-B839, SW-REQ-260922-MP00, SW-REQ-260922-9ABD, SW-REQ-260922-FGZQ, SW-REQ-260922-C8HX, SW-REQ-260922-3VTN, SYS-REQ-260922-X6Z5, SW-REQ-260924-AK4Z
#mcdc:ignore:defensive SW-REQ-260922-Q6ZS: payload_shape_correct=F, select_invoked=T => FALSE -- the payload is one deterministic perl encode ahead of the single summon; a malformed payload means perl died and set -e kills the script before any summon, so invoked-with-bad-shape is structural [reviewed: REVIEW-M2]
#mcdc:ignore:defensive SW-REQ-260922-B839: no_options_given=T, usage_error_exit_one=F => FALSE -- both empty-option paths (argv and stdin mapfile) fall through to the same unconditional usage+exit 1 [reviewed: REVIEW-M2]
#mcdc:ignore:defensive SW-REQ-260922-MP00: answer_file_written=T, selection_printed=F => FALSE -- the only read of the answer file is `[[ -s $selection_file ]] && cat`; a non-empty answer is always printed [reviewed: REVIEW-M2]
#mcdc:ignore:defensive SW-REQ-260922-9ABD: empty_selection=T, exit_one_on_empty=F => FALSE -- an empty selection file takes the unconditional `exit 1` arm; there is no other exit path for it [reviewed: REVIEW-M2]
#mcdc:ignore:defensive SW-REQ-260922-3VTN: menu_closes_silently=F, no_active_request=T => FALSE -- the done-only path writes nothing to stdout or stderr on any branch; noise needs code that does not exist [reviewed: REVIEW-M2]
#mcdc:ignore:defensive SW-REQ-260922-C8HX: done_only_written=F, finish_requested=T, prompt_dismissed=T => FALSE -- dismissal reaches finishRequest(null) in Menu.qml, whose only write is the done file; a selection written by a dismissal is structurally absent [reviewed: REVIEW-M2]
#mcdc:ignore:defensive SYS-REQ-260922-X6Z5: picker_active=T, picker_answer_returned=F, selection_made=T => FALSE -- a made selection lands in the selection file, and the script prints any non-empty selection file unconditionally [reviewed: REVIEW-M2]
# mcdc:witness-out-of-process

# Server-role stub harness for the dmenu protocol pair: the stub plays
# omarchy-shell, captures the summon payload, and answers the way Menu.qml's
# finishRequest would -- selection file plus done file for a pick, done file
# alone for a dismissal.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

cat >"$STUB_DIR/omarchy-shell" <<'STUB'
#!/bin/bash
# $1=shell $2=summon $3=omarchy.menu $4=payload
printf '%s\n' "$4" >"$SPY_PAYLOAD"
sel=$(printf '%s' "$4" | jq -r '.selectionFile // empty')
donef=$(printf '%s' "$4" | jq -r '.doneFile // empty')
case "$FAKE_ANSWER" in
  selection)
    ( sleep 0.1; printf '%s\n' "$FAKE_SELECTION" >"$sel"; : >"$donef" ) &
    ;;
  done-only)
    ( sleep 0.1; : >"$donef" ) &
    ;;
esac
STUB
chmod +x "$STUB_DIR/omarchy-shell"

# Runs a dmenu script against the stub; leaves stdout in $OUT, stderr in $ERR,
# exit status in $STATUS, and the captured payload in $PAYLOAD (empty when the
# script never summoned).
run_dmenu() {
  local script="$1"; shift
  rm -f "$TMPDIR/payload"
  OUT=$(PATH="$STUB_DIR:$PATH" SPY_PAYLOAD="$TMPDIR/payload" FAKE_ANSWER="$FAKE_ANSWER" FAKE_SELECTION="${FAKE_SELECTION:-}" \
    "${OMARCHY_TEST_BASH:-$BASH}" "$ROOT/bin/$script" "$@" < /dev/null 2>"$TMPDIR/err") && STATUS=0 || STATUS=$?
  ERR=$(cat "$TMPDIR/err")
  PAYLOAD=""
  [[ -f $TMPDIR/payload ]] && PAYLOAD=$(cat "$TMPDIR/payload")
  return 0
}

# --- A pick: payload shape, answer printed, exit zero ---------------------

FAKE_ANSWER=selection
FAKE_SELECTION=$(printf 'Brave\tbrowser')
run_dmenu omarchy-menu-select "Pick a browser" Brave Firefox Zen -- --width 520 --maxheight 520
# SW-REQ-260922-MP00:error_handling:nominal
# SW-REQ-260922-B839:error_handling:negative
[[ $STATUS -eq 0 ]] || fail "menu select exits zero on a pick" "status: $STATUS err: $ERR"
[[ $OUT == "$FAKE_SELECTION" ]] || fail "menu select prints the answer file" "out: $OUT"
printf '%s' "$PAYLOAD" | jq -e '
  .mode == "select"
  and .prompt == "Pick a browser"
  and .options == ["Brave", "Firefox", "Zen"]
  and (.selectionFile | length) > 0
  and (.doneFile | length) > 0
  and .width == 520
  and .maxHeight == 520' >/dev/null ||
  fail "menu select payload carries mode, prompt, options, files, and geometry" "payload: $PAYLOAD"
# MCDC SW-REQ-260922-Q6ZS: payload_shape_correct=T, select_invoked=T => TRUE
# MCDC SYS-REQ-260922-X6Z5: picker_active=T, picker_answer_returned=T, selection_made=T => TRUE
# MCDC SW-REQ-260922-MP00: answer_file_written=T, selection_printed=T => TRUE
# MCDC SW-REQ-260922-FGZQ: finish_requested=T, selection_and_done_written=T => TRUE
# MCDC SW-REQ-260922-9ABD: empty_selection=F, exit_one_on_empty=F => TRUE [no-action: the run exits zero with its selection printed -- the empty-selection path is not taken]
# MCDC SW-REQ-260924-AK4Z: caller_exits_bounded=F, peer_unresponsive=F => TRUE [no-action: the stub answers every summon, so the deadline never engages -- no bounded-exit event occurs]
# MCDC SW-REQ-260922-3VTN: menu_closes_silently=F, no_active_request=F => TRUE [no-action: the run answers its request -- the silent-close path is not taken while a request is active]
# MCDC SW-REQ-260922-C8HX: done_only_written=F, finish_requested=T, prompt_dismissed=F => TRUE [no-action: the answered prompt writes both selection and done files -- the done-only dismissal path is not taken]
# MCDC SW-REQ-260922-B839: no_options_given=F, usage_error_exit_one=F => TRUE [no-action: stderr is empty -- no usage error when options are given]
pass "menu select summons a shaped payload and prints the pick"

# --- A dismissal: done file only, silent exit one --------------------------

FAKE_ANSWER=done-only
run_dmenu omarchy-menu-select "Pick a browser" Brave Firefox Zen
[[ $STATUS -eq 1 ]] || fail "menu select exits one on a dismissal" "status: $STATUS"
[[ -z $OUT ]] || fail "menu select prints nothing on a dismissal" "out: $OUT"
[[ -z $ERR ]] || fail "menu select stays silent on a dismissal" "err: $ERR"
# MCDC SW-REQ-260922-3VTN: menu_closes_silently=T, no_active_request=T => TRUE
# MCDC SW-REQ-260922-9ABD: empty_selection=T, exit_one_on_empty=T => TRUE
# MCDC SW-REQ-260922-C8HX: done_only_written=T, finish_requested=T, prompt_dismissed=T => TRUE
# MCDC SW-REQ-260922-C8HX: done_only_written=F, finish_requested=F, prompt_dismissed=T => TRUE [no-action: the dismissal arrives through the same finishRequest done-file write as any finish -- the stub answers with the done file alone, so a dismissal without a finish has no path]
# MCDC SW-REQ-260922-FGZQ: finish_requested=T, selection_and_done_written=F => FALSE
# MCDC SYS-REQ-260922-X6Z5: picker_active=T, picker_answer_returned=F, selection_made=F => TRUE [no-action: stdout is empty and the exit status is one -- no answer is returned when no selection was made]
# MCDC SW-REQ-260922-MP00: answer_file_written=F, selection_printed=F => TRUE [no-action: stdout is empty -- nothing is printed when the menu wrote no answer]
pass "menu select closes silently with exit one on a dismissal"

# --- No options: usage error, no summon ------------------------------------

FAKE_ANSWER=selection
run_dmenu omarchy-menu-select "Pick a browser"
[[ $STATUS -eq 1 ]] || fail "menu select without options exits one" "status: $STATUS"
# SW-REQ-260922-B839:error_handling:nominal
# SW-REQ-260922-MP00:error_handling:negative
[[ $ERR == "Usage: omarchy-menu-select <prompt> [option...] [-- menu args...]" ]] ||
  fail "menu select without options prints usage" "err: $ERR"
[[ -z $PAYLOAD ]] || fail "menu select without options never summons" "payload: $PAYLOAD"
# MCDC SYS-REQ-260922-X6Z5: picker_active=F, picker_answer_returned=F, selection_made=T => TRUE [no-action: the picker never activates -- the payload spy captured nothing, so no selection file exists that could record a selection]
# MCDC SW-REQ-260922-B839: no_options_given=T, usage_error_exit_one=T => TRUE
# MCDC SW-REQ-260922-Q6ZS: payload_shape_correct=F, select_invoked=F => TRUE [no-action: the payload spy captured nothing -- zero summon calls without options]
# MCDC SW-REQ-260922-FGZQ: finish_requested=F, selection_and_done_written=F => TRUE [no-action: the payload spy captured nothing -- the run never reaches a finish]
pass "menu select refuses an empty option list with usage and exit one"

# --- Input mode: same protocol, text answer --------------------------------

FAKE_ANSWER=selection
FAKE_SELECTION="15"
run_dmenu omarchy-menu-input "Reminder in minutes" --width 400
[[ $STATUS -eq 0 && $OUT == "15" ]] || fail "menu input prints the entered text" "status: $STATUS out: $OUT"
printf '%s' "$PAYLOAD" | jq -e '
  .mode == "input"
  and .prompt == "Reminder in minutes"
  and (.selectionFile | length) > 0
  and (.doneFile | length) > 0
  and .width == 400' >/dev/null ||
  fail "menu input payload carries mode, prompt, files, and width" "payload: $PAYLOAD"
# MCDC SW-REQ-260922-MP00: answer_file_written=T, selection_printed=T => TRUE
pass "menu input summons a shaped payload and prints the answer"

FAKE_ANSWER=done-only
run_dmenu omarchy-menu-input "Reminder in minutes"
[[ $STATUS -eq 1 && -z $OUT && -z $ERR ]] ||
  fail "menu input exits one silently on a dismissal" "status: $STATUS out: $OUT err: $ERR"
# MCDC SW-REQ-260922-9ABD: empty_selection=T, exit_one_on_empty=T => TRUE
pass "menu input exits one silently on a dismissal"
