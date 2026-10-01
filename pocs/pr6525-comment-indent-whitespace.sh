#!/bin/sh
# Reproduces: KI-MENU-JSONC-COMMENT-INDENT-WHITESPACE
# Green tripwire (pins the defect, exits 0 while it is present) for the
# regression omacom/omarchy#6525 introduces: a whole-line // comment indented
# with a JS whitespace character that JSON does not accept (VT, FF, no-break
# space, U+1680, the U+2000 spaces, line/paragraph separator, U+202F, U+205F,
# ideographic space, a byte-order mark) now empties the whole menu file. The
# old line-anchored regex ^\s*\/\/ removed that character with the comment;
# the PR's scanner drops the comment but keeps the character, and JSON.parse
# rejects it. Control: the same file indented with ASCII spaces parses.
# Input is the text Quickshell's FileView hands to the parser (checked live
# under Quickshell 0.3.1: a LEADING byte-order mark is dropped by FileView,
# every other character is kept), so the indentation here sits on the second
# line, not at the start of the file.
#   exit 0 = defect present (tripwire green), 1 = fixed, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node is required"; exit 2; }
MODEL="$ROOT/shell/plugins/menu/MenuModel.js" node --input-type=commonjs - <<'JS'
const m = require(process.env.MODEL)
const quiet = console.warn; console.warn = () => {}
const doc = ch => '{\n' + ch + ch + '// a comment line\n  "a": {"label": "A"},\n  "b": {"label": "B"}\n}\n'
const control = m.parseMenuJsonc(doc(' ')).length
if (control !== 2) { console.log('SETUP: control (ASCII-indented comment) parsed to ' + control + ' rows'); process.exit(2) }
console.log('ok: control: a comment line indented with ASCII spaces keeps both rows')
const chars = ['\u000b', '\u000c', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ',
  ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', '　', '﻿']
let present = 0
for (const ch of chars) {
  const rows = m.parseMenuJsonc(doc(ch)).length
  const name = 'U+' + ch.charCodeAt(0).toString(16).toUpperCase().padStart(4, '0')
  if (rows === 0) { console.log('SYMPTOM: a comment line indented with ' + name + ' empties the file (0 rows, base 2)'); present++ }
  else console.log('fixed: a comment line indented with ' + name + ' keeps ' + rows + ' rows')
}
console.warn = quiet
console.log(present + ' of ' + chars.length + ' JS whitespace characters outside JSON whitespace, indenting a comment line, empty the menu file')
process.exit(present === chars.length ? 0 : 1)
JS
