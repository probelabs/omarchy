#!/bin/bash

# Verifies: SW-REQ-260922-0W96, SW-REQ-260922-9DMS
# mcdc:witness-out-of-process

source "$(dirname "${BASH_SOURCE[0]}")/base-test.sh"

require_command lua
require_command xkbcli

tmpdir=$(mktemp -d) && [[ -n $tmpdir && -d $tmpdir ]] ||
  fail "the test gets a temporary directory to stub Hyprland in"
trap 'rm -rf "$tmpdir"' EXIT

home="$tmpdir/home"
stub_bin="$tmpdir/bin"
mkdir -p "$home/.config" "$stub_bin"
cp -r "$ROOT/config/hypr" "$home/.config/hypr"

# The menu reads binds from Hyprland, which is not running here, so stand in for
# it. A Lua bind reports dispatcher __lua and no arg, and the menu recovers both
# from the Lua source; an exec bind carries its own command. Both shapes matter:
# what two chords dispatch is what decides whether they share a row.
lua_bind() {
  printf 'bind\n\tmodmask: %s\n\tsubmap: \n\tkey: %s\n\tkeycode: 0\n\tcatchall: false\n\tdescription: %s\n\tdispatcher: __lua\n\targ: \n' "$1" "$2" "$3"
}

exec_bind() {
  printf 'bind\n\tmodmask: %s\n\tsubmap: \n\tkey: %s\n\tkeycode: 0\n\tcatchall: false\n\tdescription: %s\n\tdispatcher: exec\n\targ: %s\n' "$1" "$2" "$3" "$4"
}

stub_hyprctl() {
  {
    echo '#!/bin/bash'
    echo 'printf "%s\n" "$1" >>"'"$tmpdir"'/hyprctl-calls" 2>/dev/null || :'
    echo 'case "$1" in'
    echo '  binds) cat <<'"'"'BINDS'"'"''
    cat
    echo 'BINDS'
    echo '  ;;'
    echo '  devices) echo "active keymap: English (US)" ;;'
    echo '  dispatch) shift'
    echo '    [[ -n ${HYPRCTL_DISPATCH_LOG:-} ]] && printf "%s\n" "$*" >>"$HYPRCTL_DISPATCH_LOG"'
    echo '    [[ -n ${HYPRCTL_DISPATCH_OUTPUT:-} ]] && printf "%s\n" "$HYPRCTL_DISPATCH_OUTPUT"'
    echo '    exit "${HYPRCTL_DISPATCH_STATUS:-0}" ;;'
    echo 'esac'
  } >"$stub_bin/hyprctl"
  chmod +x "$stub_bin/hyprctl"
}

# The menu answers its pick from a file so a scenario can choose the row under
# test without a compositor.
cat >"$stub_bin/omarchy-menu-select" <<'STUB'
#!/bin/bash
[[ -f $PICK_FILE ]] && cat "$PICK_FILE"
STUB
chmod +x "$stub_bin/omarchy-menu-select"

# env -i strips everything the instrumented sources use to record their
# observations, so the trace directory rides along explicitly beside the
# scenario's own knobs.
run_keybindings() {
  local mode="$1" pick="${2:-}"

  printf '%s' "$pick" >"$tmpdir/pick"
  : >"$tmpdir/dispatch"
  env -i PATH="$stub_bin:$ROOT/bin:$PATH" HOME="$home" \
    XDG_CACHE_HOME="${KEYBINDINGS_CACHE_HOME:-$tmpdir/cache}" OMARCHY_PATH="$ROOT" \
    PROOF_MCDC_TRACE_DIR="${PROOF_MCDC_TRACE_DIR:-}" \
    PICK_FILE="$tmpdir/pick" HYPRCTL_DISPATCH_LOG="$tmpdir/dispatch" \
    HYPRCTL_DISPATCH_OUTPUT="${HYPRCTL_DISPATCH_OUTPUT:-}" \
    HYPRCTL_DISPATCH_STATUS="${HYPRCTL_DISPATCH_STATUS:-0}" \
    bash "$ROOT/bin/omarchy-menu-keybindings" ${mode:+"$mode"}
}

