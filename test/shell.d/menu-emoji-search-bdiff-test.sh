#!/bin/bash

# Proof-side witness for SW-REQ-261004-H41S (mirror only; not part of the
# upstream change). The menu's Trigger > Emoji row opens the emoji picker. This
# test replays the emoji inputs of the behaviour-diff corpus through
# test/bdiff/harness.mjs, which runs this checkout's real picker functions from
# shell/plugins/emojis/Emojis.qml (open, loadEmojis, setFilter, rebuildDisplay,
# activateIndex, applySelected) with its EmojiSearch.js and emojis.json under
# node:vm, and records the emoji that Enter hands to omarchy-menu-emoji-insert.

# Verifies: SW-REQ-261004-H41S
#mcdc:ignore:defensive SW-REQ-261004-H41S: emoji_query_typed=T, emoji_results_ranked=F => FALSE -- filterEmojis has one path for a search text that is not empty: matchRank puts every match in the whole-word, keyword-start or inside group as it reads emojis.json, and it returns the three groups joined, cut at the limit; a list out of that order needs the single file-order list of upstream 393a43d4 back [reviewed: REVIEW-261004-9G63]
# mcdc:witness-out-of-process

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The harness output does not depend on the locale; LC_ALL=C.UTF-8 pins it
# anyway, as the other harness witness does.
LC_ALL=C.UTF-8 run_node_test <<'JS'
const fs = require('fs')
const crypto = require('crypto')
const { execFileSync } = require('child_process')

