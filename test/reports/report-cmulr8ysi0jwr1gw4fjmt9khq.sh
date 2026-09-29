#!/bin/sh
# Reproducer for report cmulr8ysi0jwr1gw4fjmt9khq (omacom/omarchy#10601):
# opening the menu costs time quadratic in its row count.
#
# It counts WORK, not time. A standalone QML file is generated from the REAL
# shell/plugins/menu/Menu.qml pieces that decide the cost, copied verbatim:
# the `visibleRowsHeight` binding line, rowHeightForDetail, rowListHeight,
# dmenuRowListHeight and rebuildDmenuDisplay (the path every
# `omarchy-menu-select` caller such as the Super+K keybindings menu takes).
# Only geometry and cursor helpers are stubbed; foldedListHeight is replaced by
# a counter that records each height pass and how many rows that pass walked.
# The file then runs in the real Qt QML engine (offscreen), so binding
# re-evaluation follows Qt's own dependency tracking. A menu of N options is
# built by rebuildDmenuDisplay() exactly as a summon does.
# Correct (linear): a rebuild walks each row a bounded number of times
# (<= 2 walks per row in total). Defect: the walk count grows with N^2
# (231 rows -> ~N(N+1)/2 row visits, one height pass per append).
#   exit 0 = linear, 1 = DEFECT (superlinear), 2 = SETUP (no Qt QML runtime).
set -u
ROOT=$(cd "$(dirname "$0")/../.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
QMLSRC="$ROOT/shell/plugins/menu/Menu.qml"
[ -f "$QMLSRC" ] || { echo "SETUP: $QMLSRC is missing"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node (>= 18) is required to extract the QML under test"; exit 2; }
QMLBIN=""
for c in qml6 qml /usr/lib/qt6/bin/qml; do
  if command -v "$c" >/dev/null 2>&1; then QMLBIN=$(command -v "$c"); break; fi
done
[ -n "$QMLBIN" ] || { echo "SETUP: the Qt 6 'qml' runtime (qt6-declarative) is required and was not found"; exit 2; }

WORK=$(mktemp -d) || { echo "SETUP: mktemp failed"; exit 2; }
trap 'rm -f "$WORK"/harness-*.qml "$WORK"/out-*; rmdir "$WORK" 2>/dev/null' EXIT INT TERM
export QMLSRC WORK

node --input-type=commonjs - <<'JS' || { echo "SETUP: could not extract the height binding from Menu.qml"; exit 2; }
const fs = require("fs")
const src = fs.readFileSync(process.env.QMLSRC, "utf8")
function extract(name) {
  const at = src.search(new RegExp("\\n  function " + name + "\\s*\\("))
  if (at < 0) throw new Error("no function " + name)
  let i = src.indexOf("{", at), depth = 0, q = null
  for (; i < src.length; i++) {
    const c = src[i]
    if (q) { if (c === "\\") i++; else if (c === q) q = null; continue }
    if (c === '"' || c === "'" || c === "`") { q = c; continue }
    if (c === "/" && src[i + 1] === "/") { i = src.indexOf("\n", i); continue }
    if (c === "{") depth++
    else if (c === "}" && --depth === 0) return "  " + src.slice(at + 1, i + 1).trim()
  }
  throw new Error("unterminated function " + name)
}
const binding = src.match(/^[ \t]*property int visibleRowsHeight:.*$/m)
if (!binding) throw new Error("no visibleRowsHeight binding")
const real = ["rowHeightForDetail", "rowListHeight", "dmenuRowListHeight", "rebuildDmenuDisplay"].map(extract).join("\n\n")
for (const n of [231, 462]) {
  const qml = `import QtQuick
Item {
  id: root
  // --- stubs: geometry values only (they do not influence how often heights are computed)
  property int baseRowHeight: 50
  property int detailRowHeight: 58
  property int rowSpacing: 4
  property int dividerHeight: 17
  property int rowPeek: 27
  property string mode: "select"
  readonly property bool dmenuActive: mode === "select" || mode === "input"
  property string filterText: ""
  property bool searchDivider: false
  property int dmenuMaxHeight: 0
  property var dmenuOptions: []
  property int selectedIndex: 0
  property int layoutSerial: 0
  property var probe: ({ passes: 0, visits: 0 })
  function availableRowsHeight() { return 1000000 }
  function revealCursor() {}
  function foldedListHeight(totals, available) {
    probe.passes += 1
    probe.visits += totals.length
    return totals.length ? totals[totals.length - 1] : root.baseRowHeight
  }
  ListModel { id: displayModel }

  // --- verbatim from shell/plugins/menu/Menu.qml
${binding[0]}

${real}

  Component.onCompleted: {
    var opts = []
    for (var i = 0; i < ${n}; i++) opts.push("\\u2318\\tBinding " + i + "\\tdispatch " + i)
    root.dmenuOptions = opts
    probe.passes = 0
    probe.visits = 0
    root.rebuildDmenuDisplay()
    console.warn("RESULT rows=" + displayModel.count + " passes=" + probe.passes + " visits=" + probe.visits + " height=" + root.visibleRowsHeight)
    Qt.quit()
  }
}
`
  fs.writeFileSync(process.env.WORK + "/harness-" + n + ".qml", qml)
}
JS

DEFECT=0
for n in 231 462; do
  QT_QPA_PLATFORM=offscreen QT_FORCE_STDERR_LOGGING=1 LC_ALL=C.UTF-8 "$QMLBIN" "$WORK/harness-$n.qml" > "$WORK/out-$n" 2>&1
  line=$(grep -o 'RESULT rows=[0-9]* passes=[0-9]* visits=[0-9]* height=[0-9-]*' "$WORK/out-$n" | head -1)
  if [ -z "$line" ]; then
    echo "SETUP: the Qt QML runtime could not run the harness:"; sed -n '1,15p' "$WORK/out-$n"; exit 2
  fi
  rows=$(echo "$line" | sed 's/.*rows=\([0-9]*\).*/\1/')
  passes=$(echo "$line" | sed 's/.*passes=\([0-9]*\).*/\1/')
  visits=$(echo "$line" | sed 's/.*visits=\([0-9]*\).*/\1/')
  [ "$rows" -eq "$n" ] || { echo "SETUP: harness built $rows rows, expected $n"; exit 2; }
  if [ "$visits" -le $((2 * n)) ]; then
    echo "ok: $n-row menu open: $passes height pass(es), $visits row visits (linear)"
  else
    echo "DEFECT: $n-row menu open: $passes height passes walked $visits rows (linear bound $((2 * n)); triangular sum $((n * (n + 1) / 2))) -- the height binding re-walks the whole list on every append"
    DEFECT=1
  fi
done
exit $DEFECT