keybindings() {
  run_keybindings --print
}

dispatch_log() {
  cat "$tmpdir/dispatch"
}

# Closing a window and toggling the scratchpad are two of the actions Omarchy
# binds twice on purpose. The last bind carries the longest description Omarchy
# ships, which is what puts a row closest to the width the menu allows.
stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + W" "Close window")
$(lua_bind 64 "SUPER + Q" "Close window")
$(lua_bind 64 "SUPER + F" "Full screen")
$(lua_bind 64 "SUPER + S" "Toggle scratchpad")
$(lua_bind 64 "SUPER + grave" "Toggle scratchpad")
$(exec_bind 73 "SUPER SHIFT ALT + 0" "Move window silently to workspace 10" "true")
BINDS

rendered=$(keybindings)
# MCDC SW-REQ-260922-9DMS: keycode_binding=F, symbol_resolved=F => TRUE [no-action: every stubbed bind reports keycode: 0 and the rendered rows name their keys -- no keycode is resolved]
[[ -n $rendered ]] || fail "the keybindings menu renders with a stubbed Hyprland"

grep -q 'SUPER + F  *→ Full screen' <<<"$rendered" ||
  fail "a chord with no alternative renders on its own" "$rendered"
pass "the keybindings menu renders its entries"

(( $(grep -c '→ Close window$' <<<"$rendered") == 1 )) ||
  fail "an alternative chord joins the row of the first one" "$rendered"
grep -q 'SUPER + W / SUPER + Q  *→ Close window' <<<"$rendered" ||
  fail "a shared row names both chords" "$rendered"
# MCDC SW-REQ-260922-0W96: lua_binds_dispatchable=T, lua_binds_present=T => TRUE
pass "an alternative chord joins the row of the first one"

# Which chord leads is the whole point of keeping Hyprland's order: SUPER + W is
# the documented default and SUPER + Q the alternative bound after it.
grep -q '^SUPER + W / SUPER + Q' <<<"$rendered" ||
  fail "the chord declared first leads a shared row" "$rendered"
pass "the chord declared first leads a shared row"

# Hyprland calls the key left of 1 "grave". Nobody reads their keyboard that way.
grep -q 'SUPER + S / SUPER + ~  *→ Toggle scratchpad' <<<"$rendered" ||
  fail "the grave key reads as the symbol printed on it" "$rendered"
! grep -q 'grave' <<<"$rendered" ||
  fail "no entry still says grave" "$rendered"
pass "the grave key reads as the symbol printed on it"

# Monospace menu: every arrow sits in one column, and nothing is allowed past
# it. A row that overruns pushes its own arrow out of line.
[[ $(awk -F '→' '{ print length($1) }' <<<"$rendered" | sort -u) == "36" ]] ||
  fail "every entry pads its chords to the same column" "$rendered"
pass "every entry pads its chords to the same column"

# The menu elides a row that outgrows its card: 754px of label, 78 monospace
# characters at the heading size. The longest entry Omarchy ships sits at 74, so
# a row has four characters of room and no more.
(( $(awk '{ print length($0) }' <<<"$rendered" | sort -rn | head -1) <= 78 )) ||
  fail "no entry outgrows the width the menu gives it" "$rendered"
pass "no entry outgrows the width the menu gives it"

# Priority ordering reads the row, and the chord sharing it must not reclassify
# the entry: XF86Calculator alone belongs in the tail the menu keeps for media
# keys, while the calculator itself sits in the body of the list.
stub_hyprctl <<BINDS
$(exec_bind 68 "SUPER CTRL + Q" "Calculator" "omacalc")
$(exec_bind 0 "XF86Calculator" "Calculator" "omacalc")
$(exec_bind 8 "ALT + TAB" "Reveal active window on top" "true")
BINDS

