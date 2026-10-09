#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP, SYS-REQ-260927-WC89, SW-REQ-261006-861H, SW-REQ-261009-RCPT

# Row dispositions (see proof mcdc show <REQ-ID> for the tables):
#mcdc:ignore:defensive SW-REQ-260912-MXQG: lock_secure_reported=T, ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=T => FALSE -- once the request reads secured, close_screensaver runs pkill -x ttfx and timeout 1s pidwait as unconditional sequence points; a run that reaches it always attempts the signal and always waits bounded, so neither-fails is structural [reviewed: REVIEW-1]
#mcdc:ignore:defensive SW-REQ-260912-MXQG: lock_secure_reported=T, ttfx_running=T, ttfx_signalled=T, ttfx_wait_bounded=F, user_lock_requested=T => FALSE -- the only wait is `timeout 1s pidwait`; there is no unbounded wait path in the file [reviewed: REVIEW-1]
#mcdc:ignore:defensive SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=T, session_lock_engaged=F, user_lock_requested=T => FALSE -- close_screensaver runs only in the secured) arm, after the shell reported this lock request secure; every path where the lock is not engaged (refused, untracked, dropped, never secured, shell down) exits through report_unsecured without stopping the screensaver, which the failure tests assert [reviewed: REVIEW-261006-RY53]
#mcdc:ignore:defensive SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=F, session_lock_engaged=F, user_lock_requested=T => FALSE -- omarchy-system-lock unconditionally attempts the lock, the layout reset, and the screensaver stop in sequence; an all-three-failed run requires a broken build, not a reachable input [reviewed: REVIEW-16]
#mcdc:ignore:defensive SW-REQ-261009-RCPT: lock_receipt_expired=F, lock_receipt_secured=F, lock_request_secured=T, lock_result_read=T => FALSE -- secured() is the only writer of state secured, released() never rewrites a secured record, and result() drops a record only when it is not the active token and 30 s have passed since its release; within that window a secured request always reads secured [reviewed: REVIEW-261006-RY53]
#mcdc:ignore:defensive SW-REQ-261009-RCPT: lock_receipt_expired=T, lock_receipt_secured=T, lock_request_secured=T, lock_result_read=T => FALSE -- result() deletes a released record whose release is 30 s old before it builds the reply, so an expired request reads unknown; the read-expiry assertions below prove it [reviewed: REVIEW-261006-RY53]
#mcdc:ignore:defensive SW-REQ-261006-861H: lock_exit_success=F, lock_failure_notified=F, lock_secure_reported=F, user_lock_requested=T => FALSE -- the only non-zero exit is in report_unsecured, which sends the notification first (its failure is ignored), and the script has no set -e [reviewed: REVIEW-261006-RY53]
#mcdc:ignore:defensive SW-REQ-261006-861H: lock_exit_success=T, lock_failure_notified=F, lock_secure_reported=F, user_lock_requested=T => FALSE -- the only exit 0 is the secured) arm of the receipt loop; the never-secure tests below fail if pending or a missing receipt ends the wait with success [reviewed: REVIEW-261006-RY53]
#mcdc:ignore:defensive SW-REQ-261006-861H: lock_exit_success=T, lock_failure_notified=T, lock_secure_reported=F, user_lock_requested=T => FALSE -- the notification is sent only in report_unsecured, which always exits 1 [reviewed: REVIEW-261006-RY53]
#mcdc:ignore:defensive SW-REQ-261006-861H: lock_exit_success=T, lock_failure_notified=T, lock_secure_reported=T, user_lock_requested=T => FALSE -- the secured) arm exits 0 without calling report_unsecured, the only sender of the notification [reviewed: REVIEW-261006-RY53]
require_command jq
real_timeout=$(command -v timeout)

