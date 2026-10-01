// Reproducer: inside Style, search "font", open the Font row, press Back.
// Drives the shipped code: MenuModel.js search + setActiveMenu/goBack/activateIndex
// extracted verbatim from Menu.qml (same extraction the menu test suite uses).
// (written for the evidence-clip recording session, landed here 2026-10-01).
// Paths resolve repo-relative; the menu
// fixture is the copy recorded at the clip's revs, override with MENU_DATA=<file>.
const fs = require("fs")
const vm = require("vm")
const path = require("path")
const REPO = path.resolve(__dirname, "../../..")
const plugin = (...p) => path.join(REPO, "shell", "plugins", "menu", ...p)
const M = require(plugin("MenuModel.js"))

const parsed = M.parseMenuJsonc(fs.readFileSync(process.env.MENU_DATA || path.join(__dirname, "omarchy-menu-default.jsonc"), "utf8"))
const merged = M.mergeMenuSources(parsed, [])
const byId = merged.items
const menu = merged.itemOrder.map(id => byId[id])
const toRow = e => ({ itemId: e.id, label: e.label, kind: e.kind, target: e.target })

const rowsOf = parent => menu.filter(e => e.parent === parent).map(toRow)
const searchResults = q =>
  menu.filter(e => M.matchesQuery(e, q, true))
      .sort((a, b) => (M.searchScore(byId, b, q) || 0) - (M.searchScore(byId, a, q) || 0))
      .map(toRow)

let visible = [], view = "menu", results = []
const root = {
  activeMenu: "root", navStack: [], selectedIndex: 0, filterText: "", cursorActive: true,
  deleteConfirmOpen: false, dmenuActive: false,
  item(id) { return byId[id] || (id === "root" ? { parent: "" } : null) },
  rowSelectable(i) { return i >= 0 && i < visible.length },
  rebuildDisplay() {
    visible = view === "search" ? results : rowsOf(this.activeMenu)
    if (this.selectedIndex >= visible.length) this.selectedIndex = visible.length - 1
  },
  disarmPointer() {}, invalidateVolatileProvider() {}, loadProviderForMenu() {},
}

const qml = fs.readFileSync(plugin("Menu.qml"), "utf8")
const pick = name => qml.match(new RegExp("  function " + name + "\\([\\s\\S]*?\\n  \\}\\n"))[0]
const nav = vm.runInNewContext(
  "(function(){" + pick("setActiveMenu") + pick("goBack") + pick("activateIndex") +
  "return {setActiveMenu: setActiveMenu, goBack: goBack, activateIndex: activateIndex}})()",
  { root: root, displayModel: { get count() { return visible.length }, get(i) { return visible[i] } },
    panel: { freezeCardTop() {} }, pointerGate: { allowInitialSample() {} } }
)
root.setActiveMenu = nav.setActiveMenu
root.goBack = nav.goBack
root.activateIndex = nav.activateIndex

visible = rowsOf("root")
root.selectedIndex = visible.findIndex(r => r.itemId === "style")
nav.setActiveMenu("style", true)
console.log("open Style; rows: " + visible.map(r => r.itemId).join(", "))

results = searchResults("font"); view = "search"
root.rebuildDisplay()
root.selectedIndex = results.findIndex(r => r.itemId === "style.font")
for (const r of results) console.log("  result: " + r.itemId + " (" + r.label + ")")
console.log("search font -> " + results.length + " result: " + results[0].itemId + " (" + results[0].label + ")")

nav.activateIndex(root.selectedIndex)
console.log("Enter -> open " + root.activeMenu)

view = "menu"; results = []
nav.goBack()
const row = visible[root.selectedIndex]
console.log("Back -> cursor row " + root.selectedIndex + ": " + row.itemId + " (" + row.label + ")")
