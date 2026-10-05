#!/usr/bin/env node
// Behaviour-diff harness for the Omarchy menu plugin (proof.yaml
// project.review.behavior_diff). `proof change behavior-diff` runs it once per
// input at the BASE and at the HEAD revision, each in a throwaway worktree, and
// records every input whose output differs. The base's output is the oracle.
//
//   node test/bdiff/harness.mjs <rev> <input>
//
// <rev> is the revision worktree (the engine's {rev}); every product file is
// read from there, so base and head each run their OWN code. <input> is one
// input file (the engine's {input}). The input extension picks the mode:
//
//   .jsonc   MenuModel.js parse of one menu JSONC file:
//              (a) parseMenuJsonc(text) rows, (b) JSON.parse(stripJsonc(text))
//              or ERR. The file is decoded the way Quickshell FileView text()
//              hands it to QML: invalid UTF-8 bytes become U+FFFD and a
//              leading byte-order mark is dropped (checked live under
//              Quickshell 0.3.1); every other character is kept.
//   .events  request-lifecycle simulator (#9056 / #9057 area). Replays one
//              event sequence against the REAL bodies of the request functions
//              of <rev>/shell/plugins/menu/Menu.qml under node:vm, and prints
//              each summoning caller's outcome and the final menu state.
//   other    a usage message on stderr, exit 2.
//
// Output is deterministic (no times, no paths, no pids), so any base/head
// difference is a behaviour difference of the code under <rev>.
//
// SCALE and TIMING partitions, honestly: the engine's scale mode runs N
// CONCURRENT invocations of this harness on the same input, and its timing
// mode starts N invocations staggered by interval_ms. Each invocation is a
// separate, single-threaded, deterministic simulation, so those modes only
// check that the harness is stable under load (every invocation must print
// the same output). The burst / interleaving that matters for the menu
// request lifecycle — many summons while an answer write is still running —
// is encoded IN the event file and replayed in-process, with the shared QML
// Process modelled as it behaves live (see the .events section below).
//
// Robustness: a revision that lacks MenuModel.js / Menu.qml / one of the
// functions prints a MISSING marker instead of crashing (exit 0), so base and
// head stay comparable. The harness writes NOTHING to disk: product code runs
// in a vm context with no require/process, and every process spawn it would
// make (Quickshell.execDetached, Process.running) is recorded, not executed.
import fs from 'node:fs'
import path from 'node:path'
import vm from 'node:vm'

const HARNESS = 'omarchy-bdiff v1'
const VM_TIMEOUT_MS = 15000

function usage(msg) {
  process.stderr.write(`${msg}\nusage: node test/bdiff/harness.mjs <rev-worktree> <input.jsonc|input.events>\n`)
  process.exit(2)
}

const [, , revArg, inputArg] = process.argv
if (!revArg || !inputArg) usage('missing argument')
const rev = path.resolve(revArg)
const input = path.resolve(inputArg)
const ext = path.extname(input).toLowerCase()

let out = []
const emit = line => out.push(line)

function readRev(rel) {
  try { return fs.readFileSync(path.join(rev, rel), 'utf8') } catch { return null }
}

// Quickshell FileView text() semantics (checked live under Quickshell 0.3.1):
// replacement characters for invalid sequences, a leading BOM dropped
// (ignoreBOM: false), a BOM anywhere else kept.
function readInputText() {
  const bytes = fs.readFileSync(input)
  return new TextDecoder('utf-8', { fatal: false, ignoreBOM: false }).decode(bytes)
}

function errName(e) {
  return (e && e.name) ? `${e.name}: ${String(e.message).split('\n')[0]}` : String(e)
}