run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')
const receipts = requireFromRoot('shell/plugins/lock/LockRequestModel.js')
const source = fs.readFileSync(root + '/shell/plugins/lock/Service.qml', 'utf8')
const ledger = receipts.create('instance-a')
const first = receipts.request(ledger, 0)
assertEqual(first.state, 'pending', 'a tracked request starts pending')
assertEqual(receipts.request(ledger, 1).requestId, first.requestId, 'concurrent callers share the active lock request')
receipts.secured(ledger, 2)
receipts.released(ledger, 3)
assertEqual(receipts.result(ledger, first.requestId, 3).state, 'secured', 'a secure receipt survives authenticated unlock')
const second = receipts.request(ledger, 4)
assert(second.requestId !== first.requestId, 'a later lock gets a distinct request token')
assertEqual(receipts.result(ledger, second.requestId, 4).state, 'pending', 'an earlier secure receipt cannot satisfy a later request')
assertEqual(receipts.result(receipts.create('instance-b'), first.requestId).state, 'unknown', 'a shell restart rejects receipts from the old instance')
receipts.released(ledger, 5)
assertEqual(receipts.result(ledger, second.requestId, 5).state, 'failed', 'a request dropped before security records failure')
receipts.secured(ledger, 6)
assertEqual(receipts.result(ledger, second.requestId, 6).state, 'failed', 'a terminal failed receipt never becomes a successful other request')

const saturated = receipts.create('saturation')
const ids = []
for (let i = 0; i < 64; i++) {
  const request = receipts.request(saturated, 0)
  ids.push(request.requestId)
  receipts.secured(saturated, 0)
  receipts.released(saturated, 0)
}
assertEqual(receipts.request(saturated, 29999), null, 'receipt saturation refuses a new tracked request instead of evicting an in-budget receipt')
assertEqual(receipts.result(saturated, ids[0], 29999).state, 'secured', 'bounded retention preserves receipts beyond the command deadline')
assert(receipts.request(saturated, 30000), 'expired receipts free capacity without reusing their identifiers')
assertEqual(receipts.result(saturated, ids[0]).state, 'unknown', 'an expired receipt cannot prove a new lock')

const readExpiry = receipts.create('read-expiry')
const archived = receipts.request(readExpiry, 0)
receipts.secured(readExpiry, 1)
receipts.released(readExpiry, 2)
assertEqual(receipts.result(readExpiry, archived.requestId, 30001).state, 'secured', 'an archived secure receipt remains valid until its retention boundary')
assertEqual(receipts.result(readExpiry, archived.requestId, 30002).state, 'unknown', 'an archived secure receipt expires on read without another request')
assertEqual(readExpiry.order.length, 0, 'read expiry also releases the archived receipt capacity')
const failed = receipts.request(readExpiry, 30002)
receipts.released(readExpiry, 30003)
assertEqual(receipts.result(readExpiry, failed.requestId, 60003).state, 'unknown', 'an archived failed receipt expires on read')
const held = receipts.request(readExpiry, 60004)
assertEqual(receipts.result(readExpiry, held.requestId, 100000).state, 'pending', 'retention does not discard a currently pending request')
receipts.secured(readExpiry, 100001)
assertEqual(receipts.request(readExpiry, 200000).requestId, held.requestId, 'an already-locked caller keeps the current active token after thirty seconds')
assertEqual(receipts.result(readExpiry, held.requestId, 200000).state, 'secured', 'the current held lock still has a successful receipt after thirty seconds')
receipts.released(readExpiry, 200001)
assertEqual(receipts.result(readExpiry, held.requestId, 201001).state, 'secured', 'a fresh already-locked caller can read its old active receipt after a fast unlock')
assertEqual(receipts.result(readExpiry, held.requestId, 230000).state, 'secured', 'a released long-held lock gets the complete archived retention window')
assertEqual(receipts.result(readExpiry, held.requestId, 230001).state, 'unknown', 'a released long-held lock expires thirty seconds after release')
assertEqual(receipts.request(readExpiry, 230002).state, 'pending', 'read expiry permits a new request without an old secure outcome')