const harness = path.join(root, 'test/bdiff/harness.mjs')
const corpus = path.join(root, 'test/bdiff/corpus/lifecycle')
const run = input => execFileSync('node', [harness, root, path.join(corpus, input)], { encoding: 'utf8', env: Object.assign({}, process.env, { LC_ALL: 'C.UTF-8' }) })
// The harness output, read by its labels: the state the picker opens with
// (the shown, top and digest lines after "opened"), then each later state and
// each Enter, in order.
const parse = out => {
  const states = []
  const enters = []
  let opened = false
  for (const line of out.split('\n')) {
    const label = line.split(' ')[0]
    if (label === 'opened') opened = true
    else if (label === 'shown') states.push({ shown: line, query: JSON.parse(/^shown query=("(?:[^"\\]|\\.)*")/.exec(line)[1]), count: +/ count=(\d+) /.exec(line)[1] })
    else if ((label === 'top' || label === 'digest') && states.length) states[states.length - 1][label] = line
    else if (label === 'enter') { enters.push(line); if (states.length) states[states.length - 1].enter = line }
  }
  return { opened, states, enters }
}
const steps = out => {
  const { states } = parse(out)
  const lines = []
  for (const state of states.slice(1)) lines.push(state.shown, state.top)
  for (const line of out.split('\n')) if (line.split(' ')[0] === 'enter') lines.push(line)
  return lines.join('\n')
}
const insert = emoji => `enter $OMARCHY_PATH/bin/omarchy-menu-emoji-insert ${emoji} opened=false`

// Each case: description, input, the lines the harness prints after the
// picker opens (what it lists after each step, and what Enter picks).
// The counts and the first 12 emojis are a snapshot of the shipped
// emojis.json, like the upstream test's check of ok, key, tea, fr and ear:
// a change to the data changes them. Cases marked "control" print the same
// at the base, where the old search runs; the others differ there.
const cases = [
  // Reproduces: KI-MENU-EMOJI-SEARCH-INSIDE-WORD
  // MCDC SW-REQ-261004-H41S: emoji_query_typed=T, emoji_results_ranked=T => TRUE
  ['ok lists the OK hand first, and Enter picks it, not the broken heart', 'seq-emoji-ok.events', [
    'shown query="ok" count=36 first=👌 cursor=0',
    'top 👌 👍 🙆 🙆‍♂️ 🙆‍♀️ 🆗 💔 👀 🧑‍🍳 👨‍🍳 👩‍🍳 🍳',
    insert('👌')]],
  ['tea lists the teacup first, not the face with tears of joy', 'seq-emoji-tea.events', [
    'shown query="tea" count=20 first=🍵 cursor=0',
    'top 🍵 🧋 😂 🥲 🥹 😢 😹 😿 🧑‍🏫 👨‍🏫 👩‍🏫 👥',
    insert('🍵')]],
  ['fr lists the flag of France first, not the cold face', 'seq-emoji-fr.events', [
    'shown query="fr" count=32 first=🇫🇷 cursor=0',
    'top 🇫🇷 🥶 🙁 ☹️ 😦 😤 🙍 🙍‍♂️ 🙍‍♀️ 🐥 🐸 🍌',
    insert('🇫🇷')]],
  ['key lists the locks and keys first, not the pile of poo (hankey)', 'seq-emoji-key.events', [
    'shown query="key" count=29 first=🔐 cursor=0',
    'top 🔐 🔑 🗝️ 🎹 ⌨️ #️⃣ *️⃣ 0️⃣ 1️⃣ 2️⃣ 3️⃣ 4️⃣',
    insert('🔐')]],
  ['car lists cars first, not the fearful face', 'seq-emoji-car.events', [
    'shown query="car" count=30 first=🚃 cursor=0',
    'top 🚃 🚋 🚓 🚔 🚗 🚙 🏎️ 🚨 💅 🤸 🤸‍♂️ 🤸‍♀️',
    insert('🚃')]],
  ['pen lists pens first, then keywords that start with pen', 'seq-emoji-pen.events', [
    'shown query="pen" count=20 first=🖋️ cursor=0',
    'top 🖋️ 🖊️ 🔏 😔 🐧 ✏️ 📝 🤗 🫢 😮 😦 👐',
    insert('🖋️')]],
  ['red lists the red heart first, not the sleepy face', 'seq-emoji-red.events', [
    'shown query="red" count=34 first=❤️ cursor=0',
    'top ❤️ 👨‍🦰 👩‍🦰 🧑‍🦰 🍎 🚗 🧧 🀄 🏮 ❓ ❗ ⭕',
    insert('❤️')]],
  ['a colon or an underscore ends a keyword: man: beard and red_haired_man rank as whole words', 'seq-emoji-man.events', [
    'shown query="man" count=205 first=👨 cursor=0',
    'top 👨 🧔‍♂️ 👨‍🦰 👨‍🦱 👨‍🦳 👨‍🦲 👱‍♂️ 👴 🙍‍♂️ 🙎‍♂️ 🙅‍♂️ 🙆‍♂️',
    insert('👨')]],
  ['a leading space and capitals rank as ok', 'seq-emoji-case.events', [
    'shown query=" OK" count=36 first=👌 cursor=0',
    'top 👌 👍 🙆 🙆‍♂️ 🙆‍♀️ 🆗 💔 👀 🧑‍🍳 👨‍🍳 👩‍🍳 🍳',
    insert('👌')]],
  ['the list ranks again after each key, and after Escape clears the search', 'seq-emoji-steps.events', [
    'shown query="o" count=1000 first=🎃 cursor=0',
    'top 🎃 ⭕ 🅾️ 🤣 😂 😛 😜 😝 🤗 🤭 🫢 😵',
    'shown query="ok" count=36 first=👌 cursor=0',
    'top 👌 👍 🙆 🙆‍♂️ 🙆‍♀️ 🆗 💔 👀 🧑‍🍳 👨‍🍳 👩‍🍳 🍳',
    'shown query="" count=1000 first=😀 cursor=0',
    'top 😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉',
    'shown query="ok" count=36 first=👌 cursor=0',
    'top 👌 👍 🙆 🙆‍♂️ 🙆‍♀️ 🆗 💔 👀 🧑‍🍳 👨‍🍳 👩‍🍳 🍳',
    insert('👌')]],
  ['one letter that matches more than 1000 emojis shows the first 1000 of the ranked list', 'seq-emoji-letter.events', [
    'shown query="e" count=1000 first=📧 cursor=0',
    'top 📧 😃 😄 😁 😊 😍 🤩 😚 😙 😜 😝 🫢',
    insert('📧')]],
  ['control: a phrase of several words still finds its emoji, as before', 'seq-emoji-phrase.events', [
    'shown query="face with tears" count=1 first=😂 cursor=0',
    'top 😂',
    insert('😂')]],
  ['control: a search text that matches nothing lists nothing, and Enter picks nothing, as before', 'seq-emoji-none.events', [
    'shown query="zzqx" count=0 first=- cursor=-',
    'top -',
    'enter - opened=true']],
  ['control: whole keywords that already come first keep their order, as before', 'seq-emoji-cat.events', [
    'shown query="cat" count=20 first=😺 cursor=0',
    'top 😺 😸 😹 😻 😼 😽 🙀 😿 😾 🐱 🐈 🐈‍⬛',
    insert('😺')]],
  ['a hyphen ends a word: mail lists e-mail first, before the email of the love letter', 'seq-emoji-mail.events', [
    'shown query="mail" count=7 first=📧 cursor=0',
    'top 📧 📬 📭 📫 📪 💌 ✉️',
    insert('📧')]],
  // MCDC SW-REQ-261004-H41S: emoji_query_typed=F, emoji_results_ranked=F => TRUE [no-action: with no search text the picker lists the first 1000 emojis of emojis.json in file order; the check below compares the whole list, by its order digest, with the file]
  ['control: with no search text the picker lists emojis.json in file order, and Enter picks the first, as before', 'seq-emoji-empty.events', [
    insert('😀')]],
]

const search = requireFromRoot('shell/plugins/emojis/EmojiSearch.js')
const outputs = {}
for (const [description, input, expected] of cases) {
  outputs[input] = run(input)
  assertEqual(steps(outputs[input]), expected.join('\n'), description)
}

const inputs = fs.readdirSync(corpus).filter(name => /^seq-emoji-.*\.events$/.test(name)).sort()
assertDeepEqual(inputs, Object.keys(outputs).sort(), 'every emoji input of the corpus is asserted here')

// Each input prints the state the picker opens with, then one state per
// @type or @clear line. The count of states comes from the corpus files.
const expectedStates = inputs.reduce((n, input) => n + 1 + fs.readFileSync(path.join(corpus, input), 'utf8').split('\n').filter(line => /^@(type|clear)( |$)/.test(line)).length, 0)
const allStates = inputs.flatMap(input => parse(outputs[input]).states)
assertEqual(allStates.length, expectedStates, 'the harness prints one state for the opening and one per @type or @clear line')

// The same emojis match as before the fix: the count is the number of
// emojis whose keywords contain the search text, at most 1000.
const data = JSON.parse(fs.readFileSync(path.join(root, 'shell/plugins/emojis/emojis.json'), 'utf8'))
const contains = query => data.filter(item => String(item.k || '').toLowerCase().includes(query.trim().toLowerCase())).length
for (const state of allStates) {
  if (state.count !== Math.min(1000, contains(state.query))) fail(`the picker lists every emoji that contains the search text (${JSON.stringify(state.query)})`, `count ${state.count}, contains ${contains(state.query)}`)
}
pass('the picker lists every emoji that contains the search text, up to 1000, for every state the inputs show')

// Golden groups, written from the requirement and read off the keywords in
// emojis.json: for each search text, emojis with the text as a whole word,
// then emojis with a keyword that starts with it, then emojis that hold it
// only inside a word. Each group is listed in file order. The picker's list
// must hold them in exactly this order: all of a group before the next group.
const golden = {
  ok: [['👌', '👍', '🙆'], [], ['💔', '👀', '🧑‍🍳']], // ok hand; thumbs up ok; gesturing ok | - | broken, look, cook
  tea: [['🍵', '🧋'], ['😂', '🥲', '🥹'], ['😤', '🧖']], // tea; bubble tea | tears, tear, tears | steam, steamy
  fr: [['🇫🇷'], ['🥶', '🙁', '☹️'], ['🌍', '🇨🇫', '🇿🇦']], // fr | freezing, frowning, frowning | africa x3
  key: [['🔐', '🔑', '🗝️'], ['🎹', '⌨️', '#️⃣'], ['💩', '🙈', '🙉']], // key x3 | keyboard x2, keycap | hankey, monkey, monkey
  car: [['🚃', '🚋', '🚓'], ['💅', '🤸'], ['😨', '🧕', '🧣']], // car x3 | care, cartwheeling | scared, headscarf, scarf
  pen: [['🖋️', '🖊️', '🔏'], ['😔', '🐧', '✏️'], ['🤗', '🫢', '😮']], // pen x3 | pensive, penguin, pencil | open x3
  red: [['❤️', '👨‍🦰', '👩‍🦰'], [], ['😪', '😨', '😩']], // red heart; red_haired x2 | - | tired, scared, tired
  man: [['👨', '🧔‍♂️', '👨‍🦰'], ['💅', '🧑‍🦽', '👩‍🦽'], ['🧔‍♀️', '👩']], // man; man: beard; red_haired_man | manicure, manual x2 | woman x2
  e: [['📧'], ['😃', '😄', '😁'], ['😀', '😆', '😅']], // e-mail | eyes x3 | grinning, satisfied, sweat
  o: [['🎃', '⭕', '🅾️'], ['🤣', '😂', '😛'], ['😃', '😄', '😅']], // jack-o-lantern; o; o button | on, of, out | joy, joy, hot
  cat: [['😺', '😸', '😹'], [], ['🍹', '🎓', '🔔']], // cat x3 | - | vacation, education, notification
  mail: [['📧', '📬', '📭'], ['📫', '📪'], ['💌', '✉️']], // e-mail; mailbox_with_mail; mailbox_with_no_mail | mailbox x2 | email x2
}
for (const [query, groups] of Object.entries(golden)) {
  const list = search.filterEmojis(data, query, 1000).map(item => item.e)
  const want = groups.flat()
  const at = want.map(emoji => list.indexOf(emoji))
  const ordered = at.every((index, i) => index >= 0 && (i === 0 || index > at[i - 1]))
  const bounds = groups.map(group => group.map(emoji => list.indexOf(emoji)))
  const separated = bounds.every((group, g) => bounds.slice(g + 1).flat().every(later => group.every(index => index < later)))
  if (!ordered || !separated) fail(`${query} lists whole words, then keyword starts, then matches inside a word`, `want ${want.join(' ')} at ${at.join(',')}`)
}
pass('each search text lists the golden whole words, then keyword starts, then matches inside a word')

// The list starts from emojis.json as parseEmojis reads it: the real file
// gives every entry, and text that is not a JSON array gives no emoji.
assertEqual(search.parseEmojis(fs.readFileSync(path.join(root, 'shell/plugins/emojis/emojis.json'), 'utf8')).length, data.length, 'the picker reads every entry of emojis.json')
assertDeepEqual([search.parseEmojis('{'), search.parseEmojis('{"e":"x"}'), search.parseEmojis('')], [[], [], []], 'text that is not a JSON array gives an empty list')

// filterEmojis on its own: the separators of the upstream test, and a
// fractional limit, which rounds up as before the fix.
assertDeepEqual(search.filterEmojis([{ e: 'in', k: 'woman' }, { e: 'colon', k: 'man: beard' }, { e: 'under', k: 'red_haired_man' }, { e: 'dash', k: 't-man' }], 'man').map(item => item.e), ['colon', 'under', 'dash', 'in'], 'a colon, an underscore or a hyphen ends a keyword; a letter does not')
assertEqual(search.filterEmojis(data, '', 1.5).length, 2, 'a fractional limit rounds up')
assertDeepEqual(search.filterEmojis([{ e: 'inside', k: 'nowhere' }, { e: 'quoted', k: 'japanese “here” button' }, { e: 'apostrophe', k: 'o’clock' }], 'here').map(item => item.e), ['quoted', 'inside'], 'curly quotes end a word')
assertDeepEqual(search.filterEmojis([{ e: 'accent', k: 'café' }, { e: 'whole', k: 'caf' }], 'caf').map(item => item.e), ['whole', 'accent'], 'an accented letter stays inside its word')
assertDeepEqual(search.filterEmojis([{ e: 'curly', k: 'woman’s boot' }, { e: 'straight', k: "woman's hat" }, { e: 'whole', k: 'woman' }], 'woman').map(item => item.e), ['whole', 'curly', 'straight'], 'an apostrophe stays inside its word')
assertDeepEqual(search.filterEmojis([{ e: 'start', k: 'okay' }, { e: 'later', k: 'broken ok' }], 'ok').map(item => item.e), ['later', 'start'], 'a whole word later in the keywords beats a match inside an earlier word')
assertDeepEqual(search.filterEmojis([{ e: 'inside', k: 'x100' }, { e: 'start', k: '100 points' }, { e: 'whole', k: 'number 10' }], '10').map(item => item.e), ['whole', 'start', 'inside'], 'digits are part of a word')

const digest = list => crypto.createHash('sha256').update(list.join('\n')).digest('hex').slice(0, 12)

// The one case where the shown set changes: e matches more than 1000 emojis,
// and the picker shows the first 1000 of the ranked list. Read from the
// requirement: split the keywords into words (letters with a case, digits and
// apostrophes); e is a whole word, or starts a word, or sits inside one. The
// shown set is every whole and every start match, then inside matches in file
// order up to 1000.
const words = text => text.toLowerCase().split(/[^0-9'’\p{Lu}\p{Ll}\p{Lt}]+/u)
const eWhole = data.filter(item => words(item.k).includes('e'))
const eStart = data.filter(item => !eWhole.includes(item) && words(item.k).some(word => word.startsWith('e')))
const eInside = data.filter(item => !eWhole.includes(item) && !eStart.includes(item) && item.k.toLowerCase().includes('e'))
const eShown = eWhole.concat(eStart, eInside).slice(0, 1000).map(item => item.e)
const letter = parse(outputs['seq-emoji-letter.events']).states.find(state => state.query === 'e')
assertEqual(letter.digest.split(' set=')[1], digest(eShown.slice().sort()), 'one letter shows every whole and start match, then inside matches in file order, up to 1000')
const firstInFile = data.filter(item => item.k.toLowerCase().includes('e')).slice(0, 1000).map(item => item.e)
assert(digest(firstInFile.slice().sort()) !== digest(eShown.slice().sort()), 'for one letter the shown set differs from the first 1000 matches in file order')
const fileOrder = data.filter(item => item && item.e).slice(0, 1000).map(item => item.e)
const opening = parse(outputs['seq-emoji-empty.events']).states[0]
assertEqual(opening.query === '' && opening.digest, `digest order=${digest(fileOrder)} set=${digest(fileOrder.slice().sort())}`, 'with no search text the list is the first 1000 emojis of emojis.json, in file order')
JS
