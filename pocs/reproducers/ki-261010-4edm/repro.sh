#!/bin/bash
# Reproduces: KI-261010-4EDM
#
# Shell segfaults in the QML engine while a menu filter keystroke rebuilds
# displayModel (draft R-1791#menu-filter-typing-qml-sigsegv). Correct
# behaviour, from SYS-REQ-260922-V7W6 ("A filter query narrows to visible,
# selectable rows whose name or description matches every term, ranked by
# match quality"): typing into the open omarchy-menu search box filters the
# list and the shell stays up.
#
# The defect is INTERMITTENT (the draft: "Not every keystroke crashes"; the
# anchor saw it twice in one session, a commenter six times in a week, and a
# prior stress ran ~15,000 filter rebuilds without a crash). This driver
# repeats the exact reported trigger in a private headless session -- a
# printable keystroke in the open menu -> Keys.onPressed -> setFilter ->
# rebuildDisplay() -> displayModel.clear() + a loop of displayModel.append(row)
# while the visibleRowsHeight binding re-evaluates on every append -- and
# watches the shell for the reported SIGSEGV.
#
# Oracle. The defect is observed only when the shell dies of SIGSEGV (its
# crash handler writes ~/.cache/quickshell/crashes/<run>/report.txt and
# re-raises) while that trigger is being driven: PROOF-REPRODUCER:
# defect-present KI-261010-4EDM. A completed stress that never takes the shell
# down is this run's defect-absent answer (the shell filtered correctly every
# time the trigger ran); how far that reaches for a fault the draft itself
# calls intermittent is the promotion decision's call, not this marker's.
# Harness failures (missing tools, no session, shell that never answers) are
# SETUP: lines and exit 2 (setupFailureExitCode).
set -u

KI="KI-261010-4EDM"
ROOT=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/../../.." && pwd)
REPRO="pocs/reproducers/ki-261010-4edm/repro.sh"

# Run budget. REPRO_STRESS_SECONDS bounds the stress; REPRO_ROUNDS bounds the
# number of filter rebuilds driven (each keystroke is one rebuild). Defaults
# are sized for the engine's 600s rerun window: session start ~5s + stress.
STRESS_SECONDS=${REPRO_STRESS_SECONDS:-240}
ROUNDS=${REPRO_ROUNDS:-600}

PROOF_ENV_DIR=${PROOF_ENV_DIR:-$HOME/proof-env}
if [ -d "$PROOF_ENV_DIR/bin" ]; then
  PATH="$PROOF_ENV_DIR/bin:$PATH"
fi
if [ -d "$PROOF_ENV_DIR/sysroot/usr/bin" ]; then
  PATH="$PROOF_ENV_DIR/sysroot/usr/bin:$PATH"
fi
export PATH

setup_fail() {
  echo "SETUP: $*"
  exit 2
}

command -v quickshell >/dev/null || setup_fail "quickshell is not on PATH"
command -v wtype >/dev/null || setup_fail "wtype is not on PATH"
command -v socat >/dev/null || setup_fail "socat is not on PATH"
command -v md5sum >/dev/null || setup_fail "md5sum is not on PATH"
command -v timeout >/dev/null || setup_fail "timeout is not on PATH"
[ -f "$ROOT/shell/shell.qml" ] || setup_fail "shell/shell.qml missing under $ROOT"
[ -f "$ROOT/default/omarchy/omarchy-menu.jsonc" ] || setup_fail "default menu jsonc missing under $ROOT"
[ -x "$ROOT/bin/omarchy-shell" ] || setup_fail "bin/omarchy-shell missing under $ROOT"

SWAY_BIN=""
SWAY_LIB=""
if [ -x "$PROOF_ENV_DIR/sysroot/usr/bin/sway" ]; then
  SWAY_BIN="$PROOF_ENV_DIR/sysroot/usr/bin/sway"
  SWAY_LIB="$PROOF_ENV_DIR/sysroot/usr/lib"
elif command -v sway >/dev/null; then
  SWAY_BIN=$(command -v sway)
fi
[ -n "$SWAY_BIN" ] || setup_fail "sway is not installed (see test/junit/live-session.sh prerequisites)"

RT=$(mktemp -d /tmp/ki-261010-4edm-rt.XXXXXX) || setup_fail "cannot create a runtime dir"
chmod 700 "$RT"
HOMEDIR=$(mktemp -d /tmp/ki-261010-4edm-home.XXXXXX) || setup_fail "cannot create a home dir"
LOG="$RT/quickshell.log"
KEYS=0
SWAY_PID=""
QS_PID=""

