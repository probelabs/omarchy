#!/usr/bin/env node
// Upstream reproducer: an inline `//` comment tail empties the WHOLE menu.
//
// Run from the omarchy repo root with node alone (no other tooling):
//   node repro-jsonc-inline-comment.js
// or against an explicit copy:
//   node repro-jsonc-inline-comment.js /path/to/MenuModel.js
//
// Expected (correct) behavior: JSONC allows `//` comments. A comment tail on
// a content line (`{"a": ...} // note`) should be stripped like the full-line
// comments the parser already handles, leaving the document intact.
//
// Observed (bug): the comment stripper in stripJsonc is line-ANCHORED
// (/^\s*\/\/[^\n]*(\n|$)/gm), so an inline comment tail survives stripping,
// JSON.parse throws on it, and the catch in parseMenuJsonc silently returns
// an EMPTY item set. One trailing comment kills every row in the menu.
//
// Note: `//` inside a string literal is data and must stay verbatim — any
// fix must be string-aware (the same requirement the trailing-comma scanner
// already honors).

const path = require("node:path");
const m = require(path.resolve(
  process.argv[2] || "shell/plugins/menu/MenuModel.js"
));

const input = '{"a": {"label": "A"}} // note';
const rows = m.parseMenuJsonc(input);

console.log("input:  " + input);
console.log("output: " + JSON.stringify(rows));

// Contrast 1: the same document without the comment parses fine.
console.log(
  'contrast no-comment      -> ' +
    JSON.stringify(m.parseMenuJsonc('{"a": {"label": "A"}}').map(r => r.label))
);
// Contrast 2: a full-line comment IS handled today.
console.log(
  "contrast full-line comment -> " +
    JSON.stringify(
      m.parseMenuJsonc('// note\n{"a": {"label": "A"}}').map(r => r.label)
    )
);
// Guard case any fix must preserve: // inside a string literal is data.
console.log(
  "guard // in string literal   -> " +
    JSON.stringify(m.parseMenuJsonc('{"a": {"label": "A // B"}}').map(r => r.label))
);

if (rows.length === 0) {
  console.log(
    "\nBUG PRESENT: one inline comment tail emptied the whole menu (0 rows)"
  );
  process.exit(1);
}
console.log("\nOK: inline comment tail stripped, menu intact (" + rows.length + " row)");
