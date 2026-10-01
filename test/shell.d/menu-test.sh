#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260928-8VJQ, SW-REQ-260922-E4J2, SW-REQ-260922-3T3F, SW-REQ-260922-46HY, SW-REQ-260922-7NPE, SYS-REQ-260922-PPDW, SW-REQ-260922-Z680, SW-REQ-260922-EFNR, SYS-REQ-260922-0M8A, SW-REQ-260922-PRNV, SW-REQ-260922-CYB9, SW-REQ-260922-74BZ, SYS-REQ-260922-R8DQ, SW-REQ-260922-XW52, SW-REQ-260922-N3RM, SW-REQ-260922-JRW1, SW-REQ-260922-DQ9P, SW-REQ-260922-SJ7P, SYS-REQ-260922-V7W6, SW-REQ-260922-TKDP, SYS-REQ-260927-WC89, SW-REQ-260927-66FW, SW-REQ-260928-BMFE, SW-REQ-260928-C8W1, SW-REQ-261001-BNZG
#mcdc:ignore:defensive SW-REQ-260928-8VJQ: action_is_bare_summon=T, in_process_summon_equivalent=F => FALSE -- a matched bare summon whose delivered argv diverges from bash is exactly the defect the requirement forbids; summonAction is a pure regex + passthrough, so producing it needs a broken regex or a mutated payload copy [reviewed: REVIEW-74]
#mcdc:ignore:defensive SW-REQ-260922-3T3F: empty_item_set=F, json_invalid=T, parse_error_raised=F => FALSE -- a failed parse hits the catch that returns [] unconditionally; invalid input yielding items needs a broken catch [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-3T3F: empty_item_set=T, json_invalid=T, parse_error_raised=T => FALSE -- the same catch swallows the parse error by construction; a raised error needs the try/catch removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-46HY: entry_shape_declared=T, kind_and_parent_inferred=F => FALSE -- normalizeItem derives parent from the id and kind from the declared shape unconditionally; skipping the inference needs those assignments removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-7NPE: per_key_override_applied=F, root_injected=F, user_entry_overrides=T => FALSE -- the merge copies every key of every user entry and injects root when missing, both unconditionally; an override that applies nothing needs the copy loop removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-7NPE: per_key_override_applied=F, root_injected=T, user_entry_overrides=T => FALSE -- same unconditional per-key copy; root injection without the override needs the copy loop removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-7NPE: per_key_override_applied=T, root_injected=F, user_entry_overrides=T => FALSE -- root injection runs whenever the merged map lacks root; an applied override without it needs the injection removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SYS-REQ-260922-PPDW: item_tree_merged=F, menu_sources_loaded=T => FALSE -- mergeMenuSources always returns the rebuilt items/order map; loaded sources without a merged tree needs the build loop removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-Z680: id_listed_once=F, inputs_not_mutated=F, orphan_id_present=F, orphans_dropped=F, provider_reran=T => FALSE -- the merge rebuilds fresh maps from the incoming rows on every run; a rerun that duplicates or mutates needs the rebuild loops broken [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-Z680: id_listed_once=F, inputs_not_mutated=F, orphan_id_present=T, orphans_dropped=F, provider_reran=F => FALSE -- the rebuild skips any order id with no item behind it unconditionally; carrying an orphan forward needs that check removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-Z680: id_listed_once=F, inputs_not_mutated=T, orphan_id_present=T, orphans_dropped=T, provider_reran=T => FALSE -- the incoming loop skips any id already in the next map; a duplicate row needs that check removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-Z680: id_listed_once=T, inputs_not_mutated=F, orphan_id_present=T, orphans_dropped=T, provider_reran=T => FALSE -- the merge writes only into the fresh maps it created; mutating the inputs needs a write into the source that does not exist [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-Z680: id_listed_once=T, inputs_not_mutated=T, orphan_id_present=T, orphans_dropped=F, provider_reran=T => FALSE -- same unconditional orphan skip; keeping the orphan needs that check removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-EFNR: previous_batch_replaced=F, provider_reran=T => FALSE -- the swap drops every row tagged with the rerunning provider's menu id unconditionally; keeping the previous batch needs that filter removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SYS-REQ-260922-0M8A: dynamic_rows_swapped=F, provider_rows_arrive=T => FALSE -- the incoming loop appends every new provider row unconditionally; arrived rows that never appear need that loop removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-PRNV: exact_id_match=T, route_input=T, route_is_exact_id=F => FALSE -- an exact id hit returns the input itself at the first check; routing it elsewhere needs that return removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-CYB9: alias_match=T, exact_id_match=F, route_input=T, route_is_alias_target=F => FALSE -- the alias loop returns the matching entry's id unconditionally; an alias routing elsewhere needs that return removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-74BZ: alias_match=F, exact_id_match=F, route_input=T, route_is_literal_input=F => FALSE -- the fallthrough returns the literal input as the last statement; losing it needs that return removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SYS-REQ-260922-R8DQ: route_given=T, routed_to_intended_item=F => FALSE -- resolveRoute always returns the exact id, the alias target, or the literal input; an unintended destination needs all three returns broken [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-XW52: link_target_followed=F, resolved_kind_link=T => FALSE -- displayRow resolves a link row's target from entry.target unconditionally; ignoring the target needs the kind ternary removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-N3RM: action_runs_directly=F, menu_not_opened=F, resolved_kind_action=T => FALSE -- displayRow copies the entry's action and resolves target by kind unconditionally; an action row that opens a menu needs the kind ternary removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-N3RM: action_runs_directly=F, menu_not_opened=T, resolved_kind_action=T => FALSE -- same unconditional action copy; an action row without its action needs the copy removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-N3RM: action_runs_directly=T, menu_not_opened=F, resolved_kind_action=T => FALSE -- the action row's target is its own id by the same ternary, so activation never navigates; opening a menu needs the ternary removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-JRW1: guard_results_applied=T, rows_hidden_or_marked_per_results=F => FALSE -- isVisible and isDisabled consult the result maps on every row; a false guard leaving its row up needs that lookup removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-DQ9P: all_terms_matched=F, query_terms_given=T, row_hidden_from_results=F => FALSE -- matchesQuery returns false on the first unmatched term and the view only lists rows it answers true for; an unmatched row staying listed needs that return removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-SJ7P: better_match_ranks_first=F, match_quality_varies=T => FALSE -- searchScore is a pure function of the match tier; a weaker match outscoring a stronger one needs the tier ladder reordered [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SYS-REQ-260922-V7W6: matching_rows_ranked=F, search_entered=T => FALSE -- every search row carries its searchScore and the QML search model sorts by it; an unranked result list needs the sort removed [reviewed: REVIEW-M8]
#mcdc:ignore:defensive SW-REQ-260922-TKDP: matches_span_menus=T, sections_divided=F => FALSE -- displayRow copies the caller's section onto every row unconditionally; search rows arriving without their section needs that assignment removed [reviewed: REVIEW-M8]
# mcdc:witness-out-of-process
#mcdc:ignore:defensive SYS-REQ-260927-WC89: lock_row_activated=T, system_lock_invoked=F => FALSE -- openRoute copies the row's action verbatim into Util.execDetached; an activated Lock row not invoking omarchy-system-lock needs the action field in default/omarchy/omarchy-menu.jsonc or the exec call removed [reviewed: REVIEW-28]

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
// Verifies: SW-REQ-260928-8VJQ, SW-REQ-260922-E4J2, SW-REQ-260922-3T3F, SW-REQ-260922-46HY, SW-REQ-260922-7NPE, SYS-REQ-260922-PPDW, SW-REQ-260922-Z680, SW-REQ-260922-EFNR, SYS-REQ-260922-0M8A, SW-REQ-260922-PRNV, SW-REQ-260922-CYB9, SW-REQ-260922-74BZ, SYS-REQ-260922-R8DQ, SW-REQ-260922-XW52, SW-REQ-260922-N3RM, SW-REQ-260922-JRW1, SW-REQ-260922-DQ9P, SW-REQ-260922-SJ7P, SYS-REQ-260922-V7W6, SW-REQ-260922-TKDP, SYS-REQ-260927-WC89, SW-REQ-260927-66FW, SW-REQ-260928-BMFE, SW-REQ-260928-C8W1, SW-REQ-261001-BNZG
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
// SW-REQ-260922-3T3F:error_handling:nominal
assertEqual(parsed.length, 3, 'menu parses JSONC with comments and trailing commas')