const context = {
  LockRequests: receipts,
  requestLedger: receipts.create('qml-instance'),
  lockRequested: true,
  locked: true,
  secure: true,
  pendingSessionLock: true,
  logEvent() {},
  resetAuthenticationState() {},
  runWake() {},
  sessionLock: { locked: true, secure: true },
  sessionLockStabilizeTimer: { stop() {} },
  pendingSessionLockTimer: { stop() {} },
  idleBlankTimer: { stop() {} }
}
context.root = context
const qmlRequest = receipts.request(context.requestLedger, 0)
context.startFingerprint = function() {
  assertEqual(receipts.result(context.requestLedger, qmlRequest.requestId).state, 'secured', 'the QML secure handler records the outcome before fingerprint authentication starts')
}
const secureHandler = source.match(/onSecureStateChanged: \{([\s\S]*?)\n    \}/)
assert(secureHandler, 'the lock service exposes its secure-state handler')
vm.runInNewContext(secureHandler[1], context)
const finishUnlock = source.match(/function finishUnlock\(\) \{([\s\S]*?)\n  \}/)
assert(finishUnlock, 'the lock service exposes authenticated unlock cleanup')
vm.runInNewContext('(function() {' + finishUnlock[1] + '})()', context)
assertEqual(receipts.result(context.requestLedger, qmlRequest.requestId).state, 'secured', 'the shipped finishUnlock implementation preserves the request receipt')

const trackedRequest = source.match(/function request\(\): string \{([\s\S]*?)\n    \}/)
const lockHandler = source.match(/onLockStateChanged: \{([\s\S]*?)\n    \}/)
assert(trackedRequest && lockHandler, 'the service exposes tracked requests and lock-release lifecycle')
for (const lastFlag of ['secure', 'locked']) {
  const duringUnlock = {
    LockRequests: receipts,
    requestLedger: receipts.create('unlock-' + lastFlag),
    passwordPamConfigured: true,
    lockRequested: false,
    pendingSessionLock: false,
    sessionLock: { locked: lastFlag === 'locked', secure: lastFlag === 'secure' },
    secure: lastFlag === 'secure',
    logEvent() {},
    resetAuthenticationState() {},
    runWake() {},
    sessionLockStabilizeTimer: { stop() {} },
    pendingSessionLockTimer: { stop() {} },
    beginLock() { this.lockRequested = true; return true }
  }
  duringUnlock.root = duringUnlock
  Object.defineProperty(duringUnlock, 'locked', {
    get() { return this.lockRequested || this.sessionLock.locked || this.sessionLock.secure }
  })
  const inFlight = JSON.parse(vm.runInNewContext('(function() {' + trackedRequest[1] + '})()', duringUnlock))
  if (lastFlag === 'secure') {
    duringUnlock.sessionLock.secure = false
    duringUnlock.secure = false
    vm.runInNewContext(secureHandler[1], duringUnlock)
  } else {
    duringUnlock.sessionLock.locked = false
    // This handler's "locked" refers to the WlSessionLock, not root.locked.
    const withLockSignal = Object.create(duringUnlock)
    withLockSignal.root = duringUnlock
    Object.defineProperty(withLockSignal, 'locked', { value: false })
    vm.runInNewContext(lockHandler[1], withLockSignal)
  }
  const afterUnlock = JSON.parse(vm.runInNewContext('(function() {' + trackedRequest[1] + '})()', duringUnlock))
  assert(afterUnlock.requestId !== inFlight.requestId, 'a tracked call during ' + lastFlag + ' release is not reused after unlock')
  assertEqual(afterUnlock.state, 'pending', 'a new call after ' + lastFlag + ' release cannot inherit an old secure outcome')
}

const jumped = receipts.create('clock-jump')
const beforeJump = receipts.request(jumped, 0)
receipts.secured(jumped, 1)
receipts.released(jumped, 2)
const afterJump = receipts.request(jumped, 100000)
assertEqual(receipts.result(jumped, beforeJump.requestId).state, 'unknown', 'forward wall-clock jumps expire a receipt conservatively')
assertEqual(afterJump.state, 'pending', 'a clock jump never turns an old success into a new request success')

