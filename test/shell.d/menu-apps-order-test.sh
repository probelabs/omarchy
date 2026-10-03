#!/bin/bash

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

run_node_test <<'JS'
const fs = require('fs')
const menuQml = fs.readFileSync(path.join(root, 'shell/plugins/menu/Menu.qml'), 'utf8')

// The Apps menu sorts its own rows, since DesktopEntries can reorder them.
// Run that comparator as written rather than restating it here.
const match = menuQml.match(/if \(active === "apps"\) \{\s*rows\.sort\((function\(a, b\) \{[\s\S]*?\n        \})\)/)
assert(match, 'apps menu sorts its rows with an inline comparator')
const compare = new Function(`return (${match[1]})`)()
const order = rows => rows.slice().sort(compare).map(row => row.label)

// App names come from each desktop entry's Name for the user's language, so
// a French or German desktop has names that start with É or Ü. Comparing
// UTF-16 code units put every one of them after Z.
assertDeepEqual(
  order([
    { label: 'Zed', itemId: 'apps.zed' },
    { label: 'Éditeur de texte', itemId: 'apps.text-editor' },
    { label: 'Übersetzer', itemId: 'apps.translator' },
    { label: 'Calculatrice', itemId: 'apps.calculator' },
    { label: 'Fichiers', itemId: 'apps.files' },
    { label: 'Terminal', itemId: 'apps.terminal' }
  ]),
  ['Calculatrice', 'Éditeur de texte', 'Fichiers', 'Terminal', 'Übersetzer', 'Zed'],
  'apps menu files an accented name under its letter, not after Z'
)

assertDeepEqual(
  order([
    { label: 'zed', itemId: 'apps.b' },
    { label: 'Alacritty', itemId: 'apps.a' },
    { label: 'Zed', itemId: 'apps.a' }
  ]),
  ['Alacritty', 'Zed', 'zed'],
  'apps menu ignores case and breaks a tie on the id'
)
JS
