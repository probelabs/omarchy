#!/bin/bash

set -euo pipefail

# Acceptance-level end-to-end tests for the menu stakeholder requirement,
# driven against the INTEGRATED system: a live Wayland compositor, a live
# quickshell omarchy shell, real IPC verbs through bin/omarchy-menu, and real
# key events through wtype. This is the stakeholder-level witness that
# per-requirement unit/system suites cannot provide (V-model: decomposition
# is not acceptance validation).
#
# STK-REQ-260922-XTNR:AC-001:acceptance
# STK-REQ-260922-XTNR:AC-002:acceptance
# SYS-REQ-260922-P708:boundary:boundary
#
# Harness gating: on a host without a Wayland compositor or quickshell (the
# macOS dogfood host) every block below skips cleanly. The run that clears
# the witness_deferred staging must happen on the integrated Linux session
# (proof box: ~/proof-env/gui/start-session.sh).
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

require_compositor "menu acceptance test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping menu acceptance test"
  exit 0
fi

if ! command -v wtype >/dev/null 2>&1; then
  pass "wtype not installed; skipping menu acceptance test"
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
# the burst rides that same device.
key_burst() {
  local args=(-s 300) k
  for k in "$@"; do
    args+=(-k "$k" -d 150)
  done
  wtype "${args[@]}"
  sleep 0.15
}

# A clean reopen: hide whatever is open, wait for the close to land, summon.
reopen_menu() {
  local payload="$1" i out
  shell_ipc_quiet shell hide omarchy.menu >/dev/null
  wait_state "menu closes before reopen" '.opened == false' 30
  for (( i = 0; i < 40; i++ )); do
    out=$(shell_ipc shell summon omarchy.menu "$payload" 2>/dev/null || true)
    if [[ $out == "ok" ]]; then
      sleep 0.4
      return 0
    fi
    sleep 0.25
  done
  return 1
}

