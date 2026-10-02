#!/bin/sh
# Reproducer for report cmur1322h0040rfw45yjijlzu (omacom/omarchy#14052):
# an uninstall confirmation left open stays over the next prompt, and the Enter
# meant for the prompt uninstalls the app.
#
# SYS-REQ-260922-X6Z5: "A script-driven select/input prompt delivers the picked
# value to the caller ...". SW-REQ-260922-8CQ4: the uninstall confirmation
# removes the app only when the user confirms it.
#
# Setup (no compositor, no Quickshell): a real bin/omarchy-menu-select caller
# runs against a stub `omarchy-shell` that only records its summon payload.
# The REAL Menu.qml request, delete and key-handling code (open, openRoute,
# openExistingMenu, openDmenu, requestDeleteSelected, cancelDelete,
# confirmDelete, activateIndex, applyDmenuSelection, cancel, finishRequest,
# onOpenedChanged and keyCatcher's Keys.onPressed, extracted verbatim) and the
# REAL ConfirmDialog.qml handleKey run in node with a stub QML scope. Rows and
# the app library are stubbed: removing the app deletes a throwaway launcher
# file in a private temp dir, like omarchy-remove-launcher-entry does. The
# resultProc command Menu.qml builds is executed with bash, as Quickshell would.
# Sequence = open the Apps menu, press Delete on the app row (confirmation up,
# Uninstall preselected), the caller summons its prompt, press Enter.
#   exit 0 = the prompt got Enter and the app is kept, 1 = DEFECT, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
SELECT="$ROOT/bin/omarchy-menu-select"
QML="$ROOT/shell/plugins/menu/Menu.qml"
CONFIRM="$ROOT/shell/Ui/ConfirmDialog.qml"
for f in "$SELECT" "$QML" "$CONFIRM"; do [ -f "$f" ] || { echo "SETUP: $f is missing"; exit 2; }; done
command -v node >/dev/null 2>&1 || { echo "SETUP: node (>= 18) is required"; exit 2; }
command -v perl >/dev/null 2>&1 || { echo "SETUP: perl (JSON::PP) is required by omarchy-menu-select"; exit 2; }
BASH_BIN=$(command -v bash) || { echo "SETUP: bash is required"; exit 2; }
"$BASH_BIN" -c '(( BASH_VERSINFO[0] >= 4 ))' || { echo "SETUP: omarchy-menu-select needs bash >= 4"; exit 2; }

WORK=$(mktemp -d) || { echo "SETUP: mktemp failed"; exit 2; }
PID=""
cleanup() { [ -n "$PID" ] && kill "$PID" 2>/dev/null; rm -f "$WORK"/bin/omarchy-shell "$WORK"/spool "$WORK"/out "$WORK"/apps/throwaway.desktop; rmdir "$WORK/bin" "$WORK/apps" "$WORK" 2>/dev/null; }
trap cleanup EXIT INT TERM
mkdir "$WORK/bin" "$WORK/apps"
cat > "$WORK/bin/omarchy-shell" <<'STUB'
#!/bin/sh
# stub: `omarchy-shell shell summon omarchy.menu <payload>` -> record the payload
printf '%s\n' "$4" >> "$SPOOL"
STUB
chmod +x "$WORK/bin/omarchy-shell"
export SPOOL="$WORK/spool" DESKTOP="$WORK/apps/throwaway.desktop" QML CONFIRM BASH_BIN
: > "$SPOOL"
printf '[Desktop Entry]\nType=Application\nName=Throwaway\nExec=true\n' > "$DESKTOP"

# The caller is started first; its payload is fed to the menu once the confirmation is up.
PATH="$WORK/bin:$PATH" "$BASH_BIN" "$SELECT" "Pick a fruit" apple banana cherry > "$WORK/out" 2>&1 &
PID=$!
n=0
while [ ! -s "$SPOOL" ]; do
  n=$((n + 1)); [ $n -gt 400 ] && { echo "SETUP: omarchy-menu-select never summoned the menu"; exit 2; }
  sleep 0.05
done