cleanup() {
  trap '' TERM INT
  [ -n "${QS_PID:-}" ] && kill -TERM "$QS_PID" 2>/dev/null
  [ -n "${SWAY_PID:-}" ] && kill -TERM "$SWAY_PID" 2>/dev/null
  for _ in 1 2 3 4 5 6 7 8 9 10; do
    if { [ -z "${QS_PID:-}" ] || ! kill -0 "$QS_PID" 2>/dev/null; } && \
       { [ -z "${SWAY_PID:-}" ] || ! kill -0 "$SWAY_PID" 2>/dev/null; }; then
      break
    fi
    sleep 0.2
  done
  [ -n "${QS_PID:-}" ] && kill -KILL "$QS_PID" 2>/dev/null
  [ -n "${SWAY_PID:-}" ] && kill -KILL "$SWAY_PID" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$RT" "$HOMEDIR"
}
trap 'exit 143' TERM INT
trap cleanup EXIT

# ---------------------------------------------------------------- session
cat >"$RT/sway.conf" <<'CONF'
xwayland disable
output HEADLESS-1 resolution 1920x1080 position 0,0
bar {
  mode invisible
}
default_border none
CONF

# The reports crashed with hardware GPU rendering (the anchor: hybrid AMD
# Radeon 780M + Intel i915, amdgpu/i915). Run the same class of rendering when
# the box has a GPU: WLR_RENDERER=gles2 lets clients use OpenGL/EGL. Fall back
# to the project's pixman/software recipe (test/junit/live-session.sh) when no
# GL renderer can be created. Which path ran is printed below and is what the
# promotion record's environmentMatch describes.
RENDER_MODE="hardware-gl (WLR_RENDERER=gles2)"
QT_RENDER_ARGS=""
start_sway() {
  env -i \
    LD_LIBRARY_PATH="$SWAY_LIB" \
    XDG_RUNTIME_DIR="$RT" \
    HOME="$HOMEDIR" \
    WLR_BACKENDS=headless \
    WLR_RENDERER="$1" \
    WLR_LIBINPUT_NO_DEVICES=1 \
    PATH="/usr/local/sbin:/usr/local/bin:/usr/bin" \
    "$SWAY_BIN" -c "$RT/sway.conf" >"$RT/sway.log" 2>&1 &
  SWAY_PID=$!
  WAY=""
  for _ in $(seq 1 100); do
    WAY=$(cd "$RT" && ls wayland-* 2>/dev/null | grep -v '\.lock$' | head -1)
    [ -n "$WAY" ] && return 0
    kill -0 "$SWAY_PID" 2>/dev/null || return 1
    sleep 0.2
  done
  return 1
}

if ! start_sway gles2; then
  kill "$SWAY_PID" 2>/dev/null
  wait "$SWAY_PID" 2>/dev/null
  SWAY_PID=""
  RENDER_MODE="software (WLR_RENDERER=pixman, QT_QUICK_BACKEND=software)"
  QT_RENDER_ARGS="QT_QUICK_BACKEND=software"
  if ! start_sway pixman; then
    echo "SETUP: private headless sway did not come up"
    sed -n '1,20p' "$RT/sway.log"
    exit 2
  fi
fi

export WAYLAND_DISPLAY=$WAY
export XDG_RUNTIME_DIR=$RT

# ---------------------------------------------------------------- shell
# The shipped shell and the shipped default menu (OMARCHY_PATH is the
# checkout): the exact tree the reports crashed in, no user extension file.
OMARCHY_PATH="$ROOT" \
HOME="$HOMEDIR" \
XDG_CONFIG_HOME="$HOMEDIR/.config" \
XDG_CACHE_HOME="$HOMEDIR/.cache" \
XDG_STATE_HOME="$HOMEDIR/.local/state" \
XDG_DATA_HOME="$HOMEDIR/.local/share" \
XDG_DATA_DIRS="$HOMEDIR/.local/share" \
PATH="$ROOT/bin:$PATH" \
  env $QT_RENDER_ARGS quickshell -p "$ROOT/shell/shell.qml" --no-color >"$LOG" 2>&1 &
QS_PID=$!

for _ in $(seq 1 100); do
  kill -0 "$QS_PID" 2>/dev/null || break
  if OMARCHY_PATH="$ROOT" HOME="$HOMEDIR" "$ROOT/bin/omarchy-shell" -q shell ping >/dev/null 2>&1; then
    break
  fi
  sleep 0.2
done
if ! kill -0 "$QS_PID" 2>/dev/null; then
  echo "SETUP: quickshell exited before answering IPC"
  sed -n '1,40p' "$LOG"
  exit 2
fi

