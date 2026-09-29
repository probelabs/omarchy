#!/bin/sh
# Reproducer for report cmulr8l6h0i461gw40vqqv64c (omacom/omarchy#13250).
# SW-REQ-260922-E4J2: trailing commas are stripped before JSON parsing "so the
# authored JSONC parses to its declared entries". A label whose text contains
# ", ]" or ", }" must come back verbatim; a real trailing comma (outside any
# string) must still be dropped.
# Exit 0 = correct, 1 = DEFECT (label rewritten), 2 = SETUP (node missing).
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
check("label containing ', ]' survives", JSON.stringify({ b: { label: "x, ]y" } }), ['b="x, ]y"'])
check("label containing ', }' survives", JSON.stringify({ b: { label: "a, }b" } }), ['b="a, }b"'])
check("control: trailing commas outside strings are still dropped", '{"a": {"label": "A",},}', ['a="A"'])
if (defects) { console.log("RESULT: " + defects + " case(s) violate the requirement"); process.exit(1) }
console.log("RESULT: all cases parse to the declared entries")
process.exit(0)
JS
