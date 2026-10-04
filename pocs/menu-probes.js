// Probe harness: executes the REAL shell/plugins/menu/MenuModel.js functions
// against each defect-family trigger. Output: one line per probe,
// "<KEY>: <verdict>" where REAL = defect reproduced, REFUTED = behavior sound.
const fs = require("fs");
const M = require(process.argv[2]);

function t(key, fn) {
  try {
    const r = fn();
    console.log(key + ": " + (r ? "REAL  -- " : "REFUTED  -- ") + (typeof r === "string" ? r : ""));
  } catch (e) {
    console.log(key + ": THREW  -- " + e.message);
  }
}
const throws = fn => { try { fn(); return false } catch (e) { return true } };

// F1: trailing comma hidden behind a // comment
t("F1.trailing-comma-behind-comment", () => {
  const out = M.stripJsonc('{ "a": 1, // c\n}');
  return out.indexOf("1,") >= 0 || throws(() => JSON.parse(out));
});

// F2: // comment eats the newline, gluing tokens
t("F2.comment-eats-newline", () => {
  const out = M.stripJsonc('[1//c\n2]');
  return out === "[12]";
});

// F3: block comments copied through
t("F3.block-comment-passthrough", () => {
  const out = M.stripJsonc('{ /* c */ "a": 1 }');
  return out.indexOf("/*") >= 0 || throws(() => JSON.parse(out));
});

// F4: CR-terminated comment eats the rest of the file
t("F4.cr-comment-eats-file", () => {
  const out = M.stripJsonc('{\n"a": 1//c\r,\n"b": 2}');
  return out.indexOf('"b"') < 0;
});

// F7: item() walks the prototype
t("F7.item-prototype-hit", () => M.item({}, "constructor") !== null && typeof M.item({}, "toString") === "function");

// F8: resolveRoute folding + app exact-id + literal fallthrough
const routeItems = { Setup: { id: "Setup", kind: "menu", parent: "root", aliases: [] }, firefox: { id: "firefox", kind: "app", parent: "root", aliases: [] } };
const routeOrder = ["Setup", "firefox"];
t("F8a.exact-id-case-missed", () => M.resolveRoute(routeItems, routeOrder, "Setup") !== "Setup");
t("F8b.fallthrough-not-literal", () => M.resolveRoute({}, [], "Fire Fox") !== "Fire Fox");
t("F8c.app-exact-id-routable", () => M.resolveRoute(routeItems, routeOrder, "firefox") === "firefox");

// F9: mergeMenuSources drops prototype-named ids from itemOrder
t("F9.prototype-id-dropped", () => {
  const r = M.mergeMenuSources([{ id: "constructor", label: "X", parent: "root", kind: "menu", aliases: [] }], []);
  return r.items.constructor && r.itemOrder.indexOf("constructor") < 0;
});

// F10: normalize-then-merge wipes unspecified defaults
t("F10.normalize-wipes-defaults", () => {
  const def = M.normalizeItem("x", { label: "X", action: "doit", description: "keep" });
  const user = M.normalizeItem("x", { label: "X2" });
  const r = M.mergeMenuSources([def], [user]);
  return r.items.x.action === "" ;
});

// F11: mergeAppRows stale order + caller-object mutation
t("F11a.mergeAppRows-stale-order", () => {
  const items = { root: { id: "root", kind: "menu", order: 0 }, s2: { id: "s2", kind: "menu", order: 2, parent: "root" } };
  const r = M.mergeAppRows(items, ["root", "s2"], []);
  return r.items.s2.order !== 1;
});
t("F11b.mergeAppRows-mutates-caller-rows", () => {
  const row = { id: "app1", kind: "app", label: "A" };
  M.mergeAppRows({ root: { id: "root", kind: "menu", order: 0 } }, ["root"], [row]);
  return row.order === 1;
});

// F12: swapProviderRows stale order on kept rows
t("F12.swapProviderRows-stale-order", () => {
  const items = { root: { id: "root", kind: "menu", order: 0 }, s1: { id: "s1", kind: "menu", order: 1, parent: "root" } };
  const r = M.swapProviderRows(items, ["root", "s1"], "m1", [{ id: "p1", kind: "menu", label: "P" }]);
  return r.items.s1.order !== 1;
});

// F13: swapProviderRows drops a colliding provider row (static wins silently)
t("F13.collision-row-dropped", () => {
  const items = { root: { id: "root", kind: "menu", order: 0 }, clash: { id: "clash", kind: "menu", order: 1, parent: "root" } };
  const r = M.swapProviderRows(items, ["root", "clash"], "m1", [{ id: "clash", kind: "menu", label: "ProviderVersion" }]);
  return r.items.clash.label !== "ProviderVersion";
});

// F14: flat map with an entry id 'items' is treated as a wrapper
t("F14.items-key-ambiguity", () => {
  const rows = M.parseMenuJsonc('{"items": {"inner": {"label": "A"}}, "b": {"label": "B"}}');
  return JSON.stringify(rows.map(r => r.id)) === JSON.stringify(["inner"]);
});