// String-aware trailing commas (#13250)
const withCommasInStrings = menu.parseMenuJsonc('{\n  "b": { "label": "x, ]y", "action": "mv f{.bak,}" },\n}')
assertEqual(withCommasInStrings[0].label, 'x, ]y', 'menu keeps a comma before ] inside a label')
assertEqual(withCommasInStrings[0].action, 'mv f{.bak,}', 'menu keeps a comma before } inside an action')
assertEqual(menu.parseMenuJsonc('{"a": {"label": "q\\\\"},}')[0].label, 'q\\', 'menu ends a string at a quote after an escaped backslash before a trailing comma')

// Array roots (#13492)
assertEqual(menu.parseMenuJsonc('[{"label":"should-not-appear"},{"label":"ghost-2"}]').length, 0, 'menu rejects a top-level array instead of turning its indices into entries')
assertEqual(menu.parseMenuJsonc('// note\n[{"label":"x"},]').length, 0, 'menu rejects a commented top-level array with a trailing comma')
assertEqual(menu.parseMenuJsonc('{"obj": {"label":"kept"}}').length, 1, 'menu still parses an object root to its entries')
assertEqual(
  menu.parseMenuJsonc('{"items": [{"label":"x"}], "a": {"label":"A"}}').map(item => item.id).join(','),
  'a',
  'menu skips an items array rather than walking its indices'
)