summon_root() {
  local i out
  for i in 1 2 3 4 5 6 7 8 9 10; do
    out=$(timeout 2 env OMARCHY_PATH="$ROOT" HOME="$HOMEDIR" "$ROOT/bin/omarchy-shell" shell summon omarchy.menu '{"menu":"root"}' 2>/dev/null || true)
    if [ "$out" = "ok" ]; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

summon_root || {
  echo "SETUP: omarchy-menu did not summon"
  sed -n '1,40p' "$LOG"
  exit 2
}
sleep 0.6  # let the layer surface take keyboard focus before keys fly

# ---------------------------------------------------------------- oracle
# SIGSEGV witness: a quickshell crash report naming a segmentation fault, or
# the shell process dead with signal 11. Anything else that kills the shell is
# reported as inconclusive (the harness, not the defect).
crash_report_text() {
  cat "$HOMEDIR"/.cache/quickshell/crashes/*/report.txt 2>/dev/null || true
}

shell_died=0
shell_death=""
observe() {
  if kill -0 "$QS_PID" 2>/dev/null; then
    return 1
  fi
  shell_died=1
  wait "$QS_PID" 2>/dev/null
  shell_death=$?
  QS_PID=""
  return 0
}

verdict_present() {
  echo "quickshell death: ${shell_death:-unknown}; crash report follows"
  crash_report_text
  echo "PROOF-REPRODUCER: defect-present $KI"
  exit 1
}

# ---------------------------------------------------------------- stress
# Each printable keystroke in the open menu is one filter rebuild: setFilter ->
# rebuildDisplay() -> displayModel.clear() + displayModel.append(row) per
# matching row, with the visibleRowsHeight binding re-evaluating on every
# append (rowListHeight -> displayModel.get(i) -> row.section === "drilldown").
# One-char queries match the widest slice of the shipped menu (current rows
# plus drilldown rows, so the "drilldown" string compare runs too); BackSpace
# takes the filter back to empty and rebuilds again. Varying the character
# keeps the compared strings fresh, so the faulting createHashValue path
# (hashing a string for the first time) is walked on every compare.
CHARS="eaonsritldcumhpgybfvkwxqjz"
started=$(date +%s)
round=0
while [ "$round" -lt "$ROUNDS" ]; do
  now=$(date +%s)
  if [ $((now - started)) -ge "$STRESS_SECONDS" ]; then
    break
  fi
  if observe; then
    verdict_present
  fi
  c=${CHARS:$((round % ${#CHARS})):1}
  # One wtype process per burst (the virtual keyboard appears once and the
  # compositor settles seat focus during its leading sleep); the no-op Shift_L
  # primes the seat so the first meaningful key is not the one dropped.
  if [ $((round % 2)) -eq 0 ]; then
    args=(-s 200 -k Shift_L -d 12)
    for _ in 1 2 3 4 5 6 7 8; do
      args+=(-k "$c" -d 12 -k BackSpace -d 12)
      KEYS=$((KEYS + 2))
    done
    timeout 30 wtype "${args[@]}" 2>/dev/null || true
  else
    args=(-s 200 -k Shift_L -d 12)
    for _ in 1 2 3 4 5 6 7 8; do
      args+=(-k "$c" -d 12 -k "$c" -d 12 -k BackSpace -d 12 -k BackSpace -d 12)
      KEYS=$((KEYS + 4))
    done
    timeout 30 wtype "${args[@]}" 2>/dev/null || true
  fi
  # Re-open every 20 rounds: both reports crashed right after the menu opened,
  # so keep re-hitting that window and reset any dropped-key filter drift. A
  # menu that cannot be brought back means the rest of the stress would type
  # into nothing, so the stress ends there with what it has.
  if [ $((round % 20)) -eq 19 ]; then
    timeout 2 env OMARCHY_PATH="$ROOT" HOME="$HOMEDIR" "$ROOT/bin/omarchy-shell" -q shell hide omarchy.menu >/dev/null 2>&1
    sleep 0.3
    if ! summon_root; then
      echo "menu could not be re-summoned at round $round; ending the stress"
      break
    fi
    sleep 0.3
  fi
  round=$((round + 1))
  if [ $((round % 5)) -eq 0 ]; then
    echo "progress: round=$round elapsed=$(( $(date +%s) - started ))s keystrokes=$KEYS"
  fi
  sleep 0.1
done

# Final observation window: a crash report can land just after the last key.
for _ in 1 2 3 4 5 6 7 8 9 10; do
  if observe; then
    verdict_present
  fi
  sleep 0.2
done

if [ "$shell_died" -eq 1 ]; then
  echo "quickshell died without the SIGSEGV witness (death=$shell_death)"
  crash_report_text
  echo "PROOF-REPRODUCER: inconclusive $KI harness-shell-death-without-sigsegv-witness"
  exit 0
fi

report=$(crash_report_text)
if [ -n "$report" ]; then
  verdict_present
fi

echo "stress complete: rounds=$round keystrokes=$KEYS in $(( $(date +%s) - started ))s on $RENDER_MODE; quickshell still alive (pid $QS_PID); no crash report under $HOMEDIR/.cache/quickshell/crashes"
echo "PROOF-REPRODUCER: defect-absent $KI no-sigsegv-in-$KEYS-filter-keystrokes"
exit 0