// Loads <rev>/shell/plugins/menu/MenuModel.js into a fresh vm context the way
// the repo's own tests see it (CommonJS module.exports; test/shell.d/
// base-test.sh requireFromRoot). Falls back to the top-level function
// declarations when a revision has no module.exports block (QML-only script).
function loadMenuModel() {
  const rel = 'shell/plugins/menu/MenuModel.js'
  const src = readRev(rel)
  if (src === null) return { error: `MISSING ${rel}` }
  const sandbox = { module: { exports: {} }, console: { log() {}, warn() {}, error() {} } }
  sandbox.exports = sandbox.module.exports
  const ctx = vm.createContext(sandbox)
  try {
    new vm.Script(src, { filename: rel }).runInContext(ctx, { timeout: VM_TIMEOUT_MS })
  } catch (e) {
    return { error: `LOAD-ERROR ${errName(e)}` }
  }
  const api = Object.assign({}, ctx, ctx.module && ctx.module.exports)
  return { api, ctx }
}

// ---------------------------------------------------------------- .jsonc mode
function runJsonc() {
  emit(`# ${HARNESS} jsonc`)
  const text = readInputText()
  const mm = loadMenuModel()
  if (mm.error) {
    emit(`model: ${mm.error}`)
    return
  }
  // (a) the rows the menu would load
  let rows
  if (typeof mm.api.parseMenuJsonc !== 'function') rows = { marker: 'MISSING-FUNCTION parseMenuJsonc' }
  else {
    try { rows = { value: mm.api.parseMenuJsonc(text) } } catch (e) { rows = { marker: `THROW ${errName(e)}` } }
  }
  // (b) what the stripped text parses to
  let strip
  if (typeof mm.api.stripJsonc !== 'function') strip = { marker: 'MISSING-FUNCTION stripJsonc' }
  else {
    let stripped
    try { stripped = mm.api.stripJsonc(text) } catch (e) { strip = { marker: `THROW ${errName(e)}` } }
    if (!strip) {
      try { strip = { value: JSON.parse(stripped) } } catch { strip = { marker: 'ERR' } }
    }
  }
  const rowCount = rows.marker ? rows.marker : (Array.isArray(rows.value) ? String(rows.value.length) : `non-array ${typeof rows.value}`)
  const stripKind = strip.marker ? strip.marker : (Array.isArray(strip.value) ? 'array' : (strip.value === null ? 'null' : typeof strip.value))
  // Summary first: the engine's excerpts start just before the first differing
  // byte, so a changed row count / parse status is what a reviewer sees.
  emit(`summary rows=${rowCount} strip_parse=${stripKind}`)
  // JSON.stringify keeps insertion order, which is the menu order the product
  // uses (itemOrder), so it is part of the compared behaviour. Lone surrogates
  // are escaped (well-formed JSON.stringify), so output is valid UTF-8.
  emit(`rows ${rows.marker ? rows.marker : JSON.stringify(rows.value)}`)
  emit(`strip_parse ${strip.marker ? strip.marker : JSON.stringify(strip.value)}`)
}

// --------------------------------------------------------------- .events mode
//
// Event file: whitespace-separated tokens, `#` starts a comment, `S*20` (or `Sx20`) repeats a
// token n times (S*20 also works), and the directive `@slow` switches to
// slow-user timing (every answer write finishes before the next event).
//   S  select summon (a caller polling its own done file; options alpha, beta)
//   I  input summon (a caller)
//   N  select summon without a doneFile (no caller)
//   M  menu summon ({"menu":"root"})
//   A  action-alias summon ({"menu":"act"}, an action item)
//   P  activate row 0 (dmenu: pick alpha / submit input; menu: launch app)
//   R  activate row 1 (dmenu: pick beta; menu: run the action row)
//   C  close
//   X  the shared answer Process exits (fires the revision's onExited)
//
// Model (method: review notes for #9056, harness bdiff-9056.js): the shared
// QML `Process { id: resultProc }` ignores `running = true` while it is still
// running (verified live: 19/20 stranded callers on quattro), and stays busy
// until an explicit X. Quickshell.execDetached / Util.execDetached run
// immediately. After the last event every still-running write is drained.
const NAMES = ['open', 'close', 'cancel', 'finishRequest', 'openDmenu', 'openExistingMenu', 'openRoute', 'activateIndex', 'applyDmenuSelection', 'applySelected']
// Names bound OUTSIDE the with-scope (the wrapper's parameter and local).
const OUTER = new Set(['root', 'displayModel'])
const OPS = new Set(['S', 'I', 'N', 'M', 'A', 'P', 'R', 'C', 'X', 'O'])

