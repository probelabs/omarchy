// Green tripwire harness for SYS-REQ-260922-47T8 external_call_timeout_bounded.
// Reproduces: KI-MENU-GUARD-BATCH-NO-DEADLINE
// Driven by pocs/47t8-guard-batch-no-deadline.sh (see that file for the contract).
//
// Executes the REAL guard path, not a re-implementation:
//   - evaluateGuards() body, and guardProc's stdout onRead + onExited bodies,
//     are extracted verbatim from shell/plugins/menu/Menu.qml at run time;
//   - MenuModel.guardScript() is the real shell/plugins/menu/MenuModel.js;
//   - the Process element is a minimal stand-in for Quickshell's Process that
//     spawns whatever argv Menu.qml puts in guardProc.command (so a deadline
//     added there - e.g. a `timeout` prefix - is honoured), splits stdout into
//     lines like SplitParser, and reports onExited(exitCode, exitStatus) with
//     exitStatus 1 for a signal-killed child. Qt.callLater -> setImmediate.
'use strict'
const fs = require('fs')
const path = require('path')
const { spawn, spawnSync } = require('child_process')

const repo = path.resolve(__dirname, '..')
const tmp = process.env.TRIPWIRE_TMP
if (!tmp) { console.log('HARNESS ERROR: TRIPWIRE_TMP unset'); process.exit(2) }
const qml = fs.readFileSync(path.join(repo, 'shell/plugins/menu/Menu.qml'), 'utf8')
const MenuModel = require(path.join(repo, 'shell/plugins/menu/MenuModel.js'))

// --- verbatim extraction ---------------------------------------------------------
function bodyAfter(src, anchor, from) {
  const at = src.indexOf(anchor, from || 0)
  if (at < 0) return null
  let i = src.indexOf('{', at + anchor.length - 1)
  const start = i + 1
  let depth = 0
  for (; i < src.length; i++) {
    if (src[i] === '{') depth++
    else if (src[i] === '}' && --depth === 0) return src.slice(start, i)
  }
  return null
}
const evalBody = bodyAfter(qml, 'function evaluateGuards() {')
const procAt = qml.indexOf('id: guardProc')
const readBody = bodyAfter(qml, 'onRead: function(data) {', procAt)
const exitBody = bodyAfter(qml, 'onExited: function(exitCode, exitStatus) {', procAt)
if (!evalBody || procAt < 0 || !readBody || !exitBody) {
  console.log('HARNESS ERROR: could not extract evaluateGuards / guardProc handlers from Menu.qml')
  process.exit(2)
}
console.log(`extracted from Menu.qml: evaluateGuards (${evalBody.length} chars), guardProc onRead + onExited (${exitBody.length} chars)`)

const children = []

function makeMenu(env) {
  const root = {
    items: {}, whenResults: {}, checkedResults: {}, disabledResults: {},
    guardsPending: false, opened: false, rebuildDisplay() {},
  }
  const Qt = { callLater: fn => setImmediate(fn) }
  const stats = { spawns: 0, exits: [] }
  let child = null
  const guardProc = {
    collected: '',
    command: [],
    get running() { return child !== null },
    set running(v) {
      if (v && !child) start()
      else if (!v && child) { try { process.kill(-child.pid, 'SIGTERM') } catch (e) {} }
    },
  }
  const evaluateGuards = new Function('root', 'guardProc', 'MenuModel', 'Qt', evalBody)
  const onRead = new Function('guardProc', 'data', readBody)
  const onExited = new Function('root', 'guardProc', 'Qt', 'exitCode', 'exitStatus', exitBody)
  root.evaluateGuards = () => evaluateGuards(root, guardProc, MenuModel, Qt)

  function start() {
    const argv = guardProc.command.slice()
    const c = spawn(argv[0], argv.slice(1), { detached: true, stdio: ['ignore', 'pipe', 'ignore'], env })
    child = c
    children.push(c)
    stats.spawns++
    stats.lastArgv0 = argv[0]
    let buf = ''
    c.stdout.on('data', d => {
      buf += d.toString()
      let nl
      while ((nl = buf.indexOf('\n')) >= 0) { onRead(guardProc, buf.slice(0, nl)); buf = buf.slice(nl + 1) }
    })
    c.on('close', (code, signal) => {
      if (buf) onRead(guardProc, buf)
      child = null
      stats.exits.push({ at: Date.now(), code, signal })
      onExited(root, guardProc, Qt, signal ? 0 : code, signal ? 1 : 0)
    })
  }
  return { root, guardProc, stats }
}

const sleep = ms => new Promise(r => setTimeout(r, ms))
async function until(pred, ms) {
  const end = Date.now() + ms
  while (Date.now() < end) { if (pred()) return true; await sleep(25) }
  return pred()
}

let fail = 0
const ok = m => console.log('ok: ' + m)
const bad = m => { console.log('FAIL: ' + m); fail = 1 }

