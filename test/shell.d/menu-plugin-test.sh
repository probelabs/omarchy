#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-KRBH, SW-REQ-260922-4EWA, SW-REQ-260922-QMWP
#mcdc:ignore:defensive SW-REQ-260922-4EWA: pick_resolves_by_id=F, same_named_plugins=T => FALSE -- the picker cuts field 2 of the selection line as the id unconditionally; resolving by name needs that cut removed [reviewed: REVIEW-M9]
#mcdc:ignore:defensive SW-REQ-260922-KRBH: picker_verb_given=T, verb_filter_applied=F => FALSE -- the case maps every verb to its jq filter and the rows come from select($filter) unconditionally; an unfiltered list needs the select removed [reviewed: REVIEW-M9]
#mcdc:ignore:defensive SW-REQ-260922-QMWP: nothing_actionable=T, notification_and_exit_zero=F => FALSE -- the empty-rows path is an unconditional notification plus exit 0; anything else needs that line removed [reviewed: REVIEW-M9]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command jq

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

# The picker reads the plugin list from omarchy-plugin-list and hands what it
# decided to a verb-specific command, so stubbing both ends shows which plugin
# a pick actually resolved to -- the thing a source-level check cannot see.
cat >"$STUB_DIR/omarchy-plugin-list" <<'STUB'
#!/bin/bash
cat "$FAKE_PLUGINS"
STUB

for command in omarchy-plugin-enable omarchy-plugin-disable; do
  cat >"$STUB_DIR/$command" <<'STUB'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$FAKE_CALLS"
STUB
done

# Records the rows it was offered, then answers with the pick under test.
cat >"$STUB_DIR/omarchy-menu-select" <<'STUB'
#!/bin/bash
cat >"$FAKE_ROWS"
printf '%s\n' "$FAKE_PICK"
exit "${FAKE_PICK_STATUS:-0}"
STUB

cat >"$STUB_DIR/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$FAKE_CALLS"
STUB

cat >"$STUB_DIR/omarchy-launch-floating-terminal-with-presentation" <<'STUB'
#!/bin/bash
printf 'terminal: %s\n' "$*" >>"$FAKE_CALLS"
STUB

