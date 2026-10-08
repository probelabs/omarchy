#!/usr/bin/env bash
# Protocol-faithful harness for bin/omarchy-system-lock.
# The omarchy-shell stub answers at the wrapper's interface the way bin/omarchy-shell (quattro 035ce29f) does:
#   lock lock   -> stdout of Service.qml lock(): "ok" | "missing-pam" | "failed", exit 0
#   lock status -> the JSON of Service.qml status() (only the fields the scripts read)
#   no shell    -> stderr "omarchy-shell is not running", exit 1
#   reply later than OMARCHY_SHELL_IPC_TIMEOUT (default 2s) -> "omarchy-shell is not responding", exit 1,
#                  although the call itself ran (the wrapper reports, it does not retry)
# Side-effect commands (hyprctl, pkill, pidwait, flock, notification) are logging stubs; pgrep says 1Password is not running.
set -u
script=$1 scenario=$2
tmp=$(mktemp -d); trap 'rm -r -- "$tmp"' EXIT
mkdir -p "$tmp/bin"; log=$tmp/calls; : >"$log"
for c in hyprctl pkill pidwait flock omarchy-notification-send omarchy-cmd-present; do
  printf '#!/usr/bin/env bash\nprintf "%%s %%s\\n" "$(basename "$0")" "$*" >>"$CALL_LOG"\n' >"$tmp/bin/$c"
done
printf '#!/usr/bin/env bash\nexit 1\n' >"$tmp/bin/pgrep"
cat >"$tmp/bin/omarchy-shell" <<'SH'
#!/usr/bin/env bash
printf 'omarchy-shell %s\n' "$*" >>"$CALL_LOG"
st=$STATE_DIR; now=$(perl -MTime::HiRes=time -e 'printf "%.3f", time')
[[ -f $st/t0 ]] || echo "$now" >"$st/t0"
age=$(awk -v a="$now" -v b="$(cat "$st/t0")" 'BEGIN{print a-b}')
limit=${OMARCHY_SHELL_IPC_TIMEOUT:-2s}; limit=${limit%s}
notrunning() { echo "omarchy-shell is not running" >&2; exit 1; }
case $SCENARIO in
  not-running) notrunning ;;
  restart) awk -v a="$age" 'BEGIN{exit !(a<2.0)}' && notrunning ;;   # new shell answers 2s after the first call
esac
if [[ "$1 $2" == "lock lock" ]]; then
  case $SCENARIO in
    missing-pam) echo missing-pam; exit 0 ;;
    failed) echo failed; exit 0 ;;
  esac
  [[ -f $st/requested ]] || echo "$now" >"$st/requested"
  if [[ $SCENARIO == slow-reply ]]; then
    # the shell runs the call but answers after 2.5s: the wrapper gives up at its limit
    if awk -v l="$limit" 'BEGIN{exit !(l<2.5)}'; then sleep "$limit"; echo "omarchy-shell is not responding" >&2; exit 1; fi
    sleep 2.5
  fi
  echo ok; exit 0
fi
if [[ "$1 $2" == "lock status" ]]; then
  polls=$(( $(cat "$st/polls" 2>/dev/null || echo 0) + 1 )); echo $polls >"$st/polls"
  req=false; sec=false
  if [[ -f $st/requested ]]; then
    req=true
    case $SCENARIO in
      accepted-never-secure) ;;
      fast-unlock) # the user unlocked (fingerprint) before the first poll; a later lock request locks again
        if [[ ! -f $st/unlocked ]]; then touch "$st/unlocked"; rm -f "$st/requested"; req=false; else (( polls >= 3 )) && sec=true; fi ;;
      dropped) if [[ ! -f $st/dropped ]]; then touch "$st/dropped"; rm -f "$st/requested"; req=false; else (( polls >= 3 )) && sec=true; fi ;;
      *) (( polls >= 3 )) && sec=true ;;
    esac
  fi
  printf '{"locked":%s,"requested":%s,"pending":false,"sessionLocked":%s,"secure":%s,"passwordPam":true}\n' "$req" "$req" "$sec" "$sec"
  exit 0
fi
exit 0
SH
chmod +x "$tmp/bin/"*
[[ $scenario == absent ]] && rm -f "$tmp/bin/omarchy-shell"
mkdir -p "$tmp/state"
start=$(python3 -c 'import time;print(time.time())')
PATH="$tmp/bin:$PATH" CALL_LOG=$log STATE_DIR=$tmp/state SCENARIO=$scenario XDG_RUNTIME_DIR=$tmp \
  timeout -k 5s 40s "$script" >"$tmp/out" 2>"$tmp/err"
rc=$?
el=$(python3 -c "import time;print('%.1f'%(time.time()-$start))")
notif=$(grep -c '^omarchy-notification-send' "$log")
ss=$(grep -c '^pkill -f \[o\]rg.omarchy.screensaver' "$log")
reqs=$(grep -c '^omarchy-shell lock lock' "$log")
printf '%-22s exit=%-3s %5ss  lock-requests=%-2s notification=%s screensaver-closed=%s  stderr=%s\n' "$scenario" "$rc" "$el" "$reqs" "$notif" "$ss" "$(tr '\n' ' ' <"$tmp/err" | cut -c1-110)"