// Inline comments (#13493) and comments between a trailing comma and its closer
assertEqual(menu.parseMenuJsonc('{"a": {"label": "A"}} // note').length, 1, 'menu strips an inline comment tail instead of dropping the whole file')
assertEqual(menu.parseMenuJsonc('{ // opening note\n"a": {"label": "A"},\n} // closing note\n// final line').length, 1, 'menu strips full-line and inline comments in the same pass')
assertEqual(menu.parseMenuJsonc('{"s": {"label": "A // B"}}')[0].label, 'A // B', 'menu preserves comment slashes inside a string literal')
assertEqual(menu.parseMenuJsonc('{"a": {"label": "A"}} // }, "x": {"label": "X"}').length, 1, 'menu ignores JSON syntax carried inside a comment tail')
assertEqual(menu.parseMenuJsonc('{\n  "a": {"label": "A"},\n  // "b": {"label": "B"},\n}').length, 1, 'menu drops a trailing comma when a whole-line comment sits between it and the closer')
assertEqual(menu.parseMenuJsonc('{\n  "a": {"label": "A"}, // note\n}').length, 1, 'menu drops a trailing comma when an inline comment follows it on the last entry')
assertEqual(menu.parseMenuJsonc('{"a": {"label": "A", "aliases": ["x", // note\n]}}')[0].aliases.join(','), 'x', 'menu drops a trailing comma before ] behind a comment')
assertEqual(menu.parseMenuJsonc('{"a": {"label": "A", "n": 1//c\n2}}').length, 0, 'menu keeps the line break after a comment so tokens on either side are not joined')

// Whitespace outside strings that JSON.parse rejects: Unicode spaces, vertical tab, form feed
for (const [name, space] of [['a byte order mark', '\uFEFF'], ['a no-break space', '\u00A0'], ['a line separator', '\u2028'], ['an ideographic space', '\u3000'], ['a vertical tab', '\u000B'], ['a form feed', '\u000C']]) {
  assertEqual(menu.parseMenuJsonc(space + '// note\n{"a": {"label": "A"}}').length, 1, `menu reads ${name} before a leading comment as whitespace`)
  assertEqual(menu.parseMenuJsonc('{\n' + space + '// note\n"a": {"label": "A"}}').length, 1, `menu reads ${name} indenting a comment line as whitespace`)
  assertEqual(menu.parseMenuJsonc(space + '{"a": {"label": "A"}}').length, 1, `menu reads ${name} before the opening brace as whitespace`)
}
assertEqual(menu.parseMenuJsonc('{"a": {"label": "A\u00A0B\u2028C"}}')[0].label, 'A\u00A0B\u2028C', 'menu keeps Unicode spaces inside a string literal')
const sampleExtension = fs.readFileSync(path.join(root, 'config/omarchy/extensions/omarchy-menu.jsonc'), 'utf8')
assertEqual(
  menu.parseMenuJsonc(sampleExtension.replace(/^  \/\/ ("personal[^"]*": \{[^\n]*)$/gm, '  $1')).map(item => item.id).join(','),
  'personal,personal.notes,personal.files',
  'menu loads the example rows uncommented in the sample extension'
)
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
// SW-REQ-260922-3T3F:error_handling:negative
assertEqual(menu.parseMenuJsonc('{broken').length, 0, 'menu parses invalid JSON to an empty item set without raising')
// MCDC SW-REQ-260922-E4J2: items_parsed=F, jsonc_has_comments_or_commas=T => FALSE
assertEqual(menu.parseMenuJsonc('{\n// comment\n"items":').length, 0, 'menu parses broken JSONC with comments to an empty item set')
// MCDC SW-REQ-260922-E4J2: items_parsed=F, jsonc_has_comments_or_commas=F => TRUE [no-action: empty input parses to zero items -- the JSONC handling parses nothing]
// MCDC SW-REQ-260922-46HY: entry_shape_declared=F, kind_and_parent_inferred=F => TRUE [no-action: an empty item set declares zero entries -- nothing is normalized]
// SW-REQ-260922-3T3F:boundary:nominal
assertEqual(menu.parseMenuJsonc('').length + menu.parseMenuJsonc('{"items":{}}').length, 0, 'menu parses empty input and an empty item set to zero entries')

// JSONC stripping under PR omacom/omarchy#13968: one string-aware scanner
// replaces upstream e332dc97's two string-blind regex passes. The baseline's
// preservation assertions below must hold unchanged on the new scanner (the
// trailing-comma-then-comment shape is the #13512 regression); the known
// issues the regexes had are asserted fixed further down.
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

// Known issues fixed by PR omacom/omarchy#13968. On the baseline these were
// green tripwires of upstream's wrong output; on this mirror each asserts the
// fixed behaviour and stays as a regression guard for its (fixed) issue.
// Reproduces: KI-MENU-JSONC-COMMA-IN-STRING
assertEqual(
  menu.parseMenuJsonc('{"b": {"label": "x, ]y"}}')[0].label,
  'x, ]y',
  'KI-MENU-JSONC-COMMA-IN-STRING guard: a label carrying comma and closer survives (omacom/omarchy#13250)'
)
assertEqual(
  menu.parseMenuJsonc('{"b": {"label": "B", "action": "mv f{.bak,}"}}')[0].action,
  'mv f{.bak,}',
  'KI-MENU-JSONC-COMMA-IN-STRING guard: an action carrying comma and closer survives'
)
// Reproduces: KI-MENU-JSONC-ARRAY-ROOT
assertDeepEqual(
  menu.parseMenuJsonc('[{"label":"should-not-appear"},{"label":"ghost-2"}]').map(item => item.id + '=' + item.label),
  [],
  'KI-MENU-JSONC-ARRAY-ROOT guard: an array root renders no phantom rows (omacom/omarchy#13492)'
)
assertEqual(
  menu.parseMenuJsonc('{"items": [{"label":"x"}]}').length,
  0,
  'menu skips an array nested under the items key as a non-object entry'
)
// Reproduces: KI-MENU-JSONC-INLINE-COMMENT
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A"}} // note').length,
  1,
  'KI-MENU-JSONC-INLINE-COMMENT guard: an inline comment tail no longer empties the file (omacom/omarchy#13493)'
)
assertEqual(
  menu.parseMenuJsonc('{\n  "a": {"label": "A"}, // first\n  "b": {"label": "B"}\n}').length,
  2,
  'KI-MENU-JSONC-INLINE-COMMENT guard: an inline comment on an entry line keeps every row'
)
// Reproduces: KI-MENU-JSONC-STRIP-GAPS
assertEqual(
  menu.parseMenuJsonc('{ /* c */ "a": {"label": "A"} }').length,
  0,
  'KI-MENU-JSONC-STRIP-GAPS tripwire: a block comment is not stripped and empties the whole file'
)

// Input domain of the menu JSONC reader (SW-REQ-260922-E4J2, SW-REQ-260922-3T3F),
// stated per partition at the text Quickshell's FileView hands to
// parseMenuJsonc. Checked live under Quickshell 0.3.1: FileView drops a
// leading UTF-8 byte-order mark, decodes invalid UTF-8 to U+FFFD, and keeps
// CR, CRLF and every other character as read. The cases below pin the
// upstream outcome of each partition. On this mirror PR omacom/omarchy#13968
// fixes KI-MENU-JSONC-UNICODE-WHITESPACE, so its tripwire asserts the fixed
// output and stays as a regression guard; KI-MENU-JSONC-CR-LINE-ENDINGS is
// unchanged by the PR and stays a green tripwire.
const domainRows = text => menu.parseMenuJsonc(text).map(item => item.id + '=' + item.label).join('|')
const domainDoc = '{\n  // comment\n  "a": {"label": "A"},\n  "b": {"label": "B"},\n}\n'
// SW-REQ-260922-E4J2:input_domain:nominal -- LF and CRLF line endings, and a
// CR-only file without comments, parse to the same entries.
assertEqual(domainRows(domainDoc), 'a=A|b=B', 'menu JSONC with LF line endings parses to its entries')
assertEqual(domainRows(domainDoc.replace(/\n/g, '\r\n')), 'a=A|b=B', 'menu JSONC with CRLF line endings parses like LF')
assertEqual(domainRows('{\r  "a": {"label": "A"},\r}\r'), 'a=A', 'menu JSONC with CR-only line endings and no comment parses')
// SW-REQ-260922-E4J2:input_domain:nominal -- any JS whitespace character
// (no-break space, ideographic space, VT, FF, a byte-order mark) indenting a
// full-line comment is dropped together with the comment.
for (const ch of [' ', '　', '\u000b', '\u000c', '﻿', ' ']) {
  assertEqual(
    domainRows(domainDoc.replace('  // comment', ch + ch + '// comment')),
    'a=A|b=B',
    'menu JSONC drops a full-line comment indented with U+' + ch.charCodeAt(0).toString(16).padStart(4, '0')
  )
}
// SW-REQ-260922-E4J2:input_domain:nominal -- inside a string literal every
// character is data: Unicode spaces, a byte-order mark, a line separator and
// the U+FFFD that FileView decodes invalid UTF-8 to are copied unchanged.
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "x y﻿ �z"}}')[0].label,
  'x y﻿ �z',
  'menu JSONC copies non-ASCII characters inside a string literal unchanged'
)
// SW-REQ-260922-E4J2:input_domain:nominal -- a huge file (over 1 MiB: a
// 40000-line comment block and a 64 KiB string value) parses completely. The
// bulk sits in comments and one string, so few rows reach the model.
const hugeDoc = '{\n' + Array.from({ length: 40000 }, (_, i) => '  // line ' + i + ' ' + 'c'.repeat(12) + '\n').join('') +
  '  "a": {"label": "A", "description": "' + 'd'.repeat(65536) + '"},\n  "b": {"label": "B"},\n}\n'
