#!/bin/sh
# Reproduces: KI-MENU-JSONC-UNICODE-WHITESPACE
# Red reproducer: a menu JSONC file that carries a JS whitespace character JSON
# does not accept (VT, FF, no-break space, the U+2000 spaces, line/paragraph
# separator, ideographic space, a byte-order mark after the start) between
# tokens must still parse to its entries. Asserts the CORRECT behaviour, so it
# exits 1 while the defect is present. Control: the same file with an ASCII
# space parses. Input is the text Quickshell's FileView hands to the parser
# (checked live under Quickshell 0.3.1: a leading BOM is dropped by FileView,
# every other character is kept).
#   exit 0 = correct, 1 = DEFECT, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node is required"; exit 2; }
MODEL="$ROOT/shell/plugins/menu/MenuModel.js" node --input-type=commonjs - <<'JS'
const m = require(process.env.MODEL)
const doc = ch => '{\n  "a":' + ch + '{"label": "A"},\n  "b": {"label": "B"}\n}\n'
const control = m.parseMenuJsonc(doc(' ')).length
if (control !== 2) { console.log('SETUP: control (ASCII space) parsed to ' + control + ' rows'); process.exit(2) }
console.log('ok: control: ASCII space between tokens keeps both rows')
const chars = ['\u000b', '\u000c', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
  ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', '　', '﻿']
let bad = 0
for (const ch of chars) {
  const rows = m.parseMenuJsonc(doc(ch)).length
  const name = 'U+' + ch.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')
  if (rows === 2) console.log('ok: ' + name + ' between tokens keeps both rows')
  else { console.log('DEFECT: ' + name + ' between tokens empties the file (' + rows + ' rows, expected 2)'); bad++ }
}
console.log(bad + ' of ' + chars.length + ' JS whitespace characters outside JSON whitespace empty the menu file')
process.exit(bad ? 1 : 0)
JS
