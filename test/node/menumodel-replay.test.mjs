// Verifies: SW-REQ-260922-E4J2, SW-REQ-260922-3T3F, SW-REQ-260922-46HY, SW-REQ-260922-7NPE, SYS-REQ-260922-PPDW, SW-REQ-260922-Z680, SW-REQ-260922-EFNR, SYS-REQ-260922-0M8A, SW-REQ-260922-PRNV, SW-REQ-260922-CYB9, SW-REQ-260922-74BZ, SYS-REQ-260922-R8DQ, SW-REQ-260922-XW52, SW-REQ-260922-N3RM, SW-REQ-260922-JRW1, SW-REQ-260922-DQ9P, SW-REQ-260922-SJ7P, SYS-REQ-260922-V7W6, SW-REQ-260922-TKDP, SYS-REQ-260927-WC89
// node:test adapter for the proof js MC/DC engine: replays the MenuModel.js
// assertion body from test/shell.d/menu-test.sh under node:test so the
// engine's Babel instrumentation can observe MenuModel.js decisions. The
// omarchy harness pipes a prelude to plain `node`, which the js engine's
// node/vitest runner contract cannot drive (menu dogfood finding M12); this
// adapter keeps ONE source of truth: the body inside test(...) below is
// extracted verbatim from menu-test.sh.
import { test } from 'node:test'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { createRequire } from 'node:module'

const require = createRequire(import.meta.url)
const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')

function fail(description, detail) {
  if (detail) console.error(detail)
  throw new Error(description)
}
function pass(description) { /* node:test reports one line per test */ }
function assert(condition, description, detail) {
  if (!condition) fail(description, detail)
  pass(description)
}
function assertEqual(actual, expected, description) {
  assert(actual === expected, description, `expected: ${expected}\nactual:   ${actual}`)
}
function assertDeepEqual(actual, expected, description) {
  const actualJson = JSON.stringify(actual)
  const expectedJson = JSON.stringify(expected)
  assert(actualJson === expectedJson, description, `expected: ${expectedJson}\nactual:   ${actualJson}`)
}
// MenuModel.js is CommonJS (module.exports). It MUST reach the engine
// through an ESM import: module.register() loader hooks fire for ESM
// imports (including import-of-CJS, which the hook then serves as
// instrumented format:'commonjs' source), but NOT for require() of a CJS
// file — a require()'d MenuModel.js loads uninstrumented and contributes
// zero decisions. require() interop shape is preserved by unwrapping the
// namespace default.
const menuModelPath = path.join(root, 'shell/plugins/menu/MenuModel.js')
const menuModelNs = await import(pathToFileURL(menuModelPath).href)
const menuModel = menuModelNs.default ?? menuModelNs
function requireFromRoot(relativePath) {
  const abs = path.join(root, relativePath)
  if (abs === menuModelPath) return menuModel
  return require(abs)
}

test('MenuModel.js decision replay (body extracted from menu-test.sh)', () => {
const fs = require('fs')
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
const defaultMenuJsonc = fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')

const parsed = menu.parseMenuJsonc(`
{
  // comment
  "items": {
    "root": { "label": "Go" },
    "style": { "label": "Style" },
    "style.theme": {
      "label": "Themes",
      "aliases": "theme",
      "description": "appearance colors",
      "action": "omarchy-theme-set"
    },
  },
}
`)

// MCDC SW-REQ-260922-E4J2: items_parsed=T, jsonc_has_comments_or_commas=T => TRUE
// MCDC SW-REQ-260922-3T3F: empty_item_set=F, json_invalid=F, parse_error_raised=F => TRUE [no-action: the valid JSONC parses to its items -- the invalid path is not taken]
assertEqual(parsed.length, 3, 'menu parses JSONC with comments and trailing commas')
// MCDC SW-REQ-260922-46HY: entry_shape_declared=T, kind_and_parent_inferred=T => TRUE
assertDeepEqual(
  parsed.find(item => item.id === 'style.theme'),
  {
    id: 'style.theme',
    parent: 'style',
    kind: 'action',
    icon: '',
    iconFont: '',
    label: 'Themes',
    title: '',
    target: '',
    description: 'appearance colors',
    action: 'omarchy-theme-set',
    provider: '',
    aliases: ['theme'],
    when: '',
    checked: '',
    disabled: ''
  },
  'menu normalizes parsed items'
)

// Invalid input never throws and never yields items: comments present or
// not, a broken document parses to an empty set.
// MCDC SW-REQ-260922-3T3F: empty_item_set=T, json_invalid=T, parse_error_raised=F => TRUE
assertEqual(menu.parseMenuJsonc('{broken').length, 0, 'menu parses invalid JSON to an empty item set without raising')
// MCDC SW-REQ-260922-E4J2: items_parsed=F, jsonc_has_comments_or_commas=T => FALSE
assertEqual(menu.parseMenuJsonc('{\n// comment\n"items":').length, 0, 'menu parses broken JSONC with comments to an empty item set')
// MCDC SW-REQ-260922-E4J2: items_parsed=F, jsonc_has_comments_or_commas=F => TRUE [no-action: empty input parses to zero items -- the JSONC handling parses nothing]
// MCDC SW-REQ-260922-46HY: entry_shape_declared=F, kind_and_parent_inferred=F => TRUE [no-action: an empty item set declares zero entries -- nothing is normalized]
assertEqual(menu.parseMenuJsonc('').length + menu.parseMenuJsonc('{"items":{}}').length, 0, 'menu parses empty input and an empty item set to zero entries')

// JSONC stripping as upstream e332dc97 ships it: two string-blind regex
// passes. The first drops every whole-line // comment together with its line
// break; the second drops a comma whose next non-whitespace character is } or
// ]. The assertions below pin what that order gets RIGHT (preservation) and,
// tagged Reproduces, what it gets wrong (known issues, pinned as green
// tripwires: each flips red when the named upstream fix lands).
// SW-REQ-260922-E4J2: a real trailing comma before a closing brace is dropped.
assertEqual(
  menu.parseMenuJsonc('{"c": {"label": "y"},}').length,
  1,
  'menu still tolerates a real trailing comma before a closing brace'
)
// SW-REQ-260922-3T3F:boundary:negative
assertEqual(
  menu.parseMenuJsonc('{"a": undefined, }').length,
  0,
  'menu rejects a malformed value even when a strippable trailing comma is present'
)
assertDeepEqual(
  menu.parseMenuJsonc('{"d": {"label": "z", "aliases": ["a", "b",]}}')[0].aliases,
  ['a', 'b'],
  'menu still tolerates a trailing comma before a closing bracket in an array'
)
assertEqual(
  menu.parseMenuJsonc('{"i": {"label": "edge"}, }')[0].label,
  'edge',
  'menu strips a comma whose closing brace is the last character in the file'
)
assertEqual(
  menu.parseMenuJsonc('{"m": {"label": "a"}, "n": {"label": "b"}}').length,
  2,
  'menu keeps a comma between entries'
)
assertEqual(
  menu.parseMenuJsonc('{"o": {"label": "a, b"}}')[0].label,
  'a, b',
  'menu preserves a plain comma inside a string literal'
)
assertEqual(
  menu.parseMenuJsonc('{"s": {"label": "A // B"}}')[0].label,
  'A // B',
  'menu preserves comment slashes inside a string literal'
)
assertEqual(
  menu.parseMenuJsonc('{"q": {"label": "q\\" // y"}}')[0].label,
  'q" // y',
  'menu preserves comment slashes after an escaped quote inside a string literal'
)
assertEqual(
  menu.parseMenuJsonc('{"n": {"label": "plain"}}').length,
  1,
  'menu parses a comment-free object unchanged'
)
// Preservation: a trailing comma, then whole-line comments, then the closer.
// Comments go first, so the comma meets its closer and is dropped. This is
// the shape of every extension file whose last entry is followed by
// commented-out examples (omacom/omarchy#13512 regressed it to an empty menu).
assertEqual(
  menu.parseMenuJsonc('{\n  "a": {"label": "A"},\n  // note\n}').length,
  1,
  'menu keeps every row when a whole-line comment sits between a trailing comma and the closing brace'
)
assertDeepEqual(
  menu.parseMenuJsonc('{"a": {"label": "A", "aliases": ["x",\n// c\n]}}')[0].aliases,
  ['x'],
  'menu keeps array elements when a whole-line comment sits between a trailing comma and the closing bracket'
)
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A"},\n  // "x": {"label": "X"},\n}').length,
  1,
  'menu keeps every row when a commented-out entry follows the last real entry'
)
assertEqual(
  menu.parseMenuJsonc('{\n// c\n"a": {"label": "A"},\n}').length,
  1,
  'menu strips a whole-line comment before the first entry'
)
assertEqual(
  menu.parseMenuJsonc('{\r\n// c\r\n"a": {"label": "A"},\r\n}').length,
  1,
  'menu strips whole-line comments and trailing commas under CRLF line endings'
)
assertEqual(
  menu.parseMenuJsonc('{\n// it\'s "quoted\n"a": {"label": "A"}\n}').length,
  1,
  'menu strips a whole-line comment that carries an unbalanced quote'
)
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A"}}\n// end').length,
  1,
  'menu strips a final whole-line comment with no line break after it'
)
const extensionTemplate = fs.readFileSync(path.join(root, 'config/omarchy/extensions/omarchy-menu.jsonc'), 'utf8')
assertEqual(menu.parseMenuJsonc(extensionTemplate).length, 0, 'menu parses the shipped extension template as is to zero rows')
const extensionExamples = extensionTemplate.replace(/^(\s*)\/\/ ("personal[^"]*": .*)$/gm, '$1$2')
assertDeepEqual(
  menu.parseMenuJsonc(extensionExamples).map(item => item.id),
  ['personal', 'personal.notes', 'personal.files'],
  'menu keeps all three rows of the shipped extension template with its personal examples uncommented'
)
assertEqual(
  menu.parseMenuJsonc(extensionExamples.replace(/^(\s*)\/\/ ("about": .*)$/m, '$1$2')).length,
  4,
  'menu keeps all four rows of the shipped extension template with every example uncommented'
)

// Known issues, pinned as green tripwires of upstream's actual output.
// Reproduces: KI-MENU-JSONC-COMMA-IN-STRING
assertEqual(
  menu.parseMenuJsonc('{"b": {"label": "x, ]y"}}')[0].label,
  'x ]y',
  'KI-MENU-JSONC-COMMA-IN-STRING tripwire: the comma pass rewrites a label carrying comma and closer (omacom/omarchy#13250)'
)
assertEqual(
  menu.parseMenuJsonc('{"b": {"label": "B", "action": "mv f{.bak,}"}}')[0].action,
  'mv f{.bak}',
  'KI-MENU-JSONC-COMMA-IN-STRING tripwire: the comma pass rewrites an action carrying comma and closer'
)
// Reproduces: KI-MENU-JSONC-ARRAY-ROOT
assertDeepEqual(
  menu.parseMenuJsonc('[{"label":"should-not-appear"},{"label":"ghost-2"}]').map(item => item.id + '=' + item.label),
  ['0=should-not-appear', '1=ghost-2'],
  'KI-MENU-JSONC-ARRAY-ROOT tripwire: an array root renders phantom rows keyed by index (omacom/omarchy#13492)'
)
assertEqual(
  menu.parseMenuJsonc('{"items": [{"label":"x"}]}').length,
  0,
  'menu skips an array nested under the items key as a non-object entry'
)
// Reproduces: KI-MENU-JSONC-INLINE-COMMENT
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A"}} // note').length,
  0,
  'KI-MENU-JSONC-INLINE-COMMENT tripwire: an inline comment tail empties the whole file (omacom/omarchy#13493)'
)
assertEqual(
  menu.parseMenuJsonc('{\n  "a": {"label": "A"}, // first\n  "b": {"label": "B"}\n}').length,
  0,
  'KI-MENU-JSONC-INLINE-COMMENT tripwire: an inline comment on an entry line empties the whole file'
)
// Reproduces: KI-MENU-JSONC-STRIP-GAPS
assertEqual(
  menu.parseMenuJsonc('{ /* c */ "a": {"label": "A"} }').length,
  0,
  'KI-MENU-JSONC-STRIP-GAPS tripwire: a block comment is not stripped and empties the whole file'
)