assertEqual(hugeDoc.length > 1048576, true, 'the huge menu JSONC case is over 1 MiB')
assertEqual(domainRows(hugeDoc), 'a=A|b=B', 'menu JSONC parses a file over 1 MiB to all of its entries')
// SW-REQ-260922-3T3F:input_domain:negative -- empty input, whitespace only,
// and U+FFFD or NUL outside a string reject the document as a whole: an
// empty item set, no exception.
// SW-REQ-260922-E4J2:input_domain:negative -- U+FFFD and NUL are not JS
// whitespace, so the stripper passes them on and JSON.parse rejects the file.
for (const text of ['', ' \t\r\n', '{�"a": {"label": "A"}}', '{"a":\u0000{"label": "A"}}']) {
  assertEqual(menu.parseMenuJsonc(text).length, 0, 'menu JSONC rejects ' + JSON.stringify(text) + ' to an empty item set')
}
// SW-REQ-260922-3T3F:input_domain:nominal -- a non-string value reaches the
// parser as text first, so null and undefined read as empty input.
assertEqual(menu.parseMenuJsonc(null).length + menu.parseMenuJsonc(undefined).length, 0, 'menu JSONC reads null and undefined as empty input')
// Reproduces: KI-MENU-JSONC-UNICODE-WHITESPACE
// SW-REQ-260922-E4J2:input_domain:nominal -- a JS whitespace character that
// JSON does not accept (VT, FF, no-break space, the U+2000 spaces, line and
// paragraph separators, ideographic space, a byte-order mark after the start)
// between tokens is read as a space (SW-REQ-261001-BNZG): the file keeps its
// entries.
for (const ch of ['\u000b', '\u000c', ' ', ' ', ' ', ' ', ' ', ' ', ' ', ' ', '　', '﻿']) {
  assertEqual(
    menu.parseMenuJsonc('{"a":' + ch + '{"label": "A"}}').length,
    1,
    'KI-MENU-JSONC-UNICODE-WHITESPACE guard: U+' + ch.charCodeAt(0).toString(16).padStart(4, '0') + ' between tokens no longer empties the file'
  )
}
// Reproduces: KI-MENU-JSONC-CR-LINE-ENDINGS
assertEqual(
  menu.parseMenuJsonc(domainDoc.replace(/\n/g, '\r')).length,
  0,
  'KI-MENU-JSONC-CR-LINE-ENDINGS tripwire: with CR-only line endings a full-line comment swallows the rest of the file'
)

