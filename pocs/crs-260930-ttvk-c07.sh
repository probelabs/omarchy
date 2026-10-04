#!/bin/bash
# Regression reproducer for claim CRS-260930-TTVK/C07
# (KI-LOCK-FPRINT-START-FAIL-NO-RETRY; specs SYS-REQ-260912-T0XP, SW-REQ-261004-296X).
#
# Defect: when fingerprintPam.start() returned false, startFingerprint
# (shell/plugins/lock/Service.qml) only cleared fingerprintAuthenticating and armed
# no retry. Only the PAM completion and error handlers re-armed
# fingerprintRetryTimer, and neither runs when a conversation never began, so a
# failed start left fingerprint unlock dead for the rest of the lock.
# Upstream omacom/omarchy#7158 (879d6583d, merged 2026-10-04) sends a failed
# start through settleFingerprintAttempt, which arms the retry with the paced
# FingerprintModel.retryDelayMs delay, and re-runs the enrollment probe.
#
# Method: extracts startFingerprint and every Service.qml function it reaches in
# this tree (settleFingerprintAttempt, armFingerprintRetry, noteFingerprintResumed,
# refreshFingerprintStatus, when present) verbatim, loads FingerprintModel.js when
# present, and runs them in node under plain property semantics. The PAM context,
# timers, the sleep watch and the probe process are recorded stubs; start()
# returns false. The observable is whether fingerprintRetryTimer is armed.
# Control: the PAM onError handler, run the same way with an attempt in flight,
# must re-arm the retry on every tree, which shows the harness sees a re-arm.
#
# RED REPRODUCER (asserts the correct behavior): exit 0 = a failed start arms a
# retry (fix present); exit 1 = a failed start leaves no retry (defect present);
# exit 2 = the control did not re-arm, or a function could not be read.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
F="$REPO/shell/plugins/lock/Service.qml"
M="$REPO/shell/plugins/lock/FingerprintModel.js"
[[ -f $F ]] || { echo "Service.qml missing"; exit 2; }
command -v node >/dev/null || { echo "node missing"; exit 2; }

node - "$F" "$M" <<'JS'
const fs = require("fs");
const [file, modelPath] = process.argv.slice(2);
const src = fs.readFileSync(file, "utf8");

function braceBlock(text, from) {
  const open = text.indexOf("{", from);
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth === 0) return text.slice(open, i + 1);
  }
  throw new Error("unbalanced block");
}
function fn(name) {
  const at = src.search(new RegExp("\\n  function " + name + "\\("));
  if (at < 0) return null;
  const head = src.slice(at).match(/function \w+\([^)]*\)/)[0];
  return head + " " + braceBlock(src, at);
}
const names = ["startFingerprint", "settleFingerprintAttempt", "armFingerprintRetry", "noteFingerprintResumed", "refreshFingerprintStatus"];
const fns = names.map((n) => [n, fn(n)]).filter(([, t]) => t);
if (!fns.find(([n]) => n === "startFingerprint")) { console.log("startFingerprint not found (file changed?)"); process.exit(2); }
const pamAt = src.indexOf("id: fingerprintPam");
const errAt = src.indexOf("onError: function(error)", pamAt);
if (pamAt < 0 || errAt < 0) { console.log("fingerprintPam onError not found (file changed?)"); process.exit(2); }
const onError = braceBlock(src, errAt);
const model = fs.existsSync(modelPath) ? require(modelPath) : undefined;

function makeScope(startResult) {
  const calls = [];
  const timer = (name) => ({ running: false, interval: 0,
    restart() { this.running = true; calls.push(name + ".restart"); },
    start() { this.running = true; calls.push(name + ".start"); },
    stop() { this.running = false; calls.push(name + ".stop"); } });
  const scope = {
    calls,
    lockRequested: true, fingerprintConfigured: true, fingerprintAuthenticating: false,
    fingerprintAttemptReachedDevice: false, fingerprintAttemptFastError: false,
    fingerprintAttemptPromptedAtMs: 0, fingerprintUnreachedStreak: 0,
    fingerprintLastSettleMs: 0, fingerprintResumedAtMs: 0,
    sessionLock: { secure: true, locked: true },
    fingerprintPam: { active: false, start() { calls.push("fingerprintPam.start"); return startResult; }, abort() { calls.push("fingerprintPam.abort"); } },
    fingerprintRetryTimer: timer("fingerprintRetryTimer"),
    fingerprintReachTimer: timer("fingerprintReachTimer"),
    fingerprintSleepWatch: { running: false, interval: 1000, lastTickMs: Date.now() },
    fingerprintCheckProc: { running: false },
    logEvent: (m) => calls.push("log:" + m),
    FingerprintModel: model,
  };
  scope.root = scope;
  new Function("scope", `with (scope) { ${fns.map(([, t]) => t).join("\n")}\n${fns.map(([n]) => `scope.${n} = ${n};`).join("")} }`)(scope);
  return scope;
}

// Defect arm: start() fails on a secure lock with fingerprint configured.
const s = makeScope(false);
s.startFingerprint();
const armed = s.fingerprintRetryTimer.running;
console.log(`failed start: fingerprintAuthenticating=${s.fingerprintAuthenticating} retry armed=${armed}` +
  (armed ? ` (interval ${s.fingerprintRetryTimer.interval}ms)` : "") + ` calls=[${s.calls.filter((c) => !c.startsWith("log:")).join(", ")}]`);

// Control: an attempt in flight ends through the PAM onError handler.
const c = makeScope(true);
c.fingerprintAuthenticating = true;
new Function("scope", `with (scope) { ${onError.slice(1, -1)} }`)(c);
const controlOk = c.fingerprintRetryTimer.running && !c.fingerprintAuthenticating;
console.log(`control onError: retry armed=${c.fingerprintRetryTimer.running} -> ${controlOk ? "the harness observes a re-arm (intended retry path intact)" : "CONTROL FAILED"}`);
if (!controlOk) process.exit(2);
process.exit(armed ? 0 : 1);
JS
rc=$?
case $rc in
  0) echo "PASS: a failed fingerprintPam.start() arms the retry timer, so fingerprint comes back on the same lock (defect absent)"; exit 0 ;;
  1) echo "SYMPTOM: a failed fingerprintPam.start() arms no retry; fingerprint stays dead for the rest of the lock (defect present)"; exit 1 ;;
  *) echo "CONTROL FAILED or code unreadable; PoC inconclusive"; exit 2 ;;
esac