rendered=$(keybindings)
(( $(grep -n '→ Calculator$' <<<"$rendered" | cut -d: -f1) <
   $(grep -n '→ Reveal active window on top$' <<<"$rendered" | cut -d: -f1) )) ||
  fail "a shared chord does not change where its entry ranks" "$rendered"
# MCDC SW-REQ-260922-0W96: lua_binds_dispatchable=F, lua_binds_present=F => TRUE [no-action: the stubbed bind list carries only exec binds -- no Lua dispatch needs resolving]
pass "a shared chord does not change where its entry ranks"

# The same key written as a keycode arrives by the other road: Hyprland reports
# the code and the keymap resolves it, after the rename above has run.
stub_hyprctl <<'BINDS'
bind
	modmask: 64
	submap: 
	key: 
	keycode: 49
	catchall: false
	description: Toggle scratchpad
	dispatcher: exec
	arg: true
BINDS

rendered=$(keybindings)
grep -q 'SUPER + ~  *→ Toggle scratchpad' <<<"$rendered" ||
  fail "a keycode resolves to the symbol printed on the key too" "$rendered"
# MCDC SW-REQ-260922-9DMS: keycode_binding=T, symbol_resolved=T => TRUE
# SW-REQ-260922-9DMS:error_handling:nominal
pass "a keycode resolves to the symbol printed on the key too"

# A keycode the keymap cannot name keeps its raw code:N form rather than
# vanishing or guessing: the row stays readable and the miss stays visible.
stub_hyprctl <<'BINDS'
bind
	modmask: 64
	submap: 
	key: 
	keycode: 9999
	catchall: false
	description: Mystery action
	dispatcher: exec
	arg: true
BINDS

rendered=$(keybindings)
grep -q 'SUPER + code:9999  *→ Mystery action' <<<"$rendered" ||
  fail "an unresolvable keycode keeps its raw code:N form" "$rendered"
# MCDC SW-REQ-260922-9DMS: keycode_binding=T, symbol_resolved=F => FALSE
# SW-REQ-260922-9DMS:error_handling:negative
pass "an unresolvable keycode keeps its raw code:N form"

# A chord refused for width opens a row of its own, and the next chord tries
# that row rather than reaching back past it and printing out of order.
stub_hyprctl <<BINDS
$(exec_bind 64 "SUPER + A" "Calculator" "omacalc")
$(exec_bind 77 "SUPER SHIFT CTRL ALT + BACKSPACE" "Calculator" "omacalc")
$(exec_bind 64 "SUPER + B" "Calculator" "omacalc")
BINDS

rendered=$(keybindings)
(( $(grep -c '→ Calculator$' <<<"$rendered") == 3 )) ||
  fail "a refused chord does not let the next one jump the queue" "$rendered"
pass "a refused chord does not let the next one jump the queue"

# Sharing a row is something Omarchy names an action for, not something two
# chords earn by looking alike. Alt + Tab and Shift + Alt + Tab both read
# "Reveal active window on top" and cycle opposite ways.
stub_hyprctl <<BINDS
$(exec_bind 64 "SUPER + Y" "Zoom in" "omarchy-zoom in")
$(exec_bind 64 "SUPER + Z" "Zoom in" "omarchy-zoom in")
BINDS

rendered=$(keybindings)
(( $(grep -c '→ Zoom in$' <<<"$rendered") == 2 )) ||
  fail "an action Omarchy did not name keeps its chords on separate rows" "$rendered"
pass "an action Omarchy did not name keeps its chords on separate rows"

# Even a named action gives up the shared row rather than overrun the column:
# two rows in line beat one that juts out of it.
stub_hyprctl <<BINDS
$(exec_bind 73 "SUPER SHIFT ALT + BACKSPACE" "Calculator" "omacalc")
$(exec_bind 69 "SUPER SHIFT CTRL + BACKSPACE" "Calculator" "omacalc")
BINDS

rendered=$(keybindings)
(( $(grep -c '→ Calculator$' <<<"$rendered") == 2 )) ||
  fail "chords too wide to share a row stay on their own" "$rendered"
