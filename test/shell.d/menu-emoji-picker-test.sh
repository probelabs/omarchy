#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-261004-JATY
#mcdc:ignore:defensive SW-REQ-261004-JATY: emoji_listed=T, emoji_present=F, emoji_within_limit=F, query_in_keywords=F => FALSE -- filterEmojis skips a missing entry or one with no emoji before it tests the keywords or pushes, so such an entry reaches out.push only if that continue is removed [reviewed: REVIEW-261004-TD57]
#mcdc:ignore:defensive SW-REQ-261004-JATY: emoji_listed=T, emoji_present=F, emoji_within_limit=T, query_in_keywords=T => FALSE -- the emoji check runs before the keyword test, so matching keywords cannot list an entry with no emoji [reviewed: REVIEW-261004-TD57]
#mcdc:ignore:defensive SW-REQ-261004-JATY: emoji_listed=T, emoji_present=T, emoji_within_limit=F, query_in_keywords=T => FALSE -- a limit of 0 returns an empty list before the loop, and the loop breaks as soon as the list holds the limit, so a match past the limit is pushed only if that break is removed [reviewed: REVIEW-261004-TD57]
#mcdc:ignore:defensive SW-REQ-261004-JATY: emoji_listed=T, emoji_present=T, emoji_within_limit=T, query_in_keywords=F => FALSE -- out.push sits inside the test that the search text is empty or the keywords contain it, so a non-matching entry is listed only if that test is removed [reviewed: REVIEW-261004-TD57]

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The emoji picker's search (shell/plugins/emojis/EmojiSearch.js, run by
# Emojis.qml on every keystroke; Enter inserts the first entry): an emoji is
# listed exactly when the entry has an emoji, its keywords contain the search
# text and the list still has room for it. The order of the list is not part
# of this test.
run_node_test <<'JS'
// Verifies: SW-REQ-261004-JATY
const emojiSearch = requireFromRoot('shell/plugins/emojis/EmojiSearch.js')
const listed = (emojis, query, limit) => emojiSearch.filterEmojis(emojis, query, limit).map(item => item.e)
const sorted = values => values.slice().sort()
const emojis = [
  { e: 'A', k: 'grinning face smile' },
  { e: 'B', k: 'cat face' },
  { e: '', k: 'empty emoji face' },
  null,
  { e: 'C', k: 'OK hand ok_hand' },
  { e: 'D' },
  { e: 'E', k: 'teacup tea' },
]

// MCDC SW-REQ-261004-JATY: emoji_listed=T, emoji_present=T, emoji_within_limit=T, query_in_keywords=T => TRUE
assertDeepEqual(sorted(listed(emojis, 'face', 10)), ['A', 'B'], 'a search lists every emoji whose keywords contain it')
assertDeepEqual(listed(emojis, '  OK ', 10), ['C'], 'the search text is trimmed and case is ignored')
assertDeepEqual(sorted(listed(emojis, '', 10)), ['A', 'B', 'C', 'D', 'E'], 'an empty search text lists every emoji')
assertDeepEqual(sorted(listed(emojis, 'tea')), ['E'], 'with no limit given the picker lists the match')

// Not listed: keywords without the search text.
assertDeepEqual(listed(emojis, 'dog', 10), [], 'an emoji whose keywords do not contain the search text is not listed')
assert(!listed(emojis, 'face', 10).includes('E'), 'a non-matching emoji stays out while others match')

// Not listed: no emoji, even with matching keywords.
assert(!listed(emojis, 'empty', 10).length, 'an entry with an empty emoji is not listed, even when its keywords match')
assertDeepEqual(listed([null, { k: 'face' }, { e: 'F', k: 'face' }], 'face', 10), ['F'], 'a missing entry or one with no emoji is skipped')

// Not listed: no room left in the list.
const many = []
for (let i = 0; i < 1005; i++) many.push({ e: 'x' + i, k: 'face ' + i })
assertEqual(listed(many, 'face').length, 1000, 'with no limit given the list stops at 1000 matching emojis')
assertEqual(listed(many, 'face', 3).length, 3, 'the list stops at the limit the caller gives')
assert(listed(many, 'face', 3).every(e => /^x\d+$/.test(e)), 'every emoji in a full list matches')
assertDeepEqual(listed(emojis, 'face', 0), [], 'a limit of 0 lists nothing')
assertDeepEqual(listed(emojis, 'face', -2), [], 'a negative limit lists nothing')
assertEqual(listed(many, 'face', 'many').length, 1000, 'a limit that is not a number counts as 1000')

// MCDC SW-REQ-261004-JATY: emoji_listed=F, emoji_present=F, emoji_within_limit=F, query_in_keywords=F => TRUE
const full = many.slice(0, 3).concat([{ k: 'dog' }])
assert(!emojiSearch.filterEmojis(full, 'face', 3).includes(full[3]), 'an entry with no emoji and no match after a full list is not listed')
assertEqual(listed(full, 'face', 3).length, 3, 'a full list keeps only the matching emojis before it')

// What the picker reads: text that is not a JSON array gives an empty list.
assertDeepEqual(emojiSearch.parseEmojis('[{"e":"A","k":"a"}]'), [{ e: 'A', k: 'a' }], 'a JSON array is read as the emoji list')
assertDeepEqual(emojiSearch.parseEmojis('{"e":"A"}'), [], 'a JSON object gives an empty list')
assertDeepEqual(emojiSearch.parseEmojis('not json'), [], 'text that does not parse gives an empty list')
assertDeepEqual(listed('not a list', 'face', 10), [], 'a value that is not a list gives an empty list')
JS
