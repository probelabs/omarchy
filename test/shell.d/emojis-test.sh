#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-261004-JATY, SW-REQ-261004-H41S

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const emojis = requireFromRoot('shell/plugins/emojis/EmojiSearch.js')

const raw = fs.readFileSync(path.join(root, 'shell/plugins/emojis/emojis.json'), 'utf8')
const data = emojis.parseEmojis(raw)

assert(data.length > 1000, 'emoji dataset parses')
assertDeepEqual(emojis.parseEmojis('{'), [], 'invalid emoji JSON parses as empty list')
assertDeepEqual(emojis.parseEmojis('{"e":"nope"}'), [], 'non-array emoji JSON parses as empty list')

const fixture = [
  { e: 'a', k: 'grinning face smile happy' },
  { e: 'b', k: 'face with tears of joy joy tears' },
  { e: 'c', k: 'flag: united states us america' }
]

assertDeepEqual(
  emojis.filterEmojis(fixture, '  JOY  ').map(item => item.e),
  ['b'],
  'emoji filtering trims and lowercases query'
)

assertDeepEqual(
  emojis.filterEmojis(fixture, '', 2).map(item => item.e),
  ['a', 'b'],
  'emoji filtering honors result limit'
)

assertDeepEqual(
  emojis.filterEmojis(fixture, '', 0),
  [],
  'emoji filtering supports zero result limit'
)

assertEqual(
  emojis.filterEmojis(data, 'face with tears')[0].e,
  '\u{1F602}',
  'emoji filtering finds face with tears of joy'
)

// The picker selects the first result, so Enter inserts it: the query as a
// whole keyword comes first, then a keyword that starts with it, then one that
// only contains it, each group in file order.
const ranked = [
  { e: 'inside', k: 'broken heart' },
  { e: 'start1', k: 'okay' },
  { e: 'start2', k: 'okra' },
  { e: 'whole1', k: 'ok hand' },
  { e: 'whole2', k: 'ok button' }
]

assertDeepEqual(
  emojis.filterEmojis(ranked, 'ok').map(item => item.e),
  ['whole1', 'whole2', 'start1', 'start2', 'inside'],
  'emoji filtering ranks whole keywords, then keyword starts, then matches inside a word'
)

assertDeepEqual(
  [1, 2].map(limit => emojis.filterEmojis(ranked, 'ok', limit).map(item => item.e)),
  [['whole1'], ['whole1', 'whole2']],
  'emoji filtering applies the result limit after ranking'
)

assertDeepEqual(
  emojis.filterEmojis([
    { e: 'inside', k: 'woman' },
    { e: 'colon', k: 'man: beard' },
    { e: 'underscore', k: 'red_haired_man' },
    { e: 'hyphen', k: 'he-man' },
    { e: 'later', k: 'superman man' }
  ], 'man').map(item => item.e),
  ['colon', 'underscore', 'hyphen', 'later', 'inside'],
  'emoji filtering ends a keyword at punctuation such as _, - and :'
)

assertDeepEqual(
  emojis.filterEmojis([
    { e: 'digits', k: '100 points' },
    { e: 'number', k: '10 ten' }
  ], '10').map(item => item.e),
  ['number', 'digits'],
  'emoji filtering counts digits as part of a keyword'
)

assertDeepEqual(
  ['face with', 'nothing like this'].map(query => emojis.filterEmojis([
    { e: 'inside', k: 'surface without' },
    { e: 'whole', k: 'face with tears' }
  ], query).map(item => item.e)),
  [['whole', 'inside'], []],
  'emoji filtering ranks a multi-word query the same way and finds nothing for no match'
)

assertEqual(
  emojis.filterEmojis(fixture, '', 1.5).length,
  2,
  'emoji filtering rounds a fractional limit up'
)

assertDeepEqual(
  emojis.filterEmojis([
    { e: 'inside', k: 'thereafter' },
    { e: 'quoted', k: 'japanese “here” button' }
  ], 'here').map(item => item.e),
  ['quoted', 'inside'],
  'emoji filtering ends a keyword at typographic quotes'
)

assertDeepEqual(
  ['te', 's'].map(query => emojis.filterEmojis([
    { e: 'accented', k: 'côte' },
    { e: 'apostrophe', k: 'woman’s boot' },
    { e: 'ascii', k: "man's boot" },
    { e: 'start', k: 'tender shoe' }
  ], query).map(item => item.e)),
  [['start', 'accented'], ['start', 'apostrophe', 'ascii']],
  'emoji filtering keeps accented letters and apostrophes inside their word'
)

// On the shipped data each of these words now puts the emoji it names first.
assertDeepEqual(
  ['ok', 'key', 'tea', 'fr', 'ear'].map(word => (emojis.filterEmojis(data, word)[0] || {}).e),
  ['\u{1F44C}', '\u{1F510}', '\u{1F375}', '\u{1F1EB}\u{1F1F7}', '\u{1F442}'],
  'emoji filtering finds the OK hand, key lock, tea, French flag and ear first'
)
JS

TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT

mkdir -p "$TMPDIR/bin"

cat >"$TMPDIR/bin/wl-copy" <<'SH'
#!/bin/bash
args="$*"
target="$WL_COPY_OUT"
if [[ $args == "--type text/plain --sensitive --foreground" ]]; then
  target="$WL_COPY_EMOJI_OUT"
fi

printf '%s\n' "$args" >"$target.args"
cat >"$target"
SH

cat >"$TMPDIR/bin/wtype" <<'SH'
#!/bin/bash
printf '%s\n' "$*" >"$WTYPE_OUT"
SH

cat >"$TMPDIR/bin/sleep" <<'SH'
#!/bin/bash
exit 0
SH

chmod +x "$TMPDIR/bin/wl-copy" "$TMPDIR/bin/wtype" "$TMPDIR/bin/sleep"

WL_COPY_OUT="$TMPDIR/copy" WL_COPY_EMOJI_OUT="$TMPDIR/emoji" WTYPE_OUT="$TMPDIR/wtype" PATH="$TMPDIR/bin:$PATH" \
  "$ROOT/bin/omarchy-menu-emoji-insert" "😀"

[[ $(<"$TMPDIR/emoji") == "😀" ]] || fail "emoji insert helper copies emoji transiently"
pass "emoji insert helper copies emoji transiently"

[[ $(<"$TMPDIR/emoji.args") == "--type text/plain --sensitive --foreground" ]] || fail "emoji insert helper serves sensitive transient clipboard in foreground"
pass "emoji insert helper serves transient clipboard in foreground"

[[ $(<"$TMPDIR/wtype") == "-M shift -k Insert -m shift" ]] || fail "emoji insert helper pastes with shift insert"
pass "emoji insert helper pastes with shift insert"
