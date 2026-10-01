// test/junit/merge.mjs -- merge the per-suite JUnit parts of one proof test run
// into the single report project.checks.test_results.report_path names.
//
//   node test/junit/merge.mjs <root> <dir>
//     reads  <dir>/parts/*.xml   (one per proof.yaml test command)
//     writes <dir>/junit.xml     (atomically: tmp + rename)
//
// Parts come in two shapes:
//   - test/junit/junit.sh output: one <testsuite> of per-script <testcase>s;
//   - node --test --test-reporter=junit output: top-level <testcase>s directly
//     under <testsuites>, and nested <testsuite>s for describe()/subtests, with
//     ABSOLUTE file="" paths.
// proof reads all of these layouts, but it reads ONE report file, so the
// parts are merged: every part becomes ONE <testsuite name="<part>"> holding
// all of its <testcase>s (nesting flattened; node already sets classname to
// the parent suite), and absolute file paths under <root> are made
// repo-relative so the evidence assembler can join results to tagged test
// files.
import fs from 'node:fs'
import path from 'node:path'

const [root, dir] = process.argv.slice(2)
if (!root || !dir) {
  console.error('usage: node test/junit/merge.mjs <root> <dir>')
  process.exit(2)
}
const partsDir = path.join(dir, 'parts')
const parts = fs.existsSync(partsDir)
  ? fs.readdirSync(partsDir).filter(f => f.endsWith('.xml')).sort()
  : []

const realRoot = fs.realpathSync(root)
const rootPrefix = realRoot + path.sep
const real = p => { try { return fs.realpathSync(p) } catch { return path.resolve(p) } }
const testcaseRe = /<testcase\b[^>]*?(?:\/>|>[\s\S]*?<\/testcase>)/g

function attr(tag, name) {
  const m = tag.match(new RegExp(`\\s${name}="([^"]*)"`))
  return m ? m[1] : undefined
}

function relativizeFile(tc) {
  return tc.replace(/(<testcase\b[^>]*?\sfile=")([^"]*)(")/, (all, pre, file, post) => {
    const abs = file.startsWith('file://') ? decodeURIComponent(file.slice('file://'.length)) : file
    if (path.isAbsolute(abs) && real(abs).startsWith(rootPrefix)) {
      return pre + path.relative(realRoot, real(abs)).split(path.sep).join('/') + post
    }
    return all
  })
}

let total = 0, failures = 0, errors = 0, skipped = 0, seconds = 0
const suites = []
for (const part of parts) {
  const name = part.replace(/\.xml$/, '')
  const xml = fs.readFileSync(path.join(partsDir, part), 'utf8')
  const cases = (xml.match(testcaseRe) || []).map(relativizeFile)
  let f = 0, e = 0, s = 0, t = 0
  for (const tc of cases) {
    const head = tc.match(/^<testcase\b[^>]*>/)[0]
    t += Number(attr(head, 'time')) || 0
    if (/<failure\b/.test(tc)) f++
    else if (/<error\b/.test(tc)) e++
    else if (/<skipped\b/.test(tc)) s++
  }
  total += cases.length; failures += f; errors += e; skipped += s; seconds += t
  suites.push(
    `  <testsuite name="${name}" tests="${cases.length}" failures="${f}" errors="${e}" skipped="${s}" time="${t.toFixed(3)}">\n` +
    cases.map(tc => '    ' + tc).join('\n') + (cases.length ? '\n' : '') +
    '  </testsuite>'
  )
}

const out =
  '<?xml version="1.0" encoding="UTF-8"?>\n' +
  `<testsuites name="proof test commands" tests="${total}" failures="${failures}" errors="${errors}" skipped="${skipped}" time="${seconds.toFixed(3)}">\n` +
  suites.join('\n') + (suites.length ? '\n' : '') +
  '</testsuites>\n'
const target = path.join(dir, 'junit.xml')
fs.writeFileSync(target + '.tmp', out)
fs.renameSync(target + '.tmp', target)
console.error(`junit: ${path.relative(root, target)} <- ${parts.length} part(s), ${total} test(s), ${failures + errors} failed, ${skipped} skipped`)
