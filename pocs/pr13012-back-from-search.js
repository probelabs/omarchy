#!/usr/bin/env node
// PoC (PR omacom/omarchy#13012 review, advisory): Back after drilling into a
// DEEPER submenu from a filtered root search parks the cursor on an unrelated
// root row. Executes the REAL setActiveMenu / goBack / rebuildDisplay /
// settleCursor / nextSelectable / rowSelectable bodies from Menu.qml under vm
// against the real MenuModel.js and the shipped default menu.
// Mechanism: setActiveMenu pushes {menu: activeMenu, index: selectedIndex,
// itemId} where index points into the FILTERED list and itemId is the deeper
// row just entered. goBack clears the filter, restores selectedIndex = index
// in the UNFILTERED list, and the itemId loop finds nothing (the deeper row is
// not a root row), so the cursor stays on whatever root row sits at that
// index. The baseline (pre-PR) reset the cursor to row 0.
// Green tripwire: exit 0 = defect present (cursor on an unrelated row);
// exit 1 = fixed (cursor on the row 0 or on the entered row's root ancestor).
'use strict'
const fs = require('fs'), path = require('path'), vm = require('vm')
const repo = process.env.POC_REPO || path.resolve(__dirname, '..')
const menuModel = require(path.join(repo, 'shell/plugins/menu/MenuModel.js'))
const qml = fs.readFileSync(path.join(repo, 'shell/plugins/menu/Menu.qml'), 'utf8')
const fn = name => {
  const m = qml.match(new RegExp('\\n  function ' + name + '\\([^)]*\\) \\{[\\s\\S]*?\\n  \\}\\n'))
  if (!m) { console.log('UNEXPECTED: ' + name + ' not found'); process.exit(2) }
  return m[0]
}
const names = ['setActiveMenu', 'goBack', 'rebuildDisplay', 'settleCursor', 'nextSelectable', 'rowSelectable']
const defaults = menuModel.parseMenuJsonc(fs.readFileSync(path.join(repo, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const merged = menuModel.mergeMenuSources(defaults, [])
const model = []
const displayModel = { clear() { model.length = 0 }, append(r) { model.push(r) }, get count() { return model.length }, get(i) { return model[i] } }
const r = {
  dmenuActive: false, rowsLoaded: true, activeMenu: 'root', filterText: '', searchDivider: false,
  navStack: [], selectedIndex: 0, cursorActive: true,
  items: merged.items, itemOrder: merged.itemOrder, whenResults: {}, disabledResults: {}, checkedResults: {},
  item(id) { return this.items[id] || null },
  isDescendantOf(id, a) { return menuModel.isDescendantOf(this.items, id, a) },
  isVisible(e) { return menuModel.isVisible(this.items, this.itemOrder, this.whenResults, e) },
  isDisabled(e) { return menuModel.isDisabled(this.disabledResults, e) },
  matchesQuery(e, q) { return menuModel.matchesQuery(e, q, this.isVisible(e) && !this.isDisabled(e)) },
  parentPathFor(id) { return menuModel.parentPathFor(this.items, id) },
  searchScore(e, q) { return menuModel.searchScore(this.items, e, q) },
  displayRow(e, d, s, sec) { return menuModel.displayRow(this.items, this.itemOrder, this.checkedResults, this.disabledResults, e, d, s, sec) },
  revealCursor() {}, disarmPointer() {}, invalidateVolatileProvider() {}, loadProviderForMenu() {}
}
const fns = vm.runInNewContext(`(function() { ${names.map(fn).join('\n')}; return { ${names.join(', ')} } })()`, {
  root: r, displayModel, layoutSerial: 0, Qt: { callLater() {} },
  panel: { freezeCardTop() {} }, pointerGate: { allowInitialSample() {} }
})
for (const n of names) r[n] = fns[n].bind(r)

// Root search for a query whose best rows include a DEEPER submenu.
r.rebuildDisplay()
const rootRows = model.map(x => x.itemId)
r.filterText = 'font'
r.rebuildDisplay()
const filtered = model.map(x => ({ id: x.itemId, kind: x.kind }))
const pick = filtered.findIndex(x => x.id && x.id.includes('.') && menuModel.childCount(r.items, r.itemOrder, x.id) > 0)
if (pick < 1) { console.log('UNEXPECTED: no deeper submenu at index>=1 for query font: ' + JSON.stringify(filtered)); process.exit(2) }
r.selectedIndex = pick
const entered = filtered[pick].id
r.setActiveMenu(entered, true)          // Enter on a submenu row drills in with history
r.goBack()                              // Backspace / Left on an empty filter
const landed = model[r.selectedIndex] && model[r.selectedIndex].itemId
const ancestor = rootRows.find(id => menuModel.isDescendantOf(r.items, entered, id))
console.log(JSON.stringify({ query: 'font', filtered_index: pick, entered, back_to: r.activeMenu, landed_index: r.selectedIndex, landed_row: landed, root_ancestor: ancestor }))
if (r.activeMenu === 'root' && r.selectedIndex === pick && landed !== ancestor && r.selectedIndex !== 0) {
  console.log('SYMPTOM: Back restored the filtered-list index into the unfiltered root list; cursor on unrelated row ' + landed + ' (defect present)')
  process.exit(0)
}
console.log('PASS-REFUTED: cursor on row 0 or on the entered row\'s ancestor')
process.exit(1)