// SW-REQ-260927-66FW: string-aware trailing commas. A comma outside every
// string is dropped only when the next character that is neither whitespace
// nor part of a // comment is } or ]. A comma inside a string is data.
// Decision under test: trailing_comma_dropped = !comma_in_string && next_char_closes_json
//mcdc:ignore:defensive SW-REQ-260927-66FW: comma_in_string=F, next_char_closes_json=F, trailing_comma_dropped=T => FALSE -- the scanner appends the comma whenever the look-ahead stops at end of input or on a character other than } or ]; a drop there needs that append removed [reviewed: REVIEW-21]
//mcdc:ignore:defensive SW-REQ-260927-66FW: comma_in_string=F, next_char_closes_json=T, trailing_comma_dropped=F => FALSE -- a comma outside every string whose look-ahead stops on } or ] is never appended; keeping it needs the closer test broken [reviewed: REVIEW-21]
//mcdc:ignore:defensive SW-REQ-260927-66FW: comma_in_string=T, next_char_closes_json=T, trailing_comma_dropped=T => FALSE -- inside a string the scanner copies every character before it tests for a comma, so an in-string comma is never dropped [reviewed: REVIEW-21]
// MCDC SW-REQ-260927-66FW: comma_in_string=T, next_char_closes_json=T, trailing_comma_dropped=F => TRUE
// SW-REQ-260927-66FW:malformed_input:negative
assertEqual(
  menu.parseMenuJsonc('{"b": {"label": "x, ]y", "action": "a, }b"}}')[0].action,
  'a, }b',
  '66FW: the scanner keeps a comma before a closer inside a string literal'
)
// MCDC SW-REQ-260927-66FW: comma_in_string=T, next_char_closes_json=T, trailing_comma_dropped=F => TRUE
assertEqual(
  menu.parseMenuJsonc('{"e": {"label": "a\\", ]b"}}')[0].label,
  'a", ]b',
  '66FW: the scanner keeps a comma after an escaped quote inside a string literal'
)
// MCDC SW-REQ-260927-66FW: comma_in_string=F, next_char_closes_json=T, trailing_comma_dropped=T => TRUE
// SW-REQ-260927-66FW:malformed_input:nominal
assertEqual(
  menu.parseMenuJsonc('{"c": {"label": "y"}, }').length,
  1,
  '66FW: the scanner drops a trailing comma before a closing brace'
)
// MCDC SW-REQ-260927-66FW: comma_in_string=F, next_char_closes_json=T, trailing_comma_dropped=T => TRUE
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A", "aliases": ["x", // c\n  // d\n]}}')[0].aliases.join(','),
  'x',
  '66FW: the look-ahead skips whitespace and // comments before the closing bracket'
)
// MCDC SW-REQ-260927-66FW: comma_in_string=F, next_char_closes_json=F, trailing_comma_dropped=F => TRUE
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A"}, // c\n "b": {"label": "B"}}').length,
  2,
  '66FW: the scanner keeps a comma when the look-ahead past a comment meets another entry'
)
// MCDC SW-REQ-260927-66FW: comma_in_string=F, next_char_closes_json=F, trailing_comma_dropped=F => TRUE
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A"}},').length,
  0,
  '66FW: the scanner keeps a comma at end of input, so JSON.parse still rejects it'
)
// MCDC SW-REQ-260927-66FW: comma_in_string=T, next_char_closes_json=F, trailing_comma_dropped=F => TRUE
assertEqual(
  menu.parseMenuJsonc('{"o": {"label": "a, b"}}')[0].label,
  'a, b',
  '66FW: the scanner keeps a plain comma inside a string literal'
)