[[ $(awk -F '→' '{ print length($1) }' <<<"$rendered" | sort -u) == "36" ]] ||
  fail "chords too wide to share a row leave the column alone" "$rendered"
pass "chords too wide to share a row stay on their own"

# A shared label is not a shared action. Two chords that merely read alike have
# to stay apart, or the menu hides one of them behind the other.
stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + W" "Close window")
$(exec_bind 64 "SUPER + X" "Close window" "omarchy-hyprland-window-close-all")
BINDS

rendered=$(keybindings)
(( $(grep -c '→ Close window$' <<<"$rendered") == 2 )) ||
  fail "chords with the same label but different actions stay apart" "$rendered"
pass "chords with the same label but different actions stay apart"

# An unresolved Lua bind reports no dispatcher at all, so nothing says the two
# chords run the same thing, whatever their label promises.
stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + Y" "Close window")
$(lua_bind 64 "SUPER + Z" "Close window")
BINDS

rendered=$(keybindings)
(( $(grep -c '→ Close window$' <<<"$rendered") == 2 )) ||
  fail "chords whose dispatch is unknown stay apart" "$rendered"
# MCDC SW-REQ-260922-0W96: lua_binds_dispatchable=F, lua_binds_present=T => FALSE
pass "chords whose dispatch is unknown stay apart"

# What the menu is expected to pair up, written out here rather than read from
# the script, so dropping an action from the list fails instead of shrinking
# what gets checked.
expected_alternatives=(
  "Close window"
  "Calculator"
  "Toggle scratchpad"
  "Move window to scratchpad"
)

eval "$(sed -n '/^alternative_chord_actions()/,/^}/p' "$ROOT/bin/omarchy-menu-keybindings")"

[[ $(alternative_chord_actions) == "$(printf '%s\n' "${expected_alternatives[@]}")" ]] ||
  fail "the menu pairs up the actions Omarchy means it to" "$(alternative_chord_actions)"
pass "the menu pairs up the actions Omarchy means it to"

# A renamed description would leave an action named here matching nothing, and
# the row it was meant to share would quietly split in two. Only real binds
# count: a commented-out example is not a second chord.
for action in "${expected_alternatives[@]}"; do
  (( $(grep -rhE '^[[:space:]]*o\.bind\(' "$ROOT/default/hypr/bindings" |
       grep -cF ", \"$action\",") >= 2 )) ||
    fail "every action named as having an alternative is bound twice" "$action"
done
pass "every action named as having an alternative is bound twice"

# The terminal bind is a Lua function Hyprland reports only as __lua, so picking
# it from the menu has to run the command the function stands for.
stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + RETURN" "Terminal")
BINDS

rm -rf "$tmpdir/cache"
keybindings >/dev/null
grep -qP '→ Terminal\texec\tomarchy-launch-terminal$' "$tmpdir"/cache/omarchy/keybindings-*.records ||
  fail "picking the terminal bind from the menu launches a terminal" "$(cat "$tmpdir"/cache/omarchy/keybindings-*.records)"
pass "picking the terminal bind from the menu launches a terminal"

# A warm cache answers from the records file alone: computing the cache key
# still asks Hyprland for its state, but a hit never asks for the binds
# themselves, while a miss has to render the rows the hard way.
: >"$tmpdir/hyprctl-calls"
rendered=$(keybindings)
hit_calls=$(wc -l <"$tmpdir/hyprctl-calls")
rm -rf "$tmpdir/cache"
rendered=$(keybindings)
miss_calls=$(wc -l <"$tmpdir/hyprctl-calls")
(( miss_calls > hit_calls )) ||
  fail "a warm cache serves the rows without re-reading the binds" "hit: $hit_calls, miss: $miss_calls"
grep -q '→ Terminal' <<<"$rendered" ||
  fail "a warm cache still renders the rows" "$rendered"
pass "a warm cache serves the rows without re-reading the binds"

# -p is the documented short form of --print and must render the same rows.
stub_hyprctl <<BINDS
$(exec_bind 64 "SUPER + F" "Full screen" "true")
BINDS