const user = [
  menu.normalizeItem('style.theme', { label: 'Theme picker', aliases: ['theme', 'colors'], action: 'custom-theme' }),
  menu.normalizeItem('tools', { label: 'Tools' })
]
const merged = menu.mergeMenuSources(parsed, user)
// MCDC SYS-REQ-260922-PPDW: item_tree_merged=T, menu_sources_loaded=T => TRUE
assertEqual(merged.items['style.theme'].label, 'Theme picker', 'menu user entries override default entries')
assertEqual(merged.items['style.theme'].order, 2, 'menu preserves original order on override')
assert(merged.items.root, 'menu injects root when merging sources')

// MCDC SW-REQ-260922-7NPE: per_key_override_applied=T, root_injected=T, user_entry_overrides=T => TRUE
const overrideMerge = menu.mergeMenuSources(
  [menu.normalizeItem('a.b', { label: 'Default' })],
  [menu.normalizeItem('a.b', { label: 'Override' })]
)
assertEqual(overrideMerge.items['a.b'].label, 'Override', 'menu applies a user override per key')
assert(
  overrideMerge.items.root && overrideMerge.itemOrder[0] === 'root',
  'menu injects root when the sources lack it'
)

// MCDC SW-REQ-260922-7NPE: per_key_override_applied=F, root_injected=F, user_entry_overrides=F => TRUE [no-action: merging zero user entries applies zero overrides -- the tree equals the defaults and root needs no injection]
const noUserMerge = menu.mergeMenuSources(parsed, [])
assertEqual(noUserMerge.items['style.theme'].label, 'Themes', 'menu leaves default entries untouched without user entries')

// MCDC SYS-REQ-260922-PPDW: item_tree_merged=F, menu_sources_loaded=F => TRUE [no-action: with no sources loaded the merged tree holds only the injected root -- no items are merged]
const emptyMerge = menu.mergeMenuSources([], [])
assertDeepEqual(Object.keys(emptyMerge.items), ['root'], 'menu merges empty sources to just the injected root')

assertEqual(menu.slugify('Power Saver!'), 'power-saver', 'menu slugifies provider rows')
assertEqual(menu.pathFor(merged.items, 'style.theme'), 'Style › Theme picker', 'menu builds item paths')
assertEqual(menu.parentPathFor(merged.items, 'style.theme'), 'Style', 'menu builds parent paths')
assert(menu.isDescendantOf(merged.items, 'style.theme', 'style'), 'menu detects descendants')
assertEqual(menu.childCount(merged.items, merged.itemOrder, 'style'), 1, 'menu counts children')
assertEqual(menu.labelFor({ id: 'style.theme', label: 'Theme', checked: 'cmd' }, { 'style.theme': true }), 'Theme ✓', 'menu appends checked marker')
assertEqual(menu.labelFor({ id: 'install.browser.zen', label: 'Zen', disabled: 'cmd' }, {}, { 'install.browser.zen': true }), 'Zen ✓', 'menu marks a disabled row as something you already have')
assertEqual(menu.labelFor({ id: 'install.browser.zen', label: 'Zen', disabled: 'cmd' }, {}, { 'install.browser.zen': false }), 'Zen', 'menu leaves an uninstalled row unmarked')

const visibilityItems = {
  hardware: menu.normalizeItem('hardware', { label: 'Hardware' }),
  laptop: menu.normalizeItem('hardware.laptop', { label: 'Laptop', when: 'is-laptop', action: 'toggle-laptop' }),
  nested: menu.normalizeItem('nested', { label: 'Nested' }),
  branch: menu.normalizeItem('nested.branch', { label: 'Branch' }),
  leaf: menu.normalizeItem('nested.branch.leaf', { label: 'Leaf', when: 'has-leaf', action: 'run-leaf' }),
  dynamic: menu.normalizeItem('dynamic', { label: 'Dynamic', provider: 'items' })
}
const visibilityOrder = Object.keys(visibilityItems)
// MCDC SW-REQ-260922-JRW1: guard_results_applied=T, rows_hidden_or_marked_per_results=T => TRUE
assert(!menu.isVisible(visibilityItems, visibilityOrder, { 'hardware.laptop': false }, visibilityItems.hardware), 'menu hides a submenu with no visible children')
assert(menu.isVisible(visibilityItems, visibilityOrder, { 'hardware.laptop': true }, visibilityItems.hardware), 'menu shows a submenu with a visible child')
assert(!menu.isVisible(visibilityItems, visibilityOrder, { 'nested.branch.leaf': false }, visibilityItems.nested), 'menu hides recursively empty submenus')
assert(menu.isVisible(visibilityItems, visibilityOrder, {}, visibilityItems.dynamic), 'menu keeps provider-backed submenus visible')
// MCDC SW-REQ-260922-JRW1: guard_results_applied=F, rows_hidden_or_marked_per_results=F => TRUE [no-action: with empty guard results the nested submenu stays visible -- nothing is hidden or marked]
assert(menu.isVisible(visibilityItems, visibilityOrder, {}, visibilityItems.nested), 'menu leaves rows untouched when no guard results exist')

