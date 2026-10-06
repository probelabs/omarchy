// Verifies: SW-REQ-260922-SJ7P, SYS-REQ-260922-V7W6
// Regression net for the issue reproducers validated through report intake
// (fork branches report/<id>, scripts copied verbatim into test/reports/).
// Every script follows one contract: exit 0 = the reported behaviour is
// correct, 1 = DEFECT reproduced, 2 = SETUP (a required runtime is missing).
//
// On this baseline (upstream e332dc97 product code) five reports reproduce an
// upstream defect. Each is pinned as an EXPECTED FAILURE: the test asserts
// exit 1 and the DEFECT line, and is bound to its known issue with a
// Reproduces marker. When the upstream fix lands the script exits 0 and the
// test goes red, which is the signal to close the known issue and flip the
// expectation. The sixth report (#10340) is not a defect; its script asserts
// the specified ranking and must exit 0.
import { test } from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const root = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..', '..')

function runReport(id) {
  const script = path.join(root, 'test', 'reports', `report-${id}.sh`)
  const r = spawnSync('sh', [script], { cwd: root, encoding: 'utf8', timeout: 120000 })
  return { status: r.status, out: (r.stdout || '') + (r.stderr || '') }
}

function expectReport(t, id, wantExit, wantLine) {
  const { status, out } = runReport(id)
  if (status === 2) { t.skip(`SETUP: ${out.trim().split('\n').pop()}`); return }
  assert.equal(status, wantExit, `report ${id}: expected exit ${wantExit}, got ${status}\n${out}`)
  assert.match(out, wantLine, `report ${id}: output does not carry the expected verdict line\n${out}`)
}

// Reproduces: KI-MENU-JSONC-COMMA-IN-STRING
test('report #13250 (comma and closer inside a label): expected failure while KI-MENU-JSONC-COMMA-IN-STRING is open', t => {
  expectReport(t, 'cmulr8l6h0i461gw40vqqv64c', 1, /DEFECT: label containing ', \]' survives/)
})

// Reproduces: KI-MENU-JSONC-ARRAY-ROOT
test('report #13492 (array root renders phantom rows): expected failure while KI-MENU-JSONC-ARRAY-ROOT is open', t => {
  expectReport(t, 'cmulr8j7z0hy31gw4pne8v6u4', 1, /DEFECT: top-level array root yields no rows/)
})

// Reproduces: KI-MENU-JSONC-INLINE-COMMENT
test('report #13493 (inline comment tail empties the menu): expected failure while KI-MENU-JSONC-INLINE-COMMENT is open', t => {
  expectReport(t, 'cmulr8j7w0hy01gw4menggvbx', 1, /DEFECT: inline comment tail after the root object/)
  // The control the original validation lacked must hold on this baseline.
  const { out } = runReport('cmulr8j7w0hy01gw4menggvbx')
  assert.match(out, /ok: control: trailing comma, whole-line comment, closer keeps the row/)
})

// Reproduces: KI-MENU-OPEN-QUADRATIC
test('report #10601 (menu open walks rows quadratically): expected failure while KI-MENU-OPEN-QUADRATIC is open', t => {
  expectReport(t, 'cmulr8ysi0jwr1gw4fjmt9khq', 1, /DEFECT: 231-row menu open/)
})

// PR omacom/omarchy#9031 (this mirror) answers a request that a new summon
// displaces: openDmenu writes its done file alone through releaseProc
// (finishDoneFile). The superseded caller is answered as cancelled and the
// report script exits 0, so the re-summon leg of KI-MENU-REQUEST-LIFECYCLE no
// longer reproduces here; the expectation is flipped to the fixed behaviour.
test('report #9057 (superseded select summon never answered): fixed by #9031, both callers answered', t => {
  expectReport(t, 'cmulr95nw0kqr1gw46i7f50xj', 0, /^ok: caller A was answered and exited/m)
})

// Not a defect: the label-prefix tier outranks the label-substring tier.
test('report #10340 (chro ranks the Chrome setting above the Google Chrome app): specified order holds', t => {
  expectReport(t, 'cmulr908f0k131gw4hy0pcx08', 0, /^ok: 'Chrome' \(label-prefix tier\) ranks above the app 'Google Chrome'/m)
})
