#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260925-XTGG
#
# Summon-while-request-active (upstream omacom/omarchy#9056 guard, fixes
# #9057): executes the REAL open / finishRequest / openDmenu /
# openExistingMenu / openRoute bodies from shell/plugins/menu/Menu.qml under
# node vm, with resultProc captured instead of spawning bash, and observes
# which answer writes each summon issues.
#mcdc:ignore:defensive SW-REQ-260925-XTGG: menu_open_called=T, no_active_request=F, prior_request_cancelled=F => FALSE -- open() calls finishRequest(null) unconditionally when requestActive is set, before openDmenu/openRoute can overwrite or clear the request; finishRequest captures the done-file path before clearing state and issues the done-only write, so an abandoned prior caller needs that call removed [reviewed: REVIEW-261001-SYQB]

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ROOT="$ROOT" run_node_test <<'JS'
// PR omacom/omarchy#9056 review witnesses (proof-side, execute product code):
// the REAL open / finishRequest / openDmenu / openExistingMenu / openRoute
// bodies from Menu.qml run under vm (bare property names resolve on the root
// stub via `with`), with resultProc captured instead of spawning bash.
function requestHarness() {
  const vm = require('vm')
  const fs = require('fs')
  const qml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
  const names = ['open', 'finishRequest', 'openDmenu', 'openExistingMenu', 'openRoute']
  const src = names.map(name => {
    const m = qml.match(new RegExp('\\n  function ' + name + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}\\n'))
    if (!m) throw new Error(name + ' not found in Menu.qml')
    return m[0]
  }).join('\n')
  const writes = []
  const resultProc = { command: [], set running(v) { if (v) writes.push(this.command.slice()) }, get running() { return false } }
  const r = {
    opened: false, mode: 'menu', requestSerial: 0, requestActive: false, selectionFile: '', doneFile: '',
    dmenuPrompt: '', dmenuOptions: [], dmenuWidth: 300, dmenuMaxHeight: 0, activeMenu: 'root', navStack: [],
    filterText: '', selectedIndex: 0, cursorActive: true, fontFamily: '', pendingInitialMenu: 'root', appLibrary: null,
    items: { root: { id: 'root', kind: 'menu' } }, itemOrder: ['root'],
    item(id) { return this.items[id] || null },
    resolveRoute(input) { return input },
    disarmPointer() {}, evaluateGuards() {}, rebuildDisplay() {}, invalidateVolatileProvider() {}, loadProviderForMenu() {},
    cancel() { this.finishRequest(null) }, runAction() {}
  }
  const fns = vm.runInNewContext(`(function() { with (root) { ${src}; return { ${names.join(', ')} } } })()`, {
    root: r, resultProc, keyCatcher: { forceActiveFocus() {} }, Qt: { callLater() {} },
    Util: { shellQuote: s => "'" + String(s).replace(/'/g, "'\\''") + "'" }, JSON, Math, Number, String, Array
  })
  for (const n of names) r[n] = fns[n]
  return { r, writes }
}
const selectPayload = (tag) => JSON.stringify({ mode: 'select', prompt: 'Pick ' + tag, options: ['a', 'b'], selectionFile: '/tmp/sel-' + tag, doneFile: '/tmp/done-' + tag })

{ // a summon while a select request is active answers the prior request as cancelled
  const { r, writes } = requestHarness()
  r.open(selectPayload('first'))
  assertEqual(r.requestActive, true, 'the first select request is active')
  assertEqual(writes.length, 0, 'opening the first request writes nothing')
  // Verifies: SW-REQ-260925-XTGG
  // MCDC SW-REQ-260925-XTGG: menu_open_called=T, no_active_request=F, prior_request_cancelled=T => TRUE
  r.open(selectPayload('second'))
  assertEqual(writes.length, 1, 'the second summon issues exactly one answer write')
  assertEqual(writes[0][2], ": > '/tmp/done-first'", 'the prior request is answered done-file-only (cancelled), no selection written')
  assertEqual(r.doneFile, '/tmp/done-second', 'the new request owns its own done file after the cancel')
  assertEqual(r.requestActive, true, 'the new request is active and not pre-answered')
}

{ // a plain route summon also cancels a pending picker
  const { r, writes } = requestHarness()
  r.open(selectPayload('pending'))
  r.open(JSON.stringify({ menu: 'root' }))
  assertEqual(writes.length, 1, 'the route summon answers the pending picker once')
  assertEqual(writes[0][2], ": > '/tmp/done-pending'", 'the pending picker is answered as cancelled')
  assertEqual(r.requestActive, false, 'no request stays active after a route summon')
}

{ // a summon with no active request cancels nothing
  const { r, writes } = requestHarness()
  // Verifies: SW-REQ-260925-XTGG
  // MCDC SW-REQ-260925-XTGG: menu_open_called=T, no_active_request=T, prior_request_cancelled=F => TRUE [no-action: no request is active before this summon, so the guard does not fire and no answer write is issued]
  r.open(selectPayload('clean'))
  assertEqual(writes.length, 0, 'a clean summon issues no answer write')
  // Verifies: SW-REQ-260925-XTGG
  // MCDC SW-REQ-260925-XTGG: menu_open_called=F, no_active_request=F, prior_request_cancelled=F => TRUE [no-action: with a request active but no new summon, open() is never entered and the request stays pending with no write]
  assertEqual(r.requestActive, true, 'the request stays pending until answered')
  assertEqual(writes.length, 0, 'an active request with no new summon receives no write')
}
JS