// `disabled:` is the softer guard: the row stays listed and only loses the
// cursor, which is how an already-installed app keeps its place in Install.
const installed = menu.normalizeItem('install.browser.zen', { label: 'Zen', disabled: 'omarchy-pkg-present zen-browser-bin', action: 'install-zen' })
assert(menu.isVisible({ 'install.browser.zen': installed }, ['install.browser.zen'], { 'install.browser.zen': false }, installed), 'menu keeps a disabled row visible')
assert(menu.isDisabled({ 'install.browser.zen': true }, installed), 'menu disables a row whose disabled: succeeded')
assert(!menu.isDisabled({ 'install.browser.zen': false }, installed), 'menu leaves a row selectable when its disabled: failed')
assert(!menu.isDisabled({ 'install.browser.zen': true }, visibilityItems.laptop), 'menu never disables a row that declares no disabled:')
// MCDC SW-REQ-260922-DQ9P: all_terms_matched=F, query_terms_given=F, row_hidden_from_results=F => TRUE [no-action: the browse row is built without a query -- no term matching runs and nothing is hidden]
// MCDC SYS-REQ-260922-V7W6: matching_rows_ranked=F, search_entered=F => TRUE [no-action: the browse row carries score 0 -- no search ranking runs outside search]
// MCDC SW-REQ-260922-TKDP: matches_span_menus=F, sections_divided=F => TRUE [no-action: the browse row carries an empty section -- no search sections exist to divide]
assert(
  menu.displayRow({ 'install.browser.zen': installed }, ['install.browser.zen'], {}, { 'install.browser.zen': true }, installed, '', 0).disabled,
  'menu display rows carry their disabled state'
)
assert(
  /function matchesQuery\(entry, query\) \{\s*\n\s*return MenuModel\.matchesQuery\(entry, query, root\.isVisible\(entry\) && !root\.isDisabled\(entry\)\)/.test(menuQml),
  'menu search skips disabled rows, which belong to the submenu they sit in rather than a list of what you can do'
)

assert(
  /if \(drilldownRows\[f\]\.kind === "app"\) appRows\.push\(drilldownRows\[f\]\)[\s\S]*?rows = appRows\.concat\(currentRows\)\.concat\(deeperRows\)/.test(menuQml),
  'menu pins matching app rows above the direct children in search'
)

const entry = merged.items['style.theme']
// MCDC SW-REQ-260922-DQ9P: all_terms_matched=T, query_terms_given=T, row_hidden_from_results=F => FALSE
assert(menu.matchesQuery(entry, 'theme', true), 'menu matches labels and aliases')
assert(menu.matchesQuery(entry, 'colors', true), 'menu matches aliases')
// MCDC SW-REQ-260922-DQ9P: all_terms_matched=F, query_terms_given=T, row_hidden_from_results=T => FALSE
assert(!menu.matchesQuery(entry, 'missing', true), 'menu rejects missing terms')
// MCDC SW-REQ-260922-DQ9P: all_terms_matched=T, query_terms_given=T, row_hidden_from_results=T => TRUE
assert(!menu.matchesQuery(entry, 'theme', false), 'menu hides invisible matches')
// MCDC SW-REQ-260922-SJ7P: better_match_ranks_first=T, match_quality_varies=T => TRUE
assert(menu.searchScore(merged.items, entry, 'theme') < menu.searchScore(merged.items, entry, 'appearance'), 'menu scores name matches above description matches')

// MCDC SW-REQ-260922-N3RM: action_runs_directly=T, menu_not_opened=T, resolved_kind_action=T => TRUE
// MCDC SW-REQ-260922-XW52: link_target_followed=F, resolved_kind_link=F => TRUE [no-action: the action row's target is its own id -- no link target is followed]
// MCDC SW-REQ-260922-TKDP: matches_span_menus=T, sections_divided=T => TRUE
assertDeepEqual(
  menu.displayRow(merged.items, merged.itemOrder, {}, {}, entry, 'Style', 12, 'search'),
  {
    itemId: 'style.theme',
    disabled: false,
    kind: 'action',
    icon: '',
    iconFont: '',
    appIcon: '',
    appId: '',
    label: 'Theme picker',
    target: 'style.theme',
    detail: 'Style',
    path: 'Style › Theme picker',
    childCount: 0,
    action: 'custom-theme',
    provider: '',
    score: 12,
    section: 'search'
  },
  'menu builds display rows'
)

// A link row routes its activation to the target menu; a menu-kind row opens
// its submenu and runs nothing itself.
const linkEntry = menu.normalizeItem('go.setup', { label: 'Setup', target: 'setup' })
// MCDC SW-REQ-260922-XW52: link_target_followed=T, resolved_kind_link=T => TRUE
assertEqual(
  menu.displayRow(merged.items, merged.itemOrder, {}, {}, linkEntry, '', 0).target,
  'setup',
  'menu follows a link row to its target'
)
// MCDC SW-REQ-260922-N3RM: action_runs_directly=F, menu_not_opened=F, resolved_kind_action=F => TRUE [no-action: the menu-kind row carries no action -- nothing runs directly]
const menuRow = menu.displayRow(merged.items, merged.itemOrder, {}, {}, merged.items.style, '', 0)
assert(
  menuRow.kind === 'menu' && menuRow.action === '' && menuRow.target === 'style',
  'menu kind rows open their submenu instead of running an action'
)

const defaultItems = menu.parseMenuJsonc(defaultMenuJsonc)
const defaultById = Object.fromEntries(defaultItems.map(item => [item.id, item]))

// Needs the real menu: app rows sort after all menu items, and only at that
// item count does the order tiebreak alone bury an installed app.
const rankBase = menu.mergeMenuSources(defaultItems, [])
const ranked = menu.mergeAppRows(rankBase.items, rankBase.itemOrder, [
  { id: 'apps.brave', parent: 'apps', kind: 'app', label: 'Brave', description: '', aliases: [] },
  { id: 'apps.fontforge', parent: 'apps', kind: 'app', label: 'FontForge', description: '', aliases: [] },
  { id: 'apps.zen', parent: 'apps', kind: 'app', label: 'Zen Browser', description: '', aliases: [] }
])
const rankScore = (id, query) => menu.searchScore(ranked.items, ranked.items[id], query)
// MCDC SYS-REQ-260922-V7W6: matching_rows_ranked=T, search_entered=T => TRUE
assert(
  ['install.browser.brave', 'remove.browser.brave', 'setup.default.browser.brave'].every(
    id => rankScore('apps.brave', 'brave') < rankScore(id, 'brave')
  ),
  'menu ranks an installed app above menu entries matching the query equally well'
)
assert(
  ['install.browser.zen', 'remove.browser.zen', 'setup.default.browser.zen'].every(
    id => rankScore('apps.zen', 'zen') < rankScore(id, 'zen')
  ),
  'menu ranks an app matching the query as a whole word above exact-labeled menu entries'
)
assert(
  rankScore('apps.fontforge', 'font') < rankScore('style.font', 'font'),
  'menu ranks an installed app above a menu entry even when the menu entry matches better'
)

// "vsc" matches the VSCode menu entries by label prefix but the installed
// app only by keyword substring, so without an apps-first bias the app
// sorts second. The menu must still put the app on top.
const vscRanked = menu.mergeAppRows(rankBase.items, rankBase.itemOrder, [
  { id: 'apps.code', parent: 'apps', kind: 'app', label: 'Visual Studio Code', description: 'Text Editor', aliases: ['Text Editor', 'vscode'] }
])
const vscScore = (id, query) => menu.searchScore(vscRanked.items, vscRanked.items[id], query)
assert(
  ['setup.default.editor.vscode', 'install.editor.vscode'].every(
    id => vscScore('apps.code', 'vsc') < vscScore(id, 'vsc')
  ),
  'menu ranks the installed VS Code app above its VSCode menu entries for vsc'
)

// Ranking only engages when match quality varies: two whole-word app matches
// of identical quality keep declaration order and nothing more.
const equalApps = menu.mergeAppRows(rankBase.items, rankBase.itemOrder, [
  { id: 'apps.zen-a', parent: 'apps', kind: 'app', label: 'Zen A', description: '', aliases: [] },
  { id: 'apps.zen-b', parent: 'apps', kind: 'app', label: 'Zen B', description: '', aliases: [] }
])
// MCDC SW-REQ-260922-SJ7P: better_match_ranks_first=F, match_quality_varies=F => TRUE [no-action: two whole-word app matches of identical quality differ only by declaration order -- the quality ranking never engages]
assert(
  menu.searchScore(equalApps.items, equalApps.items['apps.zen-b'], 'zen')
    - menu.searchScore(equalApps.items, equalApps.items['apps.zen-a'], 'zen') === 1,
  'menu orders equal-quality matches by declaration order alone'
)

// Routing: htop ships `Keywords=system;...`, which app rows carry as aliases.
// An installed app must never capture a menu route (SUPER+ESCAPE opens the
// `system` menu), while its keywords keep working for search.
const routed = menu.mergeAppRows(rankBase.items, rankBase.itemOrder, [
  { id: 'apps.htop', parent: 'apps', kind: 'app', label: 'Htop', description: 'Process Viewer', aliases: ['Process Viewer', 'system', 'process'] }
])
// MCDC SW-REQ-260922-PRNV: exact_id_match=T, route_input=T, route_is_exact_id=T => TRUE
// MCDC SW-REQ-260922-CYB9: alias_match=T, exact_id_match=T, route_input=T, route_is_alias_target=F => TRUE [no-action: the exact id returns before the alias loop runs]
// MCDC SW-REQ-260922-74BZ: alias_match=F, exact_id_match=T, route_input=T, route_is_literal_input=F => TRUE [no-action: the exact id returns before any fallthrough]
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'system'), 'system', 'menu routes an exact id even when an app keyword matches it')
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'process'), 'process', 'menu never routes to an app row through its keywords')
// MCDC SW-REQ-260922-CYB9: alias_match=T, exact_id_match=F, route_input=T, route_is_alias_target=T => TRUE
// MCDC SW-REQ-260922-PRNV: exact_id_match=F, route_input=T, route_is_exact_id=F => TRUE [no-action: the alias matches no item id -- the exact-id path is not taken]
// MCDC SW-REQ-260922-74BZ: alias_match=T, exact_id_match=F, route_input=T, route_is_literal_input=F => TRUE [no-action: the alias match routes to its target -- the literal fallthrough is not taken]
// MCDC SYS-REQ-260922-R8DQ: route_given=T, routed_to_intended_item=T => TRUE
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'power-menu'), 'system', 'menu routes declared aliases to their item')
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'power_menu'), 'system', 'menu normalizes underscores in routes')
// MCDC SW-REQ-260922-PRNV: exact_id_match=T, route_input=F, route_is_exact_id=F => TRUE [no-action: empty input routes to root before any id lookup runs]
// MCDC SW-REQ-260922-CYB9: alias_match=T, exact_id_match=F, route_input=F, route_is_alias_target=F => TRUE [no-action: empty input routes to root before any alias lookup runs]
// MCDC SW-REQ-260922-74BZ: alias_match=F, exact_id_match=F, route_input=F, route_is_literal_input=F => TRUE [no-action: empty input routes to root -- the literal fallthrough is not taken]
// MCDC SYS-REQ-260922-R8DQ: route_given=F, routed_to_intended_item=F => TRUE [no-action: empty input routes to root -- no route is given]
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, ''), 'root', 'menu routes empty input to root')
// MCDC SW-REQ-260922-74BZ: alias_match=F, exact_id_match=F, route_input=T, route_is_literal_input=T => TRUE
// MCDC SW-REQ-260922-CYB9: alias_match=F, exact_id_match=F, route_input=T, route_is_alias_target=F => TRUE [no-action: no alias matches -- the alias loop finds nothing and the input falls through]
assertEqual(menu.resolveRoute(routed.items, routed.itemOrder, 'no-such-route'), 'no-such-route', 'menu falls through to the literal input')
assert(menu.matchesQuery(routed.items['apps.htop'], 'system', true), 'menu still finds an app by its keywords in search')
assert(
  /function resolveRoute\(input\) \{\s*\n\s*return MenuModel\.resolveRoute\(root\.items, root\.itemOrder, input\)\s*\n\s*\}/.test(menuQml),
  'menu delegates route resolution to the shared model'
)
const triggerItems = defaultItems.filter(item => item.parent === 'trigger')
assertEqual(
  triggerItems[0].id,
  'trigger.emoji',
  'menu lists Emoji first under Trigger'
)
assertEqual(
  defaultById['trigger.emoji'].action,
  'omarchy-menu-emoji',
  'menu opens the emoji picker from Trigger'
)
assert(
  defaultById['update.omarchy'].icon === '\ue900',
  'menu update Omarchy entry uses the Omarchy glyph'
)
assert(
  defaultById['update.omarchy'].iconFont === 'omarchy',
  'menu update Omarchy entry renders the private glyph with the Omarchy font'
)
assertEqual(
  defaultById['update.themes'].when,
  'omarchy-theme-extras',
  'menu hides Extra Themes until a theme cloned from git is there to update'
)
assert(
  defaultById['setup.input'].action.includes('input.lua'),
  'menu keeps Input as a direct config action'
)
assert(
  defaultById['setup.direct-boot'].action.includes('omarchy-setup-direct-boot'),
  'menu places Direct Boot directly under Setup'
)
assert(
  defaultById['setup.reset'].action.includes('omarchy-system-factory-reset'),
  'menu exposes Reset Computer under Setup'
)
const setupEntries = defaultItems.filter(item => item.parent === 'setup')
assertEqual(
  setupEntries[setupEntries.length - 1].id,
  'setup.reset',
  'menu lists Reset Computer last under Setup'
)
const expectedAgents = {
  agy: { icon: '󰫢', label: 'Antigravity' },
  pi: { icon: '\ue901', iconFont: 'omarchy', label: 'Pi' },
  omp: { icon: '\ue903', iconFont: 'omarchy', label: 'omp' },
  opencode: { icon: '\ue902', iconFont: 'omarchy', label: 'OpenCode' },
  ori: { icon: '\ue909', iconFont: 'omarchy', label: 'Ori' },
  claude: { icon: '󰛄', label: 'Claude' },
  codex: { icon: '\ue905', iconFont: 'omarchy', label: 'Codex' },
  grok: { icon: '\ue904', iconFont: 'omarchy', label: 'Grok' },
  hermes: { icon: '\ue90a', iconFont: 'omarchy', label: 'Hermes' },
  openclaw: { icon: '\ue90c', iconFont: 'omarchy', label: 'OpenClaw' },
  copilot: { icon: '', label: 'Copilot' },
  crush: { icon: '󰋑', label: 'Crush' },
  muse: { icon: '󰛤', label: 'Muse Code' },
  'cursor-agent': { icon: '\ue90d', iconFont: 'omarchy', label: 'Cursor CLI' },

}
assert(
  Object.entries(expectedAgents).every(([agent, expected]) => {
    const entry = defaultById[`setup.default.agent.${agent}`]
    return entry
      && entry.icon === expected.icon
      && entry.iconFont === (expected.iconFont || '')
      && entry.label === expected.label
      && entry.action === `omarchy-default-agent ${agent}`
      && !entry.when
      && entry.checked.includes(`== \"${agent}\"`)
  }),
  'menu exposes every supported coding agent with its own glyph under Defaults > Agent'
)
assertDeepEqual(
  defaultItems
    .filter(item => item.parent === 'setup.default.agent')
    .map(item => item.label),
  ['Antigravity', 'Claude', 'Codex', 'Copilot', 'Crush', 'Cursor CLI', 'Grok', 'Hermes', 'Muse Code', 'omp', 'OpenClaw', 'OpenCode', 'Ori', 'Pi'],
  'menu sorts coding agents alphabetically'
)
const expectedDefaults = {
  browser: ['Chromium', 'Chrome', 'Brave', 'Brave Origin', 'Edge', 'Firefox', 'Zen'],
  terminal: ['Alacritty', 'Foot', 'Ghostty', 'Kitty'],
  editor: ['Neovim', 'VSCode', 'Cursor', 'Zed', 'Sublime Text', 'Helix', 'Vim', 'Emacs']
}
assert(
  Object.entries(expectedDefaults).every(([type, labels]) => {
    const entries = defaultItems.filter(item => item.parent === `setup.default.${type}`)
    return entries.map(item => item.label).join('\0') === labels.join('\0')
      && entries.every(item => !item.when)
  }),
  'menu always exposes every supported browser, terminal, and editor under Defaults'
)
assert(!defaultById['install.ai.crush'], 'menu removes Crush from Install > AI')
// Software you already have keeps its place in Install, dimmed rather than
// dropped, so the list reads as a catalog of what Omarchy can install.
// Chromium Account is the sole Install row with anything left to hide for, so
// any other `when:` here is a row that went back to vanishing once installed.
assertDeepEqual(
  defaultItems
    .filter(item => item.id.startsWith('install.') && item.action && item.when)
    .map(item => item.id),
  ['install.service.chromium-account'],
  'menu never hides an Install row because the software is already there'
)
assert(
  ['install.browser.zen', 'install.editor.vscode', 'install.gaming.steam', 'install.development.rust', 'install.windows'].every(
    id => defaultById[id].disabled && !defaultById[id].when
  ),
  'menu dims the Install rows for software that is already installed'
)
assertEqual(
  defaultById['install.browser.zen'].disabled,
  'omarchy-pkg-present zen-browser-bin',
  'menu asks the same presence question it used to hide the row with'
)
// A guard can still be about something other than having the software: no
// Chromium at all means no account to wire up, and that row stays hidden.
assert(
  defaultById['install.service.chromium-account'].when === '[[ -f ~/.config/chromium-flags.conf ]]'
    && defaultById['install.service.chromium-account'].disabled.includes('oauth2-client-id'),
  'menu keeps hiding Chromium Account without Chromium, and dims it once the account is set up'
)
assert(
  defaultItems.filter(item => item.id.startsWith('remove.')).every(item => !item.disabled)
    && defaultById['remove.browser.zen'].when === 'omarchy-pkg-present zen-browser-bin',
  'menu still hides Remove rows for software that is not installed'
)
assertDeepEqual(
  defaultItems
    .filter(item => item.parent === 'remove')
    .map(item => item.id),
  [
    'remove.package',
    'remove.ai',
    'remove.service',
    'remove.development',
    'remove.theme',
    'remove.gaming',
    'remove.browser',
    'remove.webapp',
    'remove.tui',
    'remove.windows',
    'remove.preinstalls',
    'remove.security'
  ],
  'menu orders Remove categories like their Install counterparts, followed by Remove-only categories'
)
assert(
  defaultById['setup.security.passwordless-sudo'].action.includes('omarchy-sudo-passwordless'),
  'menu places Passwordless Sudo under Setup > Security'
)
assert(
  !defaultById['trigger.toggle.direct-boot'] && !defaultById['trigger.toggle.passwordless-sudo'],
  'menu removes the relocated toggles from Trigger > Toggle'
)
assert(
  defaultById['style.bar.position'].kind === 'menu',
  'menu groups Menu Bar positions in a submenu'
)
assert(
  ['top', 'bottom', 'left', 'right'].every(position => defaultById[`style.bar.position.${position}`].action === `omarchy-bar position ${position}`),
  'menu lists all Menu Bar positions under Position'
)
assertEqual(
  defaultById['style.bar.transparency'].action,
  'omarchy-bar transparent toggle',
  'menu exposes Menu Bar transparency as a toggle'
)
assertDeepEqual(
  defaultItems.filter(item => item.parent === 'setup.plugin').map(item => item.label),
  ['Enable Plugin', 'Disable Plugin', 'Add Plugin', 'Clone Plugin', 'Remove Plugin'],
  'menu manages plugins from Setup > Plugins'
)
assert(
  ['enable', 'disable', 'clone', 'remove'].every(
    verb => defaultById[`setup.plugin.${verb}`].action === `omarchy-menu-plugin ${verb}`
  ),
  'menu picks a plugin the way it already picks a theme or a timezone'
)
assert(
  !defaultById['setup.plugin.enable'].when && !defaultById['setup.plugin.disable'].when,
  'menu always offers Enable and Disable, which cover the built-in plugins too'
)
assert(
  defaultById['setup.plugin.remove'].when.includes('.config/omarchy/plugins'),
  'menu hides Remove until a plugin the user installed exists to delete'
)
assert(
  defaultById['setup.plugin.add'].action.includes('omarchy-plugin-add'),
  'menu adds a plugin through the CLI, where the trust warning and clone output are visible'
)

