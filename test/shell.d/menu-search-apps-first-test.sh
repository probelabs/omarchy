#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-TKDP, SW-REQ-260922-SJ7P
#
# Search ranking and sectioning with installed apps (upstream
# omacom/omarchy#12223): executes the REAL rebuildDisplay search branch from
# shell/plugins/menu/Menu.qml under node vm against the real MenuModel.js and
# the shipped default menu merged with app rows, so the apps-first pinning and
# the divider placement are observed in execution rather than matched as
# source text.

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

ROOT="$ROOT" run_node_test <<'JS'
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
// PR omacom/omarchy#12223 review witness (proof-side, executes product code):
// runs the REAL rebuildDisplay search branch from Menu.qml under vm against
// the real MenuModel.js and the shipped default menu merged with app rows,
// so the apps-first pinning and the divider placement are observed in
// execution rather than matched as source text.
function searchDisplay(appRows, activeMenu, query) {
  const vm = require('vm')
  const fs = require('fs')
  const qml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
  const fnMatch = qml.match(/\n  function rebuildDisplay\(\) \{[\s\S]*?\n  \}\n/)
  if (!fnMatch) throw new Error('rebuildDisplay not found in Menu.qml')
  const defaults = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
  const base = menu.mergeMenuSources(defaults, [])
  const merged = menu.mergeAppRows(base.items, base.itemOrder, appRows)
  const model = []
  const displayModel = { clear() { model.length = 0 }, append(r) { model.push(r) }, get count() { return model.length } }
  const r = {
    dmenuActive: false, rowsLoaded: true, activeMenu, filterText: query, searchDivider: false,
    items: merged.items, itemOrder: merged.itemOrder, whenResults: {}, disabledResults: {}, checkedResults: {},
    item(id) { return this.items[id] || null },
    isDescendantOf(id, a) { return menu.isDescendantOf(this.items, id, a) },
    isVisible(e) { return menu.isVisible(this.items, this.itemOrder, this.whenResults, e) },
    isDisabled(e) { return menu.isDisabled(this.disabledResults, e) },
    matchesQuery(e, q) { return menu.matchesQuery(e, q, this.isVisible(e) && !this.isDisabled(e)) },
    parentPathFor(id) { return menu.parentPathFor(this.items, id) },
    searchScore(e, q) { return menu.searchScore(this.items, e, q) },
    displayRow(e, d, s, sec) { return menu.displayRow(this.items, this.itemOrder, this.checkedResults, this.disabledResults, e, d, s, sec) },
    settleCursor() {}, revealCursor() {}
  }
  const fn = vm.runInNewContext(`(function() {${fnMatch[0]}; return rebuildDisplay })()`, {
    root: r, displayModel, layoutSerial: 0, Qt: { callLater() {} }
  })
  fn.call(r)
  return { rows: model.slice(), divider: r.searchDivider }
}

{ // root search pins apps above direct children and deeper entries
  const apps = [
    { id: 'apps.chromium', parent: 'apps', kind: 'app', label: 'Chromium', description: 'Web Browser', aliases: [] },
    { id: 'apps.calculator', parent: 'apps', kind: 'app', label: 'Calculator', description: '', aliases: [] }
  ]
  const { rows, divider } = searchDisplay(apps, 'root', 'c')
  assert(rows.length > 2, 'root search for c lists rows')
  const firstMenu = rows.findIndex(row => row.kind !== 'app')
  assert(firstMenu > 0, 'apps occupy the leading rows of a root search')
  assert(rows.slice(firstMenu).every(row => row.kind !== 'app'), 'no app row sorts below a menu row')
  assert(rows.slice(0, firstMenu).every(row => row.section !== 'drilldown'), 'app rows carry no drilldown section')
  assert(rows.slice(firstMenu).every(row => row.section === 'drilldown'), 'every menu row after the apps sits in the drilldown section')
  const boundaries = rows.filter((row, i) => i > 0 && row.section === 'drilldown' && rows[i - 1].section !== 'drilldown').length
  assertEqual(boundaries, 1, 'exactly one divider is drawn, between apps and menu entries')
  assertEqual(divider, true, 'searchDivider is set when apps and menu entries both match')
}

{ // without app matches, direct children stay above deeper entries with one divider
  const { rows, divider } = searchDisplay([], 'root', 'c')
  const firstDeep = rows.findIndex(row => row.section === 'drilldown')
  assert(firstDeep > 0, 'direct children lead a root search with no app matches')
  assert(rows.slice(firstDeep).every(row => row.section === 'drilldown'), 'deeper entries all follow the divider')
  assertEqual(divider, true, 'searchDivider is set when direct and deeper matches both exist')
}

{ // a keyword-only app match outranks an exact-label menu entry (intended-behavior question)
  const ranked2 = menu.mergeAppRows(menu.mergeMenuSources(menu.parseMenuJsonc(require('fs').readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')), []).items,
    menu.mergeMenuSources(menu.parseMenuJsonc(require('fs').readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')), []).itemOrder,
    [{ id: 'apps.gradience', parent: 'apps', kind: 'app', label: 'Gradience', description: 'Customize the update look', aliases: [] }])
  const exactId = Object.keys(ranked2.items).find(id => ranked2.items[id].kind !== 'app' && String(ranked2.items[id].label).toLowerCase() === 'update')
  assert(!!exactId, 'the default menu carries an entry labelled exactly Update')
  const s = id => menu.searchScore(ranked2.items, ranked2.items[id], 'update')
  assert(s('apps.gradience') < s(exactId), 'a description-only app match ranks above the exact-label Update menu entry under the apps-first bias')
}
JS