const env = Object.assign({}, process.env, {
  HOME: path.join(tmp, 'home'),
  PATH: path.join(tmp, 'bin') + ':' + process.env.PATH,
  GUARD_STATE: path.join(tmp, 'state'),
  GUARD_LOCK: path.join(tmp, 'guard.lock'),
})
const stateRow = { id: 'row.state', label: 'State row', checked: '[[ -f "$GUARD_STATE" ]]' }

async function main() {
  // ---- control: healthy guards answer, and a re-evaluation picks up new state --
  console.log('== control: healthy guard batch ==')
  try { fs.unlinkSync(env.GUARD_STATE) } catch (e) {}
  const c = makeMenu(env)
  c.root.items = { 'row.a': { id: 'row.a', label: 'A', when: 'true' }, 'row.state': stateRow }
  c.root.evaluateGuards()
  await until(() => c.stats.exits.length === 1, 5000)
  if (c.stats.exits.length === 1 && c.root.whenResults['row.a'] === true && c.root.checkedResults['row.state'] === false)
    ok(`batch completed (${c.stats.lastArgv0} ...), answers landed: row.a when=true, row.state checked=false`)
  else bad(`control batch did not land: exits=${c.stats.exits.length} results=${JSON.stringify([c.root.whenResults, c.root.checkedResults])}`)
  fs.writeFileSync(env.GUARD_STATE, '')
  c.root.evaluateGuards()
  await until(() => c.stats.exits.length === 2, 5000)
  if (c.root.checkedResults['row.state'] === true) ok('re-evaluation after the state flip answers row.state checked=true (fresh)')
  else bad('control re-evaluation did not refresh row.state')

  // ---- defect arm: one guard blocks on a held lock; the batch never ends -------
  console.log('== defect arm: a guard expression blocks (waits on a lock held elsewhere) ==')
  try { fs.unlinkSync(env.GUARD_STATE) } catch (e) {}
  const holder = spawn('flock', [env.GUARD_LOCK, 'sleep', '300'], { detached: true, stdio: 'ignore' })
  children.push(holder)
  const held = await until(() => spawnSync('flock', ['-n', env.GUARD_LOCK, 'true']).status !== 0, 3000)
  if (!held) { console.log('HARNESS ERROR: could not hold the lock'); return 2 }

  const d = makeMenu(env)
  d.root.items = { 'row.state': stateRow }
  d.root.evaluateGuards()
  await until(() => d.stats.exits.length === 1, 5000)
  if (d.root.checkedResults['row.state'] !== false) { console.log('HARNESS ERROR: baseline answer missing'); return 2 }
  ok('baseline answer: row.state checked=false')

  // The user's menu gains a guard that waits on the lock (a reload re-evaluates).
  d.root.items = {
    'row.locked': { id: 'row.locked', label: 'Locked probe', when: 'flock "$GUARD_LOCK" true' },
    'row.state': stateRow,
  }
  const t0 = Date.now()
  d.root.evaluateGuards()
  await sleep(1000)
  // The system state changes and the menu re-evaluates (reload / reopen).
  fs.writeFileSync(env.GUARD_STATE, '')
  d.root.evaluateGuards()
  await sleep(3000)
  const secs = ((Date.now() - t0) / 1000).toFixed(1)
  const exitsSince = d.stats.exits.filter(e => e.at >= t0).length

  if (d.guardProc.running && exitsSince === 0) ok(`blocked batch still running after ${secs}s - no deadline ended it (0 exits since it started)`)
  else bad(`blocked batch ended within ${secs}s (exits since start=${exitsSince}) - a deadline is present`)
  if (d.stats.spawns === 2) ok('the re-evaluation started no new batch (spawns stay at 2) - it stands aside behind the wedged one')
  else bad(`spawns=${d.stats.spawns}, expected 2`)
  if (d.root.guardsPending === true) ok('guardsPending=true - every later evaluation is deferred behind the wedged batch')
  else bad('guardsPending is not set')
  if (d.root.checkedResults['row.state'] === false && fs.existsSync(env.GUARD_STATE))
    ok('row.state still shows checked=false while the state it describes is now true (stale answer)')
  else bad(`row.state answer is ${d.root.checkedResults['row.state']} - not stale`)
  return fail
}

main().then(rc => {
  for (const ch of children) { try { process.kill(-ch.pid, 'SIGKILL') } catch (e) {} }
  if (rc === 2) process.exit(2)
  if (!fail) {
    console.log('TRIPWIRE GREEN: the menu guard batch has no deadline - one blocking guard wedges guard freshness (healthy control refreshes normally)')
    process.exit(0)
  }
  console.log('TRIPWIRE RED: the blocked batch no longer wedges guard evaluation (deadline present?) or the control broke')
  process.exit(1)
})