const pluginPicker = fs.readFileSync(path.join(root, 'bin/omarchy-menu-plugin'), 'utf8')
assert(
  /enable\).*\(\.enabled \| not\)/.test(pluginPicker) && /disable\).*\.canDisable and \.enabled/.test(pluginPicker),
  'plugin picker offers what each verb can act on'
)
assert(
  /remove\).*\(\.firstParty \| not\)/.test(pluginPicker)
    && /clone\).*\.firstParty/.test(pluginPicker)
    && !/kinds|bar-widget|A_BAR_OPTION|NOT_A_BAR_OPTION|BAR_ICON/.test(pluginPicker),
  'plugin picker leaves plugin-kind decisions to its data and the plugin command'
)

const pluginAdd = fs.readFileSync(path.join(root, 'bin/omarchy-plugin-add'), 'utf8')
const pluginEnable = fs.readFileSync(path.join(root, 'bin/omarchy-plugin-enable'), 'utf8')
assert(
  /Now using \$id as the bar/.test(pluginEnable)
    && /omarchy-plugin-enable "\$id" "\$\{ENABLE_PLACEMENT\[@\]\}"/.test(pluginAdd),
  'plugin enable reports a bar as replacing the one in use, whether enabled or freshly added'
)
assert(
  /\.barWidget\.defaultSection \/\/ "center"/.test(pluginAdd)
    && /gum choose[\s\S]*?--selected "\$default_section"/.test(pluginAdd),
  'interactive plugin add selects the manifest placement or center fallback by default'
)
assert(
  /"omarchy-plugin-\$1" "\$id"/.test(pluginPicker),
  'plugin picker delegates enable and disable without interpreting plugin kinds'
)
// Icons ride along as "<glyph>\tlabel\tsubtext"; the menu shows the glyph,
// renders the subtext under the label, and hands back "label\tsubtext" so the
// picker can act on the id without resolving a display name. What the picker
// then does with the row it gets back is checked in menu-plugin-test.sh.
assert(
  /\.name \+ \\"\\\\t\\" \+ \.id/.test(pluginPicker)
    && /id=\$\(cut -f2 <<<"\$selection"\)/.test(pluginPicker),
  'plugin picker shows the id as row subtext and acts on the id the selection hands back'
)
assert(
  /var icon = parts\.length > 1 \? parts\.shift\(\) : ""\s*\n\s*var label = parts\.shift\(\) \|\| ""\s*\n\s*var detail = parts\.join\("\\t"\)/.test(menuQml),
  'menu select mode reads a leading icon and a trailing subtext off an option'
)
assert(
  /omarchy-launch-floating-terminal-with-presentation "omarchy-plugin-remove/.test(pluginPicker),
  'plugin picker removes where the confirmation and backup path are visible'
)

// A font installed since the shell started should show up without a restart.
const providerBlock = menuQml.match(/readonly property var providers: \(\{[\s\S]*?\n  \}\)/)[0]
assert(
  /"fonts": \{[\s\S]*?volatile: true/.test(providerBlock),
  'menu re-enumerates the font list every time it is opened'
)
assert(
  /function setActiveMenu\([\s\S]*?root\.invalidateVolatileProvider\(id\)\s*\n\s*root\.loadProviderForMenu\(id\)/.test(menuQml)
    && /function openExistingMenu\([\s\S]*?invalidateVolatileProvider\(activeMenu\)\s*\n\s*loadProviderForMenu\(activeMenu\)/.test(menuQml),
  'menu invalidates volatile providers when entering a menu, not on every keystroke'
)
assert(
  ['loadProviderForMenu', 'loadProvidersForSearch'].every(
    name => !menuQml.match(new RegExp(`function ${name}\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}`))[1].includes('invalidateVolatileProvider')
  ),
  'menu search never restarts a volatile provider'
)
assertEqual(
  defaultById['trigger.hardware.laptop-display'].when,
  'omarchy-hw-laptop',
  'menu only shows Laptop Display on laptops'
)
assertEqual(
  defaultById['trigger.hardware.mirror-display'].when,
  'omarchy-hw-laptop',
  'menu only shows Mirror Display on laptops'
)
assertEqual(
  defaultById['trigger.capture.screenrecord.webcam'].when,
  'omarchy-hw-webcam',
  'menu only shows webcam screen recording when a webcam is available'
)
assert(
  /font\.family: row\.iconFont\.length > 0 \? row\.iconFont : root\.fontFamily/.test(menuQml),
  'menu rows support per-icon font families'
)

assert(
  /function select\(delta\)[\s\S]*root\.disarmPointer\(\)[\s\S]*selectedIndex =/.test(menuQml),
  'menu keyboard navigation disarms pointer selection'
)
// A dimmed row is not a target: the cursor steps over it, the pointer refuses
// to land on it, and neither Enter nor a click can reach it.
assert(
  /function select\(delta\)[\s\S]*?var target = root\.nextSelectable\(from, delta\)\s*\n\s*if \(target < 0\) return/.test(menuQml),
  'menu keyboard navigation skips disabled rows in the direction of travel'
)
assert(
  /function rowSelectable\(index\)[\s\S]*?return !displayModel\.get\(index\)\.disabled/.test(menuQml),
  'menu reads selectability off the row'
)
assert(
  /function activateIndex\(index, fromPointer\)[\s\S]*?if \(!root\.rowSelectable\(index\)\) return/.test(menuQml),
  'menu refuses to activate a disabled row'
)
assert(
  /function selectFromPointer\(index, item, mouse\)[\s\S]*?if \(!root\.rowSelectable\(index\)\) return/.test(menuQml)
    && /onClicked: \{\s*\n\s*if \(row\.disabled\) return/.test(menuQml),
  'menu leaves the cursor put when the pointer crosses a disabled row'
)
assert(
  /opacity: row\.disabled \? 0\.4 : 1/.test(menuQml) && !/font\.italic/.test(menuQml),
  'menu renders a disabled row faded, and leaves it at that'
)
assert(
  /function rebuildDisplay\(\)[\s\S]*?root\.settleCursor\(\)/.test(menuQml),
  'menu parks the cursor on a selectable row after the rows change'
)
// A menu with nothing selectable in it has no cursor, and Return must not
// conjure one onto a disabled row just because rows exist.
assert(
  /function settleCursor\(\)[\s\S]*?root\.cursorActive = target >= 0/.test(menuQml)
    && /else if \(root\.cursorActive\) root\.activateIndex\(root\.selectedIndex\)\s*\n\s*else root\.settleCursor\(\)/.test(menuQml),
  'menu ties the cursor to a selectable row existing, both ways'
)
assert(
  /function setFilter\(nextFilter\)[\s\S]*root\.disarmPointer\(\)/.test(menuQml),
  'menu filter changes disarm pointer selection'
)
assert(
  /function setActiveMenu\(id, pushHistory, fromPointer\)[\s\S]*if \(fromPointer\) pointerGate\.allowInitialSample\(\)\s*else root\.disarmPointer\(\)/.test(menuQml),
  'menu route changes only accept an initial pointer sample for mouse activation'
)
assert(
  /\(event\.key === Qt\.Key_Backspace \|\| event\.key === Qt\.Key_Left\) && !root\.filterText[\s\S]*root\.goBack\(\)/.test(menuQml),
  'menu Left key follows empty-filter Backspace navigation'
)
assert(
  /PointerMoveGate\s*\{[\s\S]*id: pointerGate[\s\S]*referenceItem: card[\s\S]*\}/.test(menuQml),
  'menu uses shared pointer movement gate in card coordinates'
)
assert(
  /function disarmPointer\(\)[\s\S]*pointerGate\.reset\(\)/.test(menuQml),
  'menu resets pointer movement gate when pointer selection is disarmed'
)
// App rows are rebuilt from scratch on every desktop-entry rescan. The merge
// must be idempotent and must never carry an orphan id forward, or a single
// lost write turns into an app listed twice (and thrice, and so on).
const nonAppItems = {
  root: { id: 'root', kind: 'menu', label: 'Go' },
  apps: { id: 'apps', kind: 'menu', label: 'Apps', provider: 'apps' }
}
const nonAppOrder = ['root', 'apps']
const appRowsFor = ids => ids.map(id => ({ id: `apps.${id}`, kind: 'app', parent: 'apps', label: id, appId: id }))

const firstMerge = menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['alacritty', 'youtube']))
// MCDC SW-REQ-260922-Z680: id_listed_once=F, inputs_not_mutated=F, orphan_id_present=F, orphans_dropped=F, provider_reran=F => TRUE [no-action: the first merge starts from a clean map and order -- no orphan exists to drop and no provider batch is rerun]
assert(
  firstMerge.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube',
  'app merge appends app rows after the static menu items'
)

const secondMerge = menu.mergeAppRows(firstMerge.items, firstMerge.itemOrder, appRowsFor(['alacritty', 'youtube']))
assert(
  secondMerge.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube',
  'repeating the app merge with the same entries does not duplicate rows'
)

assert(
  menu.mergeAppRows(secondMerge.items, secondMerge.itemOrder, appRowsFor(['alacritty'])).itemOrder.join(',')
    === 'root,apps,apps.alacritty',
  'app merge drops rows for entries that went away'
)

assert(
  menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['youtube', 'youtube'])).itemOrder.join(',')
    === 'root,apps,apps.youtube',
  'app merge lists an app once even when two desktop entries share an id'
)

