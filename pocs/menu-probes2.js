// Probe round 2: refined triggers for F4, F12, F15e, F16.
const M = require(process.argv[2]);
function t(key, fn) {
  try {
    const r = fn();
    console.log(key + ": " + (r ? "REAL  -- " : "REFUTED") + (typeof r === "string" ? " -- " + r : ""));
  } catch (e) {
    console.log(key + ": THREW  -- " + e.message);
  }
}
const { execSync } = require("child_process");

// F4b: pure-CR line endings: // eats to EOF
t("F4b.cr-only-file-eaten", () => {
  const out = M.stripJsonc('{\r"a": 1//c\r,\r"b": 2}');
  return out.indexOf('"b"') < 0;
});

// F12b: dropping a provider row shifts kept rows' indexes; .order stays stale
t("F12b.swapProviderRows-stale-after-drop", () => {
  const items = {
    root: { id: "root", kind: "menu", order: 0 },
    p1: { id: "p1", kind: "menu", order: 1, parent: "root", providerMenu: "m1" },
    s1: { id: "s1", kind: "menu", order: 2, parent: "root" }
  };
  const r = M.swapProviderRows(items, ["root", "p1", "s1"], "m1", [{ id: "p2", kind: "menu", label: "P2", parent: "root" }]);
  return r.itemOrder.indexOf("s1") !== r.items.s1.order;
});

// F15e2: term1 matches the label, term2 only the description -> matchesQuery
// accepts but searchScore lands on the unmatched baseline (the score of a row
// that matches nothing: 80 tier minus the menu-row nudge)
t("F15e2.crossfield-collapses-to-unmatched-baseline", () => {
  const e = { id: "x", label: "alpha", description: "beta", parent: "root", kind: "menu", order: 0 };
  const none = { id: "y", label: "gamma", description: "delta", parent: "root", kind: "menu", order: 0 };
  const accepted = M.matchesQuery(e, "alpha beta", true);
  const score = M.searchScore({ x: e }, e, "alpha beta");
  return accepted && score === M.searchScore({ y: none }, none, "alpha beta");
});

// F16a2: unquoted id interpolation via the exported guardScript
t("F16a2.guardScript-id-unquoted", () => {
  const script = M.guardScript([{ id: "my;id", tag: "w", expression: "true" }]);
  return script.indexOf("echo my;id:w:1") >= 0;
});

// F16b2: one broken expression kills the whole batch under bash -n
t("F16b2.guardScript-syntax-abort", () => {
  const script = M.guardScript([
    { id: "bad", tag: "w", expression: "}" },
    { id: "ok", tag: "w", expression: "true" }
  ]);
  try { execSync("/bin/bash -n", { input: script, stdio: ["pipe", "pipe", "pipe"] }); return false; }
  catch (e) { return true; }
});

// F16c2: boolean expression throws inside guardScript (aborts generation)
t("F16c2.guardScript-boolean-expr-throws", () => {
  M.guardScript([{ id: "x", tag: "w", expression: true }]);
  return false;
});

// F16d2: generated helpers vs the real omarchy-cmd-present for option-like names
t("F16d2.guardHelpers-option-like", () => {
  const script = M.guardScript([]).length >= 0 ? "" : "";
  // guardScript embeds guardHelpers only when a reader is used; run helpers directly
  const helpers = M.guardScript([{ id: "t", tag: "w", expression: "$(omarchy-cmd-present -x)" }]);
  const out = execSync("/bin/bash", { input: helpers + "\necho done\n" }).toString();
  return out.indexOf("t:w:") >= 0;
});
console.log("ROUND2-DONE");
