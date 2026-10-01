#!/bin/bash
# Green tripwire for SYS-REQ-260922-47T8 external_call_timeout_bounded.
# Reproduces: KI-MENU-GUARD-BATCH-NO-DEADLINE
#
# Mechanism: Menu.qml evaluateGuards() runs every when:/checked:/disabled: guard
# of the menu as ONE child, guardProc.command = ["bash", "-lc", script], with
# no deadline. While guardProc.running is true, every later evaluateGuards()
# only sets guardsPending and returns. So one guard expression that blocks
# (waits on a lock, a slow probe) keeps the batch alive indefinitely, no later
# evaluation ever starts, and the menu keeps showing the last complete answer
# set - rows checked/visible for a state that no longer holds.
#
# Harness: pocs/47t8-guard-batch-no-deadline.js runs the REAL evaluateGuards()
# and guardProc onRead/onExited bodies extracted verbatim from
# shell/plugins/menu/Menu.qml at run time, with the real MenuModel.guardScript(),
# and spawns the exact argv Menu.qml sets on guardProc.command. Side effects are
# confined to a temp dir: HOME is a scratch dir, pacman (read by the guard
# prelude) is a PATH stub that lists nothing, and the blocking guard waits on a
# lock file the harness itself holds. All spawned process groups are killed on
# exit.
#
# GREEN TRIPWIRE: pins the buggy behavior, so it PASSES while the defect is
# present. Control arm: a healthy batch lands its answers and a re-evaluation
# after a state flip refreshes them. Defect arm: after a guard that blocks is
# added, the batch is still running at ~4s with zero exits, a later
# re-evaluation spawns nothing (guardsPending=true), and a row's checked answer
# stays stale after the state it describes has changed.
#
# tripwire_mutation: give the batch a deadline in Menu.qml evaluateGuards(), e.g.
#   guardProc.command = ["timeout", "-k", "1", "2", "bash", "-lc", script]
# (or a per-guard timeout in MenuModel.guardLine). The blocked batch then exits
# at ~2s, the "still running with zero exits" assertion fails, and the tripwire
# flips red. The control arm is unaffected.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
for c in node flock bash; do
  command -v "$c" >/dev/null || { echo "$c required"; exit 2; }
done
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin" "$TMP/home"
printf '#!/bin/bash\nexit 0\n' >"$TMP/bin/pacman"   # guard prelude package scan: empty, read-only
chmod +x "$TMP/bin/pacman"
TRIPWIRE_TMP="$TMP" node "$REPO/pocs/47t8-guard-batch-no-deadline.js"
