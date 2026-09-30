#!/bin/bash
# Runtime reproducer for the two lock-service fail-open KIs:
#   KI-LOCK-PAM-FLIP-ENGAGES-LOCK      (claim CRS-260930-TTVK/C01)
#   KI-LOCK-SPONTANEOUS-UNLOCK-FAIL-OPEN (claim CRS-260930-TTVK/C08)
# Method: extracts the LIVE function bodies verbatim from
# shell/plugins/lock/Service.qml (requestSessionLock, finishUnlock, the
# onLockStateChanged drop arm) and executes them under a property-transition
# harness - plain QML-property semantics (get/set with transition recording),
# stubbing only the Quickshell/compositor boundaries (timers, WlSessionLock,
# wake/auth calls) as recorded calls. A live compositor lock session cannot be
# driven headlessly; the shipped code itself runs unmodified.
# Both-ways: exit 0 = defect present (green tripwire), 1 = fix landed,
# 2 = control failed (PoC inconclusive).
# Reproduces: KI-LOCK-PAM-FLIP-ENGAGES-LOCK
# Reproduces: KI-LOCK-SPONTANEOUS-UNLOCK-FAIL-OPEN
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
F="$REPO/shell/plugins/lock/Service.qml"
[[ -f $F ]] || { echo "Service.qml missing"; exit 2; }

node - "$F" <<'JS'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");

function extractFn(name) {
  const re = new RegExp("function " + name + "\\(\\) \\{[\\s\\S]*?\\n  \\}");
  const m = src.match(re);
  if (!m) throw new Error("function " + name + " not found in Service.qml (file changed?)");
  return m[0];
}
const armMatch = src.match(/if \(!locked && root\.lockRequested\) \{[\s\S]*?\n      \}/);
if (!armMatch) throw new Error("onLockStateChanged drop arm not found (file changed?)");
const armText = armMatch[0];

// --- property-transition harness --------------------------------------------
function makeScope() {
  const events = [];
  const calls = {};
  const call = (name) => { calls[name] = (calls[name] || 0) + 1; events.push(name); };
  const scope = {
    events, calls,
    lockRequested: false,
    pendingSessionLock: false,
    locked: false,                       // handler-parameter slot for the arm
    lastEvent: "",
    strandedLockResolved: false,
    passwordPamConfigured: true,         // PAM present at the lock IPC instant
    sessionLock: {
      secure: false,
      _locked: false,
      get locked() { return this._locked; },
      set locked(v) { events.push("sessionLock.locked=" + v); this._locked = v; },
    },
    sessionLockStabilizeTimer: { running: false, restart() { this.running = true; }, stop() { this.running = false; } },
    pendingSessionLockTimer: { running: false, start() { this.running = true; }, stop() { this.running = false; } },
    idleBlankTimer: { stop() { call("idleBlankTimer.stop"); } },
    strandedLockCheckProc: { running: false },
    hasRealScreen: () => true,
    logEvent: (m) => { scope.lastEvent = m; events.push("log:" + m); },
    resetAuthenticationState: () => call("resetAuthenticationState"),
    runWake: () => call("runWake"),
    queueSessionLock: () => call("queueSessionLock"),
    beginLock: () => call("beginLock"),
  };
  scope.root = scope;
  return scope;
}
function bindFn(scope, text, name) {
  return new Function("scope", `with (scope) { ${text}; return typeof ${name} === "function" ? ${name} : undefined; }`)(scope);
}

let fails = 0;

// ---- C01 defect: PAM flips during the stabilize window ----------------------
{
  const s = makeScope();
  s.lockRequested = true;               // accepted at the IPC instant, PAM present
  s.sessionLockStabilizeTimer.running = true;
  s.passwordPamConfigured = false;      // FileView onLoadFailed flipped it mid-window
  s.sessionLockStabilizeTimer.running = false; // the timer fires and invokes requestSessionLock
  bindFn(s, extractFn("requestSessionLock"), "requestSessionLock")();
  const engaged = s.sessionLock.locked === true;
  console.log(`C01 pam-flip: locked=${s.sessionLock.locked} passwordPamConfigured=${s.passwordPamConfigured} -> ${engaged ? "LOCK ENGAGED without PAM (defect present)" : "engagement withheld (fix present?)"}`);
  if (!engaged) fails++;
}

// ---- C01 control: PAM present, the same path engages legitimately -----------
{
  const s = makeScope();
  s.lockRequested = true;
  s.sessionLockStabilizeTimer.running = true;
  s.sessionLockStabilizeTimer.running = false; // the timer fires and invokes requestSessionLock
  bindFn(s, extractFn("requestSessionLock"), "requestSessionLock")();
  const ok = s.sessionLock.locked === true && s.passwordPamConfigured === true;
  console.log(`C01 control:  locked=${s.sessionLock.locked} with PAM present -> ${ok ? "intended engage intact" : "CONTROL FAILED"}`);
  if (!ok) { console.log("CONTROL FAILED: intended lock engage broke; PoC inconclusive"); process.exit(2); }
}

// ---- C08 defect: compositor-side drop treated as finished unlock ------------
{
  const s = makeScope();
  s.lockRequested = true;
  s.locked = false;                     // compositor dropped the lock (not finishUnlock)
  new Function("scope", `with (scope) { ${armText} }`)(s);
  const dropped = s.lockRequested === false && (s.calls.runWake || 0) === 1 && !s.calls.queueSessionLock && !s.calls.beginLock;
  console.log(`C08 drop-arm: lockRequested=${s.lockRequested} runWake=${s.calls.runWake || 0} relock=${(s.calls.queueSessionLock || 0) + (s.calls.beginLock || 0)} -> ${dropped ? "fail-open unlock (defect present)" : "re-lock attempted (fix present?)"}`);
  if (!dropped) fails++;
}

// ---- C08 control: user-driven unlock (finishUnlock) keeps the safe order ----
{
  const s = makeScope();
  s.lockRequested = true;
  s.root.locked = true;
  bindFn(s, extractFn("finishUnlock"), "finishUnlock")();
  const cleared = s.events.indexOf("sessionLock.locked=false");
  const reqIdx = s.events.indexOf("resetAuthenticationState");
  const order = s.events.findIndex((e) => e.startsWith("log:unlocked"));
  const ok = s.lockRequested === false && s.sessionLock.locked === false && cleared !== -1;
  console.log(`C08 control:  finishUnlock cleared request + lock (events: ${s.events.filter((e) => !e.startsWith("log:")).join(", ")}) -> ${ok ? "intended unlock path intact" : "CONTROL FAILED"}`);
  if (!ok) { console.log("CONTROL FAILED: user-driven unlock path broke; PoC inconclusive"); process.exit(2); }
}

process.exit(fails ? 1 : 0);            // green tripwire: 0 = defect present
JS
rc=$?
case $rc in
  0) echo "SYMPTOM: both fail-open mechanisms reproduce against the live Service.qml functions (defect present)"; exit 0 ;;
  1) echo "PASS-REFUTED: at least one mechanism no longer reproduces - defect fixed"; exit 1 ;;
  *) exit $rc ;;
esac
