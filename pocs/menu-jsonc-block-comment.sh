#!/bin/sh
# Reproduces: KI-MENU-JSONC-STRIP-GAPS
# Red reproducer: a /* */ block comment in menu JSONC must not drop the file.
# Asserts the CORRECT behaviour (the entries survive), so it exits 1 while the
# defect is present. Control: the same entry with a whole-line // comment.
#   exit 0 = correct, 1 = DEFECT, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node is required"; exit 2; }
MODEL="$ROOT/shell/plugins/menu/MenuModel.js" node --input-type=commonjs - <<'JS'
const m = require(process.env.MODEL)
const control = m.parseMenuJsonc('{\n  // note\n  "a": {"label": "A"}\n}').length
if (control !== 1) { console.log("SETUP: control (whole-line comment) parsed to " + control + " rows"); process.exit(2) }
console.log("ok: control: whole-line // comment keeps the row")
const rows = m.parseMenuJsonc('{ /* note */ "a": {"label": "A"} }').length
if (rows === 1) { console.log("ok: block comment is stripped and the row survives"); process.exit(0) }
console.log("DEFECT: block comment left in the text: the file parses to " + rows + " rows (expected 1)")
process.exit(1)
JS
