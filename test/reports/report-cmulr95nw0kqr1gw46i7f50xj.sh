#!/bin/sh
# Reproducer for report cmulr95nw0kqr1gw46i7f50xj (omacom/omarchy#9057):
# summoning a select menu again before the previous one was answered leaves the
# earlier omarchy-menu-select polling its done file forever.
#
# SYS-REQ-260922-X6Z5: "A script-driven select/input prompt delivers the picked
# value to the caller ...; cancellation reaches the caller as no-selection."
#
# Setup (no compositor, no Quickshell): two real bin/omarchy-menu-select callers
# run against a stub `omarchy-shell` that only records each summon payload.
# The recorded payloads are then fed, in order, to the REAL Menu.qml request
# functions (open, openDmenu, finishRequest, cancel — extracted verbatim from
# shell/plugins/menu/Menu.qml and run in node with a stub QML scope; the
# resultProc or Quickshell.execDetached command they build is executed with
# bash exactly as Quickshell would). Sequence = press Super+K, press Super+K again, then Escape.
# Once the menu has closed nothing else will ever write a done file, so a
# caller whose done file does not exist at that point can never exit on its
# own. No wall-clock assertion: waits are event-driven, bounded only as a
# setup safety net.
#   exit 0 = every caller was answered and exited, 1 = DEFECT, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
SELECT="$ROOT/bin/omarchy-menu-select"
QML="$ROOT/shell/plugins/menu/Menu.qml"
for f in "$SELECT" "$QML"; do [ -f "$f" ] || { echo "SETUP: $f is missing"; exit 2; }; done
command -v node >/dev/null 2>&1 || { echo "SETUP: node (>= 18) is required"; exit 2; }
command -v perl >/dev/null 2>&1 || { echo "SETUP: perl (JSON::PP) is required by omarchy-menu-select"; exit 2; }
BASH_BIN=$(command -v bash) || { echo "SETUP: bash is required"; exit 2; }
"$BASH_BIN" -c '(( BASH_VERSINFO[0] >= 4 ))' || { echo "SETUP: omarchy-menu-select needs bash >= 4 (found $("$BASH_BIN" -c 'echo $BASH_VERSION'))"; exit 2; }

WORK=$(mktemp -d) || { echo "SETUP: mktemp failed"; exit 2; }
PIDS=""
cleanup() { for p in $PIDS; do kill "$p" 2>/dev/null; done; rm -f "$WORK"/bin/omarchy-shell "$WORK"/spool "$WORK"/spool.done "$WORK"/out.*; rmdir "$WORK/bin" "$WORK" 2>/dev/null; }
trap cleanup EXIT INT TERM
mkdir "$WORK/bin"
cat > "$WORK/bin/omarchy-shell" <<'STUB'
#!/bin/sh
# stub: `omarchy-shell shell summon omarchy.menu <payload>` -> record the payload
printf '%s\n' "$4" >> "$SPOOL"
STUB
chmod +x "$WORK/bin/omarchy-shell"
export SPOOL="$WORK/spool"
: > "$SPOOL"

wait_lines() { # $1 = line count; event wait on the spool, bounded as a setup safety net
  n=0
  while [ "$(wc -l < "$SPOOL")" -lt "$1" ]; do
    n=$((n + 1)); [ $n -gt 400 ] && { echo "SETUP: omarchy-menu-select never summoned the menu (caller $1)"; exit 2; }
    sleep 0.05
  done
}
start_caller() { # $1 = name; the background job IS the omarchy-menu-select process
  PATH="$WORK/bin:$PATH" "$BASH_BIN" "$SELECT" Keybindings "Super+K  Keybindings" "Super+Space  Menu" -- --width 800 --height 500 > "$WORK/out.$1" 2>&1 &
}
start_caller A; PID_A=$!; PIDS="$PID_A"; wait_lines 1
start_caller B; PID_B=$!; PIDS="$PIDS $PID_B"; wait_lines 2

