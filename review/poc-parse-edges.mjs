// PoC for DEFECT-review surviving claims (fix/jsonc-trailing-comma-in-strings campaign,
// CRS-0017/C03 = CRS-0019/C01 top-level array phantom rows; CRS-0017/C01 = CRS-0019/C02 =
// CRS-0020/C01 inline comments not stripped). Both pre-date the fix branch (quattro behaves
// identically; the delta touched only stripJsonc's comma handling). Run: node review/poc-parse-edges.mjs
import { createRequire } from "node:module";
const m = createRequire(import.meta.url)("../shell/plugins/menu/MenuModel.js");

// C-ARRAY: a top-level JSON array of objects is non-object JSON per 3T3F's contract
// ("non-object JSON ... yield an empty or skipped item set"), yet yields a phantom
// menu item with id "0" because typeof [] === "object" passes the guard and for..in
// iterates array indices.
const phantom = m.parseMenuJsonc('[{"label":"should-not-appear"}]');
console.log("top-level array of objects ->", JSON.stringify(phantom));
console.log("  phantom row present:", phantom.length === 1 && phantom[0].id === "0" && phantom[0].parent === "root");

// C-INLINE-COMMENT: the comment stripper is line-anchored (^\s*//), so a trailing
// inline comment survives stripping, JSON.parse throws, and the WHOLE menu silently
// goes empty via the 3T3F catch instead of ignoring the comment.
const withInline = m.parseMenuJsonc('{"a": {"label": "A"}} // note');
console.log("inline trailing comment   ->", JSON.stringify(withInline), "(whole menu empty)");