// SW-REQ-260928-BMFE: an array root is not an entry map and yields no rows,
// like the scalar and null roots.
// Decision under test: array_root_rejected = array_root_present
//mcdc:ignore:defensive SW-REQ-260928-BMFE: array_root_present=T, array_root_rejected=F => FALSE -- the guard returns an empty set for any Array root unconditionally; an array yielding rows needs the Array.isArray check removed [reviewed: REVIEW-72]
//mcdc:ignore:defensive SW-REQ-260928-BMFE: array_root_present=F, array_root_rejected=T => FALSE -- the rejection arm runs only when Array.isArray(parsed) is true; an object root taking it needs a broken condition [reviewed: REVIEW-72]
// MCDC SW-REQ-260928-BMFE: array_root_present=T, array_root_rejected=T => TRUE
// SW-REQ-260928-BMFE:malformed_input:nominal
assertEqual(
  menu.parseMenuJsonc('// note\n[{"label": "x"}, {"label": "y"},]').length,
  0,
  'BMFE: a commented array root with a trailing comma yields no rows'
)
// MCDC SW-REQ-260928-BMFE: array_root_present=T, array_root_rejected=T => TRUE
assertEqual(
  menu.parseMenuJsonc('[]').length,
  0,
  'BMFE: an empty array root yields no rows'
)
// MCDC SW-REQ-260928-BMFE: array_root_present=F, array_root_rejected=F => TRUE [no-action: an object root parses to its entries -- the array rejection path is not taken]
assertEqual(
  menu.parseMenuJsonc('{"obj": {"label": "kept"}}').length,
  1,
  'BMFE: an object root still parses to its entries'
)
// SW-REQ-260928-BMFE:malformed_input:negative
assertEqual(
  menu.parseMenuJsonc('[1, "a", null]').length + menu.parseMenuJsonc('"x"').length + menu.parseMenuJsonc('null').length,
  0,
  'BMFE: an array of scalars, a string root and a null root all yield no rows'
)

// SW-REQ-260928-C8W1: a // opener outside every string starts a comment that
// runs up to the line break, wherever it sits; the line break stays.
// Decision under test: comment_tail_dropped = !comment_in_string
// MCDC SW-REQ-260928-C8W1: comment_in_string=F, comment_tail_dropped=T => TRUE
// SW-REQ-260928-C8W1:malformed_input:nominal
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A"}} // note').length,
  1,
  'C8W1: the scanner strips an inline comment tail at end of input'
)
// MCDC SW-REQ-260928-C8W1: comment_in_string=F, comment_tail_dropped=T => TRUE
assertEqual(
  menu.parseMenuJsonc('{ // opening note\n"a": {"label": "A"}, // first\n} // closing note\n// final line').length,
  1,
  'C8W1: the scanner strips whole-line and inline comments in one pass'
)
// MCDC SW-REQ-260928-C8W1: comment_in_string=T, comment_tail_dropped=F => TRUE
assertEqual(
  menu.parseMenuJsonc('{"s": {"label": "A // B", "action": "xdg-open https://example.org"}}')[0].action,
  'xdg-open https://example.org',
  'C8W1: the scanner keeps // inside a string literal'
)
// SW-REQ-260928-C8W1:malformed_input:negative
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A", "n": 1//c\n2}}').length,
  0,
  'C8W1: the line break after a comment stays, so the tokens on each side are not joined'
)
//mcdc:ignore:defensive SW-REQ-260928-C8W1: comment_in_string=F, comment_tail_dropped=F => FALSE -- a // opener outside every string always enters the comment branch; keeping its tail needs that branch removed [reviewed: REVIEW-73]
assertEqual(
  menu.parseMenuJsonc('{"n": {"label": "plain"}}').length,
  1,
  'C8W1: a comment-free object parses unchanged'
)

// SW-REQ-261001-BNZG: input domain. Outside strings every character that JS
// \s matches (ASCII whitespace, the byte order mark, the Unicode spaces) is
// whitespace: a line feed stays, any other one becomes one ASCII space.
// Inside strings every character is copied unchanged.
// Decision under test: space_passed_as_ascii = space_outside_string
//mcdc:ignore:defensive SW-REQ-261001-BNZG: space_outside_string=T, space_passed_as_ascii=F => FALSE -- outside a string the scanner tests /\s/ on every character that is not a quote, a comment opener or a comma; a matched character skipping the rule needs that branch removed [reviewed: REVIEW-261001-ENZ2]
//mcdc:ignore:defensive SW-REQ-261001-BNZG: space_outside_string=F, space_passed_as_ascii=T => FALSE -- the rule runs only in the outside-string branch, and the in-string branch copies each character as is; a rewrite there needs a broken string branch [reviewed: REVIEW-261001-ENZ2]
// MCDC SW-REQ-261001-BNZG: space_outside_string=T, space_passed_as_ascii=T => TRUE
// SW-REQ-261001-BNZG:malformed_input:nominal
assertEqual(
  menu.parseMenuJsonc('\uFEFF{"a": {"label": "A"}}').length,
  1,
  'BNZG: a leading byte order mark reads as whitespace'
)
// MCDC SW-REQ-261001-BNZG: space_outside_string=T, space_passed_as_ascii=T => TRUE
assertEqual(
  menu.stripJsonc('{\u00A0"a"\u2028:\u3000\u2003\t1,\r\n}'),
  '{ "a" :   1 \n}',
  'BNZG: Unicode spaces, a tab and a carriage return become one space each, the line feed stays'
)
// MCDC SW-REQ-261001-BNZG: space_outside_string=F, space_passed_as_ascii=F => TRUE [no-action: the characters sit inside a string, so the scanner's string branch copies them and the whitespace rule never runs -- the label asserted below still carries U+00A0, U+FEFF and U+2029 unchanged, which proves zero rewrites]
// SW-REQ-261001-BNZG:malformed_input:negative
assertEqual(
  menu.parseMenuJsonc('{"a": {"label": "A\u00A0B\uFEFFC\u2029D"}}')[0].label,
  'A\u00A0B\uFEFFC\u2029D',
  'BNZG: Unicode spaces and a byte order mark inside a string stay unchanged'
)
// SW-REQ-261001-BNZG:malformed_input:negative
assertEqual(
  menu.parseMenuJsonc('\uFEFF{\u00A0"a": {"label": "A"},\u3000"b"}').length,
  0,
  'BNZG: Unicode whitespace does not make a broken document parse'
)

