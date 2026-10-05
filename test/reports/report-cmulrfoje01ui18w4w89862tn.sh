#!/bin/sh
# Reproducer for report cmulrfoje01ui18w4w89862tn (omacom/omarchy#7630):
# "Search ranks Remove > Development > Rust above the RustDesk app - Enter runs
# the removal".
#
# It loads the shipped default menu (default/omarchy/omarchy-menu.jsonc) through
# MenuModel.parseMenuJsonc + mergeMenuSources, merges an installed "RustDesk"
# desktop entry the way Menu.qml builds app rows (MenuModel.mergeAppRows), then
# ranks the root-menu search for "rust" with MenuModel.matchesQuery +
# MenuModel.searchScore and the ordering Menu.qml rebuildDisplay applies
# (current-menu rows, then drilldown rows, each sorted by score then path).
# Menu.qml selects row 0 after a query change and Enter activates the selected
# row, so row 0 is what Enter runs. Search skips hidden and disabled rows
# (Menu.qml matchesQuery). Guards are runtime shell checks; the model is a
# system with ~/.rustup present and RustDesk installed: rows whose guard tests
# ~/.rustup follow it (remove.development.rust visible, install.development.rust
# disabled), every other row is visible and enabled.
#   exit 1 + "AS-REPORTED:"     a destructive remove/uninstall row is row 0 (the Enter target)
#   exit 0 + "NOT-AS-REPORTED:" row 0 is not a destructive row
#   exit 2 + "SETUP:"           node or the product files are missing
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node (>= 18) is required and was not found on PATH"; exit 2; }
MODEL="$ROOT/shell/plugins/menu/MenuModel.js"
MENU="$ROOT/default/omarchy/omarchy-menu.jsonc"
for f in "$MODEL" "$MENU"; do [ -f "$f" ] || { echo "SETUP: $f is missing"; exit 2; }; done
export MODEL MENU
node --input-type=commonjs - <<'JS'
const fs = require("fs")
let m
try { m = require(process.env.MODEL) } catch (e) { console.log("SETUP: cannot load MenuModel.js: " + e.message); process.exit(2) }
const defaults = m.parseMenuJsonc(fs.readFileSync(process.env.MENU, "utf8"))
if (!defaults.length) { console.log("SETUP: the default menu parsed to no rows"); process.exit(2) }
let merged = m.mergeMenuSources(defaults, [])
const app = { id: "apps.rustdesk", parent: "apps", kind: "app", icon: "", appIcon: "rustdesk", appId: "rustdesk",
  label: "RustDesk", title: "", target: "", description: "Remote desktop", action: "", provider: "", aliases: [],
  when: "", checked: "", disabled: "", order: 0 }
merged = m.mergeAppRows(merged.items, merged.itemOrder, [app])
const items = merged.items, order = merged.itemOrder
const REMOVE = "remove.development.rust"
if (!items[REMOVE]) { console.log("SETUP: the default menu has no " + REMOVE + " entry"); process.exit(2) }
const rustup = e => /\.rustup/.test(String(e.disabled || ""))
const query = "rust", active = "root"
const current = [], drill = []
for (const id of order) {
  const e = items[id]
  if (!e || id === "root") continue
  if (!m.isDescendantOf(items, id, active)) continue
  if (!m.matchesQuery(e, query, !rustup(e))) continue
  const row = { id, kind: e.kind, path: m.pathFor(items, id), score: m.searchScore(items, e, query), action: e.action || "" }
  ;(e.parent === active ? current : drill).push(row)
}
const sort = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path)
current.sort(sort); drill.sort(sort)
const rows = current.concat(drill)
console.log("search '" + query + "' from the root menu, top rows (row 1 is the Enter target):")
rows.slice(0, 6).forEach((r, i) => console.log("  " + (i + 1) + ". [" + r.kind + "] " + r.path + " (score " + r.score + ")" + (r.action ? " -> " + r.action : "")))
const iApp = rows.findIndex(r => r.id === app.id), iRem = rows.findIndex(r => r.id === REMOVE)
if (iApp < 0 || iRem < 0) { console.log("SETUP: expected rows not in the result (app " + iApp + ", remove " + iRem + ")"); process.exit(2) }
const destructive = r => /^(remove|uninstall)\b|\.remove\.|^remove\./.test(r.id) || /omarchy-(remove|pkg-drop)|uninstall/.test(r.action)
if (destructive(rows[0])) {
  console.log("AS-REPORTED: row 1 (the Enter target) is the destructive row [" + rows[0].kind + "] " + rows[0].path + " (" + rows[0].action + "); the RustDesk app is row " + (iApp + 1))
  process.exit(1)
}
console.log("NOT-AS-REPORTED: row 1 is [" + rows[0].kind + "] " + rows[0].path + "; the remove row is row " + (iRem + 1))
process.exit(0)
JS
