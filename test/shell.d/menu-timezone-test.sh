#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-SWFT, SW-REQ-260922-4VAV
#mcdc:ignore:defensive SW-REQ-260922-SWFT: timezone_picked=T, timezone_set_and_refreshed=F => FALSE -- after a successful pick the set-timezone call, the clock refresh, and the notification are unconditional sequence points under set -e [reviewed: REVIEW-M3]
#mcdc:ignore:defensive SW-REQ-260922-4VAV: timezone_not_set=F, timezone_pick_cancelled=T => FALSE -- a cancelled pick takes `|| exit 1` before any set-timezone call; setting a zone from a cancelled pick is structurally absent [reviewed: REVIEW-M3]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

STUB_DIR="$TMPDIR/stub"
mkdir -p "$STUB_DIR"

cat >"$STUB_DIR/timedatectl" <<'STUB'
#!/bin/bash
printf 'timedatectl %s\n' "$*" >>"$SPY_LOG"
if [[ $1 == "list-timezones" ]]; then
  printf 'UTC\nEurope/Berlin\nAmerica/New_York\n'
fi
STUB

cat >"$STUB_DIR/sudo" <<'STUB'
#!/bin/bash
exec "$@"
STUB

cat >"$STUB_DIR/omarchy-menu-select" <<'STUB'
#!/bin/bash
if [[ $FAKE_PICK == "<cancel>" ]]; then
  exit 1
fi
printf '%s\n' "$FAKE_PICK"
STUB

cat >"$STUB_DIR/omarchy-shell" <<'STUB'
#!/bin/bash
printf 'omarchy-shell %s\n' "$*" >>"$SPY_LOG"
STUB

cat >"$STUB_DIR/omarchy-notification-send" <<'STUB'
#!/bin/bash
printf 'notification: %s\n' "$*" >>"$SPY_LOG"
STUB

chmod +x "$STUB_DIR"/*

run_timezone() {
  local pick="$1"
  : >"$TMPDIR/calls"
  PATH="$STUB_DIR:$PATH" SPY_LOG="$TMPDIR/calls" FAKE_PICK="$pick" \
    "${OMARCHY_TEST_BASH:-$BASH}" "$ROOT/bin/omarchy-menu-timezone" >"$TMPDIR/out" 2>&1 && STATUS=0 || STATUS=$?
  CALLS=$(cat "$TMPDIR/calls")
}

# A completed pick sets the zone, refreshes the clock, and notifies.
# SW-REQ-260922-SWFT:external_call_timeout_bounded:nominal -- the zone is set as soon as omarchy-menu-select answers
run_timezone "Europe/Berlin"
[[ $STATUS -eq 0 ]] || fail "menu timezone exits zero on a pick" "status: $STATUS"
[[ $CALLS == *"timedatectl set-timezone Europe/Berlin"* ]] ||
  fail "menu timezone sets the picked zone" "calls: $CALLS"
[[ $CALLS == *"omarchy-shell -q omarchy.clock refresh"* ]] ||
  fail "menu timezone refreshes the clock widget" "calls: $CALLS"
[[ $CALLS == *"notification: Timezone is now set to Europe/Berlin"* ]] ||
  fail "menu timezone notifies the new zone" "calls: $CALLS"
# MCDC SW-REQ-260922-SWFT: timezone_picked=T, timezone_set_and_refreshed=T => TRUE
# MCDC SW-REQ-260922-4VAV: timezone_not_set=F, timezone_pick_cancelled=F => TRUE [no-action: a completed pick is not a cancellation -- the spy log shows the zone being set, not kept]
pass "menu timezone sets and refreshes a picked zone"

# A cancelled pick changes nothing: no set-timezone, no refresh, no
# notification, exit one from the `|| exit 1` guard.
# SW-REQ-260922-SWFT:external_call_timeout_bounded:negative -- the wait is bounded inside omarchy-menu-select, which exits one when the shell that took the request exits (menu-dmenu-test.sh); that exit one ends this caller like a cancel
run_timezone "<cancel>"
[[ $STATUS -eq 1 ]] || fail "menu timezone exits one on a cancelled pick" "status: $STATUS"
[[ $CALLS != *"set-timezone"* ]] ||
  fail "menu timezone never sets a zone from a cancelled pick" "calls: $CALLS"
[[ $CALLS != *"refresh"* && $CALLS != *"notification"* ]] ||
  fail "menu timezone skips refresh and notification on a cancelled pick" "calls: $CALLS"
# MCDC SW-REQ-260922-4VAV: timezone_not_set=T, timezone_pick_cancelled=T => TRUE [no-action: the spy log contains zero set-timezone calls -- the zone is untouched after a cancel]
# MCDC SW-REQ-260922-SWFT: timezone_picked=F, timezone_set_and_refreshed=F => TRUE [no-action: the spy log contains zero set-timezone calls -- nothing is set or refreshed without a pick]
pass "menu timezone leaves the zone untouched on a cancelled pick"
