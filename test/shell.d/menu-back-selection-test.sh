#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-261001-B4CK
#
# Back restores the parent selection (upstream omacom/omarchy#13012): executes
# the REAL setActiveMenu / goBack / rebuildDisplay / settleCursor /
# nextSelectable / rowSelectable bodies from shell/plugins/menu/Menu.qml under
# node vm against the real MenuModel.js and the shipped default menu.
#mcdc:ignore:defensive SW-REQ-261001-B4CK: back_navigated=T, remembered_row_present=T, remembered_row_selected=F => FALSE -- after rebuildDisplay, setActiveMenu scans displayModel for the remembered itemId and selects the first index whose row matches and is selectable; a present, selectable remembered row left unselected needs that loop removed [reviewed: REVIEW-B4CK]

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ROOT="$ROOT" run_node_test <<'JS'
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
// PR omacom/omarchy#13012 review witnesses (proof-side, execute product code):
// the REAL setActiveMenu / goBack / rebuildDisplay / settleCursor /
// nextSelectable / rowSelectable bodies from Menu.qml run under vm against the
// real MenuModel.js and the shipped default menu.
function navHarness(disabledResults) {
  const vm = require('vm')
  const fs = require('fs')
  const qml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
  const names = ['setActiveMenu', 'goBack', 'rebuildDisplay', 'settleCursor', 'nextSelectable', 'rowSelectable']
  const src = names.map(name => {
    const m = qml.match(new RegExp('\\n  function ' + name + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}\\n'))
    if (!m) throw new Error(name + ' not found in Menu.qml')
    return m[0]
  }).join('\n')
  const defaults = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
  const merged = menu.mergeMenuSources(defaults, [])
  const model = []
  const displayModel = { clear() { model.length = 0 }, append(r) { model.push(r) }, get count() { return model.length }, get(i) { return model[i] } }
  const r = {
    dmenuActive: false, rowsLoaded: true, activeMenu: 'root', filterText: '', searchDivider: false,
    navStack: [], selectedIndex: 0, cursorActive: true,
    items: merged.items, itemOrder: merged.itemOrder, whenResults: {}, disabledResults: disabledResults || {}, checkedResults: {},
    item(id) { return this.items[id] || null },
    isDescendantOf(id, a) { return menu.isDescendantOf(this.items, id, a) },
    isVisible(e) { return menu.isVisible(this.items, this.itemOrder, this.whenResults, e) },
    isDisabled(e) { return menu.isDisabled(this.disabledResults, e) },
    matchesQuery(e, q) { return menu.matchesQuery(e, q, this.isVisible(e) && !this.isDisabled(e)) },
    parentPathFor(id) { return menu.parentPathFor(this.items, id) },
    searchScore(e, q) { return menu.searchScore(this.items, e, q) },
    displayRow(e, d, s, sec) { return menu.displayRow(this.items, this.itemOrder, this.checkedResults, this.disabledResults, e, d, s, sec) },
    revealCursor() {}, disarmPointer() {}, invalidateVolatileProvider() {}, loadProviderForMenu() {}
  }
  const fns = vm.runInNewContext(`(function() { ${src}; return { ${names.join(', ')} } })()`, {
    root: r, displayModel, layoutSerial: 0, Qt: { callLater() {} },
    panel: { freezeCardTop() {} }, pointerGate: { allowInitialSample() {} }
  })
  for (const n of names) r[n] = fns[n].bind(r)
  r.rebuildDisplay()
  return { r, model }
}

{ // Back from a submenu reselects the row that opened it
  const { r, model } = navHarness()
  const styleIndex = model.findIndex(row => row.itemId === 'style')
  assert(styleIndex > 0, 'the default root menu lists Style below the first row')
  r.selectedIndex = styleIndex
  r.setActiveMenu('style', true)
  assertEqual(r.navStack.length, 1, 'drilling in pushes one navigation record')
  assertEqual(r.navStack[0].menu, 'root', 'the navigation record names the parent menu')
  assertEqual(r.navStack[0].itemId, 'style', 'the navigation record remembers the selected row id')
  // MCDC SW-REQ-261001-B4CK: back_navigated=T, remembered_row_present=T, remembered_row_selected=T => TRUE
  r.goBack()
  assertEqual(r.activeMenu, 'root', 'Back returns to the parent menu')
  assertEqual(model[r.selectedIndex].itemId, 'style', 'Back reselects the row that opened the submenu')
}

{ // Back falls back to the saved index when the remembered row is no longer selectable
  const { r, model } = navHarness()
  const styleIndex = model.findIndex(row => row.itemId === 'style')
  r.selectedIndex = styleIndex
  r.setActiveMenu('style', true)
  r.items.style = Object.assign({}, r.items.style, { disabled: 'omarchy-cmd-missing nothing' })
  r.disabledResults = { style: true }
  // MCDC SW-REQ-261001-B4CK: back_navigated=T, remembered_row_present=F, remembered_row_selected=F => TRUE [no-action: the remembered row is disabled, so the id loop selects nothing and the saved index (settled off disabled rows) stands]
  r.goBack()
  assert(model[r.selectedIndex].itemId !== 'style', 'Back never parks the cursor on the now-disabled remembered row')
  assert(!model[r.selectedIndex].disabled, 'Back leaves the cursor on a selectable row')
}

{ // entering a menu without Back keeps the cursor at the first row
  const { r, model } = navHarness()
  // MCDC SW-REQ-261001-B4CK: back_navigated=F, remembered_row_present=F, remembered_row_selected=F => TRUE [no-action: a forward drill-in carries no restore record, so setActiveMenu starts at row 0]
  r.selectedIndex = 3
  r.setActiveMenu('style', true)
  assertEqual(r.selectedIndex, 0, 'a forward drill-in starts on the first row')
}
JS