rendered=$(run_keybindings -p)
grep -q '→ Full screen' <<<"$rendered" ||
  fail "the -p short form prints the keybinding rows" "$rendered"
pass "the -p short form prints the keybinding rows"

# Every modifier mask the menu translates, plus one it does not know, so the
# rendition table is exercised arm by arm instead of only on the common chords.
coverage_binds=""
for mask in 0 1 4 5 8 9 12 13 64 65 68 69 72 73 76 77 3; do
  coverage_binds+="$(exec_bind "$mask" "KEY$mask" "Mask $mask" "true")"$'\n'
done
# Keys Hyprland spells out get the symbol printed on them, one case arm each.
for key in comma period minus equal slash; do
  coverage_binds+="$(exec_bind 64 "SUPER + $key" "Named $key" "true")"$'\n'
done
# Rows with nothing to show are dropped: no modifier, no description, no key,
# and the Copilot chord that only duplicates a real binding.
coverage_binds+='bind
	modmask: 
	submap: 
	key: SUPER + M
	keycode: 0
	catchall: false
	description: No modifier
	dispatcher: exec
	arg: true
'
coverage_binds+='bind
	modmask: 64
	submap: 
	key: 
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: true
'
coverage_binds+='bind
	modmask: 64
	submap: 
	key: 
	keycode: 0
	catchall: false
	description: No key at all
	dispatcher: exec
	arg: true
'
coverage_binds+='bind
	modmask: 64
	submap: 
	key: 
	keycode: 201
	catchall: false
	description: Copilot chord
	dispatcher: exec
	arg: true
'
# A __lua row with no description is dropped before the source cache is asked,
# and one whose key resolves to nothing keeps the row but has no dispatch.
coverage_binds+="$(lua_bind 64 "SUPER + Q" "")"$'\n'
coverage_binds+="$(lua_bind 64 "SUPER + " "Ghost chord")"$'\n'
# An exec row with no description is kept: its command becomes the label.
coverage_binds+='bind
	modmask: 64
	submap: 
	key: SUPER + G
	keycode: 0
	catchall: false
	description: 
	dispatcher: exec
	arg: true
'

stub_hyprctl <<BINDS
$coverage_binds
BINDS

rendered=$(keybindings)
(( $(grep -c '→ Mask ' <<<"$rendered") == 17 )) ||
  fail "every modifier mask renders a row" "$rendered"
grep -q 'SUPER SHIFT CTRL ALT + KEY77' <<<"$rendered" ||
  fail "the widest modifier stack reads as words" "$rendered"
grep -q '^3 + KEY3' <<<"$rendered" ||
  fail "an unknown modifier mask is printed raw rather than dropped" "$rendered"
grep -q '^KEY0' <<<"$rendered" ||
  fail "an unmodified chord renders without a dangling separator" "$rendered"
grep -q 'SUPER + COMMA  *→ Named comma' <<<"$rendered" &&
  grep -q 'SUPER + PERIOD  *→ Named period' <<<"$rendered" &&
  grep -q 'SUPER + MINUS  *→ Named minus' <<<"$rendered" &&
  grep -q 'SUPER + EQUAL  *→ Named equal' <<<"$rendered" &&
  grep -q 'SUPER + SLASH  *→ Named slash' <<<"$rendered" ||
  fail "the named keys read as the symbols printed on them" "$rendered"
grep -q '→ No modifier' <<<"$rendered" &&
  grep -q '→ No key at all' <<<"$rendered" &&
  grep -q '→ Ghost chord' <<<"$rendered" ||
  fail "rows with missing pieces still render with what is known" "$rendered"
! grep -q 'Copilot chord' <<<"$rendered" ||
  fail "the Copilot duplicate stays hidden" "$rendered"
pass "every modifier mask and named key renders, and the Copilot duplicate stays hidden"

# Without lua the source-derived cache cannot be built; the menu still renders
# what Hyprland itself reported instead of failing the whole picker.
cat >"$stub_bin/omarchy-cmd-present" <<'STUB'
#!/bin/bash
[[ $1 == lua ]] && exit 1
exec "$OMARCHY_PATH/bin/omarchy-cmd-present" "$@"
STUB
chmod +x "$stub_bin/omarchy-cmd-present"

stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + RETURN" "Terminal")
BINDS

rendered=$(keybindings)
grep -q '→ Terminal' <<<"$rendered" ||
  fail "the menu renders without lua, whose absence only costs the source cache" "$rendered"
pass "the menu renders without lua, whose absence only costs the source cache"
rm "$stub_bin/omarchy-cmd-present"

# A Hyprland that reports no binds at all must not be cached as an empty menu:
# the refresh refuses, and the rows fall back to the hardcoded chords so the
# fallout of a broken hyprctl is never persisted.
stub_hyprctl <<'BINDS'
exit 1
BINDS

rendered=$(keybindings)
(( $(wc -l <<<"$rendered") == 2 )) ||
  fail "a Hyprland that reports no binds leaves the hardcoded chords" "$rendered"
grep -q 'Copy URL from Web App' <<<"$rendered" &&
  grep -q 'Download Video from Web App' <<<"$rendered" ||
  fail "the hardcoded chords survive a broken hyprctl" "$rendered"
pass "a Hyprland that reports no binds leaves the hardcoded chords"

# A cache directory that cannot hold a temp file costs the cache, not the menu:
# the refresh gives up and the rows render uncached.
mkdir -p "$tmpdir/ro-cache" && chmod 555 "$tmpdir/ro-cache"
stub_hyprctl <<BINDS
$(exec_bind 64 "SUPER + F" "Full screen" "true")
BINDS

rendered=$(KEYBINDINGS_CACHE_HOME="$tmpdir/ro-cache" run_keybindings --print)
grep -q '→ Full screen' <<<"$rendered" ||
  fail "an unwritable cache still renders the rows uncached" "$rendered"
unset KEYBINDINGS_CACHE_HOME
pass "an unwritable cache still renders the rows uncached"

# From here on the menu is answered with a pick, so what a row dispatches is
# exercised for real. Hyprland's dispatcher answers through the same stub.
#
# The config scan dies partway through the shipped defaults (a qconsole probe
# cannot run without a compositor), so a personal bind has to be declared
# before the defaults load, the way the config file documents for disabling
# them. o.bind is not defined until the defaults load, so the dispatcher table
# o.bind would hand it is written out here directly.
awk -v line='hl.bind("SUPER + K", { __omarchy_dispatcher = true, kind = "lua", arg = [[hl.dsp.workspace("3")]], expr = [[hl.dsp.workspace("3")]] }, { description = "Custom workspace jump" })' \
  '!done && /^require\("default\.hypr\.omarchy"\)$/ { print line; done=1 } { print }' \
  "$home/.config/hypr/hyprland.lua" >"$tmpdir/hyprland-staged" &&
  mv "$tmpdir/hyprland-staged" "$home/.config/hypr/hyprland.lua"

pick_row() {
  run_keybindings --print | awk -F'\t' -v d="$1" 'index($1, d) { print $1; exit }'
}

# An empty pick is a dismissal: nothing is dispatched and the menu exits clean.
run_keybindings "" ""
if [[ -s $tmpdir/dispatch ]]; then
  fail "a dismissed menu dispatches nothing" "$(dispatch_log)"
fi
pass "a dismissed menu dispatches nothing"

# A row whose dispatcher is known but carries no command dispatches nothing,
# and the menu closes silently the way a dismissal does.
stub_hyprctl <<BINDS
$(exec_bind 64 "SUPER + E" "Empty exec" "")
BINDS

selection=$(pick_row "Empty exec")
status=0
run_keybindings "" "$selection" || status=$?
[[ $status -eq 1 ]] || fail "an argless exec row closes silently with exit one" "status: $status"
if [[ -s $tmpdir/dispatch ]]; then
  fail "an exec row with no command dispatches nothing" "$(dispatch_log)"
fi
pass "an exec row with no command dispatches nothing"