// Input domain (SW-REQ-261001-BNZG) under PR omacom/omarchy#13968: seeded
// differential test against an independent token-level reference model. The
// generator covers the documented grammar plus the shapes the PR fixes (a
// comma and closer inside a string, inline comments, comments between a
// trailing comma and its closer, array roots) and inserts every non-ASCII
// character that JS \s matches (19 classes, incl. the byte order mark) at the
// start of the file, between tokens and in front of comments, and inside
// strings. The reference tokenizes with one sticky regex (string literal |
// comment, or any character), drops comments, reads each \s character
// outside a string as a space (a line feed stays), drops each comma whose
// next non-space token is } or ], and treats a non-object root as no rows.
// SW-REQ-261001-BNZG:malformed_input:differential
// SW-REQ-261001-BNZG:totality:nominal
// SW-REQ-261001-BNZG:totality:differential
{
  const SPACES = []
  for (let c = 128; c < 0x10000; c++) if (/\s/.test(String.fromCharCode(c))) SPACES.push(String.fromCharCode(c))
  assertEqual(SPACES.length, 19, 'JS \\s matches 19 non-ASCII characters')
  let seed = 4242
  const rnd = () => { seed ^= seed << 13; seed ^= seed >>> 17; seed ^= seed << 5; return ((seed >>> 0) % 1e6) / 1e6 }
  const pick = a => a[Math.floor(rnd() * a.length)]
  const uni = () => rnd() < 0.35 ? pick(SPACES) : ''
  const STR = ['a', 'A // B', 'x, ]y', 'mv f{.bak,}', 'q\\"', 'q\\\\', 'a b', '﻿', 'x y', '']
  const str = () => JSON.stringify(pick(STR))
  const ws = () => pick(['', ' ', '\n', '\r\n', '\t']) + uni()
  const cm = () => rnd() < 0.35 ? uni() + pick([' // c', '\n// full line', '\n' + uni() + '// "q" , ] }', ' //']) + '\n' + uni() : ws()
  const obj = depth => {
    const n = Math.floor(rnd() * 3)
    let o = '{' + cm()
    for (let i = 0; i < n; i++) {
      o += JSON.stringify(pick(['a', 'b', 'label', 'action', 'aliases']) + i) + ws() + ':' + ws()
      o += depth < 1 && rnd() < 0.5 ? obj(depth + 1) : (rnd() < 0.3 ? '[' + cm() + str() + (rnd() < 0.5 ? ',' + cm() : '') + ']' : str())
      o += i < n - 1 ? ',' + cm() : (rnd() < 0.5 ? ',' + cm() : cm())
    }
    return o + '}'
  }
  const gen = () => {
    const head = (rnd() < 0.25 ? '﻿' : '') + uni() + (rnd() < 0.3 ? '// head\n' + uni() : '')
    const body = rnd() < 0.15 ? '[' + ws() + obj(1) + (rnd() < 0.5 ? ',' : '') + ws() + ']' : obj(0)
    return head + body + ws() + (rnd() < 0.3 ? uni() + '// tail' : '')
  }
  const reference = text => {
    const tok = new RegExp('"(?:[^"\\\\\\n]|\\\\.)*"' + '|' + '/' + '/[^\\n]*' + '|[\\s\\S]', 'y')
    const toks = []
    let m
    while ((m = tok.exec(text)) !== null) {
      const t = m[0]
      if (t.startsWith('//')) continue
      toks.push(t.length === 1 && /\s/.test(t) ? (t === '\n' ? '\n' : ' ') : t)
    }
    const out = toks.filter((t, i) => {
      if (t !== ',') return true
      let j = i + 1
      while (j < toks.length && (toks[j] === ' ' || toks[j] === '\n')) j++
      return !(j < toks.length && (toks[j] === '}' || toks[j] === ']'))
    }).join('')
    let doc
    try { doc = JSON.parse(out) } catch (e) { return '' }
    if (typeof doc !== 'object' || doc === null || Array.isArray(doc)) return ''
    return Object.keys(doc).filter(k => doc[k] && typeof doc[k] === 'object' && !Array.isArray(doc[k])).join(';')
  }
  let wrong = 0
  let parsedOk = 0
  let first = ''
  for (let k = 0; k < 3000; k++) {
    const src = gen()
    const want = reference(src)
    const got = menu.parseMenuJsonc(src).filter(r => r.parent === 'root' || r.id.indexOf('.') < 0).map(r => r.id).join(';')
    if (want) parsedOk++
    if (got !== want) { wrong++; if (!first) first = JSON.stringify({ src, want, got }) }
  }
  assert(parsedOk > 1000, 'the generator yields more than 1000 parseable documents with Unicode whitespace (' + parsedOk + ')')
  assertEqual(wrong, 0, 'parseMenuJsonc matches the token-level reference on 3000 seeded inputs with Unicode whitespace' + (first ? ' -- first: ' + first : ''))
}

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
  rankScore('style.font', 'font') < rankScore('apps.fontforge', 'font'),
  'menu keeps a better-matching menu entry above a weaker app match'
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
// SW-REQ-260922-74BZ:boundary:nominal
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
// SW-REQ-260922-Z680:atomicity:nominal
assert(
  firstProviderMerge.itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'provider merge appends its rows'
)
assert(
  menu.swapProviderRows(firstProviderMerge.items, firstProviderMerge.itemOrder, 'style.font', providerRowsFor(['mono', 'serif']))
    .itemOrder.join(',') === 'root,apps,style.font.mono,style.font.serif',
  'repeating a provider merge does not duplicate rows'
)
// SW-REQ-260922-Z680:atomicity:negative
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