export QML BASH_BIN
node --input-type=commonjs - <<'JS'
const fs = require("fs"), cp = require("child_process")
const src = fs.readFileSync(process.env.QML, "utf8")
// Extract `function NAME(...) { ... }` from the QML root, skipping strings and comments.
function extract(name) {
  const at = src.search(new RegExp("\\n  function " + name + "\\s*\\("))
  if (at < 0) return null
  let i = src.indexOf("{", at), depth = 0, q = null
  for (; i < src.length; i++) {
    const c = src[i]
    if (q) { if (c === "\\") i++; else if (c === q) q = null; continue }
    if (c === '"' || c === "'" || c === "`") { q = c; continue }
    if (c === "/" && src[i + 1] === "/") { i = src.indexOf("\n", i); continue }
    if (c === "{") depth++
    else if (c === "}" && --depth === 0) return src.slice(at + 1, i + 1).trim()
  }
  return null
}
const names = ["open", "openDmenu", "finishRequest", "cancel"]
const fns = {}
for (const n of names) { fns[n] = extract(n); if (!fns[n]) { console.log("SETUP: Menu.qml has no function " + n); process.exit(2) } }

const writes = []
const root = {
  mode: "menu", requestSerial: 0, applySerial: 0, requestActive: false, selectionFile: "", doneFile: "",
  dmenuPrompt: "", dmenuOptions: [], dmenuWidth: 300, dmenuMaxHeight: 0, activeMenu: "root", navStack: [],
  filterText: "", selectedIndex: 0, cursorActive: true, opened: false, fontFamily: "", pendingInitialMenu: "root",
  get dmenuActive() { return this.mode === "select" || this.mode === "input" },
  rebuildDisplay() {}, disarmPointer() {}, evaluateGuards() {}, invalidateVolatileProvider() {}, loadProviderForMenu() {},
  openRoute() { throw new Error("route path not expected for a select summon") },
  keyCatcher: { forceActiveFocus() {} }, Qt: { callLater() {} },
  Util: { shellQuote: s => "'" + String(s).replace(/'/g, "'\\''") + "'", execDetached() {} },
  resultProc: { command: [], set running(v) { if (!v) return; writes.push(this.command[2]); cp.execFileSync(process.env.BASH_BIN, this.command.slice(1)) } },
  Quickshell: { execDetached(command) { writes.push(command[2]); cp.execFileSync(process.env.BASH_BIN, command.slice(1)) } }
}
root.root = root
const scope = new Function("root", "with (root) { " + names.map(n => "root." + n + " = " + fns[n].replace(/^function \w+/, "function")).join(";\n") + " }")
scope(root)

const payloads = fs.readFileSync(process.env.SPOOL, "utf8").trim().split("\n").map(l => JSON.parse(l))
if (payloads.length !== 2 || payloads.some(p => p.mode !== "select" || !p.doneFile)) { console.log("SETUP: unexpected summon payloads"); process.exit(2) }
root.open(JSON.stringify(payloads[0]))   // Super+K
root.open(JSON.stringify(payloads[1]))   // Super+K again, first popup still unanswered
root.cancel()                            // Escape
console.log("menu closed: opened=" + root.opened + " requestActive=" + root.requestActive + "; done-file writes issued by Menu.qml: " + writes.length)
// A caller is answered iff a write command Menu.qml issued creates its done file.
const answered = payloads.map(p => writes.some(w => w.includes(root.Util.shellQuote(p.doneFile))) ? "answered" : "unanswered")
fs.writeFileSync(process.env.SPOOL + ".done", answered.join("\n") + "\n")
JS
rc=$?
[ $rc -eq 0 ] || { echo "SETUP: menu harness failed (rc $rc)"; exit 2; }

DEFECT=0
i=0
for name in A B; do
  i=$((i + 1))
  state=$(sed -n "${i}p" "$SPOOL.done")
  pid=$PID_A; [ $name = B ] && pid=$PID_B
  if [ "$state" = answered ]; then
    wait "$pid"; rc=$?
    echo "ok: caller $name was answered and exited (omarchy-menu-select rc $rc: cancel = no selection)"
  else
    alive=no; kill -0 "$pid" 2>/dev/null && alive=yes
    echo "DEFECT: caller $name (superseded summon) never got an answer: the menu closed without ever creating its done file, so this omarchy-menu-select polls it forever (still running: $alive)"
    DEFECT=1
  fi
done
exit $DEFECT
