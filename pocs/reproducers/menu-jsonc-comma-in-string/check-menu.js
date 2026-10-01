// Reproducer: parse a menu JSONC file with the shipped MenuModel.js
// (from the scratchpad/omarchy-v2 recording session; originally staged ad hoc
// in a session dir, landed here 2026-10-01). The model path defaults to the
// repo-relative shipped file; override with MENU_MODEL=<path> for BEFORE-rev runs.
const M = require(process.env.MENU_MODEL || require("path").resolve(__dirname, "../../../shell/plugins/menu/MenuModel.js"))
const fs = require("fs")
const file = process.argv[2]
const rows = M.parseMenuJsonc(fs.readFileSync(file, "utf8"))
console.log(file + ": " + rows.length + " rows")
for (const r of rows)
  console.log("  id=" + r.id + "  label=" + r.label + (r.description ? "  desc=" + r.description : ""))