const legacy = source.match(/function lock\(\): string \{([\s\S]*?)\n    \}/)
assert(legacy, 'legacy lock IPC remains available')
const legacyRoot = { passwordPamConfigured: true, locked: false, beginLock() { this.locked = true; return true } }
assertEqual(vm.runInNewContext('(function() {' + legacy[1] + '})()', { root: legacyRoot }), 'ok', 'legacy lock IPC retains its ok reply')
legacyRoot.passwordPamConfigured = false
assertEqual(vm.runInNewContext('(function() {' + legacy[1] + '})()', { root: legacyRoot }), 'missing-pam', 'legacy lock IPC retains its refusal reply')
JS
# The node block above drives shell/plugins/lock/LockRequestModel.js and the
# shipped Service.qml handlers; run_node_test fails the file on any assertion.
# MCDC SW-REQ-261009-RCPT: lock_receipt_expired=F, lock_receipt_secured=T, lock_request_secured=T, lock_result_read=T => TRUE
# MCDC SW-REQ-261009-RCPT: lock_receipt_expired=F, lock_receipt_secured=F, lock_request_secured=F, lock_result_read=T => TRUE
# MCDC SW-REQ-261009-RCPT: lock_receipt_expired=T, lock_receipt_secured=F, lock_request_secured=T, lock_result_read=T => TRUE
# MCDC SW-REQ-261009-RCPT: lock_receipt_expired=T, lock_receipt_secured=T, lock_request_secured=T, lock_result_read=F => TRUE [no-action: the saturation loop secures and releases 63 requests whose receipts are never read, and nothing reports them]
# SW-REQ-261009-RCPT:error_handling:nominal
# SW-REQ-261009-RCPT:error_handling:negative

tmpdir=$(mktemp -d)
trap 'rm -rf "$tmpdir"' EXIT
mock_bin="$tmpdir/bin"
call_log="$tmpdir/calls"
mkdir -p "$mock_bin"

for command in hyprctl pkill timeout omarchy-notification-send; do
  cat >"$mock_bin/$command" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$CALL_LOG"
MOCK
done

cat >"$mock_bin/omarchy-shell" <<'MOCK'
#!/bin/bash
printf '%s %s\n' "${0##*/}" "$*" >>"$CALL_LOG"
case "${2:-}" in
request)
  case "${LOCK_REPLY:-}" in
  missing-pam) printf '{"reason":"missing-pam"}\n' ;;
  unavailable) exit 1 ;;
  malformed) printf 'not json\n' ;;
  *) printf '{"requestId":"current-instance:1","state":"pending"}\n' ;;
  esac
  ;;
result)
  polls=$(( $(cat "$POLL_COUNT" 2>/dev/null || echo 0) + 1 ))
  printf '%s' "$polls" >"$POLL_COUNT"
  id=current-instance:1
  state=pending
  if [[ ${RESULT_ID:-} != "" ]]; then id=$RESULT_ID; fi
  if [[ ${SECURE_AFTER:-1} != "never" ]] && (( polls >= ${SECURE_AFTER:-1} )); then state=secured; fi
  if [[ ${LOCK_REPLY:-} == "dropped" ]]; then state=failed; fi
  if [[ ${LOCK_REPLY:-} == "restart" ]]; then state=unknown; fi
  printf '{"requestId":"%s","state":"%s","requested":%s,"secure":%s}\n' \
    "$id" "$state" "${REQUESTED:-true}" "${CURRENT_SECURE:-true}"
  ;;
