#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-261002-DK0D
#mcdc:ignore:defensive SW-REQ-261002-DK0D: menu_untouched_on_root=T, pending_route_opened=F, pending_route_resolves=T, route_fell_back_before_load=T => FALSE -- rebuildItemsFromSources calls openRoute(pending) whenever the pending route resolves and the open menu still shows root with nothing typed; a resolved pending route left unopened needs that call removed (the 821ae589 behaviour) [reviewed: REVIEW-261002-NS9R]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The shell hands a summon queued during startup to the menu as soon as the
# plugin loads, before either FileView has read its JSONC file. These checks
# run Menu.qml's own open path and FileView handlers in a vm context and load
# the two files in either order around the summon.
run_node_test <<'JS'
const fs = require('fs')
const vm = require('vm')

const MenuModel = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const defaultJsonc = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')
const stockUserJsonc = fs.readFileSync(path.join(root, 'config/omarchy/extensions/omarchy-menu.jsonc'), 'utf8')
const personalJsonc = '{ "personal": {"label":"Personal"}, "personal.notes": {"label":"Notes","action":"notes"} }'

const qmlFunctions = ['open', 'close', 'openRoute', 'resolveRoute', 'item', 'openExistingMenu', 'openDmenu', 'cancel',
  'parseMenuJsonc', 'rebuildItemsFromSources'].map(name => {
  const fn = menuQml.match(new RegExp(`  function ${name}\\([^]*?\\n  }`))
  if (!fn) fail(`Menu.qml provides ${name}`)
  return fn[0]
})

function handler(fileId, signal) {
  const found = menuQml.match(new RegExp(`id: ${fileId}\\n[^]*?${signal}: (\\{[^\\n]*\\})`))
  if (!found) fail(`Menu.qml ${fileId} handles ${signal}`)
  return found[1]
}
const defaultLoaded = handler('defaultMenuFile', 'onLoaded')
const userLoaded = handler('userMenuFile', 'onLoaded')
const userLoadFailed = handler('userMenuFile', 'onLoadFailed')
const pendingDefault = menuQml.match(/property string pendingInitialMenu: "([^"]*)"/)

// A freshly loaded plugin: no rows yet, nothing open. Display, guards and
// providers are QML-side effects outside this path, so they are no-ops here.
function startMenu() {
  const menu = vm.createContext({
    MenuModel,
    Qt: { callLater() {} },
    keyCatcher: { forceActiveFocus() {} },
    appLibrary: null,
    pendingInitialMenu: pendingDefault ? pendingDefault[1] : fail('Menu.qml declares pendingInitialMenu'),
    defaultMenuItems: [],
    userMenuItems: [],
    items: ({}),
    itemOrder: [],
    opened: false,
    mode: 'menu',
    rowsLoaded: false,
    activeMenu: 'root',
    filterText: '',
    selectedIndex: 0,
    cursorActive: false,
    requestSerial: 0,
    requestActive: false,
    selectionFile: '',
    doneFile: '',
    navStack: [],
    providerRevision: 0,
    providersLoaded: ({}),
    providerQueue: [],
    actions: [],
    evaluateGuards() {},
    rebuildDisplay() {},
    loadProvidersForSearch() {},
    loadProviderForMenu() {},
    invalidateVolatileProvider() {},
    disarmPointer() {},
    finishRequest() { menu.opened = false },
    runAction(action) { menu.actions.push(action) }
  })
  menu.root = menu
  Object.defineProperty(menu, 'dmenuActive', { get: () => menu.mode === 'select' || menu.mode === 'input' })
  for (const fn of qmlFunctions) vm.runInContext(fn, menu)
  return menu
}

function load(menu, signal, raw) {
  menu.text = () => raw
  vm.runInContext(signal, menu)
}

const summon = (menu, payload) => menu.open(JSON.stringify(payload))
const loadDefault = menu => load(menu, defaultLoaded, defaultJsonc)
const loadUser = (menu, raw) => load(menu, userLoaded, raw)
const noUserFile = menu => load(menu, userLoadFailed, '')

let menu = startMenu()
summon(menu, { menu: 'system' })
loadDefault(menu)
noUserFile(menu)
assertEqual(menu.activeMenu, 'system', 'a route summoned before the default menu file loads opens once it does')
// Verifies: SW-REQ-261002-DK0D
// Reproduces: KI-MENU-PENDING-INITIAL-MENU-DEAD
// MCDC SW-REQ-261002-DK0D: menu_untouched_on_root=T, pending_route_opened=T, pending_route_resolves=T, route_fell_back_before_load=T => TRUE
menu.activeMenu = 'style'
loadDefault(menu)
assertEqual(menu.activeMenu, 'style', 'a replayed route is not replayed again by a later reload')

