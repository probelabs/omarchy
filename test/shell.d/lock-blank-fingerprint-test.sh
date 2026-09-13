#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-ND55

# Row dispositions (see proof mcdc show SW-REQ-260912-ND55 for the table):
#mcdc:ignore:defensive SW-REQ-260912-ND55: blank_displays=F, idle_timeout_expired=T, password_auth_in_flight=F, timer_rearmed_after_suspend=F => FALSE -- every expired idle timer ends in runBlank, an in-flight password hold, or a post-suspend re-arm; an expiry with none of the three needs a broken handler [reviewed: REVIEW-3]

run_node_test <<'JS'
const fs = require('fs')
const serviceQml = fs.readFileSync(path.join(root, 'shell/plugins/lock/Service.qml'), 'utf8')

// The fingerprint PAM stays armed for the whole lock waiting for a finger, so
// `authenticating` is true from lock until unlock on every machine with a
// reader enrolled. Gating the blank on it leaves the panel lit all night.
assert(
  /if \(root\.lockRequested && !root\.authenticatingPassword\) root\.runBlank\(\)/.test(serviceQml),
  'only a password check in flight stops the blank timer from blanking'
)
// MCDC SW-REQ-260912-ND55: blank_displays=T, idle_timeout_expired=T, password_auth_in_flight=F, timer_rearmed_after_suspend=F => TRUE
// MCDC SW-REQ-260912-ND55: blank_displays=F, idle_timeout_expired=T, password_auth_in_flight=T, timer_rearmed_after_suspend=F => TRUE

assert(
  !/idleBlankTimer[\s\S]*?!root\.authenticating\)/.test(serviceQml),
  'the blank timer never gates on the combined authenticating state'
)

assert(
  /onAuthenticatingPasswordChanged: \{\s*if \(!lockRequested\) return\s*if \(authenticatingPassword\) idleBlankTimer\.stop\(\)\s*else armBlankTimer\(\)/.test(serviceQml),
  'the blank timer is held off by password entry and re-armed when it finishes'
)

assert(
  /function runWake\(\) \{[\s\S]*if \(lockRequested\) armBlankTimer\(\)/.test(serviceQml),
  'a wake re-arms the blank timer while the session stays locked'
)
// MCDC SW-REQ-260912-ND55: blank_displays=F, idle_timeout_expired=T, password_auth_in_flight=F, timer_rearmed_after_suspend=T => TRUE
// MCDC SW-REQ-260912-ND55: blank_displays=F, idle_timeout_expired=F, password_auth_in_flight=F, timer_rearmed_after_suspend=F => TRUE [no-action: the source assertions pin runBlank behind idleBlankTimer.onTriggered and the wake re-arm behind runWake; without an expiry no blank and no re-arm run]

assert(
  !/onAuthenticatingChanged:/.test(serviceQml),
  'the combined authenticating state no longer drives the blank timer'
)
JS
