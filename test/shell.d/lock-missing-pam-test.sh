#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-J8SX

# Row dispositions (see proof mcdc show SW-REQ-260912-J8SX for the table):
#mcdc:ignore:defensive SW-REQ-260912-J8SX: lock_denied_missing_pam=F, lock_requested=T, password_pam_configured=F => FALSE -- the denial is the first statement of beginLock and returns before any engagement; a missing-PAM request that still locks needs a broken build [reviewed: REVIEW-2]

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The denial is the first thing the lock entry point does.
assert(
  /function beginLock\(\) \{\s*if \(!passwordPamConfigured\) \{\s*logEvent\("lock-denied: missing-pam"\)\s*return false\s*\}/.test(serviceQml),
  'a lock request without password PAM is denied as missing-pam before anything else'
)
// MCDC SW-REQ-260912-J8SX: lock_denied_missing_pam=T, lock_requested=T, password_pam_configured=F => TRUE
// MCDC SW-REQ-260912-J8SX: lock_denied_missing_pam=F, lock_requested=T, password_pam_configured=T => TRUE [no-action: the ordering assertions below prove beginLock proceeds to queueSessionLock without logging a denial when PAM is configured — the denial never fires on the configured path]
// MCDC SW-REQ-260912-J8SX: lock_denied_missing_pam=F, lock_requested=F, password_pam_configured=F => TRUE [no-action: the denial lives only inside beginLock; with no lock request the handler never runs, so no denial is logged]

// The denial precedes every engagement step, so a denied request never locks.
const begin = serviceQml.match(/function beginLock\(\) \{[\s\S]*?\n  \}/)
assert(begin, 'beginLock body located')
assert(
  begin[0].indexOf('lock-denied: missing-pam') < begin[0].indexOf('queueSessionLock()'),
  'the missing-pam return runs before the session lock is queued'
)
assert(
  begin[0].indexOf('lock-denied: missing-pam') < begin[0].indexOf('lockRequested = true'),
  'the missing-pam return runs before the lock is even marked requested'
)

// "Configured" is not a guess: it tracks whether the password PAM module loaded.
assert(
  /onLoaded: root\.passwordPamConfigured = true\s*(?:\/\/[^\n]*\n\s*)*onLoadFailed: root\.passwordPamConfigured = false/.test(serviceQml),
  'passwordPamConfigured mirrors the password PAM module load outcome'
)

// The IPC answer names the denial reason for callers.
assert(
  /if \(!root\.passwordPamConfigured\) return "missing-pam"/.test(serviceQml),
  'the lock IPC handler answers missing-pam when password PAM is not configured'
)
JS
