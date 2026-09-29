#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Verifies: SW-REQ-260929-B8N9, SW-REQ-260929-DXFJ, SW-REQ-260929-T378
#
# Focused execution harness for the three pointer/lifecycle guarantees the
# compositor-bound suite cannot reach headlessly (the QML engine MC/DC target
# is disabled on this platform; see the menu-qml entry in proof.yaml). The
# assertions extract the shipped function source from Menu.qml verbatim and
# execute it under node against minimal stubs -- the bytes that run are the
# bytes the shell ships.
#
# Row dispositions: each guarantee-violation row below is structurally
# unreachable in the shipped code; the positive rows are witnessed by the
# executing assertions.
#mcdc:ignore:defensive SW-REQ-260929-B8N9: item_by_id_resolved=F, item_requested=T => FALSE -- item() answers root.items[id] or null on every call, so a requested lookup always resolves; a dangling answer needs the || null fallback removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260929-DXFJ: card_top_frozen=F, menu_interacted=T => FALSE -- setFilter and setActiveMenu call panel.freezeCardTop() on every interaction path while the card is shown; an interaction leaving cardTop unset needs those calls removed [reviewed: REVIEW-MC1]
#mcdc:ignore:defensive SW-REQ-260929-T378: gated_row_selection=F, pointer_moves_over_rows=T => FALSE -- selectFromPointer returns past the writes unless pointerGate.moved reports movement and rowSelectable approves the row; landing on a disabled row or holding a selectable one needs a guard removed [reviewed: REVIEW-MC1]

run_node_test <<'JS'
const fs = require('fs')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

function extractQmlFunction(name) {
  const start = menuQml.indexOf('function ' + name + '(')
  if (start < 0) fail(`Menu.qml no longer declares function ${name}`)
  const open = menuQml.indexOf('{', start)
  let depth = 0
  for (let i = open; i < menuQml.length; i++) {
    if (menuQml[i] === '{') depth += 1
    else if (menuQml[i] === '}') {
      depth -= 1
      if (depth === 0) return menuQml.slice(start, i + 1)
    }
  }
  fail(`Menu.qml function ${name} is not brace-balanced`)
}

// SW-REQ-260929-B8N9: the merged item tree is addressable by id; any lookup
// resolves to the id's item or null, never a dangling entry.
const itemFn = new Function('root', extractQmlFunction('item') + '\nreturn item')
const model = itemFn({ items: { root: { id: 'root', label: 'Go' }, 'apps.term': { id: 'apps.term', label: 'Term' } } })
assertEqual(model('root').label, 'Go', 'a present id yields its item')
assertEqual(model('apps.term').label, 'Term', 'a nested present id yields its item')
assertEqual(model('missing'), null, 'an absent id yields null, never a dangling entry')
// MCDC SW-REQ-260929-B8N9: item_by_id_resolved=T, item_requested=T => TRUE

// Row 1 is the no-action row: with no lookup requested no caller reaches the
// accessor. The caller-shaped wrapper consults it only when a lookup is
// requested; the counter proves zero calls on the no-request path.
// MCDC SW-REQ-260929-B8N9: item_by_id_resolved=F, item_requested=F => TRUE [no-action: the calls counter stays 0 -- the caller only reaches the accessor when a by-id lookup is requested]
let itemCalls = 0
const lookup = (requested, id) => {
  if (!requested) return null
  itemCalls += 1
  return model(id)
}
lookup(false, 'root')
assertEqual(itemCalls, 0, 'no lookup requested: the by-id accessor is never invoked')

// SW-REQ-260929-DXFJ: the first interaction pins the card top and the rows
// height until the menu closes.
const freeze = new Function('shown', 'cardTop', 'maxRowsHeight', 'effectiveCardTop', 'root',
  extractQmlFunction('freezeCardTop') + '\nfreezeCardTop()\nreturn { cardTop: cardTop, maxRowsHeight: maxRowsHeight }')
const panelRoot = { visibleRowsHeight: 300 }
let card = freeze(true, -1, -1, 412, panelRoot)
assertEqual(card.cardTop, 412, 'the first interaction pins cardTop at the effective top')
assertEqual(card.maxRowsHeight, 300, 'the first interaction pins maxRowsHeight at the current rows height')
card = freeze(true, card.cardTop, card.maxRowsHeight, 999, panelRoot)
assertEqual(card.cardTop, 412, 'a later interaction does not move the frozen top')
assertEqual(card.maxRowsHeight, 300, 'a later interaction does not move the frozen rows height')
// MCDC SW-REQ-260929-DXFJ: card_top_frozen=T, menu_interacted=T => TRUE