const orphanedItems = {}
for (const key in firstMerge.items) orphanedItems[key] = firstMerge.items[key]
delete orphanedItems['apps.youtube']
const healed = menu.mergeAppRows(orphanedItems, firstMerge.itemOrder, appRowsFor(['alacritty', 'youtube']))
// MCDC SW-REQ-260922-Z680: id_listed_once=T, inputs_not_mutated=T, orphan_id_present=T, orphans_dropped=T, provider_reran=T => TRUE
assert(
  healed.itemOrder.join(',') === 'root,apps,apps.alacritty,apps.youtube'
    && !!healed.items['apps.youtube']
    && Object.keys(orphanedItems).length === 3
    && !orphanedItems['apps.youtube'],
  'app merge heals an order entry whose item went missing instead of duplicating it'
)

assert(
  !firstMerge.items['apps.youtube'].hasOwnProperty('__probe')
    && (() => {
      const before = Object.keys(nonAppItems).length
      menu.mergeAppRows(nonAppItems, nonAppOrder, appRowsFor(['gimp']))
      return Object.keys(nonAppItems).length === before
    })(),
  'app merge leaves the map it was handed untouched'
)

const providerRowsFor = values => values.map(value => ({ id: `style.font.${value}`, kind: 'action', parent: 'style.font', label: value }))
const firstProviderMerge = menu.swapProviderRows(nonAppItems, nonAppOrder, 'style.font', providerRowsFor(['mono', 'serif']))
// MCDC SW-REQ-260922-EFNR: previous_batch_replaced=F, provider_reran=F => TRUE [no-action: the first provider merge starts from a map with no style.font rows -- no previous batch exists to replace]
// MCDC SYS-REQ-260922-0M8A: dynamic_rows_swapped=T, provider_rows_arrive=T => TRUE
assert(
  firstProviderMerge.itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'provider merge appends its rows'
)
assert(
  menu.swapProviderRows(firstProviderMerge.items, firstProviderMerge.itemOrder, 'style.font', providerRowsFor(['mono', 'serif']))
    .itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'repeating a provider merge does not duplicate rows'
)
// A plugin drops out of the Enable list the moment it is enabled, so a
// provider that runs again has to lose the rows it contributed last time.
const rerunProviderMerge = menu.swapProviderRows(firstProviderMerge.items, firstProviderMerge.itemOrder, 'style.font', providerRowsFor(['serif']))
// MCDC SW-REQ-260922-EFNR: previous_batch_replaced=T, provider_reran=T => TRUE
assert(
  rerunProviderMerge.itemOrder.join(',') === 'root,apps,style.font.serif',
  'provider merge drops rows the provider no longer lists'
)
// MCDC SYS-REQ-260922-0M8A: dynamic_rows_swapped=F, provider_rows_arrive=F => TRUE [no-action: an empty batch swaps zero rows -- the existing rows pass through untouched]
assert(
  menu.swapProviderRows(firstProviderMerge.items, firstProviderMerge.itemOrder, 'style.other', providerRowsFor([]))
    .itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'provider merge leaves rows belonging to another provider alone'
)
// Rows are keyed by id, so a provider handing over two rows with the same id
// would lose one. Distinct plugin ids can slugify alike, which is why the
// menu makes each row id its own before merging.
assertEqual(
  ['acme.foo', 'acme_foo', 'acme-foo'].map(menu.slugify).join(','),
  'acme-foo,acme-foo,acme-foo',
  'menu slugs collide across plugin ids that differ only in separator'
)
assert(
  /var rowId = menuId \+ "\." \+ root\.slugify\(value\)\s*\n\s*while \(takenIds\[rowId\]\) rowId \+= "-"/.test(menuQml),
  'menu keeps colliding provider rows apart so none is dropped'
)

// The maps live in QML `var` properties, where an in-place write is
// occasionally dropped by the engine, so both merges must hand back fresh
// objects for the caller to assign in one shot.
assert(
  /var merged = MenuModel\.mergeAppRows\(root\.items, root\.itemOrder, appRows\)\s*\n\s*root\.items = merged\.items\s*\n\s*root\.itemOrder = merged\.itemOrder/.test(menuQml),
  'menu assigns the rebuilt app item map instead of mutating it in place'
)
assert(
  /var merged = MenuModel\.swapProviderRows\(root\.items, root\.itemOrder, menuId, providerRows\)\s*\n[\s\S]*?root\.items = merged\.items\s*\n\s*root\.itemOrder = merged\.itemOrder/.test(menuQml),
  'menu assigns the rebuilt provider item map instead of mutating it in place'
)
assert(
  !/root\.items\[[^\]]+\] =/.test(menuQml) && !/delete root\.items\[/.test(menuQml),
  'menu never writes into the item map held by the var property'
)

for (const functionName of ['openExistingMenu', 'openDmenu']) {
  const openMatch = menuQml.match(new RegExp(`function ${functionName}\\([^)]*\\) \\{([\\s\\S]*?)\\n  \\}`))
  assert(openMatch, `menu ${functionName} function exists`)
  assert(
    openMatch[1].indexOf('root.disarmPointer()') < openMatch[1].indexOf('opened = true')
      && !openMatch[1].includes('pointerGate.allowInitialSample()'),
    `menu ${functionName} ignores a stale hidden-pointer position when becoming visible`
  )
}
assert(
  /function selectFromPointer\(index, item, mouse\)[\s\S]*pointerGate\.moved\(item, mouse\)[\s\S]*root\.selectedIndex = index/.test(menuQml),
  'menu only selects from pointer after real movement'
)
assert(
  /onPositionChanged: function\(mouse\) \{\s*root\.selectFromPointer\(row\.index, row, mouse\)\s*\}/.test(menuQml),
  'menu row hover routes through pointer movement gate'
)
assert(
  /onEntered: root\.selectFromPointer\(row\.index, row, \{\s*x: mouseArea\.mouseX,\s*y: mouseArea\.mouseY\s*\}\)/.test(menuQml),
  'menu samples pointer movement immediately when entering a row'
)
assert(
  /function activateIndex\(index, fromPointer\)[\s\S]*root\.setActiveMenu\(row\.target \|\| row\.itemId, true, fromPointer\)/.test(menuQml)
    && /onClicked:[\s\S]*root\.activateIndex\(row\.index, true\)/.test(menuQml),
  'mouse activation carries pointer intent into subordinate menus'
)

// WC89: menu -> lock interface contract. The default config's Lock row
// carries action "omarchy-system-lock" verbatim, and openRoute runs action
// rows through Util.execDetached (REVIEW-28).
const defaultEntries = menu.parseMenuJsonc(defaultMenuJsonc)
const entryById = {}
for (const e of defaultEntries) entryById[e.id] = e
// MCDC SYS-REQ-260927-WC89: lock_row_activated=T, system_lock_invoked=T => TRUE
assert(
  entryById['system.lock'] && entryById['system.lock'].action === 'omarchy-system-lock',
  'menu Lock row invokes the lock component entry point omarchy-system-lock'
)
assert(
  /function openRoute\(initialMenu\)[\s\S]*entry\.kind === "action" && entry\.action[\s\S]*root\.runAction\(entry\.action\)/.test(menuQml)
    && /function runAction\(action\)[\s\S]*Util\.execDetached\(command\)/.test(menuQml),
  'menu action rows exec their action as a subprocess'
)
// MCDC SYS-REQ-260927-WC89: lock_row_activated=F, system_lock_invoked=F => TRUE [no-action: the other system.* rows carry their own actions (systemctl suspend et al.) -- no lock invocation occurs without the Lock row]
assert(
  entryById['system.suspend'] && entryById['system.suspend'].action === 'systemctl suspend',
  'menu non-lock rows carry no lock invocation'
)
})

// ---------------------------------------------------------------------------
// Preservation: upstream e332dc97 parses its documented JSONC grammar (object
// root, whole-line // comments, trailing commas, strings that never carry a
// comma followed by } or ]) to exactly the declared entries. Seeded
// differential property test against an independent reference model: drop
// whole comment lines, then drop (string-aware) each comma whose next
// significant character closes. Pins the comment-then-comma order that a
// single-pass scanner (omacom/omarchy#13512) broke for 1,021 of 20,000 inputs.
// The off-grammar shapes are known issues: KI-MENU-JSONC-COMMA-IN-STRING,
// KI-MENU-JSONC-INLINE-COMMENT, KI-MENU-JSONC-ARRAY-ROOT,
// KI-MENU-JSONC-STRIP-GAPS.
// ---------------------------------------------------------------------------
// Verifies: SW-REQ-260922-E4J2, SW-REQ-260922-3T3F
test('jsonc preservation: seeded differential property over the documented grammar', () => {
  let seed = 12345
  const rnd = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return ((seed >>> 0) % 1e6) / 1e6 }
  const pick = a => a[Math.floor(rnd() * a.length)]
  const STR = ['a', 'A // B', 'q\\"', 'http://x', 'q\\\\', '\u00e9\u2014\u2713', '', 'a, b', 'x ]y', '{"k": 1}', '// not a comment']
  const str = () => JSON.stringify(pick(STR))
  const ws = () => pick(['', ' ', '\n', '\n  ', '\r\n', '\t'])
  const cm = () => rnd() < 0.3 ? '\n' + pick(['', '  ', '\t']) + pick(['// full line', '// c, } ]', '//', '// "quoted', '// x\r']) + '\n' : ws()
  function gen() {
    const n = 1 + Math.floor(rnd() * 3)
    let o = (rnd() < 0.2 ? '// head\n' : '') + '{' + cm()
    for (let i = 0; i < n; i++) {
      o += JSON.stringify('k' + i) + ':' + ws() + '{' + cm() + '"label":' + ws() + str()
        + (rnd() < 0.4 ? ',' + cm() + '"aliases":' + ws() + '[' + cm() + str() + (rnd() < 0.5 ? ',' + cm() : cm()) + ']' : '')
        + (rnd() < 0.4 ? ',' + cm() : cm()) + '}'
      o += i < n - 1 ? ',' + cm() : (rnd() < 0.5 ? ',' + cm() : cm())
    }
    return o + '}' + (rnd() < 0.3 ? '\n// tail line' : '')
  }
  function reference(text) {
    const kept = text.split('\n').filter(line => !/^\s*\/\//.test(line)).join('\n')
    let out = ''
    let inString = false
    for (let i = 0; i < kept.length; i++) {
      const c = kept[i]
      if (inString) { out += c; if (c === '\\') out += kept[++i]; else if (c === '"') inString = false }
      else if (c === '"') { inString = true; out += c }
      else if (c === ',') { let j = i + 1; while (j < kept.length && /\s/.test(kept[j])) j++; if (kept[j] !== '}' && kept[j] !== ']') out += c }
      else out += c
    }
    const doc = JSON.parse(out)
    return Object.keys(doc).map(k => k + '=' + (doc[k].label || k) + '|' + JSON.stringify((doc[k].aliases || []).filter(x => x))).join(';')
  }
  let wrong = 0
  let first = ''
  for (let k = 0; k < 2000; k++) {
    const src = gen()
    const want = reference(src)
    const got = menuModel.parseMenuJsonc(src).map(r => r.id + '=' + r.label + '|' + JSON.stringify(r.aliases)).join(';')
    if (got !== want) { wrong++; if (!first) first = JSON.stringify({ src, want, got }) }
  }
  assertEqual(wrong, 0, 'parseMenuJsonc matches the reference model on 2000 seeded inputs of the documented grammar' + (first ? ' -- first: ' + first : ''))
})
// ---------------------------------------------------------------------------
// MC/DC unique-cause cases for MenuModel.js (quattro, code_mcdc target
// menu-js-menumodel). One test block per function; every decision arm and
// every condition outcome is driven through the exported public API with
// plain data arguments — no getters, no private reflection.
// ---------------------------------------------------------------------------