node --input-type=commonjs - <<'JS'
const fs = require("fs"), cp = require("child_process")
const menuSrc = fs.readFileSync(process.env.QML, "utf8")
const confirmSrc = fs.readFileSync(process.env.CONFIRM, "utf8")
function setup(msg) { console.log("SETUP: " + msg); process.exit(2) }
// Brace-matched block starting at `at` (skips strings and // comments).
function block(src, at) {
  let i = src.indexOf("{", at), depth = 0, q = null
  for (; i < src.length; i++) {
    const c = src[i]
    if (q) { if (c === "\\") i++; else if (c === q) q = null; continue }
    if (c === '"' || c === "'" || c === "`") { q = c; continue }
    if (c === "/" && src[i + 1] === "/") { i = src.indexOf("\n", i); continue }
    if (c === "{") depth++
    else if (c === "}" && --depth === 0) return src.slice(at, i + 1).trim()
  }
  return null
}
function fn(src, name) {
  const at = src.search(new RegExp("\\n  function " + name + "\\s*\\("))
  if (at < 0) return null
  return block(src, at + 1)
}
const names = ["open", "openRoute", "openExistingMenu", "openDmenu", "requestDeleteSelected", "cancelDelete",
  "confirmDelete", "activateIndex", "applyDmenuSelection", "cancel", "finishRequest"]
const fns = {}
for (const n of names) { fns[n] = fn(menuSrc, n); if (!fns[n]) setup("Menu.qml has no function " + n) }
const keyAt = menuSrc.indexOf("Keys.onPressed: function(event)")
if (keyAt < 0) setup("Menu.qml has no keyCatcher Keys.onPressed handler")
const keySrc = block(menuSrc, keyAt + "Keys.onPressed: ".length)
const openedChanged = (menuSrc.match(/\n  onOpenedChanged: (.*)/) || [])[1]
if (!keySrc || !openedChanged) setup("cannot extract the key handler or onOpenedChanged")
const handleKeySrc = fn(confirmSrc, "handleKey")
if (!handleKeySrc) setup("ConfirmDialog.qml has no function handleKey")

const Qt = { Key_Escape: 1, Key_Tab: 2, Key_Backtab: 3, Key_Backspace: 4, Key_Return: 5, Key_Enter: 6, Key_Delete: 7,
  Key_Left: 8, Key_Up: 9, Key_Right: 10, Key_Down: 11, Key_PageUp: 12, Key_PageDown: 13, NoModifier: 0, ShiftModifier: 1,
  callLater(f) { f() } }
