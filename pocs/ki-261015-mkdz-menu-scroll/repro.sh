#!/bin/bash
# Reproduces: KI-261015-MKDZ
# Menu list moves only a small distance per touchpad scroll gesture.
#
# The menu's ListView (shell/plugins/menu/Menu.qml, resultList) carries no
# wheel handling of its own, so touchpad scroll lands on Qt's default
# Flickable behaviour: each axis event becomes a small kinetic flick instead
# of tracking the finger. The reports ask for travel "consistent with other
# scrollable UIs on the system" — the list should keep up with the finger
# (about 1:1, as GTK, Chromium and foot do), and the accepted fixes scale it
# further (upstream PR #7451: angleDelta.y * 3).
#
# This reproducer opens the real menu plugin in a private headless sway
# session, sends touchpad scroll gestures through the wlr-virtual-pointer
# protocol (axis_source=finger, pixel deltas), and measures how far the
# product's own resultList moves per gesture, read through a read-only
# IpcHandler probe injected into a PRIVATE COPY of Menu.qml (the shipped
# tree is never modified).
#
# Assertion: 8 touchpad axis events of 60 finger-pixels (480 px of finger
# travel) must move the list at least 480 px. The baseline moves far less
# (measured 360 px, 30% short and with weaker streams far worse), so the run
# reports the defect. A fix that tracks or scales the finger (PR #7451's
# WheelHandler, or any 1:1+ scroll handling) moves >= 480 px and the run
# reports the defect absent.
set -u

KI="KI-261015-MKDZ"
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
PROOF_ENV_DIR="${PROOF_ENV_DIR:-$HOME/proof-env}"

setup_fail() {
  echo "SETUP: $*"
  exit 2
}

command -v python3 >/dev/null || setup_fail "python3 is not on PATH"
command -v quickshell >/dev/null || setup_fail "quickshell is not on PATH"
command -v md5sum >/dev/null || setup_fail "md5sum is not on PATH"
command -v timeout >/dev/null || setup_fail "timeout is not on PATH"

SWAY_BIN="$PROOF_ENV_DIR/sysroot/usr/bin/sway"
SWAY_LIB="$PROOF_ENV_DIR/sysroot/usr/lib"
if [[ ! -x $SWAY_BIN ]]; then
  SWAY_BIN=$(command -v sway || true)
  SWAY_LIB=""
fi
[[ -n ${SWAY_BIN:-} ]] || setup_fail "sway not found (set PROOF_ENV_DIR or install sway)"
[[ -f $REPO/test/junit/sway-headless.conf ]] || setup_fail "sway-headless.conf missing from the checkout"
[[ -d $REPO/shell/plugins/menu ]] || setup_fail "shell/plugins/menu missing from the checkout"

CC_BIN=""
for candidate in cc gcc clang; do
  if command -v "$candidate" >/dev/null; then CC_BIN=$candidate; break; fi
done
[[ -n $CC_BIN ]] || setup_fail "no C compiler (cc/gcc/clang) to build the virtual-pointer helper"
[[ -e /usr/include/wayland-client.h ]] || setup_fail "wayland-client headers missing (/usr/include/wayland-client.h)"
$CC_BIN -E -x c - -o /dev/null </dev/null 2>/dev/null || setup_fail "C compiler cannot preprocess: $CC_BIN"

TMPDIR=$(mktemp -d /tmp/ki-261015-mkdz.XXXXXX) || setup_fail "mktemp failed"
RT=""
HP=""
QS_PID=""
cleanup() {
  [[ -n $QS_PID ]] && kill "$QS_PID" 2>/dev/null
  [[ -n $HP ]] && kill "$HP" 2>/dev/null
  wait 2>/dev/null
  rm -rf "$TMPDIR"
}
trap cleanup EXIT

# ------------------------------------------------------------- vptr helper
cp "$REPO/pocs/ki-261015-mkdz-menu-scroll/vptr.c" \
   "$REPO/pocs/ki-261015-mkdz-menu-scroll/wlr-vptr-protocol.c" \
   "$REPO/pocs/ki-261015-mkdz-menu-scroll/wlr-vptr-client-protocol.h" "$TMPDIR/" ||
  setup_fail "virtual-pointer helper sources missing from pocs/ki-261015-mkdz-menu-scroll/"
