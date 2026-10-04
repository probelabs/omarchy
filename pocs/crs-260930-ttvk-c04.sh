#!/bin/bash
# Runtime reproducer for claim CRS-260930-TTVK/C04
# (KI-LOCK-SCREENS-CHANGE-BLANK-LOST; spec SYS-REQ-260912-T0XP).
#
# Mechanism: while locked, the idle blank timer is one-shot. Once it has fired and
# blanked the displays, a screen add/remove runs onScreensChanged
# (shell/plugins/lock/Service.qml), which clears displaysBlank so a returning panel
# shows the wallpaper, but calls neither armBlankTimer nor runWake. Nothing then
# restarts the countdown, so every display stays lit until the next keypress.
#
# Method: extracts the LIVE onScreensChanged body, runWake and armBlankTimer
# verbatim from Service.qml and runs them in node under plain property semantics.
# The state is "locked, idle blank already fired": lockRequested true,
# displaysBlank true, idleBlankTimer not running. The calls the handler makes into
# the lock and stranded-lock machinery (requestSessionLock, checkStrandedLock,
# strandedLockRetryTimer.rearm, wakeProcess, nudgeFingerprint) are recorded stubs.
# The observable is whether the idle blank timer runs again after the event.
# Control: runWake, the keypress path, from the same state must re-arm the timer,
# which shows the harness sees a re-arm.
#
# GREEN TRIPWIRE: exit 0 = after a screen change the blank intent is gone and no
# timer will blank the displays again (defect present); exit 1 = the handler
# re-arms the blank (fix present); exit 2 = control failed or code unreadable.
# Reproduces: KI-LOCK-SCREENS-CHANGE-BLANK-LOST
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
F="$REPO/shell/plugins/lock/Service.qml"
[[ -f $F ]] || { echo "Service.qml missing"; exit 2; }
command -v node >/dev/null || { echo "node missing"; exit 2; }

node - "$F" <<'JS'
const fs = require("fs");
const src = fs.readFileSync(process.argv[2], "utf8");
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
  if (at < 0) throw new Error("function " + name + " not found in Service.qml (file changed?)");
  return "function " + name + "() " + braceBlock(src, at);
}
const scAt = src.indexOf("function onScreensChanged()");
if (scAt < 0) { console.log("onScreensChanged not found (file changed?)"); process.exit(2); }
const handler = braceBlock(src, scAt).slice(1, -1);
let runWake, armBlankTimer;
try { runWake = fn("runWake"); armBlankTimer = fn("armBlankTimer"); } catch (e) { console.log(String(e.message)); process.exit(2); }

function makeScope() {
  const calls = [];
  const scope = {
    calls,
    lockRequested: true, displaysBlank: true, monitorDpmsKnown: true,
    idleBlankTimer: { running: false, armedAt: 0,
      restart() { this.running = true; calls.push("idleBlankTimer.restart"); },
      start() { this.running = true; calls.push("idleBlankTimer.start"); },
      stop() { this.running = false; } },
    wakeProcess: { running: false },
    strandedLockRetryTimer: { rearm() { calls.push("strandedLockRetryTimer.rearm"); } },
    requestSessionLock: () => calls.push("requestSessionLock"),
    checkStrandedLock: () => calls.push("checkStrandedLock"),
    nudgeFingerprint: () => calls.push("nudgeFingerprint"),
  };
  scope.root = scope;
  new Function("scope", `with (scope) { ${armBlankTimer}\n${runWake}\nscope.armBlankTimer = armBlankTimer; scope.runWake = runWake; }`)(scope);
  return scope;
}

// Defect arm: a screen add/remove after the one-shot blank has fired.
const s = makeScope();
new Function("scope", `with (scope) { ${handler} }`)(s);
const lost = s.displaysBlank === false && !s.idleBlankTimer.running;
console.log(`screens changed: displaysBlank=${s.displaysBlank} idleBlankTimer.running=${s.idleBlankTimer.running} calls=[${s.calls.join(", ")}] -> ` +
  (lost ? "blank intent cleared and nothing re-arms the blank (defect present)" : "blank re-armed (fix present?)"));

// Control: the keypress path (runWake) from the same state re-arms the blank.
const c = makeScope();
c.runWake();
const ok = c.idleBlankTimer.running === true;
console.log(`control runWake: idleBlankTimer.running=${c.idleBlankTimer.running} -> ${ok ? "the wake path re-arms the blank (intended path intact)" : "CONTROL FAILED"}`);
if (!ok) process.exit(2);
process.exit(lost ? 0 : 1);
JS
rc=$?
case $rc in
  0) echo "SYMPTOM: a screen change while locked clears the blank and never re-arms the idle blank timer; displays stay lit until a keypress (defect present)"; exit 0 ;;
  1) echo "PASS-REFUTED: the screen-change handler re-arms the blank - defect fixed"; exit 1 ;;
  *) echo "CONTROL FAILED or code unreadable; PoC inconclusive"; exit 2 ;;
esac