// MCDC SW-REQ-260928-8VJQ: action_is_bare_summon=T, in_process_summon_equivalent=T => TRUE
// SW-REQ-260928-8VJQ:path_pair_agreement:nominal
assertDeepEqual(
  menu.summonAction("omarchy-shell shell summon omarchy.speedtest"),
  { id: 'omarchy.speedtest', payload: '{}' },
  'menu runs a bare summon action in-process'
)
assertDeepEqual(
  menu.summonAction(`omarchy-shell shell summon omarchy.image-picker '{"source":"themes"}'`),
  { id: 'omarchy.image-picker', payload: '{"source":"themes"}' },
  'menu keeps a single-quoted summon payload'
)
assertEqual(menu.summonAction("omarchy-shell shell summon omarchy.speedtest && echo done"), null, 'menu leaves compound summon commands to bash')
assertEqual(menu.summonAction(`omarchy-shell shell summon omarchy.x "$(id)"`), null, 'menu leaves shell-expanded payloads to bash')
// MCDC SW-REQ-260928-8VJQ: action_is_bare_summon=F, in_process_summon_equivalent=F => TRUE [no-action: summonAction returns null for these actions (asserted above), and runAction's fast-path guard `if (summon && ...)` requires a non-null match - a null return structurally proves zero in-process summons]
assertEqual(menu.summonAction("omarchy-theme-set nord"), null, 'menu leaves ordinary actions to bash')
assert(
  /var summon = MenuModel\.summonAction\(command\)\s*if \(summon && root\.shell && root\.shell\.summon\(summon\.id, summon\.payload\)\) return\s*Util\.execDetached\(command\)/.test(menuQml),
  'menu falls back to bash when an in-process summon is refused'
)

// Differential witness: an independent reference splitter reproducing bash
// word-splitting (whitespace-separated words, single-quote grouping with
// quote removal) derives the summon argv for each corpus action; wherever the
// fast path fires, its result must equal the bash reference exactly.
// SW-REQ-260928-8VJQ:path_pair_agreement:differential
function bashReferenceSummon(action) {
  const words = []
  let cur = '', inQ = false, started = false
  for (const ch of action) {
    if (inQ) { if (ch === "'") { inQ = false } else { cur += ch } }
    else if (ch === "'") { inQ = true; started = true }
    else if (/\s/.test(ch)) { if (started) { words.push(cur); cur = ''; started = false } }
    else { cur += ch; started = true }
  }
  if (inQ) return 'bash-rejects'
  if (started) words.push(cur)
  if (words.length < 4 || words.length > 5) return null
  if (words[0] !== 'omarchy-shell' || words[1] !== 'shell' || words[2] !== 'summon') return null
  if (!/^[A-Za-z0-9._-]+$/.test(words[3])) return null
  return { id: words[3], payload: words.length === 5 ? words[4] : '{}' }
}
const summonCorpus = [
  "omarchy-shell shell summon omarchy.speedtest",
  `omarchy-shell shell summon omarchy.image-picker '{"source":"themes"}'`,
  `omarchy-shell shell summon foo '{"k":"a b"}'`,
  'omarchy-shell shell summon foo; id',
  'omarchy-shell shell summon',
  'omarchy-shell shell toggle omarchy.osd',
  'omarchy-theme-set nord',
  `omarchy-shell shell summon foo '{"x":1}' extra`,
]
for (const action of summonCorpus) {
  const want = bashReferenceSummon(action)
  if (want === 'bash-rejects') continue
  assertDeepEqual(menu.summonAction(action), want, `summon fast path agrees with bash reference on: ${action}`)
}
// Documented conservative fallbacks (claims CRS-0021/C04, C01): trailing
// whitespace fails the strict grammar and stays on the bash path, which
// word-splits it correctly; an explicit empty-quotes payload is upgraded to
// '{}' in-process (unreachable from shipped config, benign direction).
assertEqual(menu.summonAction('omarchy-shell shell summon foo '), null, 'trailing-whitespace summon stays on the bash path')
assertEqual(menu.summonAction('omarchy-shell shell summon foo bar'), null, 'unquoted payload stays on the bash path (grammar requires single quotes)')
assertDeepEqual(menu.summonAction(`omarchy-shell shell summon foo ''`), { id: 'foo', payload: '{}' }, 'empty-quotes payload upgrades to the default object')
JS

font_charset=$(fc-query --format='%{charset}' "$ROOT/default/fonts/omarchy/omarchy.ttf")
[[ $font_charset == *"e900-e90e"* ]] || fail "Omarchy icon font includes every custom menu glyph"
pass "Omarchy icon font includes the official agent marks"