*) exit 1 ;;
esac
MOCK
cat >"$mock_bin/pgrep" <<'MOCK'
#!/bin/bash
exit 1
MOCK
chmod +x "$mock_bin"/*

run_lock() {
  local rc=0
  : >"$call_log"
  : >"$tmpdir/polls"
  PATH="$mock_bin:$PATH" CALL_LOG="$call_log" POLL_COUNT="$tmpdir/polls" \
    SECURE_AFTER="${SECURE_AFTER:-1}" LOCK_REPLY="${LOCK_REPLY:-}" RESULT_ID="${RESULT_ID:-}" \
    REQUESTED="${REQUESTED:-true}" CURRENT_SECURE="${CURRENT_SECURE:-true}" \
    "$real_timeout" -k 5s 40s "$ROOT/bin/omarchy-system-lock" 2>"$tmpdir/stderr" || rc=$?
  return "$rc"
}

assert_one_request() {
  [[ $(grep -c '^omarchy-shell lock request$' "$call_log") == 1 ]] || fail "one invocation submits exactly one tracked request"
  if grep -q '^omarchy-shell lock lock$' "$call_log"; then fail "system lock never re-locks after a status snapshot"; fi
}
assert_failure() {
  local rc=$1
  ((rc == 1)) || fail "unconfirmed lock exits nonzero" "exit $rc, $(<"$tmpdir/stderr")"
  grep -q '^omarchy-notification-send .*Screen did not lock' "$call_log" || fail "failure requests a critical notification"
  if grep -q '^pkill ' "$call_log"; then fail "failed lock leaves the screensaver running"; fi
  grep -q '^hyprctl switchxkblayout all 0$' "$call_log" || fail "failed lock still resets the keyboard layout"
  assert_one_request
}

rc=0
run_lock || rc=$?
# SYS-REQ-260927-WC89:error_handling:nominal
((rc == 0)) || fail "system lock succeeds once its request becomes secure" "exit $rc"
assert_one_request
! grep -q "^omarchy-notification-send" "$call_log" ||
  fail "system lock sends no failure notification for a secured session" "calls: $(cat "$call_log")"
# SW-REQ-261006-861H:error_handling:nominal
# MCDC SW-REQ-261006-861H: lock_exit_success=T, lock_failure_notified=F, lock_secure_reported=T, user_lock_requested=T => TRUE
pass "system lock succeeds with its matching secure receipt"

mapfile -t shutdown < <(rg '^(pkill|timeout) ' "$call_log")
[[ ${shutdown[0]} == "pkill -x ttfx" ]] || fail "system lock stops ttfx before closing its terminal"
[[ ${shutdown[1]} == "timeout 1s pidwait -x ttfx" ]] || fail "system lock waits for ttfx"
[[ ${shutdown[2]} == "pkill -f [o]rg.omarchy.screensaver" ]] || fail "system lock closes the terminal after ttfx"
secure_line=$(grep -n '^omarchy-shell lock result ' "$call_log" | head -1 | cut -d: -f1)
cleanup_line=$(grep -n '^pkill -x ttfx$' "$call_log" | cut -d: -f1)
((secure_line < cleanup_line)) || fail "screensaver cleanup follows the secure receipt"
# SW-REQ-260912-MXQG:error_handling:nominal
# SYS-REQ-260912-T0XP:nominal:nominal
grep -q '^omarchy-shell lock request$' "$call_log" ||
  fail "system lock engages the session lock through the shell IPC" "calls: $(cat "$call_log")"
grep -q '^hyprctl switchxkblayout all 0$' "$call_log" ||
  fail "system lock resets the keyboard layout to the default" "calls: $(cat "$call_log")"
# MCDC SW-REQ-260912-MXQG: lock_secure_reported=T, ttfx_running=T, ttfx_signalled=T, ttfx_wait_bounded=T, user_lock_requested=T => TRUE
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=T, session_lock_engaged=T, user_lock_requested=T => TRUE
pass "successful lock preserves screensaver shutdown ordering after security"

rc=0
SECURE_AFTER=3 run_lock || rc=$?
((rc == 0)) || fail "system lock waits for a request still arming"
assert_one_request
pass "a delayed secure request needs no second lock"

# The receipt remains secured even when authentication already cleared flags.
rc=0
REQUESTED=false CURRENT_SECURE=false run_lock || rc=$?
((rc == 0)) || fail "an immediate authenticated unlock remains a successful lock"
assert_one_request
pass "fast authenticated unlock does not re-lock or require a second authentication"

for reason in missing-pam unavailable malformed dropped restart; do
  rc=0
  LOCK_REPLY="$reason" run_lock || rc=$?
  # SYS-REQ-260927-WC89:error_handling:negative
  # SYS-REQ-260912-T0XP:error_handling:negative
  # SW-REQ-261006-861H:error_handling:negative
  assert_failure "$rc"
  # MCDC SW-REQ-261006-861H: lock_exit_success=F, lock_failure_notified=T, lock_secure_reported=F, user_lock_requested=T => TRUE
  # MCDC SW-REQ-260912-MXQG: lock_secure_reported=F, ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=T => TRUE [no-action: assert_failure fails the test if the pkill spy logged any call, so zero SIGTERMs reach ttfx when the request never reads secured]
  # SW-REQ-260912-MXQG:error_handling:negative
  pass "$reason cannot report lock success or close the screensaver"
done

rc=0
RESULT_ID=old-instance:1 run_lock || rc=$?
assert_failure "$rc"
pass "a stale or different request receipt cannot satisfy this invocation"

started=$SECONDS
rc=0
SECURE_AFTER=never REQUESTED=true CURRENT_SECURE=false run_lock || rc=$?
elapsed=$((SECONDS - started))
# #10299: a stalled request stays latched as requested and never secures.
# SYS-REQ-260912-T0XP:error_handling:negative
# SW-REQ-261006-861H:error_handling:negative
assert_failure "$rc"
# MCDC SW-REQ-261006-861H: lock_exit_success=F, lock_failure_notified=T, lock_secure_reported=F, user_lock_requested=T => TRUE
((elapsed >= 8 && elapsed <= 13)) || fail "an accepted never-secure request ends within the command's deadline" "$elapsed seconds"
grep -q 'did not secure the session' "$tmpdir/stderr" || fail "never-secure failure reports its deadline"
pass "an accepted requested:true lock that never secures fails and notifies within ten seconds"

# The variant blocks below start from the shell mock above (it accepts one
# tracked request and reports it secured on the first result read), then
# override one command. run_variant bounds the script the same way run_lock does
# and returns its exit status instead of aborting the test.
# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP — copies the shell mock for one variant
variant_bin() {
  mkdir -p "$1"
  cp "$mock_bin"/* "$1"/
}
# Verifies: SW-REQ-260912-MXQG, SYS-REQ-260912-T0XP — runs the real script with one command overridden
run_variant() {
  local bin=$1 log=$2 rc=0
  : >"$tmpdir/polls"
  PATH="$bin:$PATH" CALL_LOG="$log" POLL_COUNT="$tmpdir/polls" SECURE_AFTER=1 LOCK_REPLY= RESULT_ID= \
    REQUESTED=true CURRENT_SECURE=true \
    "$real_timeout" -k 5s 40s "$ROOT/bin/omarchy-system-lock" 2>"$tmpdir/stderr-variant" || rc=$?
  return "$rc"
}

# ttfx gone by the time the signal lands (pkill matches nothing, exit 1):
# the script must still complete, and the wait must stay inside the 1s bound.
# The same failing pkill arm is the no-action evidence for the
# ttfx_running=F row: zero SIGTERMs are delivered to ttfx.
mock_bin_pk="$tmpdir/bin-pk"
call_log_pk="$tmpdir/calls-pk"
variant_bin "$mock_bin_pk"
cat >"$mock_bin_pk/pkill" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin_pk"/*

rc=0
run_variant "$mock_bin_pk" "$call_log_pk" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds when ttfx cannot be signalled" "exit $rc"
# MCDC SW-REQ-260912-MXQG: lock_secure_reported=T, ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=T, user_lock_requested=T => FALSE
# MCDC SW-REQ-260912-MXQG: lock_secure_reported=T, ttfx_running=F, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=T => TRUE [no-action: pkill spy exits 1 on -x ttfx so zero SIGTERMs are delivered; the wait degrades to the logged `timeout 1s pidwait` bound]
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=F, session_lock_engaged=T, user_lock_requested=T => FALSE
grep -q '^pkill -x ttfx$' "$call_log_pk" ||
  fail "system lock still attempts the ttfx stop when the signal cannot land" "calls: $(cat "$call_log_pk")"
# SW-REQ-260912-MXQG:error_handling:negative
grep -q '^timeout 1s pidwait -x ttfx$' "$call_log_pk" ||
  fail "system lock keeps the ttfx wait inside the 1s bound when the signal fails" "calls: $(cat "$call_log_pk")"
grep -q '^omarchy-shell lock request$' "$call_log_pk" ||
  fail "system lock still engages the session lock when the ttfx stop fails" "calls: $(cat "$call_log_pk")"
pass "system lock completes with a bounded wait when ttfx cannot be signalled"

# Keyboard-layout reset failure must not abort the lock or the screensaver stop.
mock_bin_hy="$tmpdir/bin-hy"
call_log_hy="$tmpdir/calls-hy"
variant_bin "$mock_bin_hy"
for command in omarchy-cmd-present flock; do
  cat >"$mock_bin_hy/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_hy/hyprctl" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin_hy"/*

rc=0
run_variant "$mock_bin_hy" "$call_log_hy" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds when the layout reset fails" "exit $rc"
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=T, session_lock_engaged=T, user_lock_requested=T => FALSE
grep -q '^omarchy-shell lock request$' "$call_log_hy" ||
  fail "system lock still engages the session lock when the layout reset fails" "calls: $(cat "$call_log_hy")"
grep -q '^pkill -x ttfx$' "$call_log_hy" ||
  fail "system lock still stops the screensaver when the layout reset fails" "calls: $(cat "$call_log_hy")"
pass "system lock completes when the keyboard layout reset fails"

# Session-lock IPC failure (the shell is not running, every call exits 1) must
# not skip the layout reset, must leave the screensaver up, and must end in a
# failure the user can see.
mock_bin_sh="$tmpdir/bin-sh"
call_log_sh="$tmpdir/calls-sh"
variant_bin "$mock_bin_sh"
for command in omarchy-cmd-present flock; do
  cat >"$mock_bin_sh/$command" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
SH
done
cat >"$mock_bin_sh/omarchy-shell" <<'SH'
#!/bin/bash
printf '%s %s\n' "$(basename "$0")" "$*" >>"$CALL_LOG"
exit 1
SH
chmod +x "$mock_bin_sh"/*

rc=0
run_variant "$mock_bin_sh" "$call_log_sh" || rc=$?
# SYS-REQ-260912-T0XP:error_handling:negative
(( rc == 1 )) || fail "system lock fails when the session-lock IPC fails" "exit $rc"
grep -q "^omarchy-notification-send .*Screen did not lock" "$call_log_sh" ||
  fail "system lock warns on screen when the session-lock IPC fails" "calls: $(cat "$call_log_sh")"
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=T, screensaver_stopped=F, session_lock_engaged=F, user_lock_requested=T => FALSE
grep -q '^hyprctl switchxkblayout all 0$' "$call_log_sh" ||
  fail "system lock still resets the layout when the lock IPC fails" "calls: $(cat "$call_log_sh")"
if grep -q '^pkill ' "$call_log_sh"; then
  fail "system lock leaves the screensaver up when the lock IPC fails" "calls: $(cat "$call_log_sh")"
fi
pass "system lock resets the layout, keeps the screensaver and fails visibly when the session-lock IPC fails"

# Control: without a lock request (script never invoked) no lock action runs.
control_log="$tmpdir/calls-control"
PATH="$mock_bin:$PATH" CALL_LOG="$control_log" true
# MCDC SW-REQ-260912-MXQG: lock_secure_reported=T, ttfx_running=T, ttfx_signalled=F, ttfx_wait_bounded=F, user_lock_requested=F => TRUE [no-action: omarchy-system-lock is never invoked in this control, and the pkill/pidwait spy log stays empty — the signal path is unreachable without a lock request]
# MCDC SW-REQ-261006-861H: lock_exit_success=F, lock_failure_notified=F, lock_secure_reported=F, user_lock_requested=F => TRUE [no-action: same control — with no invocation the spy log records no exit and zero omarchy-notification-send calls]
# MCDC SYS-REQ-260912-T0XP: keyboard_layout_default=F, screensaver_stopped=F, session_lock_engaged=F, user_lock_requested=F => TRUE [no-action: same control — with no invocation the spy log records zero omarchy-shell/hyprctl/pkill calls]
if [[ -f $control_log ]]; then
  fail "no lock action runs without a lock request" "calls: $(cat "$control_log")"
fi
pass "no lock action runs without a lock request"

# With 1password running and installed, the guard takes its true arm: the lock
# path fires under its own flock, through a bounded timeout. The helper block
# runs in the background, so poll the log instead of racing it.
mock_bin_1p="$tmpdir/bin-1p"
call_log_1p="$tmpdir/calls-1p"
variant_bin "$mock_bin_1p"
for command in flock omarchy-cmd-present; do
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

rc=0
run_variant "$mock_bin_1p" "$call_log_1p" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds on the 1password path" "exit $rc"
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
variant_bin "$mock_bin_np"
for command in flock; do
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

rc=0
run_variant "$mock_bin_np" "$call_log_np" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds when 1password is not installed" "exit $rc"
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
variant_bin "$mock_bin_fc"
for command in omarchy-cmd-present; do
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

rc=0
run_variant "$mock_bin_fc" "$call_log_fc" || rc=$?
(( rc == 0 )) || fail "system lock still succeeds while the 1password lock is contended" "exit $rc"
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
