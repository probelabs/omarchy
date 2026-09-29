#!/bin/sh
# Reproducer for report cmulr8j7z0hy31gw4pne8v6u4 (omacom/omarchy#13492).
# SW-REQ-260922-3T3F: "Unparseable input (after stripping), non-object JSON, and
# non-object entries yield an empty or skipped item set". A menu.jsonc whose
# root is a JSON array is non-object JSON and must yield no rows.
# Exit 0 = correct, 1 = DEFECT (phantom rows), 2 = SETUP (node missing).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node (>= 18) is required and was not found on PATH"; exit 2; }
MODEL="$ROOT/shell/plugins/menu/MenuModel.js"
[ -f "$MODEL" ] || { echo "SETUP: $MODEL is missing"; exit 2; }
export MODEL
node --input-type=commonjs - <<'JS'
let m
try { m = require(process.env.MODEL) } catch (e) { console.log("SETUP: cannot load MenuModel.js: " + e.message); process.exit(2) }
if (typeof m.parseMenuJsonc !== "function") { console.log("SETUP: MenuModel.js exports no parseMenuJsonc"); process.exit(2) }
let defects = 0
function parse(src) {
  try { return m.parseMenuJsonc(src) } catch (e) { return { thrown: e.message } }
}
function check(name, src, want) {
  const rows = parse(src)
  const got = Array.isArray(rows) ? rows.map(r => r.id + "=" + JSON.stringify(r.label)) : rows
  const ok = JSON.stringify(got) === JSON.stringify(want)
  console.log((ok ? "ok: " : "DEFECT: ") + name + " -- input " + JSON.stringify(src) + " -> rows " + JSON.stringify(got) + (ok ? "" : " (expected " + JSON.stringify(want) + ")"))
  if (!ok) defects++
}
check("top-level array root yields no rows", '[{"label":"should-not-appear"},{"label":"ghost-2"}]', [])
check("control: null root yields no rows", 'null', [])
check("control: number root yields no rows", '42', [])
check("control: object root still parses", '{"a": {"label": "A"}}', ['a="A"'])
if (defects) { console.log("RESULT: " + defects + " case(s) violate the requirement"); process.exit(1) }
console.log("RESULT: all cases parse to the declared entries")
process.exit(0)
JS
