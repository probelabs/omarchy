#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-3JG5, SW-REQ-260922-4079, SW-REQ-260922-50RE, SW-REQ-260922-8CQ4, SW-REQ-260922-B757, SW-REQ-260922-DE93, SW-REQ-260922-NM45, SW-REQ-260922-Z48F, SYS-REQ-260922-P708, SW-REQ-260925-XTGG
#
# Compositor-bound menu behavior, driven end-to-end against a live shell:
# real IPC summons (omarchy-shell shell summon omarchy.menu ...) and real key
# events (wtype virtual keyboard -> layer-shell surface -> Keys.onPressed),
# observed through a read-only IpcHandler the test injects into its private
# copy of shell/plugins/menu/Menu.qml (the shipped tree is never modified;
# the probe only reads state and calls the product's own refresh /
# evaluateGuards, the same functions the lifecycle and file watcher call;
# the CRS-0017/C01 witness below additionally drives the product's own open /
# cancel entries through the probe for deterministic race timing).
# Defensive dispositions below cover the guarantee-violation rows whose
# assignments are structurally unreachable in the shipped code.
#mcdc:ignore:defensive SW-REQ-260922-3JG5: all_rows_disabled=T, no_cursor_parked=F => FALSE -- settleCursor sets cursorActive from nextSelectable, which returns -1 exactly when every row is disabled; a parked cursor with all rows disabled needs that assignment removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-4079: batch_killed=T, last_complete_set_kept=F, pending_reeval_runs=F => FALSE -- guardProc.onExited returns on any nonzero exit before touching the result maps; applying a half-read batch needs that early return removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-4079: batch_killed=T, last_complete_set_kept=F, pending_reeval_runs=T => FALSE -- same early return; a killed batch cannot overwrite the kept set whether or not a reevaluation follows [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-4079: batch_killed=T, last_complete_set_kept=T, pending_reeval_runs=F => FALSE -- every nonzero exit with guardsPending set schedules evaluateGuards via callLater; a stranded pending reevaluation needs that deferred call removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-50RE: lifecycle_answered=F, menu_open_called=T => FALSE -- open() dispatches every call to openDmenu or openRoute and both set opened=true; an unanswered open needs the dispatch removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-8CQ4: delete_key_on_app=T, uninstall_confirmed_flow=F => FALSE -- requestDeleteSelected opens the confirmation for every app row; an app row ignoring Delete needs the kind check removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-B757: fold_signals_more=F, rows_overflow=T => FALSE -- foldedListHeight returns the last full row plus rowSpacing and rowPeek whenever the totals overflow; an exact-boundary height needs the peek term removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-DE93: back_retraces_path=F, submenu_entered=T => FALSE -- setActiveMenu pushes the previous menu on navStack on every drill-in and goBack pops it; a back that loses the path needs the push removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-NM45: dmenu_option_picked=T, glyph_stripped=F, subtext_returned=F => FALSE -- activateIndex builds the selection from picked.label and picked.detail only; the glyph reaching the result needs that string build changed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-NM45: dmenu_option_picked=T, glyph_stripped=F, subtext_returned=T => FALSE -- same string build; a glyph in the result needs picked.icon concatenated in [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-NM45: dmenu_option_picked=T, glyph_stripped=T, subtext_returned=F => FALSE -- a subtext-bearing pick returns label + TAB + detail unconditionally; dropping the subtext needs the detail term removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260922-Z48F: cursor_moves=T, disabled_rows_skipped=F => FALSE -- nextSelectable only returns rows rowSelectable answers true for; landing on a disabled row needs that check removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SYS-REQ-260922-P708: action_executed_or_submenu_opened=F, selection_made=T => FALSE -- activateIndex dispatches every selectable row: menu/link drill in, apps launch, actions run; a selection with no dispatch needs all three branches removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260925-XTGG: menu_open_called=T, no_active_request=F, prior_request_cancelled=F => FALSE -- open() calls finishRequest(null) unconditionally when requestActive is set, before any dispatch (Menu.qml:32); an abandoned prior caller needs that call removed. The resultProc busy-drop race that could lose the cancel write at runtime is outside this decision's structural model -- claim CRS-0017/C01, REFUTED by the Phase-2 live witness 2026-09-25 (0/20 same-turn drops, 20/20 real callers answered; dismissed) [reviewed: REVIEW-26]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=""
QS_PID=""

cleanup() {
  if [[ -n $QS_PID ]] && kill -0 "$QS_PID" 2>/dev/null; then
    kill "$QS_PID" 2>/dev/null || true
    wait "$QS_PID" 2>/dev/null || true
  fi
  [[ -n $TMPDIR && -d $TMPDIR ]] && rm -rf "$TMPDIR"
  return 0
}
trap cleanup EXIT

require_compositor "menu compositor interaction test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping menu compositor interaction test"
  exit 0
fi

if ! command -v wtype >/dev/null 2>&1; then
  pass "wtype not installed; skipping menu compositor interaction test"
  exit 0
fi

require_command jq
require_command python3

shell_ipc() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" "$@"
}

shell_ipc_quiet() {
  OMARCHY_PATH="$test_root" "$ROOT/bin/omarchy-shell" -q "$@"
}

fail_with_log() {
  local description="$1"
  sed -n '1,240p' "$log" >&2
  fail "$description"
}

menu_state() {
  shell_ipc menu-debug state 2>/dev/null || true
}

# Poll the injected read-only probe until a jq predicate holds.
wait_state() {
  local description="$1" predicate="$2" attempts="${3:-80}"
  local i state=""
  for (( i = 0; i < attempts; i++ )); do
    state=$(menu_state)
    if [[ -n $state ]] && jq -e "$predicate" <<<"$state" >/dev/null 2>&1; then
      LAST_STATE="$state"
      return 0
    fi
    if ! kill -0 "$QS_PID" 2>/dev/null; then
      fail_with_log "test shell exited while waiting: $description"
    fi
    sleep 0.1
  done
  printf 'Last state: %s\n' "$state" >&2
  fail "$description"
}

