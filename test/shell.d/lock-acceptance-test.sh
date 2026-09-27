#!/bin/bash

set -euo pipefail

# Acceptance-level end-to-end test for the lock stakeholder requirement,
# driven against the INTEGRATED system: a live Hyprland session and the live
# quickshell omarchy shell with its lock plugin. The user-facing entry point
# bin/omarchy-system-lock runs for real, and the locked outcome is read back
# from the COMPOSITOR (hyprctl monitors solitaryBlockedBy contains LOCK) via
# bin/omarchy-hyprland-session-locked — the compositor-reported lock state
# the criterion asks for.
#
# STK-REQ-260912-XJ5D:AC-001:acceptance
#
# Harness gating: on a host without a Wayland compositor or quickshell (the
# macOS dogfood host) this test skips cleanly. The run that clears the
# witness_deferred staging must happen inside the integrated proof session
# (proof box: ~/proof-env/gui/start-session.sh; source
# ~/proof-env/gui/session.env first so hyprctl and omarchy-shell reach the
# proof instance).
#
# Cleanup note for the operator: the proof Hyprland instance is disposable.
# After this test locks it, restart the session with start-session.sh (it is
# idempotent and kills only its own instance) before running menu suites.
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_compositor "lock acceptance test"

if ! command -v quickshell >/dev/null 2>&1; then
  pass "quickshell not installed; skipping lock acceptance test"
  exit 0
fi

require_command hyprctl
require_command jq

# The shell must be answering before a lock can be requested of it.
shell_up=false
for _ in {1..50}; do
  if "$ROOT/bin/omarchy-shell" -q shell ping >/dev/null 2>&1; then
    shell_up=true
    break
  fi
  sleep 0.2
done
if ! $shell_up; then
  pass "omarchy shell not running in this session; skipping lock acceptance test"
  exit 0
fi

# Precondition: the session starts unlocked (or undetermined-but-answerable
# is not acceptable here: an acceptance run starts from a known state).
"$ROOT/bin/omarchy-hyprland-session-locked" && locked_rc=0 || locked_rc=$?
if [[ $locked_rc -eq 0 ]]; then
  pass "session is already locked; restart the proof session before the acceptance run"
  exit 1
fi

# The stakeholder action: lock the session through the real entry point.
"$ROOT/bin/omarchy-system-lock"

# The compositor-reported outcome: ext-session-lock held by the shell's lock
# plugin shows up as LOCK in solitaryBlockedBy on a monitor. Poll: the lock
# engage is asynchronous across the IPC boundary.
locked=false
for _ in {1..100}; do
  if "$ROOT/bin/omarchy-hyprland-session-locked"; then
    locked=true
    break
  fi
  sleep 0.2
done

$locked || fail "compositor reports a locked session after omarchy-system-lock" \
  "hyprctl monitors: $(hyprctl -j monitors 2>/dev/null | jq -c '[.[] | {name, solitaryBlockedBy}]' 2>/dev/null || echo unavailable)"

pass "AC-001: omarchy system lock results in a compositor-reported locked session (STK-REQ-260912-XJ5D AC-001)"