VPTR="$TMPDIR/vptr"
$CC_BIN -O2 -o "$VPTR" "$TMPDIR/vptr.c" "$TMPDIR/wlr-vptr-protocol.c" -lwayland-client -lm >/dev/null 2>&1 ||
  setup_fail "cannot build the virtual-pointer helper (libwayland-client missing?)"
[[ -x $VPTR ]] || setup_fail "virtual-pointer helper did not build"

# ------------------------------------------------- staged shell + read-only probe
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_root" "$test_home"
cp -a "$REPO/shell" "$test_root/shell" || setup_fail "cannot copy shell/"
ln -s "$REPO/config" "$test_root/config"
mkdir -p "$test_root/bin"
for f in "$REPO"/bin/*; do ln -s "$f" "$test_root/bin/$(basename "$f")"; done

python3 - "$test_root/shell/plugins/menu/Menu.qml" <<'PY' || setup_fail "probe injection failed"
import sys

path = sys.argv[1]
source = open(path).read()
anchor = "  ListModel { id: displayModel }"
assert source.count(anchor) == 1, "injection anchor not unique"

probe = anchor + """

  // TEST-ONLY probe, injected into this private copy of Menu.qml by
  // pocs/ki-261015-mkdz-menu-scroll/repro.sh. Read-only observation of the
  // product's own scroll state; never present in the shipped tree.
  IpcHandler {
    target: "menu-debug"

    function state(): string {
      return JSON.stringify({
        opened: root.opened,
        activeMenu: root.activeMenu,
        rowCount: displayModel.count,
        contentY: resultList.contentY,
        originY: resultList.originY,
        contentHeight: resultList.contentHeight,
        listHeight: resultList.height,
        cardX: card.x, cardY: card.y, cardW: card.width, cardH: card.height,
        listInCardX: resultList.mapToItem(card, 0, 0).x,
        listInCardY: resultList.mapToItem(card, 0, 0).y
      })
    }
  }
"""
open(path, "w").write(source.replace(anchor, probe))
PY

# One long submenu: 60 rows of menu items, so the list scrolls.
menu_dir="$test_home/.config/omarchy/extensions"
mkdir -p "$menu_dir"
{
  echo '{'
  echo '  "long": {"label":"Long"},'
  for i in $(seq -w 1 60); do
    printf '  "long.r%s": {"label":"Row%s","action":"true"},\n' "$i" "$i"
  done
  echo '}'
} >"$menu_dir/omarchy-menu.jsonc"

# --------------------------------------------------------------- live session
RT=$(mktemp -d /tmp/ki-261015-mkdz-rt.XXXXXX) || setup_fail "mktemp failed"
chmod 700 "$RT"
env -i \
  LD_LIBRARY_PATH="$SWAY_LIB" \
  XDG_RUNTIME_DIR="$RT" \
  HOME="$HOME" \
  WLR_BACKENDS=headless \
  WLR_RENDERER=pixman \
  WLR_LIBINPUT_NO_DEVICES=1 \
  PATH="/usr/local/sbin:/usr/local/bin:/usr/bin" \
  "$SWAY_BIN" -c "$REPO/test/junit/sway-headless.conf" >"$RT/sway.log" 2>&1 &
HP=$!
WAY=""
for _ in $(seq 1 120); do
  WAY=$(cd "$RT" && ls wayland-[0-9] 2>/dev/null | head -1)
  [[ -n $WAY && -S $RT/$WAY ]] && break
  kill -0 "$HP" 2>/dev/null || break
  sleep 0.25
done
[[ -n ${WAY:-} ]] || setup_fail "private headless sway did not start"
export XDG_RUNTIME_DIR="$RT" WAYLAND_DISPLAY="$WAY"
export SWAYSOCK
SWAYSOCK=$(ls "$RT"/sway-ipc.*.sock 2>/dev/null | head -1)

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
XDG_DATA_HOME="$test_home/.local/share" \
XDG_DATA_DIRS="$test_home/xdg-data-dirs" \
PATH="$REPO/bin:$PATH" \
QT_QPA_PLATFORM=wayland \
QT_QUICK_BACKEND=software \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

shell_ipc() {
  OMARCHY_PATH="$test_root" PATH="$REPO/bin:$PATH" HOME="$test_home" \
    "$REPO/bin/omarchy-shell" "$@"
}
state() { shell_ipc menu-debug state 2>/dev/null; }

for _ in $(seq 1 80); do
  shell_ipc -q shell ping >/dev/null 2>&1 && break
  kill -0 "$QS_PID" 2>/dev/null || { tail -20 "$log"; setup_fail "quickshell exited before IPC came up"; }
  sleep 0.1
done

socket_id=$(printf '%s\n%s' "$test_root/shell" "$WAYLAND_DISPLAY" | md5sum)
socket="$XDG_RUNTIME_DIR/omarchy-shell-${socket_id:0:16}.sock"

# The menu plugin and its user extension load asynchronously: wait until the
# root menu shows the fixture entry before summoning its submenu.
ready=0
for _ in $(seq 1 80); do
  rm -f "$socket"
  shell_ipc shell summon omarchy.menu '{"menu":"root"}' >/dev/null 2>&1 || true
  sleep 0.3
  s=$(state)
  if [[ -n $s ]] && echo "$s" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d.get('opened') and d.get('rowCount', 0) >= 1 else 1)
" 2>/dev/null; then
    ready=1
    break
  fi
done
[[ $ready == 1 ]] || { tail -20 "$log"; setup_fail "menu plugin probe never answered"; }

opened=0
for _ in $(seq 1 20); do
  rm -f "$socket"
  shell_ipc shell summon omarchy.menu '{"menu":"long"}' >/dev/null 2>&1 || true
  sleep 0.4
  s=$(state)
  if [[ -n $s ]] && echo "$s" | python3 -c "
import json, sys
d = json.load(sys.stdin)
sys.exit(0 if d.get('activeMenu') == 'long' and d.get('rowCount', 0) >= 40 else 1)
" 2>/dev/null; then
    opened=1
    break
  fi
done
[[ $opened == 1 ]] || { tail -20 "$log"; setup_fail "could not open the long submenu"; }

# --------------------------------------------------------------- the measurement
read_state() { state | python3 -c "import json,sys; print(json.dumps(json.load(sys.stdin)))"; }
s0=$(read_state) || setup_fail "menu-debug state is not readable"
geom=$(echo "$s0" | python3 -c "
import json, sys
d = json.load(sys.stdin)
lx = d['cardX'] + d['listInCardX']
ly = d['cardY'] + d['listInCardY']
lw = d['cardW'] - 2 * d['listInCardX']
lh = d['listHeight']
print('%d %d %d %d' % (lx + lw / 2, ly + lh / 2, d['contentHeight'], d['listHeight']))
")
read -r px py content_h list_h <<<"$geom"
(( content_h > list_h + 600 )) || setup_fail "menu list is too short to scroll (content=$content_h list=$list_h)"

# The headless output is 1920x1080 (test/junit/sway-headless.conf): map the
# list centre to the virtual pointer's 0..65535 absolute frame.
mx=$(( px * 65535 / 1920 ))
my=$(( py * 65535 / 1080 ))
"$VPTR" move "$mx" "$my" >/dev/null 2>&1 || setup_fail "virtual pointer motion failed"
sleep 0.3

# One touchpad gesture stream: 8 axis events of 60 finger-pixels each, the
# shape a two-finger swipe produces in small frames. Total finger travel:
# 480 px. The helper warm-up runs inside the same device lifetime.
"$VPTR" scroll finger 60 3 8 80 >/dev/null 2>&1 || setup_fail "virtual pointer scroll failed"
sleep 1.5

s1=$(read_state) || setup_fail "menu-debug state is not readable after scrolling"
travel=$(printf '%s\n%s\n' "$s0" "$s1" | python3 -c "
import json, sys
a = json.loads(sys.stdin.readline())
b = json.loads(sys.stdin.readline())
print('%d' % round(b['contentY'] - a['contentY']))
")

# The reports' expectation: travel consistent with other scrollable UIs on
# the system — the list keeps up with the finger (1:1). Accepted fixes go
# further (upstream PR #7451 scales the wheel delta by 3).
expected=480
echo "touchpad stream: 8 events x 60 finger-px = 480 px of finger travel"
echo "list travel: ${travel}px (expect >= ${expected}px)"
if (( travel >= expected )); then
  echo "PROOF-REPRODUCER: defect-absent $KI"
  exit 0
fi
echo "PROOF-REPRODUCER: defect-present $KI"
exit 1
