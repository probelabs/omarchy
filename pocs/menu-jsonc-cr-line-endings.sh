#!/bin/sh
# Reproduces: KI-MENU-JSONC-CR-LINE-ENDINGS
# Red reproducer: a menu JSONC file saved with CR-only line endings must parse
# to its entries when it carries a whole-line // comment. Asserts the CORRECT
# behaviour, so it exits 1 while the defect is present. Controls: the same
# file with LF and with CRLF endings, and the CR-only file without a comment.
# Input is the text Quickshell's FileView hands to the parser (checked live
# under Quickshell 0.3.1: CR is kept as read).
#   exit 0 = correct, 1 = DEFECT, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node is required"; exit 2; }
MODEL="$ROOT/shell/plugins/menu/MenuModel.js" node --input-type=commonjs - <<'JS'
const m = require(process.env.MODEL)
const lf = '{\n  // shortcuts\n  "a": {"label": "A"},\n  "b": {"label": "B"}\n}\n'
const rows = t => m.parseMenuJsonc(t).length
for (const [name, text] of [['LF', lf], ['CRLF', lf.replace(/\n/g, '\r\n')], ['CR-only without comment', lf.replace('  // shortcuts\n', '').replace(/\n/g, '\r')]]) {
  if (rows(text) !== 2) { console.log('SETUP: control ' + name + ' parsed to ' + rows(text) + ' rows'); process.exit(2) }
  console.log('ok: control: ' + name + ' keeps both rows')
}
const cr = rows(lf.replace(/\n/g, '\r'))
if (cr === 2) { console.log('ok: CR-only file with a comment keeps both rows'); process.exit(0) }
console.log('DEFECT: CR-only file with a whole-line comment parses to ' + cr + ' rows (expected 2): the comment pass runs to the end of the file')
process.exit(1)
JS
