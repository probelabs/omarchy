#!/bin/sh
# Reproducer for report cmulr908f0k131gw4hy0pcx08 (omacom/omarchy#10340):
# "type `chro` in the root menu: Setup > Defaults > Browser > Chrome ranks above
# the installed Google Chrome app".
#
# It loads the shipped default menu (default/omarchy/omarchy-menu.jsonc) through
# MenuModel.parseMenuJsonc + mergeMenuSources, merges an installed "Google
# Chrome" desktop entry the way Menu.qml builds app rows (MenuModel.mergeAppRows),
# then ranks the root-menu search for "chro" with MenuModel.matchesQuery +
# MenuModel.searchScore and the ordering Menu.qml rebuildDisplay applies
# (current-menu rows, then drilldown rows, each sorted by score then path).
#
# Default mode asserts what SW-REQ-260922-SJ7P specifies: "Scores tier exact
# label, whole-word app name, label prefix, label substring, name text, then
# description. Menus and links promote by 2, apps demote by 5 within a tier."
# A label-prefix match ("Chrome") therefore outranks a label-substring match
# ("Google Chrome"): the reported order IS the specified order.
#   exit 0 = ranking follows SJ7P (the reported order), 1 = DEFECT (ranking
#   deviates from SJ7P), 2 = SETUP (node or product files missing).
# REPORT_ASSERT=reporter-expectation instead asserts the reporter's requested
# policy (an installed app matching the query ranks first): exit 0 when it
# holds, 1 with NOT-MET when it does not.
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node (>= 18) is required and was not found on PATH"; exit 2; }
MODEL="$ROOT/shell/plugins/menu/MenuModel.js"
MENU="$ROOT/default/omarchy/omarchy-menu.jsonc"
for f in "$MODEL" "$MENU"; do [ -f "$f" ] || { echo "SETUP: $f is missing"; exit 2; }; done
export MODEL MENU
REPORT_ASSERT=${REPORT_ASSERT:-requirement} node --input-type=commonjs - <<'JS'
const fs = require("fs")
let m
try { m = require(process.env.MODEL) } catch (e) { console.log("SETUP: cannot load MenuModel.js: " + e.message); process.exit(2) }
const defaults = m.parseMenuJsonc(fs.readFileSync(process.env.MENU, "utf8"))
if (!defaults.length) { console.log("SETUP: the default menu parsed to no rows"); process.exit(2) }
let merged = m.mergeMenuSources(defaults, [])
const app = { id: "apps.google-chrome", parent: "apps", kind: "app", icon: "", appIcon: "google-chrome", appId: "google-chrome",
  label: "Google Chrome", title: "", target: "", description: "Access the Internet", action: "", provider: "", aliases: [],
  when: "", checked: "", disabled: "", order: 0 }
merged = m.mergeAppRows(merged.items, merged.itemOrder, [app])
const items = merged.items, order = merged.itemOrder
const SETTING = "setup.default.browser.chrome"
if (!items[SETTING]) { console.log("SETUP: the default menu has no " + SETTING + " entry"); process.exit(2) }

// Guards are runtime shell checks; model a system with Google Chrome installed:
// rows disabled by "omarchy-pkg-present google-chrome" are disabled, all other
// rows are visible and enabled.
const disabled = e => /omarchy-pkg-present google-chrome/.test(String(e.disabled || ""))
const query = "chro", active = "root"
const current = [], drill = []
for (const id of order) {
  const e = items[id]
  if (!e || id === "root") continue
  if (!m.isDescendantOf(items, id, active)) continue
  if (!m.matchesQuery(e, query, !disabled(e))) continue
  const row = { id, kind: e.kind, path: m.pathFor(items, id), score: m.searchScore(items, e, query) }
  ;(e.parent === active ? current : drill).push(row)
}
const sort = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path)
current.sort(sort); drill.sort(sort)
const rows = current.concat(drill)
console.log("search '" + query + "' from the root menu, top rows:")
rows.slice(0, 6).forEach((r, i) => console.log("  " + (i + 1) + ". [" + r.kind + "] " + r.path + " (score " + r.score + ")"))
const iApp = rows.findIndex(r => r.id === app.id), iSet = rows.findIndex(r => r.id === SETTING)
if (iApp < 0 || iSet < 0) { console.log("SETUP: expected rows not in the result (app " + iApp + ", setting " + iSet + ")"); process.exit(2) }

if (process.env.REPORT_ASSERT === "reporter-expectation") {
  if (rows[0].kind === "app") { console.log("MET: the installed app ranks first, as the reporter requests"); process.exit(0) }
  console.log("NOT-MET: first row is [" + rows[0].kind + "] " + rows[0].path + "; the installed app is row " + (iApp + 1)); process.exit(1)
}
// SJ7P tier ladder: label prefix (setting "Chrome") is a better tier than label
// substring (app "Google Chrome"); the app shift stays within its tier.
if (iSet < iApp) {
  console.log("ok: '" + items[SETTING].label + "' (label-prefix tier) ranks above the app 'Google Chrome' (label-substring tier), as SW-REQ-260922-SJ7P specifies")
  process.exit(0)
}
console.log("DEFECT: the app 'Google Chrome' (label-substring tier) ranks above '" + items[SETTING].label + "' (label-prefix tier): the order deviates from the SW-REQ-260922-SJ7P tier ladder")
process.exit(1)
JS