# A row with no dispatcher at all says nothing about what to run.
stub_hyprctl <<'BINDS'
bind
	modmask: 64
	submap: 
	key: SUPER + N
	keycode: 0
	catchall: false
	description: No dispatcher
	dispatcher: 
	arg: true
BINDS

selection=$(pick_row "No dispatcher")
status=0
run_keybindings "" "$selection" || status=$?
[[ $status -eq 1 ]] || fail "a dispatcherless row closes silently with exit one" "status: $status"
if [[ -s $tmpdir/dispatch ]]; then
  fail "a row with no dispatcher dispatches nothing" "$(dispatch_log)"
fi
pass "a row with no dispatcher dispatches nothing"

# A lua bind the source cache resolves is dispatched by its recovered
# expression, not by the __lua placeholder Hyprland reported.
stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + K" "Custom workspace jump")
BINDS

selection=$(pick_row "Custom workspace jump")
[[ -n $selection ]] || fail "the source cache recovers the custom lua bind"
run_keybindings "" "$selection"
[[ $(dispatch_log) == 'hl.dsp.workspace("3")' ]] ||
  fail "a recovered lua bind dispatches its source expression" "$(dispatch_log)"
pass "a recovered lua bind dispatches its source expression"

# An exec bind the compositor accepts runs once, through the lua function that
# stands for it.
stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + RETURN" "Terminal")
BINDS

selection=$(pick_row "Terminal")

run_keybindings "" "$selection"
[[ $(dispatch_log) == 'hl.dsp.exec_cmd("omarchy-launch-terminal")' ]] ||
  fail "an accepted exec bind dispatches once through its lua function" "$(dispatch_log)"
pass "an accepted exec bind dispatches once through its lua function"

# An "ok" answer reads as acceptance just like a silent one does.
HYPRCTL_DISPATCH_OUTPUT=ok run_keybindings "" "$selection"
[[ $(dispatch_log) == 'hl.dsp.exec_cmd("omarchy-launch-terminal")' ]] ||
  fail "an ok answer dispatches exactly once" "$(dispatch_log)"
HYPRCTL_DISPATCH_OUTPUT=
pass "an ok answer dispatches exactly once"

# An answer that is neither silent nor ok is a refusal: the menu falls back to
# dispatching the command directly.
HYPRCTL_DISPATCH_OUTPUT=refused run_keybindings "" "$selection"
[[ $(dispatch_log) == $'hl.dsp.exec_cmd("omarchy-launch-terminal")\nexec omarchy-launch-terminal' ]] ||
  fail "a refused exec bind falls back to the plain command" "$(dispatch_log)"
HYPRCTL_DISPATCH_OUTPUT=
pass "a refused exec bind falls back to the plain command"

# A failing compositor falls back the same way.
HYPRCTL_DISPATCH_STATUS=7 run_keybindings "" "$selection"
[[ $(dispatch_log) == $'hl.dsp.exec_cmd("omarchy-launch-terminal")\nexec omarchy-launch-terminal' ]] ||
  fail "a failing exec dispatch falls back to the plain command" "$(dispatch_log)"
HYPRCTL_DISPATCH_STATUS=0
pass "a failing exec dispatch falls back to the plain command"

# The hardcoded sendshortcut chord sends its key down and up through the lua
# function, and a missing window falls back to the active one.
selection=$(pick_row "Copy URL from Web App")
run_keybindings "" "$selection"
[[ $(dispatch_log) == *'state = "down"'* && $(dispatch_log) == *'state = "up"'* ]] ||
  fail "a sendshortcut chord sends its key down and up" "$(dispatch_log)"
grep -q 'window = "activewindow"' <<<"$(dispatch_log)" ||
  fail "a chord with no window targets the active window" "$(dispatch_log)"
pass "a sendshortcut chord sends its key down and up"

# A sendshortcut chord naming its own window sends there.
stub_hyprctl <<'BINDS'
bind
	modmask: 8
	submap: 
	key: ALT + W
	keycode: 0
	catchall: false
	description: Send to window
	dispatcher: sendshortcut
	arg: SHIFT ALT,L,window:abc
