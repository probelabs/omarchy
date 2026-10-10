#!/bin/bash
# Reproduces: KI-261009-DZ3P
# Stranded-lock recovery logs lock-stranded / lock-requested /
# lock-pending: screen-stabilizing, then requestSessionLock is asked to
# take the session lock. Correct behaviour (SW-REQ-260912-WJYM): the probe
# exited 0, the service does not hold a session lock (sessionLock.locked is
# false), and password PAM is configured, so the service shall take the
# session lock once. The defect: a stale sessionLock.secure (true while
# sessionLock.locked is still false — the lock surface is gone, the shell
# is still alive) makes requestSessionLock return without taking the lock.
# The functions are the live bodies from shell/plugins/lock/Service.qml.
# A headless compositor cannot raise secure without locked (the protocol
# makes that pair unreachable); the reported stall is that pair.
set -u

ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
KI="KI-261009-DZ3P"
SRC="$ROOT/shell/plugins/lock/Service.qml"

setup_fail() {
  echo "SETUP: $*"
  exit 2
}

command -v node >/dev/null || setup_fail "node is not on PATH"
[[ -f $SRC ]] || setup_fail "lock service missing: $SRC"

export KI SRC
node << 'JS'
const fs = require("fs");
const src = fs.readFileSync(process.env.SRC, "utf8");
const KI = process.env.KI;

function extractFn(name) {
  const re = new RegExp("function " + name + "\\(\\) \\{[\\s\\S]*?\\n  \\}");
  const m = src.match(re);
  if (!m) throw new Error("function " + name + " not found");
  return m[0];
}

const exited = src.match(/id: strandedLockCheckProc[\s\S]*?(onExited: function\(exitCode\) \{[\s\S]*?\n    \})/);
if (!exited) throw new Error("strandedLockCheckProc onExited not found");
const probeExitedText = exited[1].replace(/^onExited:\s*/, "");

function makeScope() {
  const events = [];
  const sessionLock = {
    secure: false,
    _locked: false,
    get locked() { return this._locked; },
    set locked(v) {
      events.push("sessionLock.locked=" + v);
      this._locked = v;
    },
  };
  const scope = {
    events,
    sessionLock,
    lockRequested: false,
    pendingSessionLock: false,
    strandedLock: false,
    strandedLockResolved: false,
    passwordPamConfigured: true,
    lastEvent: "",
    sessionLockStabilizeTimer: {
      running: false,
      restart() { this.running = true; events.push("stabilize.restart"); },
      stop() { this.running = false; },
    },
    pendingSessionLockTimer: {
      running: false,
      start() { this.running = true; },
      stop() { this.running = false; },
    },
    strandedLockCheckProc: { running: false },
    hasRealScreen: () => true,
    logEvent(m) { scope.lastEvent = m; events.push("log:" + m); },
    resetAuthenticationState() { events.push("resetAuthenticationState"); },
    armBlankTimer() { events.push("armBlankTimer"); },
    refreshBackground() {},
    refreshFingerprintStatus() {},
    Qt: { callLater(fn) { events.push("callLater"); } },
  };
  Object.defineProperty(scope, "locked", {
    get() {
      return scope.lockRequested || sessionLock.locked || sessionLock.secure;
    },
    enumerable: true,
  });
  scope.root = scope;
  return scope;
}

function bind(scope, text, name) {
  const fn = new Function(
    "scope",
    "with (scope) {\n" + text + "\nreturn " + name + ";\n}"
  )(scope);
  if (typeof fn !== "function") throw new Error(name + " did not bind");
  scope[name] = fn;
  return fn;
}

let requestSessionLockText, queueSessionLockText, beginLockText, recoverText;
try {
  requestSessionLockText = extractFn("requestSessionLock");
  queueSessionLockText = extractFn("queueSessionLock");
  beginLockText = extractFn("beginLock");
  recoverText = extractFn("recoverStrandedLock");
} catch (err) {
  console.log("SETUP: " + err.message);
  process.exit(2);
}

function load(scope) {
  bind(scope, requestSessionLockText, "requestSessionLock");
  bind(scope, queueSessionLockText, "queueSessionLock");
  bind(scope, beginLockText, "beginLock");
  bind(scope, recoverText, "recoverStrandedLock");
  scope.onProbeExited = new Function(
    "scope",
    "with (scope) {\nreturn (" + probeExitedText + ");\n}"
  )(scope);
}

function armRecovery(scope) {
  load(scope);
  scope.onProbeExited(0);
}

// Control: the same recovery with secure still false must take the session lock.
// If it does not, the harness is not executing the live take path.
{
  const scope = makeScope();
  try {
    armRecovery(scope);
  } catch (err) {
    console.log("SETUP: control recovery threw: " + err.message);
    process.exit(2);
  }
  if (scope.sessionLock.locked !== false) {
    console.log("SETUP: recovery took the session lock before the stabilize timer fired");
    process.exit(2);
  }
  const needed = ["log:lock-stranded: recovering", "log:lock-requested", "log:lock-pending: screen-stabilizing"];
  for (const line of needed) {
    if (!scope.events.includes(line)) {
      console.log("SETUP: control did not log " + line + " events=" + scope.events.join(","));
      process.exit(2);
    }
  }
  scope.sessionLockStabilizeTimer.running = false;
  scope.requestSessionLock();
  if (scope.sessionLock.locked !== true) {
    console.log("SETUP: with secure false, requestSessionLock did not take the session lock events=" + scope.events.join(","));
    process.exit(2);
  }
  console.log("control: secure=false took the session lock");
}

// Reported stall: recovery has started (those three log lines) and the
// session lock is not held, then sessionLock.secure reads true. The
// stabilize timer fires and requestSessionLock must still take the lock.
{
  const scope = makeScope();
  try {
    armRecovery(scope);
  } catch (err) {
    console.log("SETUP: defect recovery threw: " + err.message);
    process.exit(2);
  }
  if (scope.sessionLock.locked !== false || scope.lockRequested !== true) {
    console.log("SETUP: recovery did not stop at the pending request");
    process.exit(2);
  }
  scope.sessionLock.secure = true;
  scope.sessionLockStabilizeTimer.running = false;
  scope.requestSessionLock();
  console.log("after-stale-secure sessionLocked=" + scope.sessionLock.locked + " secure=" + scope.sessionLock.secure + " lastEvent=" + scope.lastEvent);
  console.log("events=" + scope.events.join(","));
  if (scope.sessionLock.locked === true) {
    console.log("PROOF-REPRODUCER: defect-absent " + KI);
    process.exit(0);
  }
  console.log("PROOF-REPRODUCER: defect-present " + KI);
  process.exit(1);
}
JS
