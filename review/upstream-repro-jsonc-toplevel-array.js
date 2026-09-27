#!/usr/bin/env node
// Upstream reproducer: a top-level JSON ARRAY of objects leaks phantom menu rows.
//
// Run from the omarchy repo root with node alone (no other tooling):
//   node repro-jsonc-toplevel-array.js
// or against an explicit copy:
//   node repro-jsonc-toplevel-array.js /path/to/MenuModel.js
//
// Expected (correct) behavior: a top-level array is not an object map of menu
// entries, so parseMenuJsonc must return an empty item set — exactly what it
// already does for every other non-object root (null, 42, "str", {} all yield
// zero rows).
//
// Observed (bug): `typeof [] === "object"` passes the guard at
// parseMenuJsonc ("typeof parsed !== 'object' || parsed === null"), the
// for..in loop then iterates ARRAY INDICES as entry ids, and each object
// element becomes a phantom menu row with id "0", "1", ... parented to root.
// The menu renders rows the user never wrote.

const path = require("node:path");
const m = require(path.resolve(
  process.argv[2] || "shell/plugins/menu/MenuModel.js"
));

const input = '[{"label":"should-not-appear"},{"label":"ghost-2"}]';
const rows = m.parseMenuJsonc(input);

console.log("input:  " + input);
console.log("output: " + JSON.stringify(rows));

const phantom =
  rows.length === 2 && rows[0].id === "0" && rows[0].parent === "root";

// Contrast: every other non-object root correctly yields zero rows.
for (const s of ["{}", "null", "42", '"str"']) {
  console.log(
    "contrast " + s + " -> " + JSON.stringify(m.parseMenuJsonc(s))
  );
}

if (phantom) {
  console.log(
    "\nBUG PRESENT: top-level array produced " + rows.length +
      " phantom row(s) with numeric string ids parented to root"
  );
  process.exit(1);
}
console.log("\nOK: top-level array yields an empty item set");
