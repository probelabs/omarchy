#!/bin/bash

# Proof-side witness for SW-REQ-261004-H41S (mirror only; not part of the
# upstream change). The menu's Trigger > Emoji row opens the emoji picker. This
# test replays the emoji inputs of the behaviour-diff corpus through
# test/bdiff/harness.mjs, which runs this checkout's real picker functions from
# shell/plugins/emojis/Emojis.qml (open, loadEmojis, setFilter, rebuildDisplay,
# activateIndex, applySelected) with its EmojiSearch.js and emojis.json under
# node:vm, and records the emoji that Enter hands to omarchy-menu-emoji-insert.

# Verifies: SW-REQ-261004-H41S
#mcdc:ignore:defensive SW-REQ-261004-H41S: emoji_query_typed=T, emoji_results_ranked=F => FALSE -- filterEmojis has one path for a search text that is not empty: it puts every match in the whole-word, keyword-start or inside list as it reads emojis.json and returns the three lists joined, cut at the limit; a list out of that order needs the single file-order list of upstream 393a43d4 back [reviewed: REVIEW-261003-NYQY]
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
const steps = out => out.split('\n').filter(line => /^(shown|top|enter) /.test(line)).slice(2).join('\n')
const insert = emoji => `enter $OMARCHY_PATH/bin/omarchy-menu-emoji-insert ${emoji} opened=false`

// Each case: description, input, the lines the harness prints after the
// picker opens (what it lists after each step, and what Enter picks).
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
  ['car lists cars first, not the fearful face', 'seq-emoji-car.events', [
    'shown query="car" count=30 first=🚃 cursor=0',
    'top 🚃 🚋 🚓 🚔 🚗 🏎️ 🚨 🤸 🤸‍♂️ 🤸‍♀️ 🥕 🎠',
    insert('🚃')]],
  ['pen lists pens first, then keywords that start with pen', 'seq-emoji-pen.events', [
    'shown query="pen" count=20 first=🖋️ cursor=0',
    'top 🖋️ 🖊️ 🔏 😔 🐧 ✏️ 📝 🤗 🫢 😮 😦 👐',
    insert('🖋️')]],
  ['red lists the red heart first, not the tired face', 'seq-emoji-red.events', [
    'shown query="red" count=34 first=❤️ cursor=0',
    'top ❤️ 👨‍🦰 👩‍🦰 🧑‍🦰 🍎 🧧 🀄 🏮 ❓ ❗ ⭕ 🔴',
    insert('❤️')]],
  ['a leading space and capitals rank as ok', 'seq-emoji-case.events', [
    'shown query=" OK" count=36 first=👌 cursor=0',
    'top 👌 👍 🙆 🙆‍♂️ 🙆‍♀️ 🆗 💔 👀 🧑‍🍳 👨‍🍳 👩‍🍳 🍳',
    insert('👌')]],
  ['the list ranks again after each key, and after Escape clears the search', 'seq-emoji-steps.events', [
    'shown query="o" count=1000 first=⭕ cursor=0',
    'top ⭕ 🅾️ 🤣 😂 🤗 🤭 🫢 😮 😦 😨 🤬 💩',
    'shown query="ok" count=36 first=👌 cursor=0',
    'top 👌 👍 🙆 🙆‍♂️ 🙆‍♀️ 🆗 💔 👀 🧑‍🍳 👨‍🍳 👩‍🍳 🍳',
    'shown query="" count=1000 first=😀 cursor=0',
    'top 😀 😃 😄 😁 😆 😅 🤣 😂 🙂 🙃 🫠 😉',
    'shown query="ok" count=36 first=👌 cursor=0',
    'top 👌 👍 🙆 🙆‍♂️ 🙆‍♀️ 🆗 💔 👀 🧑‍🍳 👨‍🍳 👩‍🍳 🍳',
    insert('👌')]],
  ['one letter that matches more than 1000 emojis shows the first 1000 of the ranked list', 'seq-emoji-letter.events', [
    'shown query="e" count=1000 first=😃 cursor=0',
    'top 😃 😄 😁 😊 🤩 😚 😙 🫢 🫣 🤨 😑 🙄',
    insert('😃')]],
  ['a phrase of several words still finds its emoji', 'seq-emoji-phrase.events', [
    'shown query="face with tears" count=1 first=😂 cursor=0',
    'top 😂',
    insert('😂')]],
  ['a search text that matches nothing lists nothing, and Enter picks nothing', 'seq-emoji-none.events', [
    'shown query="zzqx" count=0 first=- cursor=-',
    'top -',
    'enter - opened=true']],
  ['whole keywords that already come first keep their order', 'seq-emoji-cat.events', [
    'shown query="cat" count=20 first=😺 cursor=0',
    'top 😺 😸 😹 😻 😼 😽 🙀 😿 😾 🐱 🐈 🐈‍⬛',
    insert('😺')]],
  // MCDC SW-REQ-261004-H41S: emoji_query_typed=F, emoji_results_ranked=F => TRUE [no-action: with no search text the picker lists the first 1000 emojis of emojis.json in file order; the check below compares the whole list, by its order digest, with the file]
  ['with no search text the picker lists emojis.json in file order, and Enter picks the first', 'seq-emoji-empty.events', [
    insert('😀')]],
]

