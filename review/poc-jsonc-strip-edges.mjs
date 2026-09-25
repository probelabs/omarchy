// PoC for CRS-0025/C01 + CRS-0025/C02 (pre-existing, baseline MenuModel.js)
// Run: node review/poc-jsonc-strip-edges.mjs
import { createRequire } from "module";
const require = createRequire(import.meta.url);
const m = require("../shell/plugins/menu/MenuModel.js");

// C01: comma + ws + ]/} INSIDE a string value is stripped as if it were a
// trailing comma -> silent single-character corruption of the label.
const corrupted = m.stripJsonc(JSON.stringify({ a: { label: "x, ]y" } }));
console.log("C01 stripped:", corrupted);
console.log("C01 label now:", m.parseMenuJsonc(corrupted)[0].label); // "x ]y" (comma lost)

// C02: an inline trailing comment (legal JSONC) after content makes the whole
// parse fail -> parseMenuJsonc returns [] -> the entire menu silently empties.
const emptied = m.parseMenuJsonc('{"a": {"label": "x"} // trailing comment\n}');
console.log("C02 inline-comment parse length:", emptied.length); // 0
