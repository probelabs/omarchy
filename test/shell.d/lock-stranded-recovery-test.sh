#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-WJYM, SYS-REQ-260912-FRG0

# Row dispositions (see proof mcdc show <REQ-ID> for the tables):
#mcdc:ignore:defensive SW-REQ-260912-WJYM: password_pam_configured=T, recovery_logged=F, stranded_lock_detected=T, stranded_lock_recovered_once=F => FALSE -- the recovery guard (strandedLock && !locked && passwordPamConfigured) routes every detected+configured stranded lock into recoverStrandedLock; ignoring it needs a broken build [reviewed: REVIEW-13]
#mcdc:ignore:defensive SW-REQ-260912-WJYM: password_pam_configured=T, recovery_logged=F, stranded_lock_detected=T, stranded_lock_recovered_once=T => FALSE -- logEvent("lock-stranded: recovering") sits inside the recovery block next to beginLock(); recovering without logging is structurally absent [reviewed: REVIEW-13]
#mcdc:ignore:defensive SW-REQ-260912-WJYM: password_pam_configured=T, recovery_logged=T, stranded_lock_detected=T, stranded_lock_recovered_once=F => FALSE -- the journal entry is emitted only by the recovery path; logging without recovering is structurally absent [reviewed: REVIEW-13]

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The compositor holds the lock past its client, so a fresh shell must retake it.
assert(
  /Component\.onCompleted:[\s\S]*checkStrandedLock\(\)/.test(serviceQml),
  'the lock service asks the compositor whether the session is locked at startup'
)

assert(
  /id: strandedLockCheckProc[\s\S]*omarchy-hyprland-session-locked/.test(serviceQml),
  'the startup check goes through the shared session lock helper'
)

// "No output to read" taken for "unlocked" leaves the failsafe up for good.
assert(
  /onExited: function\(exitCode\) \{[\s\S]*if \(exitCode === 2\) return/.test(serviceQml),
  'an undetermined answer never resolves the check'
)

assert(
  /if \(exitCode === 2\) return\s*\n\s*root\.strandedLockResolved = true/.test(serviceQml),
  'only a compositor that reports a lock counts as a stranded lock'
)
// MCDC SW-REQ-260912-WJYM: password_pam_configured=F, recovery_logged=F, stranded_lock_detected=T, stranded_lock_recovered_once=F => TRUE [no-action: the recoverStrandedLock guard returns early when !passwordPamConfigured — the source assertion above pins recovery behind the PAM gate, so no recovery or log runs without it]
// MCDC SW-REQ-260912-WJYM: password_pam_configured=T, recovery_logged=F, stranded_lock_detected=F, stranded_lock_recovered_once=F => TRUE [no-action: the exitCode === 2 return and the exitCode === 0 gate prove no recovery path runs when the probe does not report a stranded lock]

// omarchy-restart-shell re-locks a fresh shell, possibly mid-question.
assert(
  /root\.strandedLock = exitCode === 0 && !root\.locked && !root\.lockRequested/.test(serviceQml),
  'a lock this shell took while the check was in flight is not stranded'
)

assert(
  /id: strandedLockRetryTimer[\s\S]*running: !root\.strandedLockResolved && remaining > 0/.test(serviceQml),
  'the check retries while the compositor cannot answer, and stops once it has'
)

// A display asleep for hours outlasts any retry budget.
assert(
  /function onScreensChanged\(\) \{[\s\S]*root\.checkStrandedLock\(\)/.test(serviceQml),
  'a screen coming back re-asks whether a lock is stranded'
)

// One probe is not enough: a monitor still coming up cannot answer.
assert(
  /function onScreensChanged\(\) \{[\s\S]*strandedLockRetryTimer\.rearm\(\)[\s\S]*root\.checkStrandedLock\(\)/.test(serviceQml),
  'a screen coming back gives the check its settling time again'
)

assert(
  /function rearm\(\) \{\s*if \(!root\.strandedLockResolved\) remaining = budget/.test(serviceQml),
  're-arming never restarts a check that already has its answer'
)

// A lock this shell owns ends the search.
assert(
  /function checkStrandedLock\(\) \{\s*if \(strandedLockResolved \|\| strandedLockCheckProc\.running\) return[\s\S]*if \(locked \|\| lockRequested\) \{\s*strandedLockResolved = true/.test(serviceQml),
  'a lock this shell took is not treated as stranded'
)

assert(
  /function recoverStrandedLock\(\) \{\s*if \(!strandedLock \|\| locked \|\| !passwordPamConfigured\) return/.test(serviceQml),
  'recovery is skipped unless a stranded lock is waiting and PAM can authenticate it'
)

// The compositor answer and the PAM config land asynchronously, in either
// order, so whichever arrives last has to drive the recovery.
assert(
  /onPasswordPamConfiguredChanged: \{[\s\S]*checkStrandedLock\(\)/.test(serviceQml),
  'recovery retries once the PAM config has loaded'
)

// The failsafe can be cleared from a TTY while PAM is still loading.
assert(
  /onPasswordPamConfiguredChanged: \{\s*if \(!passwordPamConfigured\) return\s*\n\s*strandedLock = false\s*\n\s*strandedLockResolved = false/.test(serviceQml),
  'a late PAM config re-asks the compositor instead of trusting a stale answer'
)

assert(
  /strandedLock = false\s*\n\s*logEvent\("lock-stranded: recovering"\)\s*\n\s*beginLock\(\)/.test(serviceQml),
  'recovery takes the lock once and records it in the journal'
)
// MCDC SW-REQ-260912-WJYM: password_pam_configured=T, recovery_logged=T, stranded_lock_detected=T, stranded_lock_recovered_once=T => TRUE
// MCDC SYS-REQ-260912-FRG0: lock_state_queried=T, lock_state_reported=T, stranded_lock_recovered=T => TRUE
JS
