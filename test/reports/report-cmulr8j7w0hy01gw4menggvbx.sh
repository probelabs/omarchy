#!/bin/sh
# Reproducer for report cmulr8j7w0hy01gw4menggvbx (omacom/omarchy#13493).
# SW-REQ-260922-E4J2 (FRETish): "when jsonc_has_comments_or_commas the
# menu_model shall eventually satisfy items_parsed", where
# jsonc_has_comments_or_commas = "The JSONC source carries // comments or
# trailing commas" and items_parsed = "The item set parses to the declared
# entries". An inline // comment tail must not empty the menu; // inside a
# string is data and must stay verbatim.
# Exit 0 = correct, 1 = DEFECT (entries lost), 2 = SETUP (node missing).
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
check("inline comment tail after the root object", '{"a": {"label": "A"}} // note', ['a="A"'])
check("inline comment tail on an entry line", '{\n  "a": {"label": "A"}, // first\n  "b": {"label": "B"}\n}', ['a="A"', 'b="B"'])
check("control: full-line comment", '// note\n{"a": {"label": "A"}}', ['a="A"'])
check("control: // inside a string is data", '{"a": {"label": "A // B"}}', ['a="A // B"'])
check("control: trailing comma, whole-line comment, closer keeps the row", '{\n  "a": {"label": "A"},\n  // note\n}', ['a="A"'])
if (defects) { console.log("RESULT: " + defects + " case(s) violate the requirement"); process.exit(1) }
console.log("RESULT: all cases parse to the declared entries")
process.exit(0)
JS