const removed = [], writes = []
let rows = [], opened = false
const t = {
  mode: "menu", requestSerial: 0, applySerial: 0, requestActive: false, selectionFile: "", doneFile: "", dmenuPrompt: "",
  dmenuOptions: [], dmenuWidth: 300, dmenuMaxHeight: 0, activeMenu: "root", pendingInitialMenu: "root", navStack: [],
  filterText: "", selectedIndex: 0, cursorActive: false, fontFamily: "", deleteConfirmOpen: false, deleteTarget: null,
  items: { root: { kind: "menu" }, apps: { kind: "menu", parent: "root" } }, itemOrder: ["root", "apps"],
  get dmenuActive() { return this.mode === "select" || this.mode === "input" },
  appLibrary: { remove(appId) { removed.push(appId); if (appId === "throwaway.desktop") fs.rmSync(process.env.DESKTOP, { force: true }) },
    refreshIcons() {}, launch() {} },
  item(id) { return t.items[id] || null },
  resolveRoute(input) { return input },
  rebuildDisplay() {
    rows = t.dmenuActive ? t.dmenuOptions.map(label => ({ kind: "option", label }))
      : t.activeMenu === "apps" ? [{ kind: "app", appId: "throwaway.desktop", label: "Throwaway" }]
      : [{ kind: "menu", itemId: "apps", label: "Apps" }]
  },
  rowSelectable() { return true }, disarmPointer() {}, evaluateGuards() {}, invalidateVolatileProvider() {},
  loadProviderForMenu() {}, loadProvidersForSearch() {}, setFilter(v) { t.filterText = v }, settleCursor() {},
  runAction() {}, applySelected() {}, goBack() {}, select() {},
  displayModel: { get count() { return rows.length }, get(i) { return rows[i] } },
  keyCatcher: { forceActiveFocus() {} }, panel: { freezeCardTop() {} }, pointerGate: { reset() {}, allowInitialSample() {} },
  Qt, Util: { shellQuote: s => "'" + String(s).replace(/'/g, "'\\''") + "'", editsFilter: () => false, execDetached() {} },
  resultProc: { command: [], set running(v) { if (!v) return; writes.push(this.command[2]); cp.execFileSync(process.env.BASH_BIN, this.command.slice(1)) } }
}
const deleteConfirm = { selectedIndex: 1, get opened() { return t.deleteConfirmOpen },
  canceled() { t.cancelDelete() }, confirmed() { t.confirmDelete() } }
t.deleteConfirm = deleteConfirm
// Unknown identifiers resolve to the scope (undefined) instead of escaping to globals.
const scope = new Proxy(t, { has: (o, k) => k in o || !(k in globalThis) })
t.root = scope
const install = new Function("scope", "with (scope) { return {" +
  names.map(n => n + ": " + fns[n].replace(/^function \w+/, "function")).join(",\n") +
  ", __onOpenedChanged: function() { " + openedChanged + " }" +
  ", __key: " + keySrc + " } }")
const bound = install(scope)
for (const n of names) t[n] = bound[n]
Object.defineProperty(t, "opened", { get() { return opened },
  set(v) { const changed = v !== opened; opened = v; if (changed) bound.__onOpenedChanged() } })
deleteConfirm.handleKey = new Function("root", "Qt", "with (root) { return " + handleKeySrc.replace(/^function \w+/, "function") + " }")(deleteConfirm, Qt)
const press = (key, text) => bound.__key({ key: Qt[key], modifiers: Qt.NoModifier, text: text || "", accepted: false })

const payload = fs.readFileSync(process.env.SPOOL, "utf8").trim().split("\n").map(l => JSON.parse(l))[0]
if (!payload || payload.mode !== "select" || !payload.doneFile) setup("unexpected summon payload")

t.open(JSON.stringify({ menu: "apps" }))     // Super+Alt+Space: the Apps menu
press("Key_Delete")                          // Delete on the app row
if (!t.deleteConfirmOpen || !t.deleteTarget || t.deleteTarget.appId !== "throwaway.desktop")
  setup("Delete on the app row did not raise the uninstall confirmation")
console.log("uninstall confirmation up for " + t.deleteTarget.label + " (Uninstall preselected: " + (deleteConfirm.selectedIndex === 1) + ")")
t.open(JSON.stringify(payload))              // the script's prompt arrives, confirmation unanswered
console.log("prompt summoned: mode=" + t.mode + " options=" + JSON.stringify(t.dmenuOptions) + " confirmation still open=" + t.deleteConfirmOpen)
press("Key_Return")                          // Enter meant for the prompt (cursor on 'apple')
console.log("after Enter: menu opened=" + t.opened + "; app library removals: " + JSON.stringify(removed) + "; result writes: " + writes.length)
JS
rc=$?
[ $rc -eq 0 ] || { echo "SETUP: menu harness failed (rc $rc)"; exit 2; }

n=0
while kill -0 "$PID" 2>/dev/null; do
  n=$((n + 1)); [ $n -gt 100 ] && break
  sleep 0.05
done
if kill -0 "$PID" 2>/dev/null; then
  caller="still running (never answered)"
else
  wait "$PID"; crc=$?; PID=""
  caller="exit $crc, printed: $(tr '\n' ' ' < "$WORK/out")"
fi
echo "prompt caller: $caller"

DEFECT=0
if [ ! -e "$DESKTOP" ]; then
  echo "DEFECT: the Enter meant for the prompt confirmed the stale uninstall confirmation: the app's launcher file was removed"
  DEFECT=1
fi
case "$caller" in
  "exit 0, printed: apple "*) echo "ok: the prompt received Enter and its caller got 'apple'" ;;
  *) echo "DEFECT: the prompt's caller did not get the picked value ('apple'): $caller"; DEFECT=1 ;;
esac
[ $DEFECT -eq 0 ] && echo "ok: the app is still installed"
exit $DEFECT