test('mcdc stripJsonc: the two regex passes and the empty-input fallback', () => {
  // raw || "": a missing input strips to the empty string (both arms).
  assertEqual(menuModel.stripJsonc(undefined), '', 'stripJsonc treats a missing input as empty')
  assertEqual(menuModel.stripJsonc('{}'), '{}', 'stripJsonc passes comment-free, comma-free input through')
  // Pass 1: a whole-line comment goes with its line break, indented or not.
  assertEqual(menuModel.stripJsonc('// a\n  // b\n{}'), '{}', 'stripJsonc drops whole-line comments with their line breaks')
  // Pass 2: a comma before } or ] across whitespace is dropped; before anything else it stays.
  assertEqual(menuModel.stripJsonc('{"a": 1 , }'), '{"a": 1  }', 'stripJsonc drops a comma whose next non-whitespace is a brace')
  assertEqual(menuModel.stripJsonc('["a", ]'), '["a" ]', 'stripJsonc drops a comma whose next non-whitespace is a bracket')
  assertEqual(menuModel.stripJsonc('{"a": 1 ,"b": 2}'), '{"a": 1 ,"b": 2}', 'stripJsonc keeps a comma before another entry')
  assertEqual(menuModel.stripJsonc('{"a": 1,'), '{"a": 1,', 'stripJsonc keeps a comma at end of input')
  // Order: comments go first, so a comma separated from its closer only by comment lines is dropped.
  assertEqual(menuModel.stripJsonc('[1,\n// c\n]'), '[1\n]', 'stripJsonc drops a trailing comma separated from its closer by a whole-line comment')
  // Reproduces: KI-MENU-JSONC-INLINE-COMMENT
  assertEqual(menuModel.stripJsonc('{"a": 1} // tail'), '{"a": 1} // tail', 'KI-MENU-JSONC-INLINE-COMMENT tripwire: stripJsonc leaves an inline comment tail in place')
  // Reproduces: KI-MENU-JSONC-COMMA-IN-STRING
  assertEqual(menuModel.stripJsonc('{"a": "x, ]y"}'), '{"a": "x ]y"}', 'KI-MENU-JSONC-COMMA-IN-STRING tripwire: stripJsonc drops a comma inside a string literal')
})

test('mcdc normalizeAliases: array, string, empty, non-string', () => {
  assertDeepEqual(menuModel.normalizeAliases(['a', '', null, 'b']), ['a', 'b'], 'normalizeAliases drops falsy array elements')
  assertDeepEqual(menuModel.normalizeAliases('theme'), ['theme'], 'normalizeAliases wraps a nonempty string')
  assertDeepEqual(menuModel.normalizeAliases(''), [], 'normalizeAliases rejects an empty string')
  assertDeepEqual(menuModel.normalizeAliases(5), [], 'normalizeAliases rejects a non-string non-array')
})

test('mcdc normalizeItem: parent inference edges', () => {
  assertEqual(menuModel.normalizeItem('a.b', { parent: 'custom', label: 'X' }).parent, 'custom', 'normalizeItem keeps a declared parent')
  assertEqual(menuModel.normalizeItem('a.b', { label: 'X' }).parent, 'a', 'normalizeItem derives a dotted parent')
  assertEqual(menuModel.normalizeItem('plain', { label: 'X' }).parent, 'root', 'normalizeItem parents a dotless id to root')
  assertEqual(menuModel.normalizeItem('root', { label: 'Go' }).parent, '', 'normalizeItem strips the parent of root itself')
})

// SW-REQ-260922-3T3F:error_handling:negative -- non-object roots and null/scalar/array entries yield an empty or skipped item set
test('mcdc parseMenuJsonc: scalar, null, and malformed item shapes', () => {
  assertEqual(menuModel.parseMenuJsonc('42').length, 0, 'parseMenuJsonc rejects a number root')
  assertEqual(menuModel.parseMenuJsonc('null').length, 0, 'parseMenuJsonc rejects a null root')
  assertEqual(menuModel.parseMenuJsonc('{"items": 5}').length, 0, 'parseMenuJsonc falls back to the root when items is a scalar')
  assertEqual(menuModel.parseMenuJsonc('{"items": [1]}').length, 0, 'parseMenuJsonc falls back to the root when items is an array')
  assertEqual(menuModel.parseMenuJsonc('{"a": {"label": "A"}}').length, 1, 'parseMenuJsonc uses the root object when items is absent')
  assertEqual(menuModel.parseMenuJsonc('{"a": null}').length, 0, 'parseMenuJsonc skips a null entry')
  assertEqual(menuModel.parseMenuJsonc('{"a": 5}').length, 0, 'parseMenuJsonc skips a scalar entry')
  assertEqual(menuModel.parseMenuJsonc('{"a": []}').length, 0, 'parseMenuJsonc skips an array entry')
  assertEqual(menuModel.parseMenuJsonc('{"a": {"label": "A"}, "b": {"label": "B"}}').length, 2, 'parseMenuJsonc keeps object entries')
})

// SYS-REQ-260922-PPDW:error_handling:negative -- null and id-less source entries are skipped; the tree still merges
// SYS-REQ-260922-PPDW:boundary:nominal -- null (absent) sources merge as empty lists to a tree holding only the injected root
test('mcdc mergeMenuSources: null entries, id-less entries, null sources', () => {
  const merged = menuModel.mergeMenuSources(
    [null, { label: 'no id' }, { id: 'a', label: 'A' }],
    [null, { id: 'b', label: 'B' }]
  )
  assertDeepEqual(merged.itemOrder, ['root', 'a', 'b'], 'mergeMenuSources skips null and id-less entries')
  assertEqual(merged.items.a.label, 'A', 'mergeMenuSources keeps well-formed entries')
  const nullSources = menuModel.mergeMenuSources(null, null)
  assertDeepEqual(nullSources.itemOrder, ['root'], 'mergeMenuSources treats null sources as empty lists')
})

test('mcdc mergeAppRows: non-array inputs, orphan and app carryover, row guards', () => {
  assertDeepEqual(menuModel.mergeAppRows({}, 'not-an-array', 'nope').itemOrder, [], 'mergeAppRows falls back to empty on non-array order and rows')
  assertDeepEqual(menuModel.mergeAppRows(null, ['ghost'], []).itemOrder, [], 'mergeAppRows treats a null item map as empty')
  assertDeepEqual(menuModel.mergeAppRows({ ap: { id: 'ap', kind: 'app', label: 'Z' } }, ['ap'], []).itemOrder, [], 'mergeAppRows drops app-kind rows from carryover')
  assertDeepEqual(menuModel.mergeAppRows({ st: { id: 'st', kind: 'menu', label: 'S' } }, ['ghost', 'st'], []).itemOrder, ['st'], 'mergeAppRows drops order ids with no item behind them')
  const dup = menuModel.mergeAppRows({ x: { id: 'x', kind: 'menu', label: 'X' } }, ['x'], [{ id: 'x', kind: 'app', label: 'R' }])
  assertDeepEqual(dup.itemOrder, ['x'], 'mergeAppRows never lets an incoming row displace a carried id')
  const guarded = menuModel.mergeAppRows({}, [], [{}, null, { id: 'x', kind: 'app', label: 'A' }, { id: 'x', kind: 'app', label: 'B' }])
  assertDeepEqual(guarded.itemOrder, ['x'], 'mergeAppRows skips null, id-less, and duplicate rows')
})

test('mcdc swapProviderRows: non-array inputs, orphans, provider matches, row guards', () => {
  assertDeepEqual(menuModel.swapProviderRows({}, 'nope', 'm', 'nope').itemOrder, [], 'swapProviderRows falls back to empty on non-array order and rows')
  assertDeepEqual(menuModel.swapProviderRows(null, ['ghost'], 'm', []).itemOrder, [], 'swapProviderRows treats a null item map as empty')
  assertDeepEqual(menuModel.swapProviderRows({}, ['ghost'], 'm', []).itemOrder, [], 'swapProviderRows drops order ids with no item behind them')
  assertDeepEqual(menuModel.swapProviderRows({ f: { id: 'f', providerMenu: 'm' } }, ['f'], 'm', []).itemOrder, [], 'swapProviderRows drops rows the same provider contributed')
  assertDeepEqual(menuModel.swapProviderRows({ k: { id: 'k' } }, ['k'], 'm', [{ id: 'k', label: 'R' }]).itemOrder, ['k'], 'swapProviderRows never lets an incoming row displace another row')
  const dup = menuModel.swapProviderRows({}, [], 'm', [{}, null, { id: 'r1' }, { id: 'r1' }])
  assertDeepEqual(dup.itemOrder, ['r1'], 'swapProviderRows skips null, id-less, and duplicate rows')
})

test('mcdc item: null map, miss, and hit', () => {
  assertEqual(menuModel.item(null, 'x'), null, 'item returns null for a null map')
  assertEqual(menuModel.item({}, 'x'), null, 'item returns null for a missing id')
  assertEqual(menuModel.item({ x: 'v' }, 'x'), 'v', 'item returns the stored value')
})

test('mcdc resolveRoute: go/menu literals, orphans, alias-less and app entries', () => {
  const routed = menuModel.mergeMenuSources(
    [
      { id: 'system', label: 'System', aliases: ['power-menu'] },
      { id: 'plain', label: 'Plain' },
      { id: 'sys', label: 'Sys', aliases: ['Other_Menu', null, ''] }
    ],
    []
  )
  routed.items['apps.htop'] = { id: 'apps.htop', kind: 'app', parent: 'apps', label: 'Htop', aliases: ['system'] }
  routed.itemOrder.push('apps.htop')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'go'), 'root', 'resolveRoute routes the go literal to root')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'menu'), 'root', 'resolveRoute routes the menu literal to root')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'Go'), 'root', 'resolveRoute normalizes case before literal checks')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'system'), 'system', 'resolveRoute prefers an exact id over an app keyword')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'power-menu'), 'system', 'resolveRoute matches a declared alias')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'other_menu'), 'sys', 'resolveRoute normalizes underscores in aliases and skips falsy alias entries')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'plain'), 'plain', 'resolveRoute returns an exact id for an alias-less entry')
  assertEqual(menuModel.resolveRoute(routed.items, routed.itemOrder, 'nowhere'), 'nowhere', 'resolveRoute falls through to the literal input')
  assertEqual(menuModel.resolveRoute({}, 'not-an-array', 'zz'), 'zz', 'resolveRoute treats a non-array order as empty')
  assertEqual(menuModel.resolveRoute(routed.items, ['ghost', 'plain'], 'zz'), 'zz', 'resolveRoute skips order ids with no item')
})

function mcdcChain(n, tail) {
  const items = {}
  for (let i = 1; i <= n; i++) {
    items['c' + i] = { id: 'c' + i, parent: i === 1 ? tail : 'c' + (i - 1), kind: 'menu', label: 'C' + i }
  }
  return items
}

test('mcdc depthFor: stop conditions and the 32-deep guard', () => {
  assertEqual(menuModel.depthFor({}, 'zz'), 0, 'depthFor returns 0 for a missing id')
  assertEqual(menuModel.depthFor({ x: { id: 'x', parent: '' } }, 'x'), 0, 'depthFor stops at an empty parent')
  assertEqual(menuModel.depthFor({ x: { id: 'x', parent: 'root' } }, 'x'), 0, 'depthFor stops at the root parent')
  assertEqual(menuModel.depthFor(mcdcChain(3, 'root'), 'c3'), 2, 'depthFor counts a two-step chain')
  assertEqual(menuModel.depthFor(mcdcChain(40, 'root'), 'c40'), 32, 'depthFor stops counting at the 32-deep guard')
})