// F15: searchScore robustness + shape
t("F15a.searchScore-throws-missing-label", () => throws(() => M.searchScore({ x: { id: "x" } }, { id: "x", parent: "root", order: 0 }, "q")));
t("F15b.searchScore-NaN-missing-order", () => Number.isNaN(M.searchScore({ x: { id: "x" } }, { id: "x", label: "X", parent: "root" }, "q")));
t("F15c.searchScore-empty-query-prefix", () => {
  const e = { id: "x", label: "X", parent: "root", order: 0 };
  return M.searchScore({ x: e }, e, "") === 10 * 1000;
});
// F15d (withdrawn): an app and a menu row with equal scores rank app-first.
// That is the intended order: merged omacom/omarchy#6383 (merge commit
// 35ebe2df) added the -5 so an installed app outranks an equally matching
// menu row inside its tier. The probe reports that order, not a defect.
{
  const app = { id: "a", label: "Same", parent: "root", kind: "app", order: 0 };
  const menu = { id: "m", label: "Same", parent: "root", kind: "menu", order: 1 };
  const appFirst = M.searchScore({}, app, "same") < M.searchScore({}, menu, "same");
  console.log("F15d.searchScore-app-first-by-design: " + (appFirst ? "INTENDED" : "CHANGED") + "  -- an app ranks ahead of an equal menu row (omacom/omarchy#6383)");
}
t("F15e.multiword-crossfield-collapses-to-baseline", () => {
  const e = { id: "x", label: "Alpha", description: "runs the beta tool", parent: "root", kind: "menu", order: 0 };
  return M.searchScore({ x: e }, e, "alpha beta") >= 80 * 1000 && M.matchesQuery(e, "alpha beta", true) === true;
});

// F16: guard generation
t("F16a.guardLine-id-unquoted", () => {
  const line = M.guardLine('my;id', "w", "true");
  return line.indexOf("echo my;id:w:1") >= 0;
});
t("F16b.guardScript-syntax-error-silent", () => {
  const guards = [{ id: "bad", tag: "w", expression: "}" }, { id: "ok", tag: "w", expression: "true" }];
  const script = M.guardScript(guards);
  return throws(() => require("child_process").execSync("/bin/bash -n", { input: script, stdio: ["pipe", "pipe", "pipe"] })) === false ? false : true;
});
t("F16c.substituteGuardReaders-nonstring-throws", () => throws(() => M.guardLine("id", "w", true)));
t("F16d.guardHelpers-option-like-name", () => {
  // run the generated helpers and ask for an option-like command name
  const script = M.guardHelpers() + "\nif omarchy-cmd-present -x; then echo yes; else echo no; fi\n";
  const out = require("child_process").execSync("/bin/bash", { input: script }).toString().trim();
  // real omarchy-cmd-present on PATH for comparison
  let real = "no";
  try { real = require("child_process").execSync("omarchy-cmd-present -x && echo yes || echo no", { shell: "/bin/bash" }).toString().trim(); } catch (e) { real = "cmd-helper-absent"; }
  return JSON.stringify({ gen: out, real });
});

// F17: normalizeItem edge cases
t("F17a.null-parent-kept", () => M.normalizeItem("x", { parent: null }).parent === null);
t("F17b.boolean-when-kept", () => M.normalizeItem("x", { when: true }).when === true);
t("F17c.action-zero-falsy-kind", () => M.normalizeItem("x", { action: 0 }).kind === "menu");

// F18: isDisabled prototype truthiness
t("F18.isDisabled-prototype-truthy", () => {
  return M.isDisabled({}, { id: "constructor", disabled: "x" }) === true;
});
t("F18b.labelFor-prototype-checked", () => {
  return M.labelFor({ id: "toString", label: "L", checked: "x" }, {}, {}).indexOf("✓") >= 0;
});

// F19: isDescendantOf says everything but root descends from root
t("F19.isDescendantOf-root-always", () => M.isDescendantOf({ x: { id: "x", parent: "not-in-tree" } }, "missing-id", "root") === true);

// F20: childCount counts hidden children and duplicates
t("F20.childCount-hidden-and-dupes", () => {
  const items = {
    root: { id: "root", kind: "menu", parent: "" },
    a: { id: "a", parent: "m", kind: "menu", when: "false" },
    b: { id: "b", parent: "m", kind: "menu" }
  };
  return M.childCount(items, ["m", "a", "b", "b"], "m") === 3;
});

// F21: pathFor/parentPathFor with null parent
t("F21.pathFor-null-parent", () => {
  const items = { x: { id: "x", label: "X", parent: null, kind: "menu" } };
  return JSON.stringify(M.pathFor(items, "x")) !== JSON.stringify(M.parentPathFor(items, "x"));
});

// F22: summonAction rewrites explicit empty payload to {}
t("F22.summonAction-empty-payload", () => {
  const r = M.summonAction("omarchy-shell shell summon menu ''");
  return r.payload === "{}";
});

// F23: non-string alias becomes [object Object] searchable
t("F23.alias-object-object", () => M.nameSearchText({ id: "x", label: "X", aliases: [{}] }).indexOf("[object object]") >= 0);

// F24: termInSearchWords punctuation and case
t("F24a.punctuation-glued-miss", () => M.termInSearchWords("system", "controls the system.") === false);
t("F24b.mixed-case-term-miss", () => M.termInSearchWords("System", "the system tool") === false);

// F6/F12 reachability probes are settled by caller inspection, not here.
console.log("HARNESS-DONE");
