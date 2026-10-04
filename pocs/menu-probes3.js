// Probe round 3: guardScript takes an items MAP; score comparisons use tiers.
const M = require(process.argv[2]);
const { execSync } = require("child_process");
function t(key, fn) {
  try {
    const r = fn();
    console.log(key + ": " + (r ? "REAL" : "REFUTED") + (typeof r === "string" ? " -- " + r : ""));
  } catch (e) {
    console.log(key + ": THREW  -- " + e.message);
  }
}

t("F16a2.guardScript-id-unquoted", () => {
  const script = M.guardScript({ "my;id": { when: "true" } });
  return script.indexOf("echo my;id:w:1") >= 0;
});

t("F16b2.guardScript-syntax-abort", () => {
  const script = M.guardScript({ bad: { when: "}" }, ok: { when: "true" } });
  try { execSync("/bin/bash -n", { input: script, stdio: ["pipe", "pipe", "pipe"] }); return false; }
  catch (e) { return true; }
});

t("F16c2.guardScript-boolean-expr-throws", () => {
  M.guardScript({ x: { when: true } });
  return false;
});

t("F16d2.guardHelpers-option-like", () => {
  const script = M.guardScript({ t: { when: "$(omarchy-cmd-present -x)" } });
  const out = execSync("/bin/bash", { input: script + "\necho BATCH-OK\n" }).toString();
  const line = out.split("\n").find(l => l.startsWith("t:w:"));
  let real = "?";
  try { real = execSync("omarchy-cmd-present -x 2>/dev/null && echo present || echo absent", { shell: "/bin/bash" }).toString().trim(); }
  catch (e) { real = "absent"; }
  return "gen=" + (line || "none") + " real=" + real;
});

// F15e2: an accepted cross-field match scores exactly like a row that matches nothing
// (the unmatched baseline: 80 tier, minus the menu-row nudge, so 78000 for a root menu row).
t("F15e2.crossfield-collapses-to-unmatched-baseline", () => {
  const e = { id: "x", label: "alpha", description: "beta", parent: "root", kind: "menu", order: 0 };
  const none = { id: "y", label: "gamma", description: "delta", parent: "root", kind: "menu", order: 0 };
  const accepted = M.matchesQuery(e, "alpha beta", true);
  const score = M.searchScore({ x: e }, e, "alpha beta");
  const baseline = M.searchScore({ y: none }, none, "alpha beta");
  return accepted && !M.matchesQuery(none, "alpha beta", true) && score === baseline && "score=" + score + " baseline=" + baseline;
});

// F15f: exact-label root (2) vs nested exact label (0): root swamped by depth?
t("F15f.root-exact-vs-nested", () => {
  const rootE = { id: "a", label: "Zen", parent: "root", kind: "menu", order: 0 };
  const nested = { id: "install.zen", label: "Zen", parent: "install", kind: "menu", order: 1 };
  const items = { a: rootE, "install.zen": nested };
  // root exact should beat the nested same-label row per depth tiebreak intent
  return M.searchScore(items, rootE, "zen") > M.searchScore(items, nested, "zen");
});
console.log("ROUND3-DONE");
