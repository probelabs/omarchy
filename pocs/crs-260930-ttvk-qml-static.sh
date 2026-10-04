#!/bin/bash
# Anchored evidence for CRS-260930-TTVK QML-runtime claims:
#   C01 (PAM flip during stabilize engages lock; watchdog stands down)
#   C03 (abnormal PAM error double-counts failedAttempts)
#   C04 (screensChanged clears blank intent, never re-arms the blank timer)
#   C05 (empty readlink result wipes a good backgroundPath)
#   C06 (in-place wallpaper overwrite keeps the stale poster)
#   C08 (spontaneous compositor unlock drops the request and wakes displays)
# C07 (a failed fingerprintPam.start() arms no retry) moved to the runtime
# reproducer pocs/crs-260930-ttvk-c07.sh: upstream omacom/omarchy#7158 routes the
# failed start through settleFingerprintAttempt, which arms the retry one call
# deeper, so a text anchor on startFingerprint can no longer decide it.
# Method: each assertion extracts the LIVE lines from shell/plugins/lock/
# Service.qml and asserts the defect mechanism's code shape. Every assertion
# is tied to the runtime scenario documented in the claim (traced end-to-end
# by the reviewer's ATTACK phase); a fix that changes the mechanism flips the
# corresponding assertion and this script exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
F="$REPO/shell/plugins/lock/Service.qml"
[[ -f $F ]] || { echo "Service.qml missing"; exit 2; }

fail=0
chk() { # chk <claim> <description> <pattern-found> <file-with-match>
  if grep -q "$3" "$4" 2>/dev/null; then
    echo "  [$1] PRESENT: $2"
  else
    echo "  [$1] ABSENT: $2 (fix present?)"
    fail=1
  fi
}

T="$(mktemp)"; trap 'rm -f "$T"' EXIT

echo "== C01: requestSessionLock has no passwordPamConfigured re-check =="
sed -n '/function requestSessionLock/,/^  }/p' "$F" > "$T"
chk C01 "gate only on lockRequested/sessionLock state, not PAM config" "if (!lockRequested || sessionLock.locked || sessionLock.secure) return" "$T"
if grep -q "passwordPamConfigured" "$T"; then echo "  [C01] ABSENT: PAM re-check exists (fix present?)"; fail=1; else echo "  [C01] PRESENT: no passwordPamConfigured re-check before sessionLock.locked = true"; fi
sed -n '/function checkStrandedLock/,/^  }/p' "$F" > "$T"
chk C01 "stranded watchdog stands down once lockRequested is set" "if (locked || lockRequested) {" "$T"

echo "== C03: onError and onCompleted both call handlePasswordFailure =="
sed -n '/onCompleted: function(result)/,/onError: function(error)/p' "$F" > "$T"
chk C03 "onCompleted error path calls handlePasswordFailure" "else root.handlePasswordFailure()" "$T"
sed -n '/onError: function(error)/,+2p' "$F" > "$T"
chk C03 "onError ALSO calls handlePasswordFailure (Quickshell pairs error->completed(Error))" "onError: function(error) {" "$T"
grep -q "handlePasswordFailure" "$T" && echo "  [C03] PRESENT: double-call pairing confirmed" || { echo "  [C03] ABSENT (fix present?)"; fail=1; }
sed -n '/function handlePasswordFailure/,/^  }/p' "$F" > "$T"
chk C03 "failedAttempts += 1 with no per-transaction latch" "failedAttempts += 1" "$T"

echo "== C04: screensChanged clears displaysBlank without re-arming blank =="
sed -n '/function onScreensChanged/,/^    }/p' "$F" > "$T"
chk C04 "displaysBlank = false on screens change" "root.displaysBlank = false" "$T"
if grep -qE "armBlankTimer|idleBlankTimer" "$T"; then echo "  [C04] ABSENT: blank re-arm exists (fix present?)"; fail=1; else echo "  [C04] PRESENT: no armBlankTimer/idleBlankTimer call in the handler"; fi

echo "== C05: readlink handler stores an empty result unconditionally =="
sed -n '/onStreamFinished: {/,/^      }/p' "$F" | head -20 > "$T"
chk C05 "next !== backgroundPath branch overwrites path even when empty" "if (next !== root.backgroundPath)" "$T"
if grep -qE 'next === ""|next !== ""|!next' "$T"; then echo "  [C05] ABSENT: empty guard exists (fix present?)"; fail=1; else echo "  [C05] PRESENT: no non-empty guard before backgroundPath = next"; fi

echo "== C06: refreshPoster drops a request while running; onExited commits stale poster =="
sed -n '/function refreshPoster/,/^  }/p' "$F" > "$T"
chk C06 "running guard returns without queueing the new request" "if (posterProc.running) return" "$T"
sed -n '/id: posterProc/,/^  }/p' "$F" > "$T"
chk C06 "onExited commits when sourcePath still equals backgroundPath (in-place overwrite)" "sourcePath !== root.backgroundPath" "$T"

echo "== C08: spontaneous unlock branch drops the request without re-locking =="
sed -n '/if (!locked && root.lockRequested)/,/^      }/p' "$F" > "$T"
chk C08 "lockRequested cleared on external lock loss" "root.lockRequested = false" "$T"
chk C08 "displays woken" "root.runWake()" "$T"
if grep -qE "queueSessionLock|beginLock" "$T"; then echo "  [C08] ABSENT: re-lock exists (fix present?)"; fail=1; else echo "  [C08] PRESENT: no queueSessionLock/beginLock re-lock in the branch"; fi

echo "== controls: intended safe paths present (PoC rules 3/10) =="
# C01 control: the missing-pam gate exists at the lock IPC instant - the check
# the stabilize window bypasses is present and load-bearing on the main path.
sed -n '/function lock(/,/^  }/p' "$F" > "$T"
if grep -q "passwordPamConfigured" "$T"; then
  echo "  [CTRL-C01] OK: the lock IPC still gates on passwordPamConfigured at the request instant"
else
  echo "  [CTRL-C01] FAILED: main-path PAM gate not found; PoC cannot distinguish the stabilize-window bypass from a missing gate"
  fail=2
fi
# C08 control: the user-driven unlock path (finishUnlock) pre-clears
# lockRequested BEFORE locked=false, so it never reaches the fail-open branch.
sed -n '/function finishUnlock/,/^  }/p' "$F" > "$T"
LREQ=$(grep -n "lockRequested = false" "$T" | head -1 | cut -d: -f1)
LLOCK=$(grep -n "locked = false" "$T" | head -1 | cut -d: -f1)
if [[ -n $LREQ && -n $LLOCK ]] && (( LREQ < LLOCK )); then
  echo "  [CTRL-C08] OK: finishUnlock clears the request before the lock state, so the user path never hits the fail-open branch"
else
  echo "  [CTRL-C08] FAILED: safe-path ordering not found in finishUnlock; PoC inconclusive"
  fail=2
fi

if (( fail )); then
  echo "ANCHORED-EVIDENCE: one or more mechanisms no longer present in the live file - claims possibly fixed"
  exit 1
fi
echo "ANCHORED-EVIDENCE: all 6 QML mechanism claims match the live code (C01 C03 C04 C05 C06 C08)"
exit 0