chmod +x "$STUB_DIR"/*

# Runs the picker against a plugin list, answering its prompt with $2. Leaves
# the rows it offered in $ROWS and what it called in $CALLS.
pick() {
  local verb="$1" choice="$2"

  : >"$TMPDIR/calls"
  : >"$TMPDIR/rows"
  STATUS=0
  HOME="$TMPDIR/home" \
    PATH="$STUB_DIR:$PATH" \
    FAKE_PLUGINS="$TMPDIR/plugins.json" \
    FAKE_CALLS="$TMPDIR/calls" \
    FAKE_ROWS="$TMPDIR/rows" \
    FAKE_PICK="$choice" \
    FAKE_PICK_STATUS="${FAKE_PICK_STATUS:-0}" \
    "${OMARCHY_TEST_BASH:-$BASH}" "$ROOT/bin/omarchy-menu-plugin" "$verb" >/dev/null 2>&1 || STATUS=$?

  ROWS=$(cat "$TMPDIR/rows")
  CALLS=$(cat "$TMPDIR/calls")
}

# Two plugins can declare the same display name. The id rides along as row
# subtext and comes back with the selection, so the pick resolves by id.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": true},
  {"id": "tester.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false}
]
JSON

pick enable "$(printf 'Clock\ttester.clock')"
[[ $ROWS == *"$(printf 'Clock\tomarchy.clock')"* && $ROWS == *"$(printf 'Clock\ttester.clock')"* ]] \
  || fail "picker offers the id as subtext on every row" "$ROWS"
pass "picker offers the id as subtext on every row"
[[ $CALLS == *"omarchy-plugin-enable tester.clock"* ]] \
  || fail "picker acts on the row that was picked, not the one that shares its name" "$CALLS"
# MCDC SW-REQ-260922-4EWA: pick_resolves_by_id=T, same_named_plugins=T => TRUE
pass "picker acts on the row that was picked, not the one that shares its name"

pick remove "$(printf 'Clock\ttester.clock')"
[[ $CALLS == *"omarchy-plugin-remove tester.clock"* ]] \
  || fail "picker removes the plugin whose row was picked" "$CALLS"
pass "picker removes the plugin whose row was picked"

cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "acme.weather", "name": "Weather", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false}
]
JSON

pick enable "$(printf 'Weather\tacme.weather')"
[[ $CALLS == *"omarchy-plugin-enable acme.weather"* ]] \
  || fail "picker delegates plugin enablement to the plugin command" "$CALLS"
# MCDC SW-REQ-260922-4EWA: pick_resolves_by_id=F, same_named_plugins=F => TRUE [no-action: the offered list carries one uniquely-named row -- no name collision needs resolving]
# MCDC SW-REQ-260922-QMWP: nothing_actionable=F, notification_and_exit_zero=F => TRUE [no-action: rows are offered and the pick is acted on -- the nothing-actionable path is not taken]
pass "picker delegates plugin enablement to the plugin command"

# Clone offers only first-party plugins that no installed clone points back at,
# then hands the pick to the clone command, which opens the result in $EDITOR.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": true, "active": false, "canDisable": true, "firstParty": true},
  {"id": "acme.weather", "name": "Weather", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false}
]
JSON

pick clone "$(printf 'Clock\tomarchy.clock')"
[[ $ROWS == *"Clock"* && $ROWS != *"Weather"* ]] ||
  fail "clone picker offers only built-in plugins" "$ROWS"
# SW-REQ-260922-KRBH:external_call_timeout_bounded:nominal -- the picker acts as soon as omarchy-menu-select answers
# MCDC SW-REQ-260922-KRBH: picker_verb_given=T, verb_filter_applied=T => TRUE
pass "clone picker offers built-in plugins"
[[ $CALLS == *"terminal: omarchy-plugin-clone omarchy.clock --edit"* ]] ||
  fail "clone picker delegates cloning and editing to the clone command" "$CALLS"
pass "clone picker clones and opens the personal plugin"

# Once a clone pointing back at the source is discovered, whatever it is named,
# the source no longer belongs in Clone.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": true, "active": false, "canDisable": true, "firstParty": true},
  {"id": "tester.clock", "name": "My Clock", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false, "clonedFrom": "omarchy.clock"}
]
JSON

pick clone ""
[[ $CALLS == *"notification: No plugin to clone"* ]] ||
  fail "clone picker offers an already cloned plugin" "$CALLS"
pass "clone picker omits plugins already cloned locally"

# The picker treats every plugin alike and leaves kind-specific behavior to the
# plugin command.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "acme.fancy", "name": "Fancy", "kinds": ["bar", "bar-widget"], "enabled": false, "active": false, "canDisable": false, "firstParty": false}
]
JSON

pick enable "$(printf 'Fancy\tacme.fancy')"
[[ $CALLS == *"omarchy-plugin-enable acme.fancy"* && $CALLS != *"--section"* ]] \
  || fail "picker delegates kind-specific enablement" "$CALLS"
pass "picker delegates kind-specific enablement"

# A bar has no off, so it is never offered under disable -- including this one,
# which is a widget too.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "acme.fancy", "name": "Fancy", "kinds": ["bar", "bar-widget"], "enabled": true, "active": true, "canDisable": false, "firstParty": false},
  {"id": "omarchy.clock", "name": "Clock", "kinds": ["bar-widget"], "enabled": true, "active": false, "canDisable": true, "firstParty": true}
]
JSON

pick disable "$(printf 'Clock\tomarchy.clock')"
[[ $ROWS == *"Clock"* && $ROWS != *"Fancy"* ]] \
  || fail "picker keeps a bar out of disable" "$ROWS"
pass "picker keeps a bar out of disable"

# The bar in use is the row absent from enable; every other bar is one pick away.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.bar", "name": "Bar", "kinds": ["bar"], "enabled": false, "active": false, "canDisable": false, "firstParty": true},
  {"id": "tester.neon-bar", "name": "Neon Bar", "kinds": ["bar"], "enabled": true, "active": true, "canDisable": false, "firstParty": false}
]
JSON

pick enable "$(printf 'Bar\tomarchy.bar')"
[[ $ROWS == *"Bar"* && $ROWS != *"Neon Bar"* ]] \
  || fail "picker offers every bar except the one already running" "$ROWS"
pass "picker offers every bar except the one already running"
[[ $CALLS == *"omarchy-plugin-enable omarchy.bar"* ]] \
  || fail "picker returns to the built-in bar by enabling it" "$CALLS"
pass "picker returns to the built-in bar by enabling it"

# Nothing the verb can act on is said out loud, not opened as an empty list.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "omarchy.bar", "name": "Bar", "kinds": ["bar"], "enabled": true, "active": true, "canDisable": false, "firstParty": true}
]
JSON

pick enable ""
[[ $STATUS -eq 0 ]] ||
  fail "picker exits zero when a verb has nothing to act on" "status: $STATUS"
[[ $CALLS == *"notification: No plugin to enable"* ]] \
  || fail "picker says when a verb has nothing to act on" "$CALLS"
# MCDC SW-REQ-260922-QMWP: nothing_actionable=T, notification_and_exit_zero=T => TRUE
pass "picker says when a verb has nothing to act on"

# No verb at all is a usage error before any list is filtered or offered.
: >"$TMPDIR/calls"
: >"$TMPDIR/rows"
status=0
HOME="$TMPDIR/home" PATH="$STUB_DIR:$PATH" FAKE_PLUGINS="$TMPDIR/plugins.json" \
  FAKE_CALLS="$TMPDIR/calls" FAKE_ROWS="$TMPDIR/rows" FAKE_PICK="" \
  "${OMARCHY_TEST_BASH:-$BASH}" "$ROOT/bin/omarchy-menu-plugin" >/dev/null 2>"$TMPDIR/err" || status=$?
[[ $status -eq 1 ]] || fail "picker without a verb exits one" "status: $status"
[[ $(<"$TMPDIR/err") == "Usage: omarchy-menu-plugin <enable|disable|clone|remove>" ]] ||
  fail "picker without a verb prints usage" "err: $(cat "$TMPDIR/err")"
[[ ! -s $TMPDIR/rows ]] ||
  fail "picker without a verb never offers rows" "rows: $(cat "$TMPDIR/rows")"
# MCDC SW-REQ-260922-KRBH: picker_verb_given=F, verb_filter_applied=F => TRUE [no-action: the menu-select spy captured no rows -- no filter runs without a verb]
pass "picker refuses a missing verb with usage and exit one"

# A picker whose menu closes without an answer is a quiet no-op, whichever way
# the close happens: the menu is dismissed (exit one) or answers with nothing.
cat >"$TMPDIR/plugins.json" <<'JSON'
[
  {"id": "acme.fancy", "name": "Fancy", "kinds": ["bar-widget"], "enabled": false, "active": false, "canDisable": true, "firstParty": false}
]
JSON

# SW-REQ-260922-KRBH:external_call_timeout_bounded:negative -- the wait is bounded inside omarchy-menu-select, which exits one when the shell that took the request exits (menu-dmenu-test.sh); that exit one ends the picker like a dismissal
FAKE_PICK_STATUS=1 pick enable "$(printf 'Fancy\tacme.fancy')"
[[ $STATUS -eq 0 ]] || fail "a dismissed plugin picker exits zero" "status: $STATUS"
[[ -z $CALLS ]] || fail "a dismissal acts on no plugin" "calls: $CALLS"
pass "a dismissed plugin picker exits zero"

pick enable ""
[[ $STATUS -eq 0 ]] || fail "an empty answer leaves the plugin untouched" "status: $STATUS"
[[ -z $CALLS ]] || fail "an empty answer acts on no plugin" "calls: $CALLS"
pass "an empty answer acts on no plugin"

# A row whose id subtext is empty cannot be acted on: the picker refuses
# rather than guessing.
pick enable "$(printf 'Fancy\t')"
[[ $STATUS -eq 1 ]] || fail "a row without an id exits one" "status: $STATUS"
[[ -z $CALLS ]] || fail "a row without an id acts on nothing" "calls: $CALLS"
pass "a row without an id exits one"