// Apps-menu inputs (SW-REQ-261003-B7ZA). A line `@app <appId> <name>` declares
// one installed app; the name is the rest of the line, kept byte for byte as
// the decoded text (any script, accents, U+FFFD from invalid UTF-8). `O`
// summons the Apps menu ({"menu":"apps"}). Only an input that declares apps
// gets the Apps menu and runs the revision's REAL rebuildDisplay, displayRow
// and isVisible, so every other input keeps the old stub and prints exactly
// what it printed before.
const APP_LINE = /^@app[ \t]+(\S+)[ \t]+(.*)$/
// `@locale <BCP 47 tag>` collates as that locale (Qt's localeCompare uses the
// process locale); `@plugin-list` also prints the revision's
// AppSearch.sortedEntries order of the same apps. Apps inputs only.
const LOCALE_LINE = /^@locale[ \t]+(\S+)[ \t]*$/
const PLUGIN_LINE = /^@plugin-list[ \t]*$/
const APPS_NAMES = ['rebuildDisplay', 'displayRow', 'isVisible']

// Verifies: SW-REQ-261003-B7ZA
function appDirective(rawLine) {
  const m = APP_LINE.exec(rawLine)
  return m ? { appId: m[1], label: m[2] } : null
}

// Verifies: SW-REQ-261003-B7ZA
// Makes localeCompare in a vm context collate as `locale` when the input names one, and as en-US (the root
// collation Node uses under C and C.UTF-8) otherwise: Node's default follows the host's LC_ALL/LANG.
function pinLocale(ctx, locale) {
  const tag = locale || 'en-US' // pinned, so sv_SE, et_EE or th_TH hosts give the same output
  vm.runInContext('(function(locale) { var lc = String.prototype.localeCompare; String.prototype.localeCompare = function(that) { return lc.call(this, that, locale) } })', ctx)(tag)
}

// Verifies: SW-REQ-261003-B7ZA
// The order the revision's shell/services/AppSearch.js sortedEntries hands
// plugins for the declared apps (no query).
function pluginListOrder(apps, locale) {
  const rel = 'shell/services/AppSearch.js'
  const src = readRev(rel)
  if (src === null) return `MISSING ${rel}`
  const sandbox = { module: { exports: {} }, console: { log() {}, warn() {}, error() {} } }
  const ctx = vm.createContext(sandbox)
  pinLocale(ctx, locale)
  try {
    new vm.Script(src, { filename: rel }).runInContext(ctx, { timeout: VM_TIMEOUT_MS })
    const api = sandbox.module.exports
    if (typeof api.sortedEntries !== 'function') return 'MISSING-FUNCTION sortedEntries'
    const rows = api.sortedEntries(apps.map(a => ({ id: a.appId, name: a.label, noDisplay: false })), '')
    return JSON.stringify(rows.map(row => api.entryName(row.entry)))
  } catch (e) {
    return `THROW ${errName(e)}`
  }
}

// Verifies: SW-REQ-261003-B7ZA
// The item tree of an apps input: the fixed ITEMS, an Apps menu under root,
// and one app row per declaration, in file order (the order DesktopEntries
// would hand them over; the menu must not depend on it).
function appsItems(apps) {
  const items = Object.assign({}, ITEMS, { apps: { id: 'apps', kind: 'menu', label: 'Apps', parent: 'root' } })
  for (const a of apps) items['apps.' + a.appId] = { id: 'apps.' + a.appId, kind: 'app', appId: a.appId, label: a.label, parent: 'apps' }
  return items
}

