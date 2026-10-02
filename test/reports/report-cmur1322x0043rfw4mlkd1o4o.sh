#!/bin/sh
# Reproducer for report cmur1322x0043rfw4mlkd1o4o (omacom/omarchy#14053):
# a route summoned while the shell starts opens the main menu instead.
#
# SYS-REQ-260922-R8DQ: "A route string (exact id, declared alias, or normalized
# spelling) opens the item it denotes". SW-REQ-260922-N3RM: a route that
# resolves to an action runs it.
#
# Setup (no compositor, no Quickshell): the REAL Menu.qml route and source code
# (open, openRoute, openExistingMenu, openDmenu, resolveRoute, item,
# parseMenuJsonc, rebuildItemsFromSources, cancel, finishRequest, applySelected,
# setActiveMenu, plus menuFilesAnswered when the tree has it, and both JSONC
# FileViews' onLoaded/onLoadFailed handlers, extracted verbatim) runs in node
# with the REAL MenuModel.js and the tree's stock default/omarchy/omarchy-menu.jsonc.
# Rendering, providers and guards are stubbed; runAction only records.
# Startup is modelled the way the shell orders it: the summon reaches open()
# before either FileView has answered, then each file answers (in both orders).
#   exit 0 = every route opened what it denotes, 1 = DEFECT, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
QML="$ROOT/shell/plugins/menu/Menu.qml"
MODEL="$ROOT/shell/plugins/menu/MenuModel.js"
DEFAULTS="$ROOT/default/omarchy/omarchy-menu.jsonc"
for f in "$QML" "$MODEL" "$DEFAULTS"; do [ -f "$f" ] || { echo "SETUP: $f is missing"; exit 2; }; done
command -v node >/dev/null 2>&1 || { echo "SETUP: node (>= 18) is required"; exit 2; }
export QML MODEL DEFAULTS

node --input-type=commonjs - <<'JS'
const fs = require("fs")
function setup(msg) { console.log("SETUP: " + msg); process.exit(2) }
process.on("uncaughtException", e => setup("menu harness threw: " + e.message))
let MenuModel
try { MenuModel = require(process.env.MODEL) } catch (e) { setup("cannot load MenuModel.js: " + e.message) }
const src = fs.readFileSync(process.env.QML, "utf8")
const defaultsText = fs.readFileSync(process.env.DEFAULTS, "utf8")
function block(s, at) { // brace-matched block from `at` (skips strings and // comments)
  let i = s.indexOf("{", at), depth = 0, q = null
  for (; i < s.length; i++) {
    const c = s[i]
    if (q) { if (c === "\\") i++; else if (c === q) q = null; continue }
    if (c === '"' || c === "'" || c === "`") { q = c; continue }
    if (c === "/" && s[i + 1] === "/") { i = s.indexOf("\n", i); continue }
    if (c === "{") depth++
    else if (c === "}" && --depth === 0) return s.slice(at, i + 1).trim()
  }
  return null
}
function fn(name) {
  const at = src.search(new RegExp("\\n  function " + name + "\\s*\\("))
  return at < 0 ? null : block(src, at + 1)
}
const names = ["open", "openRoute", "openExistingMenu", "openDmenu", "resolveRoute", "item", "parseMenuJsonc",
  "rebuildItemsFromSources", "cancel", "finishRequest", "applySelected", "setActiveMenu"]
const optional = ["menuFilesAnswered"]
const fns = {}
for (const n of names) { fns[n] = fn(n); if (!fns[n]) setup("Menu.qml has no function " + n) }
for (const n of optional) { const f = fn(n); if (f) fns[n] = f }
// The FileView handlers, by the FileView's id.
function fileView(id) {
  const at = src.indexOf("id: " + id + "\n")
  if (at < 0) setup("Menu.qml has no FileView " + id)
  const start = src.lastIndexOf("FileView {", at)
  const body = block(src, start)
  const handler = h => { const m = body.match(new RegExp("\\n\\s*" + h + ": (\\{.*\\})\\n")); return m ? m[1] : null }
  const loaded = handler("onLoaded"), failed = handler("onLoadFailed")
  if (!loaded) setup("FileView " + id + " has no onLoaded")
  return { loaded, failed }
}
const fvDefault = fileView("defaultMenuFile"), fvUser = fileView("userMenuFile")
if (!fvUser.failed) setup("FileView userMenuFile has no onLoadFailed")

