#!/bin/bash
# Reproducer for CRS-0014/C01: omarchy-menu-select waits forever when the shell
# that took the request dies before it answers.
# Reproduces: KI-MENU-SELECT-POLL-DEADLOCK
# Correct behavior (asserted): when the shell process that accepted the summon
# exits without writing done_file, the script must exit within a bounded time.
# While the defect is present this FAILS: the poll loops forever.
#
# A stand-in process named `quickshell`, started the way omarchy-launch-shell
# starts the shell (quickshell -n -p "$OMARCHY_PATH/shell"), plays the shell.
# The stub omarchy-shell accepts the summon and then either answers like the
# shell's finishRequest does (control) or kills the stand-in (peer death).
# A shell that stays alive and never answers is NOT the defect: an open picker
# may stay open as long as the user likes, so it is not asserted here.
set -u
repo=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
STUB=$(mktemp -d)
standin=
trap '[[ -n $standin ]] && kill -KILL "$standin" 2>/dev/null; rm -r -- "$STUB"' EXIT

# Unique OMARCHY_PATH, so only this stand-in matches "$OMARCHY_PATH/shell".
export OMARCHY_PATH=$STUB/omarchy
mkdir -p "$OMARCHY_PATH/shell" "$STUB/bin"
ln -s "$(command -v bash)" "$STUB/bin/quickshell"

start_standin() {
  "$STUB/bin/quickshell" -c 'while :; do sleep 0.2; done' quickshell -n -p "$OMARCHY_PATH/shell" &
  standin=$!
  disown "$standin"
  echo "$standin" > "$STUB/standin.pid"
  sleep 0.2
}

stop_standin() {
  kill -KILL "$standin" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do kill -0 "$standin" 2>/dev/null || break; sleep 0.1; done
  standin=
}

cat > "$STUB/bin/omarchy-shell" <<'SH'
#!/bin/bash
# The summon is accepted ("ok", exit 0) like the real shell IPC.
payload="${@: -1}"
field() { printf '%s' "$payload" | perl -MJSON::PP=decode_json -e 'local $/; print decode_json(<STDIN>)->{$ARGV[0]}' "$1"; }
case $SCENARIO in
  answer) # healthy shell: writes the selection, then the done file
    printf 'alpha' > "$(field selectionFile)"; : > "$(field doneFile)" ;;
  peer-death) # the shell dies 0.3s after taking the request, before answering
    ( sleep 0.3; kill -KILL "$(cat "$STUB_DIR/standin.pid")" ) >/dev/null 2>&1 & ;;
esac
echo ok
exit 0
SH
chmod +x "$STUB/bin/omarchy-shell"

run_select() {
  SCENARIO=$1 STUB_DIR=$STUB PATH="$STUB/bin:$repo/bin:$PATH" \
    timeout 5 bash "$repo/bin/omarchy-menu-select" "Pick one" alpha beta 2>"$STUB/err" </dev/null
}

# Negative control (PoC rule 3/10): a healthy shell answers; the script MUST
# return the answer promptly.
start_standin
ctrl_out=$(run_select answer)
ctrl_rc=$?
stop_standin
if [[ $ctrl_rc -ne 0 || $ctrl_out != alpha ]]; then
  echo "CONTROL FAILED: healthy shell gave rc=$ctrl_rc out='$ctrl_out' (expected alpha, rc=0); PoC cannot distinguish defect from design"
  exit 2
fi
echo "control ok: healthy shell answered '$ctrl_out' rc=$ctrl_rc"

# Peer death: the shell takes the request, then exits without answering.
start_standin
start=$SECONDS
run_select peer-death >/dev/null
rc=$?
elapsed=$((SECONDS - start))
stop_standin
if [[ $rc -eq 124 ]]; then
  echo "DEFECT PRESENT: the shell exited 0.3s after taking the request and the wait was still running at the 5s deadline (rc=124 timeout kill)"
  exit 1
fi
echo "peer death: exit rc=$rc after ${elapsed}s ($(tr '\n' ' ' <"$STUB/err"))"
[[ $rc -ne 0 && $elapsed -lt 5 ]]
