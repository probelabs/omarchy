// Verifies: SW-REQ-261004-296X, SW-REQ-261004-V813
// node:test adapter for the proof js MC/DC engine: replays the FingerprintModel.js
// assertion body of test/shell.d/lock-fingerprint-retry-test.sh (the upstream
// test of the lock screen's fingerprint retry model) under node:test so the
// engine's Babel instrumentation can observe FingerprintModel.js decisions. The
// script pipes a prelude and its `run_node_test <<'JS'` body to plain `node`,
// which the js engine's node/vitest runner contract cannot drive (the same
// reason as menumodel-replay.test.mjs and emojisearch-replay.test.mjs). The body
// is read from the script at run time, not copied, so the script stays the one
// source of truth: a change to it is replayed as it is.
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
// FingerprintModel.js is a QML JavaScript resource with a CommonJS export for
// node. It MUST reach the engine through an ESM import: module.register()
// loader hooks fire for ESM imports (including import-of-CJS), but NOT for
// require() of a CJS file, which would load it uninstrumented.
const modelPath = path.join(root, 'shell/plugins/lock/FingerprintModel.js')
const modelNs = await import(pathToFileURL(modelPath).href)
const model = modelNs.default ?? modelNs
function requireFromRoot(relativePath) {
  const abs = path.join(root, relativePath)
  if (abs === modelPath) return model
  return require(abs)
}

// The body of the script's single `run_node_test <<'JS'` heredoc. A script
// whose shape changes (no body, two bodies, a body that no longer loads
// FingerprintModel.js) fails here instead of replaying nothing.
function nodeTestBody(script) {
  const text = fs.readFileSync(path.join(root, script), 'utf8')
  const bodies = [...text.matchAll(/^run_node_test <<'JS'\n([\s\S]*?)\nJS$/gm)]
  assertEqual(bodies.length, 1, `${script} has one run_node_test body`)
  const body = bodies[0][1]
  assert(body.includes("requireFromRoot('shell/plugins/lock/FingerprintModel.js')"), `${script} loads FingerprintModel.js through requireFromRoot`)
  return body
}
function replay(script) {
  const run = new Function('require', 'path', 'root', 'fail', 'pass', 'assert', 'assertEqual', 'assertDeepEqual', 'requireFromRoot', nodeTestBody(script))
  run(require, path, root, fail, pass, assert, assertEqual, assertDeepEqual, requireFromRoot)
}

test('FingerprintModel.js decision replay (body read from lock-fingerprint-retry-test.sh)', () => {
  replay('test/shell.d/lock-fingerprint-retry-test.sh')
})

// Rows the upstream body leaves to one side of a condition.
test('mcdc classifyProbe: null and undefined probe output read unknown', () => {
  assertEqual(model.classifyProbe(null), 'unknown', 'a null probe answer reads unknown')
  assertEqual(model.classifyProbe(undefined), 'unknown', 'a missing probe answer reads unknown')
  assertEqual(model.classifyProbe('  no  '), 'no', "the probe script's no reads no with surrounding blanks")
})

test('mcdc retryDelayMs: a negative streak retries at the fast interval', () => {
  assertEqual(model.retryDelayMs(-1), model.MATCH_RETRY_MS, 'a negative streak is the fast interval')
})

test('mcdc shouldNudge: each guard decides on its own', () => {
  const capped = model.ERROR_RETRY_CAP_MS
  // Below the cap the idle guard never holds, whatever the settle says.
  assert(model.shouldNudge(100000, 0, 99999, model.ERROR_RETRY_BASE_MS * 4), 'below the cap a just-settled attempt is nudged')
  // At the cap a settle long enough ago lets the nudge through.
  assert(model.shouldNudge(100000, 0, 100000 - model.IDLE_CLEAR_MS, capped), 'at the cap an idle stretch since the settle allows the nudge')
  // Inside the cooldown of the last nudge the nudge is refused, past it allowed.
  assert(!model.shouldNudge(100000, 100000 - 1, 0, capped), 'a nudge right after the last one is refused at the cap')
  assert(model.shouldNudge(100000, 100000 - capped, 0, capped), 'a nudge one cap after the last one is allowed')
})