test('mcdc pathFor: missing id, root stop, parent-less stop, guard cap', () => {
  assertEqual(menuModel.pathFor({}, 'zz'), '', 'pathFor returns empty for a missing id')
  const rooted = mcdcChain(3, 'root')
  rooted.root = { id: 'root', parent: '', kind: 'menu', label: 'Go' }
  assertEqual(menuModel.pathFor(rooted, 'c3'), 'C1 › C2 › C3', 'pathFor stops at the root item')
  assertEqual(menuModel.pathFor({ x: { id: 'x', parent: '', label: 'X' } }, 'x'), 'X', 'pathFor stops at an empty parent')
  const parts = menuModel.pathFor(mcdcChain(40, 'root'), 'c40').split(' › ')
  assertEqual(parts.length, 32, 'pathFor walks at most 32 links')
  assert(parts[0] === 'C9' && parts[31] === 'C40', 'pathFor walks from the id toward the root')
})

test('mcdc parentPathFor: missing id, root parent, empty parent, real path', () => {
  assertEqual(menuModel.parentPathFor({}, 'zz'), '', 'parentPathFor returns empty for a missing id')
  assertEqual(menuModel.parentPathFor({ x: { id: 'x', parent: '' } }, 'x'), '', 'parentPathFor returns empty for an empty parent')
  assertEqual(menuModel.parentPathFor({ x: { id: 'x', parent: 'root' } }, 'x'), '', 'parentPathFor returns empty for the root parent')
  const items = { y: { id: 'y', parent: 'root', kind: 'menu', label: 'Y' }, x: { id: 'x', parent: 'y', kind: 'menu', label: 'X' } }
  assertEqual(menuModel.parentPathFor(items, 'x'), 'Y', 'parentPathFor builds the parent chain')
})

test('mcdc isDescendantOf: root ancestor, missing id, chain walk, guard cap', () => {
  assertEqual(menuModel.isDescendantOf({}, 'style', 'root'), true, 'isDescendantOf treats every non-root id as a root descendant')
  assertEqual(menuModel.isDescendantOf({}, 'root', 'root'), false, 'isDescendantOf does not make root its own descendant')
  assertEqual(menuModel.isDescendantOf({}, 'zz', 'style'), false, 'isDescendantOf returns false for a missing id')
  const items = mcdcChain(3, 'root')
  assertEqual(menuModel.isDescendantOf(items, 'c2', 'c1'), true, 'isDescendantOf finds a direct parent')
  assertEqual(menuModel.isDescendantOf(items, 'c3', 'c1'), true, 'isDescendantOf finds an ancestor deeper in the chain')
  assertEqual(menuModel.isDescendantOf(items, 'c3', 'nope'), false, 'isDescendantOf walks to the end without a match')
  assertEqual(menuModel.isDescendantOf({ x: { id: 'x', parent: '' } }, 'x', 'nope'), false, 'isDescendantOf stops at an empty parent')
  assertEqual(menuModel.isDescendantOf(mcdcChain(40, ''), 'c40', 'c1'), false, 'isDescendantOf stops walking at the 32-deep guard')
})

test('mcdc childCount: non-array order, orphans, matching parents', () => {
  assertEqual(menuModel.childCount({}, 'nope', 'x'), 0, 'childCount treats a non-array order as empty')
  assertEqual(menuModel.childCount({ x: { id: 'x', parent: 'p' } }, ['ghost', 'x'], 'p'), 1, 'childCount skips order ids with no item')
  assertEqual(menuModel.childCount({ x: { id: 'x', parent: 'p' }, y: { id: 'y', parent: 'q' } }, ['x', 'y'], 'p'), 1, 'childCount counts only entries parented to the id')
})

test('mcdc isVisible: null entry, guards, kinds, recursion, guard cap', () => {
  const items = {
    menu2: { id: 'menu2', parent: 'root', kind: 'menu', label: 'M2' },
    act: { id: 'act', parent: 'root', kind: 'action', label: 'Act', action: 'x' },
    link2: { id: 'link2', parent: 'root', kind: 'link', label: 'L2', target: 'act' },
    link3: { id: 'link3', parent: 'root', kind: 'link', label: 'L3', target: 'menuP' },
    menuP: { id: 'menuP', parent: 'root', kind: 'menu', label: 'MP' },
    kid: { id: 'kid', parent: 'menuP', kind: 'action', label: 'Kid' },
    guarded: { id: 'guarded', parent: 'menuP', kind: 'action', label: 'G', when: 'q' },
    menuQ: { id: 'menuQ', parent: 'root', kind: 'menu', label: 'MQ' },
    gq: { id: 'gq', parent: 'menuQ', kind: 'action', label: 'GQ', when: 'q' },
    stray: { id: 'stray', parent: 'nowhere', kind: 'action', label: 'Stray' }
  }
  const order = Object.keys(items)
  assertEqual(menuModel.isVisible(items, order, {}, null), false, 'isVisible hides a missing entry')
  assertEqual(menuModel.isVisible(items, order, null, items.guarded), true, 'isVisible treats null guard results as no answer')
  assertEqual(menuModel.isVisible(items, order, {}, items.guarded), true, 'isVisible keeps a guarded action when the guard has no result')
  assertEqual(menuModel.isVisible(items, order, { guarded: true }, items.guarded), true, 'isVisible keeps a guarded action whose guard passed')
  assertEqual(menuModel.isVisible(items, order, { guarded: false }, items.guarded), false, 'isVisible hides a guarded action whose guard failed')
  assertEqual(menuModel.isVisible(items, order, { act: false }, items.act), true, 'isVisible ignores guard results for entries without a guard')
  assertEqual(menuModel.isVisible(items, order, {}, items.act), true, 'isVisible always shows action rows')
  assertEqual(menuModel.isVisible(items, order, {}, items.link2), false, 'isVisible follows a link to a childless target')
  assertEqual(menuModel.isVisible(items, order, {}, items.link3), true, 'isVisible follows a link to a target with visible children')
  assertEqual(menuModel.isVisible(items, order, {}, items.menu2), false, 'isVisible hides a childless menu')
  assertEqual(menuModel.isVisible(items, order, {}, items.menuP), true, 'isVisible keeps a menu with a visible child')
  assertEqual(menuModel.isVisible(items, order, { gq: false }, items.menuQ), false, 'isVisible hides a menu whose every child is guard-hidden')
  assertEqual(menuModel.isVisible(items, 'not-an-array', {}, items.menuP), false, 'isVisible treats a non-array order as empty')
  assertEqual(menuModel.isVisible(items, ['ghost', 'menuP', 'kid'], {}, items.menuP), true, 'isVisible skips order ids with no item')
  assertEqual(menuModel.isVisible(items, ['menuP', 'kid', 'stray'], {}, items.menuP), true, 'isVisible skips children parented elsewhere')
  assertEqual(menuModel.isVisible(items, order, {}, items.menuQ, 32), false, 'isVisible hides anything at the recursion cap')
  const deep = mcdcChain(40, 'root')
  const deepOrder = Object.keys(deep)
  assertEqual(menuModel.isVisible(deep, deepOrder, {}, deep.c1), false, 'isVisible stops recursing at the 32-deep guard')
})

test('mcdc isDisabled and labelFor: null entries and result maps', () => {
  assertEqual(menuModel.isDisabled({}, null), false, 'isDisabled leaves a missing entry alone')
  assertEqual(menuModel.isDisabled(null, { id: 'x', disabled: 'cmd' }), false, 'isDisabled treats null results as not disabled')
  assertEqual(menuModel.isDisabled({}, { id: 'x', label: 'X' }), false, 'isDisabled leaves an entry without disabled: alone')
  assertEqual(menuModel.isDisabled({ x: true }, { id: 'x', disabled: 'cmd' }), true, 'isDisabled marks a row whose disabled: succeeded')
  assertEqual(menuModel.isDisabled({ x: false }, { id: 'x', disabled: 'cmd' }), false, 'isDisabled leaves a row whose disabled: failed')
  assertEqual(menuModel.labelFor(null, {}, {}), '', 'labelFor returns empty for a missing entry')
  assertEqual(menuModel.labelFor({ id: 'x', label: 'X' }, null, null), 'X', 'labelFor returns the plain label without results')
  assertEqual(menuModel.labelFor({ id: 'x', label: 'X', checked: 'cmd' }, { x: true }, null), 'X ✓', 'labelFor marks a checked row')
  assertEqual(menuModel.labelFor({ id: 'x', label: 'X', checked: 'cmd', disabled: 'cmd2' }, null, { x: true }), 'X ✓', 'labelFor marks a disabled row even without checked results')
  assertEqual(menuModel.labelFor({ id: 'x', label: 'X', checked: 'cmd' }, null, null), 'X', 'labelFor leaves a row unmarked without results')
  assertEqual(menuModel.labelFor({ id: 'x', label: 'X', checked: 'cmd' }, { x: false }, { x: false }), 'X', 'labelFor leaves a row unmarked when both guards failed')
})

test('mcdc leafIdFor and nameSearchText: token edges', () => {
  assertEqual(menuModel.leafIdFor('a.b.c'), 'c', 'leafIdFor returns the last dotted segment')
  assertEqual(menuModel.leafIdFor('plain'), 'plain', 'leafIdFor returns an undotted id whole')
  assertEqual(menuModel.leafIdFor(''), '', 'leafIdFor returns empty for empty input')
  assertEqual(menuModel.leafIdFor(null), '', 'leafIdFor returns empty for a missing id')
  assertEqual(menuModel.nameSearchText(null), '', 'nameSearchText returns empty for a missing entry')
  assertEqual(menuModel.nameSearchText({ id: 'a.b', label: 'Zen', aliases: ['color theme', 'zb'] }), 'zen b color theme zb', 'nameSearchText joins label, leaf, and alias tokens')
  assertEqual(menuModel.nameSearchText({ id: 'x', label: 'L', aliases: 'str' }), 'l x ', 'nameSearchText ignores a non-array aliases field')
  assertEqual(menuModel.searchableToken('a.b-c_d'), 'a b c d', 'searchableToken splits separator runs into spaces')
})

test('mcdc termInSearchWords and descriptionTextMatches: word edges', () => {
  assertEqual(menuModel.termInSearchWords('theme', 'a theme b'), true, 'termInSearchWords finds a whole word')
  assertEqual(menuModel.termInSearchWords('zz', 'a b'), false, 'termInSearchWords rejects a missing word')
  assertEqual(menuModel.termInSearchWords('', 'x'), false, 'termInSearchWords rejects an empty term')
  assertEqual(menuModel.descriptionTextMatches('zen', 'has zen here'), true, 'descriptionTextMatches accepts a query fully covered by words')
  assertEqual(menuModel.descriptionTextMatches('zen now', 'has zen here'), false, 'descriptionTextMatches rejects a query with an uncovered word')
  assertEqual(menuModel.descriptionTextMatches('', 'anything'), true, 'descriptionTextMatches accepts an empty query')
  assertEqual(menuModel.descriptionTextMatches('   ', 'anything'), true, 'descriptionTextMatches accepts a whitespace query')
})

test('mcdc matchesQuery: null entry, root row, empty query, description-only terms', () => {
  const entry = { id: 'a', label: 'Zed', description: 'the zen tool', aliases: [] }
  assertEqual(menuModel.matchesQuery(null, 'x', true), false, 'matchesQuery rejects a missing entry')
  assertEqual(menuModel.matchesQuery({ id: 'root', label: 'Go' }, 'go', true), false, 'matchesQuery never matches the root row')
  assertEqual(menuModel.matchesQuery(entry, 'zen', false), false, 'matchesQuery rejects invisible rows')
  assertEqual(menuModel.matchesQuery(entry, '', true), true, 'matchesQuery matches everything visible on an empty query')
  assertEqual(menuModel.matchesQuery(entry, 'zen', true), true, 'matchesQuery matches a description word')
  assertEqual(menuModel.matchesQuery(entry, 'zed zen', true), true, 'matchesQuery spans name and description terms')
  assertEqual(menuModel.matchesQuery(entry, 'zed nowhere', true), false, 'matchesQuery rejects one uncovered term among many')
  assertEqual(menuModel.matchesQuery(entry, '   ', true), true, 'matchesQuery treats a whitespace query as empty')
})

