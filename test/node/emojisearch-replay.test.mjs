// Verifies: SW-REQ-261004-JATY
// node:test adapter for the proof js MC/DC engine: replays the EmojiSearch.js
// assertion bodies of test/shell.d/emojis-test.sh (the upstream test) and
// test/shell.d/menu-emoji-picker-test.sh (the SW-REQ-261004-JATY witnesses)
// under node:test so the engine's Babel instrumentation can observe
// EmojiSearch.js decisions. Both scripts pipe a prelude and their
// `run_node_test <<'JS'` body to plain `node`, which the js engine's
// node/vitest runner contract cannot drive (menu dogfood finding M12, the
// same reason as menumodel-replay.test.mjs). The bodies are read from the
// scripts at run time, not copied, so each script stays the one source of
// truth: a change to either is replayed as it is.
import { test } from 'node:test'
import fs from 'node:fs'
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
// EmojiSearch.js is CommonJS (module.exports). It MUST reach the engine
// through an ESM import: module.register() loader hooks fire for ESM
// imports (including import-of-CJS, which the hook then serves as
// instrumented format:'commonjs' source), but NOT for require() of a CJS
// file — a require()'d EmojiSearch.js loads uninstrumented and contributes
// zero decisions. require() interop shape is preserved by unwrapping the
// namespace default.
const emojiSearchPath = path.join(root, 'shell/plugins/emojis/EmojiSearch.js')
const emojiSearchNs = await import(pathToFileURL(emojiSearchPath).href)
const emojiSearch = emojiSearchNs.default ?? emojiSearchNs
function requireFromRoot(relativePath) {
  const abs = path.join(root, relativePath)
  if (abs === emojiSearchPath) return emojiSearch
  return require(abs)
}

// The body of a script's single `run_node_test <<'JS'` heredoc. A script
// whose shape changes (no body, two bodies, a body that no longer loads
// EmojiSearch.js) fails here instead of replaying nothing.
function nodeTestBody(script) {
  const text = fs.readFileSync(path.join(root, script), 'utf8')
  const bodies = [...text.matchAll(/^run_node_test <<'JS'\n([\s\S]*?)\nJS$/gm)]
  assertEqual(bodies.length, 1, `${script} has one run_node_test body`)
  const body = bodies[0][1]
  assert(body.includes("requireFromRoot('shell/plugins/emojis/EmojiSearch.js')"), `${script} loads EmojiSearch.js through requireFromRoot`)
  return body
}
// Runs a body with the prelude names run_node_test gives it.
function replay(script) {
  const run = new Function('require', 'path', 'root', 'fail', 'pass', 'assert', 'assertEqual', 'assertDeepEqual', 'requireFromRoot', nodeTestBody(script))
  run(require, path, root, fail, pass, assert, assertEqual, assertDeepEqual, requireFromRoot)
}

test('EmojiSearch.js decision replay (body read from emojis-test.sh)', () => {
  replay('test/shell.d/emojis-test.sh')
})

test('EmojiSearch.js decision replay (body read from menu-emoji-picker-test.sh)', () => {
  replay('test/shell.d/menu-emoji-picker-test.sh')
})

test('mcdc filterEmojis: a null limit counts as 1000', () => {
  const many = []
  for (let i = 0; i < 1001; i++) many.push({ e: 'x' + i, k: 'face ' + i })
  assertEqual(emojiSearch.filterEmojis(many, 'face', null).length, 1000, 'filterEmojis treats a null limit like a missing one')
})
