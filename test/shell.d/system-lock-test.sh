#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT

mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

for command in omarchy-shell hyprctl pkill timeout; do
  cat >"$mock_bin/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done

cat >"$mock_bin/pgrep" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin"/*

PATH="$mock_bin:$PATH" CALL_LOG="$call_log" "$ROOT/bin/omarchy-system-lock"
mapfile -t shutdown < <(rg '^(pkill|timeout) ' "$call_log")

[[ ${shutdown[0]} == "pkill -x ttfx" ]] ||
  fail "system lock stops ttfx before closing its terminal" "calls: ${shutdown[*]}"
[[ ${shutdown[1]} == "timeout 1s pidwait -x ttfx" ]] ||
  fail "system lock waits for ttfx to exit" "calls: ${shutdown[*]}"
[[ ${shutdown[2]} == "pkill -f [o]rg.omarchy.screensaver" ]] ||
  fail "system lock closes the screensaver terminal after ttfx exits" "calls: ${shutdown[*]}"
pass "system lock waits for ttfx before closing its terminal"

# With 1password running and installed, the line-17 guard takes its true arm:
# the lock path fires under its own flock, through a bounded timeout. The
# helper block runs in the background, so poll the log instead of racing it.
mock_bin_1p="$tmpdir/bin-1p"
call_log_1p="$tmpdir/calls-1p"
mkdir -p "$mock_bin_1p"
for command in omarchy-shell hyprctl pkill timeout flock omarchy-cmd-present; do
  cat >"$mock_bin_1p/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_1p/pgrep" <<'SH'
#!/bin/bash
exit 0
SH
chmod +x "$mock_bin_1p"/*

PATH="$mock_bin_1p:$PATH" CALL_LOG="$call_log_1p" "$ROOT/bin/omarchy-system-lock"
for _ in {1..50}; do
  [[ -f $call_log_1p ]] && grep -q '^timeout --kill-after=1s 3s 1password --lock' "$call_log_1p" && break
  sleep 0.05
done
[[ -f $call_log_1p ]] || fail "system lock logs its calls when 1password is running"
grep -q '^flock -n 9$' "$call_log_1p" ||
  fail "system lock serializes the 1password lock through its own flock" "calls: $(cat "$call_log_1p")"
grep -q '^timeout --kill-after=1s 3s 1password --lock' "$call_log_1p" ||
  fail "system lock locks 1password through a bounded timeout" "calls: $(cat "$call_log_1p")"
pass "system lock locks 1password when it is running"

# Running but not installed (the guard's second condition false) must skip the
# 1password path entirely.
mock_bin_np="$tmpdir/bin-np"
call_log_np="$tmpdir/calls-np"
mkdir -p "$mock_bin_np"
for command in omarchy-shell hyprctl pkill timeout flock; do
  cat >"$mock_bin_np/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_np/pgrep" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin_np/omarchy-cmd-present" <<'SH'
#!/bin/bash
exit 1
SH
chmod +x "$mock_bin_np"/*

PATH="$mock_bin_np:$PATH" CALL_LOG="$call_log_np" "$ROOT/bin/omarchy-system-lock"
sleep 0.2
if [[ -f $call_log_np ]] && grep -q '^flock -n 9$' "$call_log_np"; then
  fail "system lock skips the 1password lock path when 1password is not installed" \
    "calls: $(cat "$call_log_np")"
fi
pass "system lock skips the 1password lock path when 1password is not installed"

# A contended 1password lock must skip the lock attempt: the flock guard's
# exit-0 arm keeps a second system-lock from stacking Electron helper trees.
mock_bin_fc="$tmpdir/bin-fc"
call_log_fc="$tmpdir/calls-fc"
mkdir -p "$mock_bin_fc"
for command in omarchy-shell hyprctl pkill timeout omarchy-cmd-present; do
  cat >"$mock_bin_fc/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_fc/pgrep" <<'SH'
#!/bin/bash
exit 0
SH
cat >"$mock_bin_fc/flock" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin_fc"/*

PATH="$mock_bin_fc:$PATH" CALL_LOG="$call_log_fc" "$ROOT/bin/omarchy-system-lock"
for _ in {1..50}; do
  [[ -f $call_log_fc ]] && grep -q '^flock -n 9$' "$call_log_fc" && break
  sleep 0.05
done
[[ -f $call_log_fc ]] && grep -q '^flock -n 9$' "$call_log_fc" ||
  fail "system lock attempts the 1password flock before giving up" "calls: ${call_log_fc:-missing}"
if grep -q '1password --lock' "$call_log_fc"; then
  fail "system lock does not lock 1password while its lock is contended" "calls: $(cat "$call_log_fc")"
fi
pass "system lock skips the 1password lock while its lock is contended"