function harness() {
  const ran = []
  const t = {
    MenuModel, mode: "menu", requestSerial: 0, applySerial: 0, requestActive: false, selectionFile: "", doneFile: "",
    dmenuPrompt: "", dmenuOptions: [], dmenuWidth: 300, dmenuMaxHeight: 0, activeMenu: "root", pendingInitialMenu: "root",
    navStack: [], filterText: "", selectedIndex: 0, cursorActive: false, fontFamily: "", opened: false, rowsLoaded: false,
    items: {}, itemOrder: [], defaultMenuItems: [], userMenuItems: [], userMenuFailed: false,
    providerRevision: 0, providersLoaded: {}, providerQueue: [], deleteConfirmOpen: false, deleteTarget: null, appLibrary: null,
    get dmenuActive() { return this.mode === "select" || this.mode === "input" },
    rebuildDisplay() {}, disarmPointer() {}, evaluateGuards() {}, invalidateVolatileProvider() {}, loadProviderForMenu() {},
    loadProvidersForSearch() {}, runAction(a) { ran.push(a) },
    defaultMenuFile: { loaded: false, reload() {} }, userMenuFile: { loaded: false, reload() {} },
    keyCatcher: { forceActiveFocus() {} }, panel: { freezeCardTop() {} }, pointerGate: { reset() {}, allowInitialSample() {} },
    Qt: { callLater(f) { f() } }, Util: { shellQuote: s => "'" + String(s).replace(/'/g, "'\\''") + "'", execDetached() {} },
    resultProc: { command: [], running: false }, text: () => ""
  }
  const scope = new Proxy(t, { has: (o, k) => k in o || !(k in globalThis) })
  t.root = scope
  const fnNames = Object.keys(fns)
  const bound = new Function("scope", "with (scope) { return {" +
    fnNames.map(n => n + ": " + fns[n].replace(/^function \w+/, "function")).join(",\n") +
    ", __defaultLoaded: function() " + fvDefault.loaded +
    ", __userLoaded: function() " + fvUser.loaded +
    ", __userFailed: function() " + fvUser.failed + " } }")(scope)
  for (const n of fnNames) t[n] = bound[n]
  return {
    t, ran,
    summon(route) { t.open(JSON.stringify({ menu: route })) },
    defaultLoads() { t.defaultMenuFile.loaded = true; t.text = () => defaultsText; bound.__defaultLoaded() },
    userLoads(text) { t.userMenuFile.loaded = true; t.text = () => text; bound.__userLoaded() },
    userMissing() { bound.__userFailed() }
  }
}

const userFile = '{\n  "personal": {"label": "Personal"},\n  "personal.notes": {"label": "Notes", "action": "true"},\n' +
  '  "hello": {"label": "Hello", "aliases": ["say-hello"], "action": "touch hello-ran"}\n}\n'
let defect = 0
function report(label, h, want) {
  const got = h.ran.length ? "ran " + JSON.stringify(h.ran) : "activeMenu=" + h.t.activeMenu + " opened=" + h.t.opened
  const ok = typeof want === "string" ? (h.t.opened && h.t.activeMenu === want && !h.ran.length) : h.ran.join() === want.ran
  console.log((ok ? "ok: " : "DEFECT: ") + label + " -> " + got + (ok ? "" : " (expected " + (typeof want === "string" ? "menu " + want : "action " + want.ran) + ")"))
  if (!ok) defect = 1
}

// Control: once both files have answered, a summon opens its route (else the harness is broken).
{ const h = harness(); h.userMissing(); h.defaultLoads(); h.summon("system")
  if (h.t.activeMenu !== "system" || !h.t.opened) setup("control failed: a summon after startup did not open system (" + h.t.activeMenu + ")")
  console.log("control: summon system after both files answered -> activeMenu=system") }

{ const h = harness(); h.summon("system"); h.userMissing(); h.defaultLoads()
  report("summon system during startup (no user file; it answers first, then the default file)", h, "system") }
{ const h = harness(); h.summon("system"); h.defaultLoads(); h.userMissing()
  report("summon system during startup (no user file; the default file answers first)", h, "system") }
{ const h = harness(); h.summon("power-menu"); h.userMissing(); h.defaultLoads()
  report("summon power-menu (alias of system) during startup", h, "system") }
{ const h = harness(); h.summon("personal"); h.userLoads(userFile); h.defaultLoads()
  report("summon personal (a menu from the user extension) during startup", h, "personal") }
{ const h = harness(); h.summon("say-hello"); h.userLoads(userFile); h.defaultLoads()
  report("summon say-hello (an action alias from the user extension) during startup", h, { ran: "touch hello-ran" }) }
process.exit(defect)
JS