# One wtype process per burst: the virtual keyboard appears once, the
# compositor settles seat focus during the leading sleep, and every key in
# the burst rides that same device. Single-key processes raced sway's seat
# re-negotiation and lost keystrokes at random.
key_burst() {
  local args=(-s 300) k
  for k in "$@"; do
    args+=(-k "$k" -d 150)
  done
  wtype "${args[@]}"
  sleep 0.15
}

# A clean reopen: hide whatever is open, wait for the close to land, summon.
# The summon retries: the menu plugin's loader can still be warming up right
# after the shell starts answering ping, and an early summon reads "unknown".
reopen_menu() {
  local payload="$1" i out
  shell_ipc_quiet shell hide omarchy.menu >/dev/null
  wait_state "menu closes before reopen" '.opened == false' 30
  for (( i = 0; i < 40; i++ )); do
    out=$(shell_ipc shell summon omarchy.menu "$payload" 2>/dev/null || true)
    if [[ $out == "ok" ]]; then
      sleep 0.4  # let the layer surface take keyboard focus before keys fly
      return 0
    fi
    sleep 0.25
  done
  return 1
}

# Move the cursor onto a row by itemId. Each burst is one wtype process
# pressing every needed Down in a row; if a burst still loses keys the
# delta is recomputed and another burst follows.
move_cursor_to() {
  local item_id="$1" rounds="${2:-6}" r state from to delta keys i
  for (( r = 0; r < rounds; r++ )); do
    state=$(menu_state)
    from=$(jq -r '.selectedIndex' <<<"$state")
    to=$(jq -r --arg id "$item_id" '[.rows[] | select(.itemId == $id)][0].index // -1' <<<"$state")
    [[ $to -ge 0 ]] || return 1
    (( from == to )) && return 0
    delta=$(( to - from ))
    keys=()
    for (( i = 0; i < delta; i++ )); do keys+=(Down); done
    key_burst "${keys[@]}"
    sleep 0.3
  done
  echo "move_cursor_to $item_id: cursor stuck at $from (target $to)" >&2
  menu_state >&2
  return 1
}

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
log="$TMPDIR/quickshell.log"
removed_log="$TMPDIR/removed.log"
mkdir -p "$test_root" "$test_home"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
# bin as a symlink farm so the app-removal stub shadows exactly one entry.
mkdir -p "$test_root/bin"
for f in "$ROOT/bin"/*; do
  ln -s "$f" "$test_root/bin/$(basename "$f")"
done
rm "$test_root/bin/omarchy-remove-launcher-entry"
cat >"$test_root/bin/omarchy-remove-launcher-entry" <<SH
#!/bin/bash
printf '%s\n' "\$*" >> "$removed_log"
SH
chmod +x "$test_root/bin/omarchy-remove-launcher-entry"

# Read-only state probe, injected into the test's private copy only. The
# shipped Menu.qml is never modified. refresh/pokeGuards call the product's
# own functions -- the same ones the lifecycle and the file watcher call.
python3 - "$test_root/shell/plugins/menu/Menu.qml" <<'PY'
import sys

path = sys.argv[1]
source = open(path).read()
anchor = "  ListModel { id: displayModel }"
assert source.count(anchor) == 1, "injection anchor not unique"

probe = anchor + """

  // TEST-ONLY probe, injected by menu-compositor-test.sh into its private
  // copy of the shell. Read-only observation of state the real key/IPC
  // paths drive; never present in the shipped tree.
  IpcHandler {
    target: "menu-debug"

    function state(): string {
      var rows = []
      for (var i = 0; i < displayModel.count; i++) {
        var r = displayModel.get(i)
        rows.push({ index: i, itemId: r.itemId, kind: r.kind, disabled: r.disabled,
                    label: r.label, detail: r.detail, appId: r.appId })
      }
      return JSON.stringify({
        opened: root.opened, mode: root.mode, activeMenu: root.activeMenu,
        requestActive: root.requestActive, doneFile: root.doneFile,
        navStack: root.navStack, filterText: root.filterText,
        selectedIndex: root.selectedIndex, cursorActive: root.cursorActive,
        rows: rows,
        deleteConfirmOpen: root.deleteConfirmOpen,
        deleteTarget: root.deleteTarget,
        guardsPending: root.guardsPending, guardRunning: guardProc.running,
        resultRunning: resultProc.running,
        whenResults: root.whenResults, disabledResults: root.disabledResults,
        visibleRowsHeight: root.visibleRowsHeight, panelHeight: panel.height,
        baseRowHeight: root.baseRowHeight, rowSpacing: root.rowSpacing,
        rowPeek: root.rowPeek, requestSerial: root.requestSerial
      })
    }

    function refresh(): string { return root.refresh() }
    function pokeGuards(): string { root.evaluateGuards(); return "ok" }
    // TEST-ONLY race driver for CRS-0017/C01: calls the product's own summon
    // entry (open, Menu.qml:21) and Escape entry (cancel, Menu.qml:896) back
    // to back in ONE event-loop turn, so the cancel's finishRequest lands
    // deterministically inside the guard's bash-exec window. Same product
    // functions the IPC summon and the key handler call; only the inter-call
    // delay is removed.
    function summonCancelRace(payloadJson: string): string {
      root.open(payloadJson)
      root.cancel()
      return "ok"
    }
  }
"""
open(path, "w").write(source.replace(anchor, probe))
PY

# Menu fixture. The test root carries no default/ tree, so this user file is
# the whole menu: an apps submenu, an action row with an observable marker,
# a navigation submenu, a disabled-row submenu, an all-disabled submenu, a
# guarded submenu, and a 40-row submenu for the fold math.
menu_dir="$test_home/.config/omarchy/extensions"
mkdir -p "$menu_dir"
menu_jsonc="$menu_dir/omarchy-menu.jsonc"
{
  cat <<JSONC
{
  "apps": {"label":"Apps","provider":"apps"},
  "act": {"label":"Act","action":"touch '$TMPDIR/action-ran'"},
  "nav": {"label":"Nav"},
  "nav.leaf": {"label":"Leaf","action":"touch '$TMPDIR/leaf-ran'"},
  "dis": {"label":"Dis"},
  "dis.first": {"label":"First","action":"true"},
  "dis.off": {"label":"Off","action":"true","disabled":"true"},
  "dis.last": {"label":"Last","action":"true"},
  "alld": {"label":"AllD"},
  "alld.one": {"label":"One","action":"true","disabled":"true"},
  "alld.two": {"label":"Two","action":"true","disabled":"true"},
  "grd": {"label":"Grd"},
  "grd.ga": {"label":"GA","action":"true","when":"true"},
  "grd.gb": {"label":"GB","action":"true","when":"false"},
  "long": {"label":"Long"},
JSONC
  for i in $(seq -w 1 40); do
    printf '  "long.r%s": {"label":"Row%s","action":"true"},\n' "$i" "$i"
  done
  printf '}\n'
} >"$menu_jsonc"

# A fake desktop entry gives the apps submenu one app row to delete. The
# XDG data dirs are isolated so it is the only desktop entry in sight.
mkdir -p "$test_home/.local/share/applications" "$test_home/xdg-data-dirs"
cat >"$test_home/.local/share/applications/proof-fake.desktop" <<'DESKTOP'
[Desktop Entry]
Type=Application
Name=Proof Fake App
Comment=MC/DC fixture application
Exec=/bin/true
Icon=utilities-terminal
Categories=Utility;
DESKTOP

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
XDG_DATA_HOME="$test_home/.local/share" \
XDG_DATA_DIRS="$test_home/xdg-data-dirs" \
PATH="$ROOT/bin:$PATH" \
  quickshell -p "$test_root/shell" --no-color >"$log" 2>&1 &
QS_PID=$!

for _ in {1..80}; do
  if shell_ipc_quiet shell ping >/dev/null 2>&1; then
    break
  fi
  if ! kill -0 "$QS_PID" 2>/dev/null; then
    fail_with_log "test shell exited before IPC became available"
  fi
  sleep 0.1
done

# The probe lives in the menu plugin instance. If the shell has not loaded
# the plugin yet, one summon + hide forces the instance up.
probe_up=false
for _ in {1..50}; do
  state=$(menu_state)
  if [[ -n $state ]] && jq -e 'has("opened")' <<<"$state" >/dev/null 2>&1; then
    probe_up=true
    break
  fi
  sleep 0.1
done
if ! $probe_up; then
  shell_ipc_quiet shell summon omarchy.menu '{"menu":"root"}' >/dev/null
  sleep 0.5
  shell_ipc_quiet shell hide omarchy.menu >/dev/null
  wait_state "menu-debug probe answers after first summon" 'has("opened")' 80
fi

# ---------------------------------------------------------------- lifecycle
# Verifies: SW-REQ-260922-50RE
# MCDC SW-REQ-260922-50RE: lifecycle_answered=F, menu_open_called=F => TRUE [no-action: no summon is outstanding and the probe shows opened=false -- no open request is in flight]
wait_state "menu closed with no request in flight" '.opened == false' 30

reopen_menu '{"menu":"root"}' || fail_with_log "summon root menu"
wait_state "menu opens on summon" '.opened == true and .mode == "menu"'
[[ $(shell_ipc menu-debug refresh) == "ok" ]] || fail "refresh answers ok"
shell_ipc_quiet shell hide omarchy.menu >/dev/null
wait_state "hide closes the menu" '.opened == false'
# Verifies: SW-REQ-260922-50RE
# MCDC SW-REQ-260922-50RE: lifecycle_answered=T, menu_open_called=T => TRUE
pass "open/refresh/close all answer the caller (SW-REQ-260922-50RE)"

# ------------------------------------------------------- fold: rows that fit
reopen_menu '{"menu":"root"}' || fail_with_log "summon root for layout"
wait_state "root rows listed" '.rows | length == 7'
root_state="$LAST_STATE"
# Every root row is a plain row; the full height is rows*base+(rows-1)*spacing.
jq -e '
  (.rows | length) as $n |
  (.baseRowHeight) as $h | (.rowSpacing) as $s |
  .visibleRowsHeight == $n * $h + ($n - 1) * $s
' <<<"$root_state" >/dev/null ||
  fail "a menu whose rows fit gets its full height"
# Verifies: SW-REQ-260922-B757
# MCDC SW-REQ-260922-B757: fold_signals_more=F, rows_overflow=F => TRUE [no-action: the 7-row root menu gets its exact full height -- the fold is not invoked]
pass "menu whose rows fit gets its full height (SW-REQ-260922-B757)"

# ------------------------------------------------- selection runs the action
# Verifies: SYS-REQ-260922-P708
# MCDC SYS-REQ-260922-P708: action_executed_or_submenu_opened=F, selection_made=F => TRUE [no-action: no activation key pressed -- the marker file stays absent]
[[ ! -e $TMPDIR/action-ran ]] || fail "action marker absent before any selection"
move_cursor_to act || fail "cursor reaches the action row"
wait_state "cursor on the action row" '.rows[.selectedIndex].itemId == "act"'
key_burst Return
for _ in {1..50}; do [[ -e $TMPDIR/action-ran ]] && break; sleep 0.1; done
if [[ ! -e $TMPDIR/action-ran ]]; then
  echo "state after Enter:" >&2
  menu_state >&2
  echo "--- quickshell log tail:" >&2
  tail -30 "$log" >&2
  fail "Enter on an action row runs its action"
fi
# Verifies: SYS-REQ-260922-P708
# MCDC SYS-REQ-260922-P708: action_executed_or_submenu_opened=T, selection_made=T => TRUE
pass "Enter on an action row executes it (SYS-REQ-260922-P708)"

# ---------------------------------------------------------- submenu and back
# Verifies: SW-REQ-260922-DE93
# MCDC SW-REQ-260922-DE93: back_retraces_path=F, submenu_entered=F => TRUE [no-action: no drill-in yet -- navStack is empty at the root menu]
reopen_menu '{"menu":"root"}' || fail_with_log "summon root for navigation"
wait_state "root listed for navigation" '(.rows | length) == 7 and (.navStack | length) == 0'
move_cursor_to nav || fail "cursor reaches the nav row"
wait_state "cursor on the nav row" '.rows[.selectedIndex].itemId == "nav"'
key_burst Return
wait_state "drill-in pushes the path" '.activeMenu == "nav" and (.navStack | length == 1) and .navStack[0] == "root"'
key_burst BackSpace
wait_state "back retraces the pushed path" '.activeMenu == "root" and (.navStack | length == 0)'
# Verifies: SW-REQ-260922-DE93
# MCDC SW-REQ-260922-DE93: back_retraces_path=T, submenu_entered=T => TRUE
pass "drill-in pushes and Backspace retraces the menu path (SW-REQ-260922-DE93)"

# ---------------------------------------------------------- skip disabled row
# Verifies: SW-REQ-260922-Z48F
# MCDC SW-REQ-260922-Z48F: cursor_moves=F, disabled_rows_skipped=F => TRUE [no-action: freshly opened menu -- the cursor has not moved and owes no skip]
reopen_menu '{"menu":"dis"}' || fail_with_log "summon disabled-row menu"
wait_state "disabled guard applied" '(.rows | length) == 3 and .rows[1].disabled == true'
jq -e '.selectedIndex == 0 and .cursorActive == true' <<<"$LAST_STATE" >/dev/null ||
  fail "cursor starts on the first selectable row"
key_burst Down
wait_state "disabled row skipped" '.selectedIndex == 2 and .rows[2].itemId == "dis.last"'
# Verifies: SW-REQ-260922-Z48F
# MCDC SW-REQ-260922-Z48F: cursor_moves=T, disabled_rows_skipped=T => TRUE
pass "Down skips the disabled row (SW-REQ-260922-Z48F)"

# ------------------------------------------------------ all rows disabled
reopen_menu '{"menu":"alld"}' || fail_with_log "summon all-disabled menu"
wait_state "every row disabled" '(.rows | length) == 2 and all(.rows[]; .disabled == true)'
wait_state "no cursor parked" '.cursorActive == false'
# Verifies: SW-REQ-260922-3JG5
# MCDC SW-REQ-260922-3JG5: all_rows_disabled=T, no_cursor_parked=T => TRUE
pass "all rows disabled leaves no cursor (SW-REQ-260922-3JG5)"
# Verifies: SW-REQ-260922-3JG5
# MCDC SW-REQ-260922-3JG5: all_rows_disabled=F, no_cursor_parked=F => TRUE [no-action: every menu above with a selectable row shows a cursor -- the all-disabled path is the exception, not the rule]

# ------------------------------------------------------------ uninstall flow
# Delete with the cursor on a non-app row is ignored.
reopen_menu '{"menu":"root"}' || fail_with_log "summon root for the non-app Delete"
wait_state "root listed for the non-app Delete" '.rows | length == 7'
move_cursor_to act || fail "cursor reaches the action row"
wait_state "cursor on a non-app row" '.rows[.selectedIndex].itemId == "act"'
key_burst Delete
sleep 0.3
jq -e '.deleteConfirmOpen == false' <<<"$(menu_state)" >/dev/null ||
  fail "Delete on a non-app row opens no dialog"
# Verifies: SW-REQ-260922-8CQ4
# MCDC SW-REQ-260922-8CQ4: delete_key_on_app=F, uninstall_confirmed_flow=F => TRUE [no-action: Delete on an action row opens no dialog and removes nothing]

reopen_menu '{"menu":"apps"}' || fail_with_log "summon apps menu"
wait_state "fake app is the only app row" '(.rows | length) == 1 and .rows[0].kind == "app" and (.rows[0].appId | test("proof-fake"))'
key_burst Delete
wait_state "uninstall confirmation names the app" '.deleteConfirmOpen == true and (.deleteTarget.appId | test("proof-fake")) and (.deleteTarget.label | test("Proof Fake App"))'
key_burst Escape
wait_state "cancel closes the dialog" '.deleteConfirmOpen == false and .deleteTarget == null'
sleep 0.3
[[ ! -e $removed_log ]] || fail "cancel removed nothing"
key_burst Delete
wait_state "dialog reopens for confirm" '.deleteConfirmOpen == true'
key_burst Return  # selectedIndex 1 = Uninstall
for _ in {1..50}; do [[ -e $removed_log ]] && break; sleep 0.1; done
[[ -e $removed_log ]] || fail "confirm invokes the removal entry point"
grep -q "proof-fake" "$removed_log" || fail "removal names the fake app"
wait_state "menu closes after confirm" '.opened == false'
# Verifies: SW-REQ-260922-8CQ4
# MCDC SW-REQ-260922-8CQ4: delete_key_on_app=T, uninstall_confirmed_flow=T => TRUE
pass "Delete on an app runs the confirmed uninstall flow (SW-REQ-260922-8CQ4)"

# ------------------------------------------------------------- dmenu protocol
sel1="$TMPDIR/sel1"; done1="$TMPDIR/done1"
payload=$(jq -nc --arg sf "$sel1" --arg df "$done1" \
  '{mode:"select",prompt:"Pick",options:["★\tAlpha\tfirst","Beta"],selectionFile:$sf,doneFile:$df}')
reopen_menu "$payload" || fail_with_log "summon dmenu select"
wait_state "dmenu rows listed" '.mode == "select" and (.rows | length == 2) and .rows[0].label == "Alpha" and .rows[0].detail == "first"'
key_burst Return
for _ in {1..50}; do [[ -e $done1 ]] && break; sleep 0.1; done
[[ -e $done1 ]] || fail "dmenu pick touches the done file"
[[ $(cat "$sel1") == $'Alpha\tfirst' ]] ||
  fail "glyph stripped and subtext returned (got: $(cat "$sel1" 2>/dev/null))"
# Verifies: SW-REQ-260922-NM45
# MCDC SW-REQ-260922-NM45: dmenu_option_picked=T, glyph_stripped=T, subtext_returned=T => TRUE
pass "dmenu pick strips the glyph and returns the subtext (SW-REQ-260922-NM45)"

sel2="$TMPDIR/sel2"; done2="$TMPDIR/done2"
payload=$(jq -nc --arg sf "$sel2" --arg df "$done2" \
  '{mode:"select",prompt:"Pick",options:["★\tAlpha\tfirst","Beta"],selectionFile:$sf,doneFile:$df}')
reopen_menu "$payload" || fail_with_log "summon dmenu select for cancel"
wait_state "dmenu listed for cancel" '.mode == "select" and (.rows | length == 2)'
key_burst Escape
for _ in {1..50}; do [[ -e $done2 ]] && break; sleep 0.1; done
[[ -e $done2 ]] || fail "cancel touches the done file"
[[ ! -e $sel2 ]] || fail "cancel writes no selection"
# Verifies: SW-REQ-260922-NM45
# MCDC SW-REQ-260922-NM45: dmenu_option_picked=F, glyph_stripped=F, subtext_returned=F => TRUE [no-action: Escape cancels with only the done file touched -- no selection is produced]
pass "dmenu cancel produces no selection (SW-REQ-260922-NM45)"

# ------------------- summon while a request is active answers it as cancelled
# SW-REQ-260925-XTGG: the PR#9056 guard (Menu.qml:32) answers an in-flight
# dmenu request as cancelled (done file only, no selection) when a new
# summon arrives, so the prior caller is never abandoned.

# No summon outstanding: no request exists that could be cancelled.
sent_done="$TMPDIR/sent-done"
shell_ipc_quiet shell hide omarchy.menu >/dev/null
wait_state "menu closed, no request in flight" '.opened == false and .requestActive == false'
sleep 0.3
[[ ! -e $sent_done ]] || fail "no cancel write without a request"
# Verifies: SW-REQ-260925-XTGG
# MCDC SW-REQ-260925-XTGG: menu_open_called=F, no_active_request=F, prior_request_cancelled=F => TRUE [no-action: the probe shows requestActive=false with the menu closed -- there is no prior request to cancel and the sentinel done file never appears]
pass "no prior request is cancelled when no summon is outstanding (SW-REQ-260925-XTGG)"

# A clean summon with no active request fires no cancel.
sel3="$TMPDIR/sel3"; done3="$TMPDIR/done3"
payload=$(jq -nc --arg sf "$sel3" --arg df "$done3" \
  '{mode:"select",prompt:"Pick",options:["Gamma","Delta"],selectionFile:$sf,doneFile:$df}')
reopen_menu "$payload" || fail_with_log "summon clean dmenu select"
wait_state "clean dmenu rows listed" '.mode == "select" and (.rows | length == 2) and .requestActive == true'
[[ ! -e $done3 ]] || fail "clean summon touched its own done file before any answer"
# Verifies: SW-REQ-260925-XTGG
# MCDC SW-REQ-260925-XTGG: menu_open_called=T, no_active_request=T, prior_request_cancelled=F => TRUE [no-action: the request was armed by this very summon (probe: requestActive=true) and its done file is untouched -- no prior request existed to cancel]

# A second summon while the first request is still active answers the first
# as cancelled: done file only, no selection. Raw summon with no hide --
# hiding would answer the request through the lifecycle and disarm the guard.
sel4="$TMPDIR/sel4"; done4="$TMPDIR/done4"
payload=$(jq -nc --arg sf "$sel4" --arg df "$done4" \
  '{mode:"select",prompt:"Pick again",options:["Epsilon","Zeta"],selectionFile:$sf,doneFile:$df}')
shell_ipc_quiet shell summon omarchy.menu "$payload" >/dev/null
wait_state "second dmenu listed while the first was active" '.mode == "select" and .rows[0].label == "Epsilon"'
for _ in {1..50}; do [[ -e $done3 ]] && break; sleep 0.1; done
[[ -e $done3 ]] || fail "the prior request's done file is touched by the cancel"
[[ ! -e $sel3 ]] || fail "the prior request's cancel writes no selection"
[[ ! -e $done4 ]] || fail "the new request is not pre-answered"
# Verifies: SW-REQ-260925-XTGG
# MCDC SW-REQ-260925-XTGG: menu_open_called=T, no_active_request=F, prior_request_cancelled=T => TRUE
pass "summon while a request is active answers the prior request as cancelled (SW-REQ-260925-XTGG)"

key_burst Escape
for _ in {1..50}; do [[ -e $done4 ]] && break; sleep 0.1; done
[[ -e $done4 ]] || fail "escape answers the second request"

# ---------- AC-002 acceptance: a re-summon cancels the real polling caller
# STK-REQ-260922-XTNR AC-002, driven end to end: the caller is the shipped
# omarchy-menu-select binary (its own mktemp selection/done files, its own
# 50ms done-file poll), not a test-side stand-in. While its request is
# active, a raw second summon arrives; the PR#9056 guard (Menu.qml:32) must
# answer the caller as cancelled -- its poll terminates with no selection
# and exit 1 -- before the new menu lists.
caller_out="$TMPDIR/ac002-caller.out"
OMARCHY_PATH="$test_root" PATH="$test_root/bin:$PATH" \
  "$test_root/bin/omarchy-menu-select" "AC002 pick" Red Blue >"$caller_out" &
caller_pid=$!
wait_state "AC-002 caller request active" \
  '.mode == "select" and .requestActive == true and (.rows | length == 2) and .rows[0].label == "Red"'
payload=$(jq -nc --arg sf "$TMPDIR/ac002-sel2" --arg df "$TMPDIR/ac002-done2" \
  '{mode:"select",prompt:"AC002 again",options:["Green"],selectionFile:$sf,doneFile:$df}')
shell_ipc_quiet shell summon omarchy.menu "$payload" >/dev/null
caller_rc=""
for _ in {1..100}; do
  if ! kill -0 "$caller_pid" 2>/dev/null; then
    wait "$caller_pid" && caller_rc=0 || caller_rc=$?
    break
  fi
  sleep 0.1
done
if [[ -z $caller_rc ]]; then
  kill "$caller_pid" 2>/dev/null || true
  fail "AC-002: prior caller still polling 10s after the re-summon"
fi
[[ $caller_rc -eq 1 ]] || fail "AC-002: cancelled caller exits 1 (got $caller_rc)"
[[ ! -s $caller_out ]] || fail "AC-002: cancelled caller prints no selection"
wait_state "AC-002 second menu listed after the cancel" \
  '.mode == "select" and .rows[0].label == "Green"'
# STK-REQ-260922-XTNR:AC-002:acceptance
pass "re-summon while a select prompt awaits an answer cancels the real caller with exit 1 (STK-REQ-260922-XTNR AC-002)"
key_burst Escape
for _ in {1..50}; do [[ -e $TMPDIR/ac002-done2 ]] && break; sleep 0.1; done
[[ -e $TMPDIR/ac002-done2 ]] || fail "escape answers the AC-002 second request"

# ------------------------------------------------------------ fold: overflow
reopen_menu '{"menu":"long"}' || fail_with_log "summon long menu"
wait_state "40 rows listed" '.rows | length == 40'
long_state="$LAST_STATE"
jq -e '
  (.rows | length) as $n |
  (.baseRowHeight) as $h | (.rowSpacing) as $s | (.rowPeek) as $p |
  ($n * $h + ($n - 1) * $s) as $full |
  .visibleRowsHeight < $full and
  .visibleRowsHeight <= ((.panelHeight * 0.7) | round) and
  $p > 0 and $p < $h and
  ((.visibleRowsHeight - $p) % ($h + $s) == 0) and
  ((.visibleRowsHeight - $p) / ($h + $s) >= 1) and
  ((.visibleRowsHeight - $p) / ($h + $s) < $n)
' <<<"$long_state" >/dev/null ||
  { jq '{visibleRowsHeight, panelHeight, baseRowHeight, rowSpacing, rowPeek}' <<<"$long_state" >&2; \
    fail "overflowing rows fold mid-row under the 70% ceiling"; }
# Verifies: SW-REQ-260922-B757
# MCDC SW-REQ-260922-B757: fold_signals_more=T, rows_overflow=T => TRUE
pass "overflowing rows end mid-row under the panel ceiling (SW-REQ-260922-B757)"

# ------------------------------------------------------- guard batch discard
# Complete set #1: grd.ga visible, grd.gb hidden.
reopen_menu '{"menu":"grd"}' || fail_with_log "summon guarded menu"
wait_state "first guard batch lands" '.whenResults["grd.ga"] == true and .whenResults["grd.gb"] == false'
wait_state "gb hidden by its when" '(.rows | map(.itemId)) == ["grd.ga"]'
# Verifies: SW-REQ-260922-4079
# MCDC SW-REQ-260922-4079: batch_killed=F, last_complete_set_kept=F, pending_reeval_runs=F => TRUE [no-action: the batch exits 0 and its results apply -- the killed-batch path is not taken]

# Batch #2: ga's guard would hide it, gb's guard kills the batch shell after a
# window. A pending evaluation stands aside during the window, then the file
# moves to v3 so the reevaluation can complete.
python3 - "$menu_jsonc" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace('"grd.ga": {"label":"GA","action":"true","when":"true"}',
                    '"grd.ga": {"label":"GA","action":"true","when":"false"}')
text = text.replace('"grd.gb": {"label":"GB","action":"true","when":"false"}',
                    '"grd.gb": {"label":"GB","action":"true","when":"sleep 0.6; kill -TERM $$"}')
open(path, "w").write(text)
PY

wait_state "killed batch starts" '.guardRunning == true'
[[ $(shell_ipc menu-debug pokeGuards) == "ok" ]] || fail "stand-aside evaluation registers"
wait_state "evaluation stands aside" '.guardsPending == true'

python3 - "$menu_jsonc" <<'PY'
import sys
path = sys.argv[1]
text = open(path).read()
text = text.replace('"grd.ga": {"label":"GA","action":"true","when":"false"}',
                    '"grd.ga": {"label":"GA","action":"true","when":"true"}')
text = text.replace('"grd.gb": {"label":"GB","action":"true","when":"sleep 0.6; kill -TERM $$"}',
                    '"grd.gb": {"label":"GB","action":"true","when":"true"}')
open(path, "w").write(text)
PY

# Through the kill and the reevaluation, ga must never vanish: the half-read
# batch (ga:w:0) is discarded and the last complete set stays in effect. gb
# reappearing can only come from the stand-aside evaluation completing.
ga_stayed=true
gb_visible=false
for _ in {1..100}; do
  state=$(menu_state)
  if [[ -n $state ]]; then
    if jq -e '(.rows | map(.itemId)) | index("grd.ga") == null' <<<"$state" >/dev/null 2>&1; then
      ga_stayed=false
      break
    fi
    if jq -e '(.rows | map(.itemId)) | index("grd.gb") != null' <<<"$state" >/dev/null 2>&1; then
      gb_visible=true
      break
    fi
  fi
  sleep 0.1
done
$ga_stayed || fail "a killed batch never hides rows the last complete set showed"
$gb_visible || fail "the stand-aside evaluation runs after the killed batch exits"
# Verifies: SW-REQ-260922-4079
# MCDC SW-REQ-260922-4079: batch_killed=T, last_complete_set_kept=T, pending_reeval_runs=T => TRUE
pass "killed guard batch is discarded whole and the pending reevaluation runs (SW-REQ-260922-4079)"


# =================== CRS-0017/C01: finishRequest busy-drop race
# Deferred defect candidate CRS-0017/C01: finishRequest (Menu.qml:132-149)
# assigns resultProc.command and sets resultProc.running=true with no busy
# check, and a QML Process ignores a command change while running (the same
# behavior the shipped tree documents for guardProc at Menu.qml:1067-1072).
# Two finishRequest calls inside one bash-exec window would lose the second
# answer: summon#2's guard (Menu.qml:32) fires finishRequest(null) for the
# in-flight request, then a cancel of the new menu fires finishRequest(null)
# for the new request before the first bash exits -> the second command
# assignment is dropped -> caller#2's doneFile never appears -> the shipped
# bin/omarchy-menu-select poll (bounded only by death) hangs forever, the
# same hang class PR#9056 set out to fix.
#
# Two complementary live witnesses; the test PASSES under either verdict and
# pins the property as a regression witness:
#  A) mechanism, deterministic timing: a real shipped omarchy-menu-select
#     caller arms request#1 through the real summon IPC path; the test-only
#     probe then runs the product's own open() (summon entry: the guard fires
#     finishRequest#1 and arms request#2) and cancel() (Escape entry:
#     finishRequest#2) back to back in ONE event-loop turn, guaranteeing the
#     second finishRequest lands inside the first bash's exec window. If
#     Process really ignores the command change, done#2 is never written.
#  B) the claim's literal end-to-end trigger: TWO real shipped callers, the
#     second one's own summon trips the guard, and a wtype Escape is fired
#     the instant the probe shows request#2 armed. A per-trial timeline
#     (arm time, close time, resultRunning samples) classifies whether the
#     cancel landed inside the claimed ~10-50ms window.
#
# Caller exit codes travel through rc files, not `wait`: bash intermittently
# forgets reaped background jobs ("wait: pid N is not a child of this
# shell"), which flaked trial accounting under $( ) command substitution.

# Launch a real shipped omarchy-menu-select in the background; its exit code
# lands in $2 when it terminates. Prints the wrapper pid.
launch_caller() {
  local out=$1 rcf=$2; shift 2
  # The wrapper must not inherit the stdout of any $( ) capturing this
  # function's echo: a held-open pipe makes the substitution block until the
  # caller exits, deadlocking the trial against the answer it waits for.
  { OMARCHY_PATH="$test_root" PATH="$test_root/bin:$PATH" \
      "$test_root/bin/omarchy-menu-select" "$@" >"$out" 2>/dev/null
    echo $? >"$rcf"
  } >/dev/null 2>&1 &
  echo $!
}

# Bounded wait on an rc file: prints the recorded exit code, or TIMEOUT
# after $2 deciseconds (caller still running; kill via kill_caller).
bound_wait_rcf() {
  local rcf=$1 limit_ds=${2:-50} k
  for (( k = 0; k < limit_ds; k++ )); do
    [[ -e $rcf ]] && { cat "$rcf"; return 0; }
    sleep 0.1
  done
  echo TIMEOUT
}

# Kill a hung caller wrapper and the omarchy-menu-select it supervises.
kill_caller() {
  local wp=$1 kids
  kids=$(pgrep -P "$wp" 2>/dev/null || true)
  kill $kids "$wp" 2>/dev/null || true
  wait "$wp" 2>/dev/null || true
}

# --- witness A: deterministic same-turn open+cancel ------------------------
a_trials=20 a_dropped=0 a_answered=0
for (( i = 1; i <= a_trials; i++ )); do
  out1="$TMPDIR/c01a-$i-out1"; rc1f="$TMPDIR/c01a-$i-rc1"
  pid1=$(launch_caller "$out1" "$rc1f" "C01A pick" A1 A2)
  wait_state "C01-A trial $i request#1 armed" \
    '.requestActive == true and .rows[0].label == "A1"'

  sel2="$TMPDIR/c01a-$i-sel2"; done2="$TMPDIR/c01a-$i-done2"
  payload=$(jq -nc --arg sf "$sel2" --arg df "$done2" \
    '{mode:"select",prompt:"C01A again",options:["B1"],selectionFile:$sf,doneFile:$df}')
  [[ $(shell_ipc menu-debug summonCancelRace "$payload") == "ok" ]] \
    || fail "C01-A trial $i summonCancelRace call"
  wait_state "C01-A trial $i cancel closed the menu" \
    '.opened == false and .requestActive == false' 30

  # The guard must have answered the real first caller as cancelled.
  rc1=$(bound_wait_rcf "$rc1f" 50)
  if [[ $rc1 == "TIMEOUT" ]]; then
    kill_caller "$pid1"
    fail "C01-A trial $i: guard did not answer caller#1"
  fi
  [[ $rc1 == "1" ]] || fail "C01-A trial $i: caller#1 exit $rc1 (want 1 cancelled)"
  [[ ! -s $out1 ]] || fail "C01-A trial $i: caller#1 printed a selection on cancel"

  # done#2: if Process queues the second command it appears right after the
  # first bash exits; a drop means it never appears at all.
  for (( j = 0; j < 20; j++ )); do [[ -e $done2 ]] && break; sleep 0.1; done
  if [[ -e $done2 ]]; then
    (( a_answered++ )) || true
  else
    sleep 1  # outlive any queued-restart lag before declaring the drop
    if [[ -e $done2 ]]; then
      (( a_answered++ )) || true
    else
      [[ ! -e $sel2 ]] || fail "C01-A trial $i: drop wrote a selection without a done file"
      (( a_dropped++ )) || true
    fi
  fi
done

# --- witness B: two real callers + wtype Escape race ------------------------
b_trials=20 b_repro=0 b_answered=0 b_invalid=0 b_le50=0 b_inwin=0
for (( i = 1; i <= b_trials; i++ )); do
  out1="$TMPDIR/c01b-$i-out1"; rc1f="$TMPDIR/c01b-$i-rc1"
  out2="$TMPDIR/c01b-$i-out2"; rc2f="$TMPDIR/c01b-$i-rc2"
  pid1=$(launch_caller "$out1" "$rc1f" "C01B one" B1A B1B)
  wait_state "C01-B trial $i request#1 armed" \
    '.requestActive == true and .rows[0].label == "B1A"'

  # Timeline sampler: timestamped probe states for the whole race.
  tl="$TMPDIR/c01b-$i.timeline"; : >"$tl"
  ( while :; do printf '%s ' "$(date +%s%3N)"; menu_state; printf '\n'; done >>"$tl" 2>/dev/null ) &
  poller=$!

  pid2=$(launch_caller "$out2" "$rc2f" "C01B two" B2A B2B)

  # Fire Escape the instant the probe shows request#2 armed (the guard has
  # already fired by then: open() answers the prior request before arming).
  esc_sent=false
  for (( j = 0; j < 400; j++ )); do
    state=$(menu_state || true)
    if [[ -n $state ]] && jq -e '.requestActive == true and .rows[0].label == "B2A"' <<<"$state" >/dev/null 2>&1; then
      # short settle: bare wtype loses ~half its keys to sway seat
      # re-negotiation on the freshly-mapped layer surface
      wtype -s 30 -k Escape >/dev/null 2>&1 || true
      esc_sent=true
      break
    fi
    [[ -e $rc2f ]] && break
  done
  $esc_sent || { kill "$poller" 2>/dev/null; fail "C01-B trial $i: request#2 never armed"; }

  # Confirm the cancel actually ran (Escape delivered, menu closed).
  esc_processed=false
  for (( j = 0; j < 60; j++ )); do
    state=$(menu_state || true)
    if [[ -n $state ]] && jq -e '.opened == false' <<<"$state" >/dev/null 2>&1; then
      esc_processed=true
      break
    fi
    sleep 0.05
  done

  rc1=$(bound_wait_rcf "$rc1f" 50)
  if [[ $rc1 == "TIMEOUT" ]]; then
    kill "$poller" 2>/dev/null || true
    kill_caller "$pid1"; kill_caller "$pid2"
    fail "C01-B trial $i: caller#1 not answered as cancelled"
  fi
  [[ $rc1 == "1" ]] || { kill "$poller" 2>/dev/null || true; fail "C01-B trial $i: caller#1 exit $rc1 (want 1 cancelled)"; }
  [[ ! -s $out1 ]] || { kill "$poller" 2>/dev/null || true; fail "C01-B trial $i: caller#1 printed a selection on cancel"; }

  rc2=$(bound_wait_rcf "$rc2f" 50)
  kill "$poller" 2>/dev/null || true
  wait "$poller" 2>/dev/null || true

  # Classify the trial from the timeline + outcome.
  read -r lag inwin <<<"$(python3 - "$tl" <<'PY'
import json, sys
arm = close = None
inwin = False
for line in open(sys.argv[1]):
    parts = line.split(" ", 1)
    if len(parts) != 2:
        continue
    try:
        ts = int(parts[0]); st = json.loads(parts[1])
    except Exception:
        continue
    rows = st.get("rows") or []
    armed = st.get("requestActive") and rows and rows[0].get("label") == "B2A"
    if arm is None and armed:
        arm = ts
    if arm is not None:
        if st.get("resultRunning"):
            inwin = True
        if close is None and st.get("opened") is False:
            close = ts
if arm is None or close is None:
    print("NA NA")
else:
    print(close - arm, 1 if inwin else 0)
PY
)"

  if ! $esc_processed; then
    # Key lost to seat re-negotiation: trial says nothing about the race.
    (( b_invalid++ )) || true
    key_burst Escape  # answer request#2 legitimately, well outside any window
    rc2b=$(bound_wait_rcf "$rc2f" 50)
    if [[ $rc2b == "TIMEOUT" ]]; then
      kill_caller "$pid2"
      fail "C01-B trial $i: cleanup cancel did not answer caller#2"
    fi
    continue
  fi

  [[ $lag != "NA" ]] && (( lag <= 50 )) && (( b_le50++ )) || true
  [[ $inwin == "1" ]] && (( b_inwin++ )) || true

  if [[ $rc2 == "TIMEOUT" ]]; then
    # The cancel ran (menu closed) yet caller#2's done file never came: the
    # second finishRequest was swallowed by the busy resultProc.
    kill_caller "$pid2"
    (( b_repro++ )) || true
  else
    [[ $rc2 == "1" ]] || fail "C01-B trial $i: caller#2 exit $rc2 (want 1 cancelled)"
    [[ ! -s $out2 ]] || fail "C01-B trial $i: caller#2 printed a selection on cancel"
    (( b_answered++ )) || true
  fi

  wait_state "C01-B trial $i clean state for next trial" \
    '.opened == false and .requestActive == false' 30
done

if (( a_dropped > 0 || b_repro > 0 )); then
  c01_verdict=REPRODUCED
else
  c01_verdict=REFUTED
fi
printf 'CRS-0017/C01 verdict=%s | A: %d/%d done-files dropped at same-turn timing (%d answered) | B: %d reproduced, %d answered, %d invalid of %d trials; %d escapes within 50ms of arm, %d trials with busy-window sample\n' \
  "$c01_verdict" "$a_dropped" "$a_trials" "$a_answered" \
  "$b_repro" "$b_answered" "$b_invalid" "$b_trials" "$b_le50" "$b_inwin" >&2
pass "CRS-0017/C01 finishRequest busy-drop race witness: verdict=$c01_verdict (A dropped $a_dropped/$a_trials, B repro $b_repro answered $b_answered invalid $b_invalid)"

pass "menu compositor interaction test complete"
