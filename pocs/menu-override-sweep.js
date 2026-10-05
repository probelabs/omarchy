// Reproducer for KI-MENU-MERGE-OVERRIDE-WIPES-DEFAULTS through the LIVE load path.
//
// Usage (from the repo root): node pocs/menu-override-sweep.js
//
// For every row of the shipped menu (default/omarchy/omarchy-menu.jsonc) and every
// user-settable field, it writes a one-field extension entry, parses both files with
// the parser each FileView in Menu.qml calls on this tree, and merges them with
// mergeMenuSources. The contract (SW-REQ-260922-7NPE) is that the merged row equals
// the shipped row with only the declared field changed.
//
// Control: an extension entry that restates a shipped row unchanged must leave that
// row unchanged. If the control fails, or the loader wiring cannot be read from
// Menu.qml, the result is INCONCLUSIVE (exit 2).
//
// Exit 1: the defect is present (at least one override changes an undeclared field).
// Exit 0: every single-field override changes only the declared field.
const fs = require('fs')
const path = require('path')

const root = path.resolve(__dirname, '..')
const m = require(path.join(root, 'shell/plugins/menu/MenuModel.js'))
const qml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

function inconclusive(why) {
  console.log('INCONCLUSIVE: ' + why)
  process.exit(2)
}

// The parser Menu.qml's FileView for <which> calls, with the flag it passes.
function parser(which) {
  const call = qml.match(new RegExp('root\\.' + which + 'MenuItems = root\\.(\\w+)\\(text\\(\\)\\)'))
  if (!call) inconclusive('no FileView assigns root.' + which + 'MenuItems in Menu.qml')
  const def = qml.match(new RegExp('function ' + call[1] + '\\(raw\\) \\{\\s*return MenuModel\\.(\\w+)\\(raw(?:,\\s*(false|true))?\\)'))
  if (!def || typeof m[def[1]] !== 'function') inconclusive('cannot resolve ' + call[1] + ' to a MenuModel parser')
  const name = def[1], flag = def[2]
  return raw => flag ? m[name](raw, flag === 'true') : m[name](raw)
}

const parseDefault = parser('default')
const parseUser = parser('user')
const shippedText = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')
const shipped = JSON.parse(m.stripJsonc(shippedText))
const rows = shipped.items && !Array.isArray(shipped.items) ? shipped.items : shipped
const fields = ['label', 'icon', 'iconFont', 'title', 'target', 'description', 'action', 'provider',
  'aliases', 'when', 'checked', 'disabled', 'parent']

const same = (got, want) => {
  const keys = Object.keys(want).sort()
  return JSON.stringify(got, keys) === JSON.stringify(want, keys) && Object.keys(got).length === keys.length
}
const merged = (id, entry) => {
  const got = m.mergeMenuSources(parseDefault(shippedText), parseUser(JSON.stringify({ [id]: entry }))).items[id]
  if (got) delete got.order
  return got
}

// Control: restating the About row unchanged leaves it unchanged.
if (!rows.about) inconclusive('the shipped menu has no about row')
if (!same(merged('about', rows.about), m.normalizeItem('about', Object.assign({}, rows.about))))
  inconclusive('control failed: restating the shipped about row changed it')
console.log('control ok: restating a shipped row unchanged leaves it unchanged')

let cases = 0, wrong = 0, example = ''
for (const id of Object.keys(rows)) {
  for (const f of fields) {
    for (const v of f === 'aliases' ? [['zz'], []] : ['zz', '']) {
      cases++
      const want = m.normalizeItem(id, Object.assign({}, rows[id], { [f]: v }))
      const got = merged(id, { [f]: v })
      if (!got || !same(got, want)) {
        wrong++
        if (!example && got && id === 'about')
          example = id + ' with only ' + f + '=' + JSON.stringify(v) + ' also changes: ' +
            Object.keys(want).filter(k => k !== f && JSON.stringify(got[k]) !== JSON.stringify(want[k]))
              .map(k => k + ' ' + JSON.stringify(want[k]) + ' -> ' + JSON.stringify(got[k])).join(', ')
      }
    }
  }
}

console.log(wrong + ' of ' + cases + ' single-field overrides change more than the declared field')
if (example) console.log('  e.g. ' + example)
if (wrong > 0) {
  console.log('DEFECT PRESENT: a one-field user override resets fields it did not declare')
  process.exit(1)
}
console.log('FIXED: every single-field override changes only the declared field')
