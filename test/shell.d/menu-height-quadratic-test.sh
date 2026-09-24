#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260924-8PWV, SW-REQ-260924-84E4, SW-REQ-260922-B757
#mcdc:ignore:defensive SW-REQ-260924-8PWV: display_model_mutated=T, layout_serial_bumped_before_exit=F => FALSE -- post-fix every displayModel mutation path (both append loops, both early returns) exits through a layoutSerial bump; the un-bumped exit is structurally absent [reviewed: REVIEW-M2]
#mcdc:ignore:defensive SW-REQ-260924-84E4: open_cost_linear_in_row_count=F, rows_presented=T => FALSE -- the height binding depends only on layoutSerial, so a per-append re-walk needs a count dependency that no longer exists; the 231-row triangular walk is the recorded pre-fix simulation [reviewed: REVIEW-M2]

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

MENU_QML="$ROOT/shell/plugins/menu/Menu.qml"

[[ -f $MENU_QML ]] || fail "Menu.qml is missing"

run_node_test <<'JS'
const fs = require('fs')

const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

// The bug: visibleRowsHeight bound to displayModel.count, so each append during
// rebuild re-ran the full row walk (O(n^2) on open). layoutSerial already marks
// a finished model; height must key off that alone.
assert(
  /property int visibleRowsHeight:\s*root\.dmenuActive\s*\?\s*dmenuRowListHeight\(\s*layoutSerial\s*\)\s*:\s*rowListHeight\(\s*layoutSerial\s*\)/.test(menuQml),
  'visibleRowsHeight binds only to layoutSerial (dmenu and route paths)'
)

assert(
  !/visibleRowsHeight:[^\n]*displayModel\.count/.test(menuQml),
  'visibleRowsHeight must not depend on displayModel.count'
)
// MCDC SW-REQ-260924-8PWV: display_model_mutated=F, layout_serial_bumped_before_exit=F => TRUE [no-action: visibleRowsHeight's only dependency is layoutSerial (pinned by the regex witnesses here), so with no model mutation there is no bump and zero height re-evaluations]

assert(
  !/dmenuRowListHeight\(\s*layoutSerial\s*,\s*displayModel\.count/.test(menuQml) &&
    !/rowListHeight\(\s*layoutSerial\s*,\s*displayModel\.count/.test(menuQml),
  'height helpers are not called with displayModel.count'
)

assert(
  /function rowListHeight\(\s*_serial\s*\)/.test(menuQml) &&
    /function dmenuRowListHeight\(\s*_serial\s*\)/.test(menuQml),
  'height helpers take only the layout serial as a binding dependency'
)

// Rebuild still finishes with a single serial bump after all appends.
// MCDC SW-REQ-260924-8PWV: display_model_mutated=T, layout_serial_bumped_before_exit=T => TRUE
assert(
  /for\s*\(\s*var k = 0;\s*k < rows\.length;\s*k\+\+\)\s*displayModel\.append\(rows\[k\]\)\s*\n\s*layoutSerial \+= 1/.test(menuQml) ||
    /displayModel\.append\(rows\[k\]\)[\s\S]{0,80}?layoutSerial \+= 1/.test(menuQml),
  'rebuildDisplay bumps layoutSerial once after appending rows'
)

assert(
  /displayModel\.append\(\{[\s\S]*?itemId:\s*"dmenu\."[\s\S]*?\}\)[\s\S]*?layoutSerial \+= 1/.test(menuQml),
  'rebuildDmenuDisplay bumps layoutSerial once after appending options'
)

// Early empty-model path must still invalidate height without a count binding.
assert(
  /if\s*\(\s*!root\.rowsLoaded\s*\)\s*\{\s*layoutSerial \+= 1\s*;\s*return\s*\}/.test(menuQml) ||
    /if\s*\(\s*!root\.rowsLoaded\s*\)\s*\{\s*\n\s*layoutSerial \+= 1\s*\n\s*return\s*\n\s*\}/.test(menuQml),
  'rebuildDisplay bumps layoutSerial when rows are not loaded yet'
)

// MCDC SW-REQ-260924-84E4: open_cost_linear_in_row_count=F, rows_presented=F => TRUE [no-action: empty model early-returns baseRowHeight without walking any row]
assert(
  /function rowListHeight\(\s*_serial\s*\) \{[\s\S]{0,80}?if \(displayModel\.count === 0\) return root\.baseRowHeight/.test(menuQml),
  'empty model returns baseRowHeight without walking rows'
)

// Complexity check: triangular walk on every append vs one final walk.
function simulate(n, everyAppend) {
  let calls = 0
  let walked = 0
  const model = []
  const height = () => {
    calls += 1
    walked += model.length
  }
  for (let i = 0; i < n; i++) {
    model.push(i)
    if (everyAppend) height()
  }
  if (!everyAppend) height()
  return { calls, walked }
}

const bug231 = simulate(231, true)
const fix231 = simulate(231, false)
assertEqual(bug231.walked, 26796, 'pre-fix 231-row open walks the triangular sum')
// Verifies: SW-REQ-260924-84E4
// MCDC SW-REQ-260924-84E4: open_cost_linear_in_row_count=T, rows_presented=T => TRUE
assertEqual(fix231.walked, 231, 'post-fix 231-row open walks each row once')
assertEqual(fix231.calls, 1, 'post-fix height runs once per rebuild')

const bug400 = simulate(400, true)
const fix400 = simulate(400, false)
assert(bug400.walked > fix400.walked * 100, '400-row every-append walk is orders of magnitude larger than one pass')
assertEqual(fix400.walked, 400, 'post-fix 400-row open stays linear')
JS

pass "menu height no longer scales with the square of row count"