menu = startMenu()
summon(menu, { menu: 'system' })
noUserFile(menu)
assertEqual(menu.activeMenu, 'root', 'with only the missing user file read, the route has nothing to resolve against yet')
loadDefault(menu)
assertEqual(menu.activeMenu, 'system', 'a route summoned before startup opens when the default file loads after the user file fails')

menu = startMenu()
summon(menu, { menu: 'power-menu' })
loadUser(menu, stockUserJsonc)
loadDefault(menu)
assertEqual(menu.activeMenu, 'system', 'an alias summoned before startup opens when the default file loads after the stock user file')

menu = startMenu()
summon(menu, { menu: 'personal' })
loadDefault(menu)
assertEqual(menu.activeMenu, 'root', 'a user-defined menu cannot resolve from the default file alone')
loadUser(menu, personalJsonc)
assertEqual(menu.activeMenu, 'personal', 'a user-defined menu summoned before startup opens when the user file loads after the default file')

menu = startMenu()
summon(menu, { menu: 'personal' })
loadUser(menu, personalJsonc)
loadDefault(menu)
assertEqual(menu.activeMenu, 'personal', 'a user-defined menu summoned before startup opens when the user file loads first')

menu = startMenu()
summon(menu, { menu: 'reminder-set' })
loadDefault(menu)
noUserFile(menu)
assertDeepEqual(menu.actions, ['omarchy-reminder -i'], 'an action alias summoned before startup runs its action once the file loads')
assertEqual(menu.opened, false, 'running a replayed action alias closes the menu')

menu = startMenu()
summon(menu, {})
const opens = menu.requestSerial
loadDefault(menu)
noUserFile(menu)
assertEqual(menu.activeMenu, 'root', 'a summon without a route opens root')
assertEqual(menu.requestSerial, opens, 'a summon without a route is not reopened when the files load')
// Verifies: SW-REQ-261002-DK0D
// MCDC SW-REQ-261002-DK0D: menu_untouched_on_root=T, pending_route_opened=F, pending_route_resolves=T, route_fell_back_before_load=F => TRUE [no-action: root resolves as soon as it is summoned, so nothing falls back and the loads do not reopen the menu]

menu = startMenu()
summon(menu, { menu: 'no-such-menu' })
loadDefault(menu)
noUserFile(menu)
const missingOpens = menu.requestSerial
assertEqual(menu.activeMenu, 'root', 'a route to a missing menu still falls back to root')
loadDefault(menu)
assertEqual(menu.requestSerial, missingOpens, 'a route to a missing menu is not reopened by a later reload')
// Verifies: SW-REQ-261002-DK0D
// MCDC SW-REQ-261002-DK0D: menu_untouched_on_root=T, pending_route_opened=F, pending_route_resolves=F, route_fell_back_before_load=T => TRUE [no-action: no load defines the missing id, so the pending route never resolves and the menu stays on root]

menu = startMenu()
summon(menu, { menu: 'personal' })
loadDefault(menu)
menu.activeMenu = 'style'
loadUser(menu, personalJsonc)
assertEqual(menu.activeMenu, 'style', 'a pending route does not pull the user out of a menu they opened')
// Verifies: SW-REQ-261002-DK0D
// MCDC SW-REQ-261002-DK0D: menu_untouched_on_root=F, pending_route_opened=F, pending_route_resolves=T, route_fell_back_before_load=T => TRUE [no-action: the user opened another menu before the user file loaded, so the resolved pending route does not move them]

menu = startMenu()
summon(menu, { menu: 'personal' })
loadDefault(menu)
menu.filterText = 'not'
loadUser(menu, personalJsonc)
assertEqual(menu.activeMenu, 'root', 'a pending route does not replace what the user typed')

menu = startMenu()
summon(menu, { menu: 'system' })
menu.close()
loadDefault(menu)
noUserFile(menu)
assertEqual(menu.opened, false, 'a route summoned and dismissed before startup stays closed')

menu = startMenu()
summon(menu, { menu: 'system' })
summon(menu, { mode: 'select', prompt: 'Pick', options: ['a', 'b'] })
loadDefault(menu)
noUserFile(menu)
assertEqual(menu.mode, 'select', 'a select prompt that replaced an early route summon is not replaced by it')

menu = startMenu()
loadDefault(menu)
noUserFile(menu)
summon(menu, { menu: 'system' })
assertEqual(menu.activeMenu, 'system', 'a summon after startup opens its route directly')
menu.activeMenu = 'style'
loadDefault(menu)
assertEqual(menu.activeMenu, 'style', 'a later reload leaves the menu where the user navigated')
JS
