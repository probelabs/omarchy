#!/bin/bash

# Proof-side witness for SW-REQ-261003-B7ZA (mirror only; not part of the
# upstream change). It replays Apps-menu inputs of the behaviour-diff corpus
# through test/bdiff/harness.mjs, which runs this checkout's real open,
# openRoute, openExistingMenu, rebuildDisplay, displayRow and isVisible from
# shell/plugins/menu/Menu.qml under node:vm and counts the comparator sorts the
# revision runs (a spy on Array.prototype.sort).

# Verifies: SW-REQ-261003-B7ZA
# mcdc:witness-out-of-process

set -euo pipefail

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command node

HARNESS="$ROOT/test/bdiff/harness.mjs"
CORPUS="$ROOT/test/bdiff/corpus/lifecycle"

# Each case: description, input, the exact `shown` line the harness prints.
CASES=(
  # MCDC SW-REQ-261003-B7ZA: apps_rows_in_letter_order=T, apps_rows_rebuilt=T => TRUE
  'an Apps summon lists French names that start with an accent under their letter'
  seq-apps-french.events
  'shown menu=apps sorts=1 rows=["Calculatrice","Écrans","Éditeur de texte","Fichiers","Terminal","Xournal++","Zed","Zellij"]'

  'the Apps order does not depend on the order the apps are handed over'
  seq-apps-french-reordered.events
  'shown menu=apps sorts=1 rows=["Calculatrice","Écrans","Éditeur de texte","Fichiers","Terminal","Xournal++","Zed","Zellij"]'

  'an Apps summon lists German names that start with an umlaut under their letter'
  seq-apps-german.events
  'shown menu=apps sorts=1 rows=["Ärztefinder","Dateien","Einstellungen","Öffentliche Ordner","Übersetzer","Uhr","Videos","Zeichnen"]'

  # MCDC SW-REQ-261003-B7ZA: apps_rows_in_letter_order=F, apps_rows_rebuilt=F => TRUE [no-action: the same apps are installed but the root menu is summoned; the sort spy shows sorts=0, so the Apps comparator never runs and the root rows keep their item order]
  'a root summon does not run the Apps sort'
  seq-apps-root-control.events
  'shown menu=root sorts=0 rows=[null,"Apps"]'
)

for ((i = 0; i < ${#CASES[@]}; i += 3)); do
  description=${CASES[i]}
  expected=${CASES[i + 2]}
  got=$(node "$HARNESS" "$ROOT" "$CORPUS/${CASES[i + 1]}" | grep '^shown ')
  if [[ $got == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected: $expected
got:      $got"
  fi
done