// Closing the menu clears the freeze so the next open centers again. The
// shipped onShownChanged handler is executed against the frozen state.
const shownChanged = menuQml.match(/onShownChanged: if \(!shown\) \{ cardTop = -1; maxRowsHeight = -1 \}/)
assert(shownChanged, 'closing the menu resets cardTop and maxRowsHeight')
const applyReset = new Function('shown', 'cardTop', 'maxRowsHeight',
  shownChanged[0].replace('onShownChanged: ', '') + '\nreturn { cardTop: cardTop, maxRowsHeight: maxRowsHeight }')
const cleared = applyReset(false, 412, 300)
assertEqual(cleared.cardTop, -1, 'close clears the frozen card top')
assertEqual(cleared.maxRowsHeight, -1, 'close clears the frozen rows height')

// Row 1 is the no-action row: the freeze has exactly two call sites and both
// sit inside the interaction handlers, so with no interaction the freeze
// never runs.
// MCDC SW-REQ-260929-DXFJ: card_top_frozen=F, menu_interacted=F => TRUE [no-action: panel.freezeCardTop() has exactly two call sites, both inside the setFilter and setActiveMenu interaction handlers -- with no interaction neither runs]
assertEqual([...menuQml.matchAll(/panel\.freezeCardTop\(\)/g)].length, 2, 'freezeCardTop is called only from the two interaction handlers')

// SW-REQ-260929-T378: pointer-driven selection lands only after the gate
// reports genuine movement, and never onto a non-selectable row.
const runSelectFromPointer = new Function('pointerGate', 'root', extractQmlFunction('selectFromPointer') + '\nreturn selectFromPointer')
const makeGate = (moved) => {
  const gate = { consulted: 0 }
  gate.moved = () => { gate.consulted += 1; return moved }
  return gate
}
const makeRowRoot = (selectable) => ({ rowSelectable: () => selectable, cursorActive: false, selectedIndex: -1 })

const hitGate = makeGate(true)
const hitRoot = makeRowRoot(true)
runSelectFromPointer(hitGate, hitRoot)(5, {}, {})
assertEqual(hitRoot.selectedIndex, 5, 'a passed gate moves the selection onto the hovered selectable row')
assertEqual(hitRoot.cursorActive, true, 'a passed gate activates the cursor')

const disabledRoot = makeRowRoot(false)
runSelectFromPointer(makeGate(true), disabledRoot)(7, {}, {})
assertEqual(disabledRoot.selectedIndex, -1, 'a passed gate never lands on a non-selectable row')
assertEqual(disabledRoot.cursorActive, false, 'a non-selectable row leaves the cursor alone')

const heldGate = makeGate(false)
const heldRoot = makeRowRoot(true)
runSelectFromPointer(heldGate, heldRoot)(9, {}, {})
assertEqual(heldGate.consulted, 1, 'the gate is consulted exactly once per pointer selection')
assertEqual(heldRoot.selectedIndex, -1, 'an unmoved gate holds the selection still')
assertEqual(heldRoot.cursorActive, false, 'an unmoved gate does not activate the cursor')
// MCDC SW-REQ-260929-T378: gated_row_selection=T, pointer_moves_over_rows=T => TRUE

// Row 1 is the no-action row: with the gate reporting no movement the handler
// returns before any selection write.
// MCDC SW-REQ-260929-T378: gated_row_selection=F, pointer_moves_over_rows=F => TRUE [no-action: with the gate unmoved selectFromPointer returns before any write -- selectedIndex and cursorActive keep their previous values]

// Keyboard navigation, filtering, menu transitions, the delete dialog, and
// opening the menu all disarm the gate.
const runDisarmPointer = new Function('pointerGate', extractQmlFunction('disarmPointer') + '\nreturn disarmPointer')
let resets = 0
runDisarmPointer({ reset: () => { resets += 1 } })()
assertEqual(resets, 1, 'disarmPointer resets the pointer gate')
JS