// Verifies: SW-REQ-261003-B7ZA
// Binds the revision's real Apps display path onto the simulated root and
// counts every comparator sort the revision runs (a spy on the context's
// Array.prototype.sort). rebuildDmenuDisplay keeps the stub's dmenu rows.
// test/shell.d/menu-apps-order-bdiff-test.sh asserts on what this prints.
function bindAppsDisplay(r, fns, rows, ctx) {
  const spy = vm.runInContext('(function() { var n = { count: 0 }; var sort = Array.prototype.sort; Array.prototype.sort = function(f) { if (typeof f === "function") n.count++; return sort.call(this, f) }; return n })()', ctx)
  for (const n of APPS_NAMES) r[n] = fns[n]
  Object.assign(r, {
    rowsLoaded: true, searchDivider: false, layoutSerial: 0,
    whenResults: {}, checkedResults: {}, disabledResults: {},
    settleCursor() {}, revealCursor() {},
    rebuildDmenuDisplay() { rows.length = 0; for (const o of this.dmenuOptions) rows.push({ label: o, detail: '' }) },
  })
  return spy
}

function parseEvents(text) {
  const ops = []
  let slow = false
  const bad = []
  const apps = []
  let locale = null
  let pluginList = false
  for (const rawLine of text.split(/\r\n|\r|\n/)) {
    const app = appDirective(rawLine)
    if (app) { apps.push(app); continue }
    const lm = LOCALE_LINE.exec(rawLine)
    if (lm) { locale = lm[1]; continue }
    if (PLUGIN_LINE.test(rawLine)) { pluginList = true; continue }
    const line = rawLine.replace(/#.*/, '')
    for (const tok of line.split(/[ \t,]+/).filter(Boolean)) {
      if (tok === '@slow') { slow = true; continue }
      const m = /^([A-Z])(?:[x*](\d+))?$/.exec(tok)
      if (!m || !OPS.has(m[1])) { bad.push(tok); continue }
      const n = m[2] === undefined ? 1 : Math.min(+m[2], 1000)
      for (let i = 0; i < n; i++) ops.push(m[1])
    }
  }
  return { ops, slow, bad, apps, locale, pluginList }
}

function extractFunctions(qml, names = NAMES) {
  const found = {}
  for (const n of names) {
    const m = qml.match(new RegExp('\\n  function ' + n + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}\\n'))
    if (m) found[n] = m[0]
  }
  const ex = qml.match(/id: resultProc\s*\n(?:\s*\/\/[^\n]*\n)*\s*onExited: \{([\s\S]*?)\n    \}/)
  return { found, onExited: ex ? ex[1] : null }
}

const ITEMS = {
  root: { id: 'root', kind: 'menu' },
  sub: { id: 'sub', kind: 'menu', parent: 'root' },
  act: { id: 'act', kind: 'action', action: 'echo act', parent: 'root' },
  lnk: { id: 'lnk', kind: 'link', target: 'sub', parent: 'root' },
}

function commandText(cmd) {
  if (Array.isArray(cmd)) return cmd.map(String).join(' ')
  if (cmd && Array.isArray(cmd.command)) return cmd.command.map(String).join(' ')
  return String(cmd)
}

function runEvents() {
  emit(`# ${HARNESS} lifecycle`)
  const { ops, slow, bad, apps, locale, pluginList } = parseEvents(readInputText())
  const appsMode = apps.length > 0
  const names = appsMode ? NAMES.concat(APPS_NAMES) : NAMES
  const items = appsMode ? appsItems(apps) : ITEMS
  emit(`events ${ops.join('') || '-'}${slow ? ' @slow' : ''}`)
  if (bad.length) emit(`ignored-tokens ${bad.join(' ')}`)
  const rel = 'shell/plugins/menu/Menu.qml'
  const qml = readRev(rel)
  if (qml === null) { emit(`lifecycle: MISSING ${rel}`); return }
  const { found, onExited } = extractFunctions(qml, names)
  const missing = names.filter(n => !found[n])
  if (missing.length) {
    // Without these the sequence cannot be replayed faithfully; report, do not guess.
    emit(`lifecycle: MISSING-FUNCTION ${missing.join(' ')}`)
    return
  }

  const S = { writes: [], busy: false, actions: [], apps: [] }
  const exec = cmd => { S.writes.push(commandText(cmd)) }
  const resultProc = {
    command: [],
    set running(v) { if (v && !S.busy) { S.busy = true; exec(this.command) } },
    get running() { return S.busy },
  }
  const mm = loadMenuModel()
  const sandbox = {
    resultProc,
    Quickshell: { execDetached: exec, env: () => '' },
    Util: { shellQuote: s => "'" + String(s).replace(/'/g, "'\\''") + "'", execDetached: exec },
    keyCatcher: { forceActiveFocus() {} },
    Qt: { callLater() {} },
    MenuModel: mm.api || {},
    console: { log() {}, warn() {}, error() {} },
  }
  const ctx = vm.createContext(sandbox)
  const rows = []
  const r = {
    opened: false, mode: 'menu', requestSerial: 0, applySerial: 0, requestActive: false,
    selectionFile: '', doneFile: '', dmenuPrompt: '', dmenuOptions: [], dmenuWidth: 300, dmenuMaxHeight: 0,
    activeMenu: 'root', navStack: [], filterText: '', selectedIndex: 0, cursorActive: true, fontFamily: '',
    pendingInitialMenu: 'root', deleteConfirmOpen: false, deleteTarget: null, shell: null,
    appLibrary: { launch(id) { S.apps.push(id) }, refreshIcons() {}, remove() {} },
    items, itemOrder: Object.keys(items),
    item(id) { return items[id] || null },
    resolveRoute(x) { return x },
    disarmPointer() {}, evaluateGuards() {}, invalidateVolatileProvider() {}, loadProviderForMenu() {},
    setActiveMenu(id) { this.activeMenu = id; this.rebuildDisplay() },
    rowSelectable(i) { return i >= 0 && i < rows.length },
    // runAction is stubbed: it is not part of the request lifecycle, and the
    // stub keeps action commands apart from answer writes.
    runAction(a) { S.actions.push(String(a)) },
    rebuildDisplay() {
      rows.length = 0
      if (this.mode === 'select' || this.mode === 'input') { for (const o of this.dmenuOptions) rows.push({ label: o, detail: '' }) }
      else rows.push({ kind: 'app', appId: 'firefox', label: 'Firefox' }, { kind: 'action', itemId: 'act', action: 'echo act' }, { kind: 'menu', itemId: 'sub' })
    },
    __dm: { get count() { return rows.length }, get(i) { return rows[i] }, clear() { rows.length = 0 }, append(row) { rows.push(row) } },
  }
  Object.defineProperty(r, 'dmenuActive', { get() { return r.mode === 'select' || r.mode === 'input' }, enumerable: true })
  // The QML id scope: names a revision's functions use resolve to root
  // properties (QML properties are reachable bare inside the component).
  const scope = new Proxy(r, {
    has(t, k) {
      if (typeof k !== 'string' || OUTER.has(k)) return false
      return k in t || (!(k in sandbox) && !(k in globalThis))
    },
  })
  const src = names.map(n => found[n]).join('\n')
  let fns
  try {
    fns = vm.runInContext(`(function(root) { var displayModel = root.__dm; with (root) { ${src}; return { ${names.join(', ')}, onExited: function() { ${onExited || ''} } } } })`, ctx, { timeout: VM_TIMEOUT_MS })(scope)
  } catch (e) {
    emit(`lifecycle: COMPILE-ERROR ${errName(e)}`)
    return
  }
  for (const n of NAMES) r[n] = fns[n]
  if (appsMode) pinLocale(ctx, locale)
  const sortSpy = appsMode ? bindAppsDisplay(r, fns, rows, ctx) : null
  if (appsMode && locale) emit(`locale ${locale}`)

  const callers = new Map()
  const stray = []
  let tag = 0
  const sel = t => '/bdiff/sel-' + t
  const done = t => '/bdiff/done-' + t
  const deliver = () => {
    for (const cmd of S.writes.splice(0)) {
      const m = cmd.match(/: > '\/bdiff\/done-(\d+)'\s*$/)
      if (!m || !callers.has(m[1])) { stray.push(cmd.replace(/\s+/g, ' ')); continue }
      const c = callers.get(m[1])
      c.writes++
      const s = cmd.match(/printf '%s\\n' '((?:[^']|'\\'')*)' > '\/bdiff\/sel-(\d+)'/)
      if (c.writes === 1) c.answer = s ? s[1].replace(/'\\''/g, "'") : '<cancel>'
      if (s && s[2] !== m[1]) c.crossed = true
    }
  }
  const exitProc = () => { if (S.busy) { S.busy = false; fns.onExited() } }
  let failure = null
  try {
    for (const op of ops) {
      switch (op) {
        case 'S': case 'I': {
          tag++
          callers.set(String(tag), { kind: op === 'S' ? 'select' : 'input', writes: 0, answer: null })
          r.open(JSON.stringify({ mode: op === 'S' ? 'select' : 'input', prompt: 'p', options: ['alpha', 'beta'], selectionFile: sel(tag), doneFile: done(tag) }))
          break
        }
        case 'N': r.open(JSON.stringify({ mode: 'select', options: ['alpha'] })); break
        case 'M': r.open(JSON.stringify({ menu: 'root' })); break
        case 'O': r.open(JSON.stringify({ menu: 'apps' })); break
        case 'A': r.open(JSON.stringify({ menu: 'act' })); break
        case 'P': r.activateIndex(0); break
        case 'R': r.activateIndex(1); break
        case 'C': r.close(); break
        case 'X': exitProc(); break
      }
      deliver()
      if (sortSpy && (op === 'O' || op === 'M')) {
        // What the summoned menu shows, in display order, and how many
        // comparator sorts the revision ran to build it.
        emit(`shown menu=${r.activeMenu} sorts=${sortSpy.count} rows=${JSON.stringify(rows.map(row => row.label))}`)
        sortSpy.count = 0
      }
      if (slow && S.busy) { exitProc(); deliver() }
    }
    let guard = 0
    while (S.busy && guard++ < 10000) { exitProc(); deliver() }
  } catch (e) {
    failure = errName(e)
  }
  if (failure) emit(`lifecycle: THROW ${failure}`)
  for (const [id, c] of callers) {
    const outcome = c.answer === null ? 'STRANDED' : (c.answer === '<cancel>' ? '<cancel>' : JSON.stringify(c.answer))
    emit(`caller ${id} ${c.kind}: ${outcome}${c.writes > 1 ? ` (written ${c.writes}x)` : ''}${c.crossed ? ' CROSSED-FILE' : ''}`)
  }
  if (!callers.size) emit('callers -')
  const owner = (String(r.doneFile).match(/done-(\d+)/) || [])[1] || '-'
  emit(`final opened=${r.opened} mode=${r.mode} requestActive=${r.requestActive} doneFileOwner=${owner}`)
  emit(`actions ${S.actions.join(',') || '-'}`)
  emit(`apps ${S.apps.join(',') || '-'}`)
  emit(`stray-writes ${stray.join(' | ') || '-'}`)
  if (appsMode && pluginList) emit(`plugin-list rows=${pluginListOrder(apps, locale)}`)
}

try {
  if (ext === '.jsonc' || ext === '.json') runJsonc()
  else if (ext === '.events') runEvents()
  else usage(`unknown input extension "${ext || '(none)'}": expected .jsonc or .events`)
} catch (e) {
  // Never a stack trace with worktree paths in it: those differ between
  // base and head and would read as a behaviour difference.
  out.push(`harness: ERROR ${errName(e)}`)
}
process.stdout.write(out.join('\n') + '\n')
