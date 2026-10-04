#!/bin/bash
# Regression reproducer for claim CRS-260930-TTVK/C02
# (KI-LOCK-FPRINT-PROBE-FAIL-OPEN; specs SYS-REQ-260912-T0XP, SW-REQ-261004-V813).
#
# Defect: the lock service's fingerprint probe (fingerprintCheckProc in
# shell/plugins/lock/Service.qml) ran `fprintd-list "$USER" 2>/dev/null | grep -qi
# finger` and echoed yes on a match. fprintd's empty-enrollment text ("User NAME
# has no fingers enrolled for ...") contains "fingers", so a user with zero prints
# got fingerprintConfigured = true and a fingerprint offer that can never match.
# Upstream omacom/omarchy#7158 (879d6583d, merged 2026-10-04) makes the probe
# print the raw `LC_ALL=C fprintd-list` output and classifies it in
# FingerprintModel.classifyProbe: only a "- #N:" row is enrolled, an explicit
# empty enrollment is "no", anything else is "unknown".
#
# Method: two stages, both taken from the live files at run time.
#  1. The probe's bash command is read from fingerprintCheckProc's command array
#     and run with bash. Only the absolute /etc/pam.d/omarchy-lock-fingerprint
#     test is pointed at a temp file that exists; a PATH stub stands in for
#     fprintd-list and prints the real daemon output shapes.
#  2. The probe's onExited handler (and applyFingerprintProbe plus
#     FingerprintModel.js when the tree has them) runs in node with the probe's
#     stdout, under plain property semantics. Timers, the PAM context and
#     startFingerprint are recorded stubs. The observable is fingerprintConfigured.
#
# RED REPRODUCER (asserts the correct behavior): exit 0 = a zero-enrollment user
# is not configured for fingerprint (fix present); exit 1 = the zero-enrollment
# probe sets fingerprintConfigured (defect present); exit 2 = the enrolled
# control was not configured, or the probe could not be read.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
F="$REPO/shell/plugins/lock/Service.qml"
M="$REPO/shell/plugins/lock/FingerprintModel.js"
[[ -f $F ]] || { echo "Service.qml missing"; exit 2; }
command -v node >/dev/null || { echo "node missing"; exit 2; }
TMP="$(mktemp -d)"; TMP="$(cd "$TMP" && pwd -P)"
cleanup() { [[ -n ${TMP:-} && -d $TMP && $(basename "$TMP") == tmp.* ]] && find "$TMP" -depth -delete 2>/dev/null; }
trap cleanup EXIT
mkdir -p "$TMP/bin"
: >"$TMP/omarchy-lock-fingerprint"                  # the PAM file the probe tests for
cat >"$TMP/bin/fprintd-list" <<'EOF'
#!/bin/bash
echo "Using device /net/reactivated/Fprint/Device/0"
case "${FPRINTD_CASE:-empty}" in
  empty) echo "User $1 has no fingers enrolled for Synaptics Sensors." ;;
  enrolled) echo "Fingerprints for user $1 on Synaptics Sensors (press):"
            echo " - #0: right-index-finger" ;;
esac
EOF
chmod +x "$TMP/bin/fprintd-list"

node - "$F" "$M" "$TMP" <<'JS'
const fs = require("fs");
const { execFileSync } = require("child_process");
const [file, modelPath, tmp] = process.argv.slice(2);
const src = fs.readFileSync(file, "utf8");

function braceBlock(text, from) {          // text from the first "{" at/after `from` to its match
  const open = text.indexOf("{", from);
  let depth = 0;
  for (let i = open; i < text.length; i++) {
    if (text[i] === "{") depth++;
    else if (text[i] === "}" && --depth === 0) return text.slice(open, i + 1);
  }
  throw new Error("unbalanced block");
}
const procAt = src.indexOf("id: fingerprintCheckProc");
if (procAt < 0) { console.log("fingerprintCheckProc not found in Service.qml (file changed?)"); process.exit(2); }
const procEnd = src.indexOf("\n  }", procAt);
const proc = src.slice(procAt, procEnd);

// Stage 1: the probe command, verbatim, with only the PAM-file test retargeted.
const cmdLine = proc.match(/command:\s*(\[.*\])\s*\n/);
if (!cmdLine) { console.log("probe command not found (file changed?)"); process.exit(2); }
const argv = JSON.parse(cmdLine[1]);
const script = argv[2].split("/etc/pam.d/omarchy-lock-fingerprint").join(tmp + "/omarchy-lock-fingerprint");
function probe(kase) {
  return execFileSync(argv[0], [argv[1], script], {
    env: { PATH: tmp + "/bin:/usr/bin:/bin", USER: "alice", HOME: tmp, FPRINTD_CASE: kase },
    stdio: ["ignore", "pipe", "pipe"],
    encoding: "utf8",
  });
}

// Stage 2: the onExited handler, verbatim, under property semantics.
const exitedAt = proc.indexOf("onExited:");
const rest = proc.slice(exitedAt + "onExited:".length);
const handler = rest.trimStart().startsWith("{") ? braceBlock(rest, 0) : rest.split("\n")[0];
const helperNames = ["applyFingerprintProbe"].filter((n) => src.includes("function " + n + "("));
const helpers = helperNames.map((n) => braceBlock(src, src.indexOf("function " + n + "(")).replace(/^/, "function " + n + "(text) "));
const model = fs.existsSync(modelPath) ? require(modelPath) : undefined;

function decide(stdout) {
  const calls = [];
  const timer = (name) => ({ running: false, interval: 0, restart() { this.running = true; calls.push(name + ".restart"); }, stop() { this.running = false; } });
  const scope = {
    fingerprintConfigured: false, lockRequested: false, fingerprintProbeStreak: 0,
    fingerprintCheckStdout: { text: stdout },
    fingerprintPam: { active: false, abort() { calls.push("fingerprintPam.abort"); } },
    fingerprintRecheckTimer: timer("fingerprintRecheckTimer"),
    fingerprintRetryTimer: timer("fingerprintRetryTimer"),
    startFingerprint: () => calls.push("startFingerprint"),
    settleFingerprintAttempt: () => calls.push("settleFingerprintAttempt"),
    FingerprintModel: model,
  };
  scope.root = scope;
  new Function("scope", `with (scope) { ${helpers.join("\n")}\n${helperNames.map((n) => `scope.${n} = ${n};`).join("")} ${handler} }`)(scope);
  return scope.fingerprintConfigured;
}

const emptyOut = probe("empty");
const control = decide(probe("enrolled"));
const empty = decide(emptyOut);
console.log(`probe output (empty enrollment): ${JSON.stringify(emptyOut.trim())}`);
console.log(`case empty-enrollment: fingerprintConfigured=${empty} -> ${empty ? "fingerprint offered to a user with no prints (defect present)" : "no fingerprint offer (fix present)"}`);
console.log(`control enrolled:      fingerprintConfigured=${control} -> ${control ? "intended path intact" : "CONTROL FAILED"}`);
if (!control) process.exit(2);
process.exit(empty ? 1 : 0);
JS
rc=$?
case $rc in
  0) echo "PASS: the lock-screen probe configures fingerprint only for an enrolled '- #N:' row; zero enrollment is not configured (defect absent)"; exit 0 ;;
  1) echo "SYMPTOM: zero-enrollment user treated as fingerprintConfigured=true on the lock screen (defect present)"; exit 1 ;;
  *) echo "CONTROL FAILED or probe unreadable; PoC inconclusive"; exit 2 ;;
esac