TMPDIR=$(mktemp -d)
test_root="$TMPDIR/omarchy"
test_home="$TMPDIR/home"
log="$TMPDIR/quickshell.log"
mkdir -p "$test_root" "$test_home"
cp -a "$ROOT/shell" "$test_root/shell"
ln -s "$ROOT/config" "$test_root/config"
mkdir -p "$test_root/bin"
for f in "$ROOT/bin"/*; do
  ln -s "$f" "$test_root/bin/$(basename "$f")"
done

# Read-only state probe, injected into the test's private copy only. The
# shipped Menu.qml is never modified.
python3 - "$test_root/shell/plugins/menu/Menu.qml" <<'PY'
import sys

path = sys.argv[1]
source = open(path).read()
anchor = "  ListModel { id: displayModel }"
assert source.count(anchor) == 1, "injection anchor not unique"

probe = anchor + """

  // TEST-ONLY probe, injected by menu-acceptance-test.sh into its private
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
        selectedIndex: root.selectedIndex, cursorActive: root.cursorActive,
        rows: rows
      })
    }
  }
"""
open(path, "w").write(source.replace(anchor, probe))
PY

# Menu fixture, authored in JSONC on purpose: trailing commas before closing
# braces (JSONC syntax the parser must strip) AND commas inside label/action
# strings (data the parser must preserve verbatim). This user file is the
# whole menu for the test root.
menu_dir="$test_home/.config/omarchy/extensions"
mkdir -p "$menu_dir"
menu_jsonc="$menu_dir/omarchy-menu.jsonc"
cat >"$menu_jsonc" <<JSONC
{
  // full-line comments are JSONC syntax too
  "act": {"label":"Act","action":"touch '$TMPDIR/action-ran'",},
  "cma": {"label":"Commas, Included",},
  "cma.run": {"label":"Run, now","action":"touch '$TMPDIR/comma-action-ran'",},
  "nav": {"label":"Nav",},
  "nav.leaf": {"label":"Leaf","action":"touch '$TMPDIR/leaf-ran'"},
  "alld": {"label":"AllD"},
  "alld.one": {"label":"One","action":"true","disabled":"true"},
  "alld.two": {"label":"Two","action":"true","disabled":"true"},
}
JSONC

OMARCHY_PATH="$test_root" \
HOME="$test_home" \
XDG_CONFIG_HOME="$test_home/.config" \
XDG_CACHE_HOME="$test_home/.cache" \
XDG_STATE_HOME="$test_home/.local/state" \
XDG_DATA_HOME="$test_home/.local/share" \
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

# Force the menu plugin instance up so the probe answers.
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

# ============================================================ AC-001 (part 1)
# Opening the menu presents the menu UI; summon/close verbs route to the
# correct plugin targets. Drive the REAL dispatcher bin/omarchy-menu, not the
# raw IPC: the stakeholder-facing entry point is `omarchy menu toggle`.
menu_bin() {
  OMARCHY_PATH="$test_root" PATH="$ROOT/bin:$PATH" "$ROOT/bin/omarchy-menu" "$@"
}

menu_bin toggle
wait_state "omarchy menu toggle presents the menu UI" '.opened == true'

menu_bin summon nav
wait_state "summon verb routes to the nav menu target" '.opened == true and .activeMenu == "nav"'

menu_bin close
wait_state "close verb closes the presented menu" '.opened == false'
pass "AC-001 part 1: toggle presents the menu UI; summon/close route to the correct plugin targets"

# ============================================================ AC-001 (part 2)
# A pick in a script-driven select prompt returns the chosen answer to the
# calling script. Run the real bin/omarchy-menu-select against the live
# shell; the answer comes back through the selection file the menu writes.
select_out="$TMPDIR/select-answer.txt"
OMARCHY_PATH="$test_root" PATH="$ROOT/bin:$PATH" HOME="$test_home" \
  "$ROOT/bin/omarchy-menu-select" "Pick a letter" Alpha Beta Gamma \
  >"$select_out" 2>"$TMPDIR/select-err.txt" &
SELECT_PID=$!

wait_state "select prompt presented in dmenu mode" '.opened == true and .mode == "select"'
# Cursor starts on Alpha; one Down lands on Beta; Return picks it.
key_burst Down
wait_state "cursor moved to the second option" '.selectedIndex == 1'
key_burst Return

select_rc=0
wait "$SELECT_PID" || select_rc=$?
[[ $select_rc -eq 0 ]] || fail "omarchy-menu-select exits zero on a pick" "rc: $select_rc err: $(cat "$TMPDIR/select-err.txt")"
[[ $(cat "$select_out") == "Beta" ]] || fail "the calling script receives the picked answer" "got: $(cat "$select_out")"
wait_state "select prompt closed after the pick" '.opened == false'
pass "AC-001 part 2: a script-driven select pick returns the chosen answer to the caller (STK-REQ-260922-XTNR AC-001)"

# ==================================================================== AC-002
# A menu entry whose label contains a comma, authored next to a trailing
# comma before a closing brace, displays verbatim and executes as written.
reopen_menu '{"menu":"root"}' || fail_with_log "summon root menu"
wait_state "comma label row presented" '[.rows[] | select(.itemId == "cma")] | length == 1'
label=$(jq -r '[.rows[] | select(.itemId == "cma")][0].label' <<<"$LAST_STATE")
[[ $label == "Commas, Included" ]] || fail "label with a comma renders verbatim" "got: $label"

key_burst Return
wait_state "comma submenu opened" '.activeMenu == "cma"'
leaf_label=$(jq -r '[.rows[] | select(.itemId == "cma.run")][0].label' <<<"$(menu_state)")
[[ $leaf_label == "Run, now" ]] || fail "submenu label with a comma renders verbatim" "got: $leaf_label"

key_burst Return
for _ in {1..30}; do
  [[ -f $TMPDIR/comma-action-ran ]] && break
  sleep 0.1
done
[[ -f $TMPDIR/comma-action-ran ]] || fail "the comma-bearing entry executed exactly as written"
pass "AC-002: comma-bearing labels render verbatim in the presented menu and the entry executes as written (STK-REQ-260922-XTNR AC-002)"

# ================================================== P708 boundary obligation
# Navigation boundaries on the integrated session: list-end wrap-around and
# the all-disabled boundary (no cursor parked). Real key events, observed
# through the probe on the live layer surface.
# SW-REQ-260922-Z48F:boundary:nominal
# SYS-REQ-260922-P708:boundary:nominal
reopen_menu '{"menu":"root"}' || fail_with_log "summon root for wrap boundary"
wait_state "cursor starts on the first row" '.selectedIndex == 0 and .cursorActive == true'
last_index=$(jq '[.rows[] | select(.disabled == false)] | length - 1' <<<"$LAST_STATE")
key_burst Up
wait_state "Up on the first row wraps to the last selectable row" ".selectedIndex == $last_index"
key_burst Down
wait_state "Down on the last row wraps back to the first" '.selectedIndex == 0'

reopen_menu '{"menu":"alld"}' || fail_with_log "summon all-disabled menu"
wait_state "all-disabled menu shows no parked cursor" '.cursorActive == false'
pass "P708 boundary: navigation wraps at list ends and parks no cursor when every row is disabled (SYS-REQ-260922-P708 boundary)"

pass "menu acceptance test complete"