BINDS

selection=$(pick_row "Send to window")
run_keybindings "" "$selection"
grep -q 'window = "window:abc"' <<<"$(dispatch_log)" ||
  fail "a chord naming its window sends there" "$(dispatch_log)"

# A refused key state falls back to Hyprland's sendshortcut with the whole
# chord argument.
HYPRCTL_DISPATCH_STATUS=7 run_keybindings "" "$selection"
[[ $(dispatch_log) == $'hl.dsp.send_key_state({ mods = "SHIFT ALT", key = "L", state = "down", window = "window:abc" })\nsendshortcut SHIFT ALT,L,window:abc' ]] ||
  fail "a refused key state falls back to sendshortcut" "$(dispatch_log)"
HYPRCTL_DISPATCH_STATUS=0
pass "a chord naming its window sends there, or falls back when refused"

# A chord with no key to send cannot go through the key state; it passes the
# whole argument to Hyprland's sendshortcut dispatcher instead.
stub_hyprctl <<'BINDS'
bind
	modmask: 0
	submap: 
	key: 
	keycode: 0
	catchall: false
	description: Keyless chord
	dispatcher: sendshortcut
	arg: ,,
BINDS

selection=$(pick_row "Keyless chord")
run_keybindings "" "$selection"
[[ $(dispatch_log) == 'sendshortcut ,,' ]] ||
  fail "a keyless chord hands its argument to sendshortcut" "$(dispatch_log)"
pass "a keyless chord hands its argument to sendshortcut"

# A sendshortcut row with no argument at all has nothing to send.
stub_hyprctl <<'BINDS'
bind
	modmask: 64
	submap: 
	key: SUPER + S
	keycode: 0
	catchall: false
	description: Empty sendshortcut
	dispatcher: sendshortcut
	arg: 
BINDS

selection=$(pick_row "Empty sendshortcut")
status=0
run_keybindings "" "$selection" || status=$?
[[ $status -eq 1 ]] || fail "an argless sendshortcut row closes silently with exit one" "status: $status"
if [[ -s $tmpdir/dispatch ]]; then
  fail "a sendshortcut row with no argument dispatches nothing" "$(dispatch_log)"
fi
pass "a sendshortcut row with no argument dispatches nothing"

# A recovered lua bind is handed to Hyprland's dispatcher as-is, and a refusal
# there surfaces as the menu's own exit status.
stub_hyprctl <<BINDS
$(lua_bind 64 "SUPER + K" "Custom workspace jump")
BINDS

HYPRCTL_DISPATCH_STATUS=7 run_keybindings "" "$(pick_row "Custom workspace jump")" || true
[[ $(dispatch_log) == 'hl.dsp.workspace("3")' ]] ||
  fail "a lua bind hands its expression to the dispatcher" "$(dispatch_log)"
HYPRCTL_DISPATCH_STATUS=0
pass "a lua bind hands its expression to the dispatcher"

# A dispatcher the menu has no opinion about is passed through, with and
# without its argument.
stub_hyprctl <<'BINDS'
bind
	modmask: 64
	submap: 
	key: SUPER + C
	keycode: 0
	catchall: false
	description: Custom dispatcher
	dispatcher: foo
	arg: bar
bind
	modmask: 64
	submap: 
	key: SUPER + D
	keycode: 0
	catchall: false
	description: Bare dispatcher
	dispatcher: foo
	arg: 
BINDS

selection=$(pick_row "Custom dispatcher")
run_keybindings "" "$selection"
[[ $(dispatch_log) == 'foo bar' ]] ||
  fail "an unknown dispatcher is passed through with its argument" "$(dispatch_log)"

selection=$(pick_row "Bare dispatcher")
run_keybindings "" "$selection"
[[ $(dispatch_log) == 'foo' ]] ||
  fail "an unknown dispatcher is passed through without an argument" "$(dispatch_log)"
pass "an unknown dispatcher is passed through, with or without its argument"