test('mcdc searchScore: every tier with a deterministic order and depth', () => {
  const mk = (id, extra) => {
    const entry = menuModel.normalizeItem(id, extra)
    entry.order = 0
    return entry
  }
  const m = {
    ex: mk('ex', { label: 'zen' }),
    px: mk('px', { label: 'P' }),
    nx: mk('nx', { label: 'zen', parent: 'px' }),
    ap: mk('ap', { label: 'Zen Browser' }),
    ap2: mk('ap2', { label: 'zenbrowser' }),
    pf: mk('pf', { label: 'zenith' }),
    ct: mk('ct', { label: 'a zen b' }),
    al: mk('al', { label: 'style', aliases: ['colors'] }),
    ds: mk('ds', { label: 'nothing', description: 'has zen here' }),
    nn: mk('nn', { label: 'nothing', description: 'blank' }),
    lk: mk('lk', { label: 'zenith', target: 'x' }),
    ax: mk('ax', { label: 'zen', action: 'run' })
  }
  m.ap.kind = 'app'
  m.ap2.kind = 'app'
  const sc = (key, query) => menuModel.searchScore(m, m[key], query)
  assertEqual(sc('ex', 'zen'), 0, 'searchScore puts an exact root-level menu label at the top of its tier')
  assertEqual(sc('ax', 'zen'), 2000, 'searchScore keeps an exact action label two points above an exact menu label')
  assertEqual(sc('nx', 'zen'), -1975, 'searchScore drops a nested exact label below root-level and adds one depth step')
  assertEqual(sc('ap', 'zen'), -100000, 'searchScore puts an app whole-word match in its own negative tier, below every menu tier')
  assertEqual(sc('ap2', 'zen'), -90000, 'searchScore keeps an app label that only prefixes the query out of the whole-word tier, still above every menu row')
  assertEqual(sc('pf', 'zen'), 8000, 'searchScore scores a label-prefix match at ten')
  assertEqual(sc('lk', 'zen'), 8000, 'searchScore scores a link row like a menu row')
  assertEqual(sc('ct', 'zen'), 28000, 'searchScore scores a mid-label match at thirty')
  assertEqual(sc('al', 'colors'), 38000, 'searchScore scores an alias-only match at forty')
  assertEqual(sc('ds', 'zen'), 58000, 'searchScore scores a description-only match at sixty')
  assertEqual(sc('nn', 'zen'), 78000, 'searchScore scores an unmatched row at eighty')
})

test('mcdc guardScript: empty maps, per-field lines, reader capture and substitution', () => {
  assertEqual(menuModel.guardScript({}), '', 'guardScript returns empty for an empty map')
  assertEqual(menuModel.guardScript({ a: null }), '', 'guardScript skips a null entry')
  assertEqual(menuModel.guardScript({ a: { id: 'a' } }), '', 'guardScript skips an entry with no guards')
  const script = menuModel.guardScript({
    a: { id: 'a', when: '$(omarchy-dns) == none', checked: 'omarchy-pkg-present git', disabled: 'omarchy-cmd-missing foot' }
  })
  assert(script.startsWith('declare -A __omarchy_pkgs=()'), 'guardScript opens with the batch helpers')
  assert(script.includes('__omarchy_read_5=$(' + menuModel.guardReaders[5] + ' 2>/dev/null) || :'), 'guardScript captures only the readers a guard uses')
  assert(!script.includes('__omarchy_read_0='), 'guardScript leaves unused readers uncaptured')
  assert(script.includes('if { ${__omarchy_read_5} == none; } >/dev/null 2>&1; then echo a:w:1; else echo a:w:0;'), 'guardScript substitutes the captured reader into when:')
  assert(script.includes('if { omarchy-pkg-present git; } >/dev/null 2>&1; then echo a:c:1; else echo a:c:0;'), 'guardScript emits checked: lines verbatim')
  assert(script.includes('if { omarchy-cmd-missing foot; } >/dev/null 2>&1; then echo a:d:1; else echo a:d:0;'), 'guardScript emits disabled: lines verbatim')
  const single = menuModel.guardScript({ b: { id: 'b', when: '$(omarchy-channel-current) == dev' } })
  assert(single.includes('__omarchy_read_0='), 'guardScript captures the channel reader when a guard uses it')
  assert(!single.includes('__omarchy_read_5='), 'guardScript does not capture the dns reader without a use')
  assert(single.includes('if { ${__omarchy_read_0} == dev; }'), 'guardScript substitutes the channel reader slot')
  const doubled = menuModel.guardScript({ c: { id: 'c', when: '$(omarchy-dns)$(omarchy-dns)' } })
  assertEqual(doubled.split('${__omarchy_read_5}').length - 1, 2, 'guardScript substitutes every reader call in one expression')
  const versioned = menuModel.guardScript({ d: { id: 'd', when: 'omarchy-pkg-present bash>=1' } })
  assert(versioned.includes('if { omarchy-pkg-present bash>=1; }'), 'guardScript passes a version-constrained package check through unrewritten')
  assert(!versioned.includes('__omarchy_read_'), 'guardScript captures nothing when no guard names a reader')
})

test('mcdc summonAction: in-process summon shape and every rejection', () => {
  assertEqual(menuModel.summonAction(undefined), null, 'summonAction rejects a missing action')
  assertEqual(menuModel.summonAction(''), null, 'summonAction rejects an empty action')
  assertEqual(menuModel.summonAction('omarchy-theme-set dark'), null, 'summonAction rejects a non-summon action')
  assertEqual(menuModel.summonAction('xomarchy-shell shell summon style'), null, 'summonAction rejects a lookalike prefix')
  assertEqual(menuModel.summonAction('omarchy-shell shell summonx style'), null, 'summonAction rejects a corrupted verb')
  assertEqual(menuModel.summonAction('omarchy-shell shell summon bad id'), null, 'summonAction rejects an id with a space')
  assertDeepEqual(menuModel.summonAction('omarchy-shell shell summon style'), { id: 'style', payload: '{}' }, 'summonAction parses a bare summon to an empty payload')
  assertDeepEqual(menuModel.summonAction("omarchy-shell shell summon style 'k=v'"), { id: 'style', payload: 'k=v' }, 'summonAction parses a quoted payload')
})


// PR omacom/omarchy#12223 witnesses (SW-REQ-260922-TKDP, SW-REQ-260922-SJ7P):
// the REAL rebuildDisplay search branch from shell/plugins/menu/Menu.qml runs
// under node vm against the real MenuModel.js and the shipped default menu
// merged with app rows. They live here, in the menu-node suite, so the mirror
// adds no suite line to proof.yaml.
test('Menu.qml rebuildDisplay search ranking with installed apps (PR #12223 witnesses)', () => {
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')
// PR omacom/omarchy#12223 review witness (proof-side, executes product code):
// runs the REAL rebuildDisplay search branch from Menu.qml under vm against
// the real MenuModel.js and the shipped default menu merged with app rows,
// so the apps-first pinning and the divider placement are observed in
// execution rather than matched as source text.
function searchDisplay(appRows, activeMenu, query) {
  const vm = require('vm')
  const fs = require('fs')
  const qml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')
  const fnMatch = qml.match(/\n  function rebuildDisplay\(\) \{[\s\S]*?\n  \}\n/)
  if (!fnMatch) throw new Error('rebuildDisplay not found in Menu.qml')
  const defaults = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
  const base = menu.mergeMenuSources(defaults, [])
  const merged = menu.mergeAppRows(base.items, base.itemOrder, appRows)
  const model = []
  const displayModel = { clear() { model.length = 0 }, append(r) { model.push(r) }, get count() { return model.length } }
  const r = {
    dmenuActive: false, rowsLoaded: true, activeMenu, filterText: query, searchDivider: false,
    items: merged.items, itemOrder: merged.itemOrder, whenResults: {}, disabledResults: {}, checkedResults: {},
    item(id) { return this.items[id] || null },
    isDescendantOf(id, a) { return menu.isDescendantOf(this.items, id, a) },
    isVisible(e) { return menu.isVisible(this.items, this.itemOrder, this.whenResults, e) },
    isDisabled(e) { return menu.isDisabled(this.disabledResults, e) },
    matchesQuery(e, q) { return menu.matchesQuery(e, q, this.isVisible(e) && !this.isDisabled(e)) },
    parentPathFor(id) { return menu.parentPathFor(this.items, id) },
    searchScore(e, q) { return menu.searchScore(this.items, e, q) },
    displayRow(e, d, s, sec) { return menu.displayRow(this.items, this.itemOrder, this.checkedResults, this.disabledResults, e, d, s, sec) },
    settleCursor() {}, revealCursor() {}
  }
  const fn = vm.runInNewContext(`(function() {${fnMatch[0]}; return rebuildDisplay })()`, {
    root: r, displayModel, layoutSerial: 0, Qt: { callLater() {} }
  })
  fn.call(r)
  return { rows: model.slice(), divider: r.searchDivider }
}

{ // root search pins apps above direct children and deeper entries
  const apps = [
    { id: 'apps.chromium', parent: 'apps', kind: 'app', label: 'Chromium', description: 'Web Browser', aliases: [] },
    { id: 'apps.calculator', parent: 'apps', kind: 'app', label: 'Calculator', description: '', aliases: [] }
  ]
  const { rows, divider } = searchDisplay(apps, 'root', 'c')
  assert(rows.length > 2, 'root search for c lists rows')
  const firstMenu = rows.findIndex(row => row.kind !== 'app')
  assert(firstMenu > 0, 'apps occupy the leading rows of a root search')
  assert(rows.slice(firstMenu).every(row => row.kind !== 'app'), 'no app row sorts below a menu row')
  assert(rows.slice(0, firstMenu).every(row => row.section !== 'drilldown'), 'app rows carry no drilldown section')
  assert(rows.slice(firstMenu).every(row => row.section === 'drilldown'), 'every menu row after the apps sits in the drilldown section')
  const boundaries = rows.filter((row, i) => i > 0 && row.section === 'drilldown' && rows[i - 1].section !== 'drilldown').length
  assertEqual(boundaries, 1, 'exactly one divider is drawn, between apps and menu entries')
  assertEqual(divider, true, 'searchDivider is set when apps and menu entries both match')
}

{ // without app matches, direct children stay above deeper entries with one divider
  const { rows, divider } = searchDisplay([], 'root', 'c')
  const firstDeep = rows.findIndex(row => row.section === 'drilldown')
  assert(firstDeep > 0, 'direct children lead a root search with no app matches')
  assert(rows.slice(firstDeep).every(row => row.section === 'drilldown'), 'deeper entries all follow the divider')
  assertEqual(divider, true, 'searchDivider is set when direct and deeper matches both exist')
}

{ // a keyword-only app match outranks an exact-label menu entry (intended-behavior question)
  const ranked2 = menu.mergeAppRows(menu.mergeMenuSources(menu.parseMenuJsonc(require('fs').readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')), []).items,
    menu.mergeMenuSources(menu.parseMenuJsonc(require('fs').readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8')), []).itemOrder,
    [{ id: 'apps.gradience', parent: 'apps', kind: 'app', label: 'Gradience', description: 'Customize the update look', aliases: [] }])
  const exactId = Object.keys(ranked2.items).find(id => ranked2.items[id].kind !== 'app' && String(ranked2.items[id].label).toLowerCase() === 'update')
  assert(!!exactId, 'the default menu carries an entry labelled exactly Update')
  const s = id => menu.searchScore(ranked2.items, ranked2.items[id], 'update')
  assert(s('apps.gradience') < s(exactId), 'a description-only app match ranks above the exact-label Update menu entry under the apps-first bias')
}
})