const outputs = {}
for (const [description, input, expected] of cases) {
  outputs[input] = run(input)
  assertEqual(steps(outputs[input]), expected.join('\n'), description)
}

const inputs = fs.readdirSync(corpus).filter(name => /^seq-emoji-.*\.events$/.test(name)).sort()
assertDeepEqual(inputs, Object.keys(outputs).sort(), 'every emoji input of the corpus is asserted here')

// The whole list, not only the first 12: an oracle written from the
// requirement text ranks emojis.json for each search text the harness shows,
// and its digests must match the harness output.
const data = JSON.parse(fs.readFileSync(path.join(root, 'shell/plugins/emojis/emojis.json'), 'utf8'))
const digest = list => crypto.createHash('sha256').update(list.join('\n')).digest('hex').slice(0, 12)
const ranked = query => {
  const needle = query.trim().toLowerCase()
  const groups = [[], [], []]
  for (const item of data) {
    const text = ' ' + String(item.k || '').toLowerCase() + ' '
    if (!needle || text.includes(' ' + needle + ' ')) groups[0].push(item.e)
    else if (text.includes(' ' + needle)) groups[1].push(item.e)
    else if (text.includes(needle)) groups[2].push(item.e)
  }
  return groups[0].concat(groups[1], groups[2]).slice(0, 1000)
}
let states = 0
for (const input of inputs) {
  const lines = outputs[input].split('\n')
  for (let i = 0; i < lines.length; i++) {
    const shown = /^shown query=("(?:[^"\\]|\\.)*") count=(\d+) /.exec(lines[i])
    if (!shown) continue
    const list = ranked(JSON.parse(shown[1]))
    const want = `digest order=${digest(list)} set=${digest(list.slice().sort())}`
    if (+shown[2] !== list.length || lines[i + 2] !== want) {
      fail(`the picker lists every match in the ranked order (${input}, query ${shown[1]})`, `expected: count=${list.length} ${want}\nactual:   count=${shown[2]} ${lines[i + 2]}`)
    }
    states++
  }
}
assert(states === 28, 'the picker lists every match in the ranked order, for every search text the inputs show', `states checked: ${states}`)

const fileOrder = data.filter(item => item && item.e).slice(0, 1000).map(item => item.e)
const opened = outputs['seq-emoji-empty.events'].split('\n')
assertEqual(opened[4], `digest order=${digest(fileOrder)} set=${digest(fileOrder.slice().sort())}`, 'with no search text the list is the first 1000 emojis of emojis.json, in file order')
JS
