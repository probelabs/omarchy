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

# The harness pins the collation of inputs without @locale to en-US; the run
# below also pins LC_ALL=C.UTF-8, as the upstream test does, so no host locale
# (sv_SE, et_EE, th_TH, ...) changes the expected orders.

# Each case: description, input, the exact lines the harness prints for the
# shown rows, the plugin list when the input asks for it, and the app an
# Enter launched, if any.
CASES=(
  # MCDC SW-REQ-261003-B7ZA: apps_rows_in_letter_order=T, apps_rows_rebuilt=T => TRUE
  'an Apps summon lists French names that start with an accent under their letter'
  seq-apps-french.events
  'shown menu=apps sorts=1 rows=["Calculatrice","Écrans","Éditeur de texte","Fichiers","Terminal","Xournal++","Zed"]'

  'the Apps order does not depend on the order the apps are handed over'
  seq-apps-french-reordered.events
  'shown menu=apps sorts=1 rows=["Calculatrice","Écrans","Éditeur de texte","Fichiers","Terminal","Xournal++","Zed"]'

  'an Apps summon lists German names that start with an umlaut under their letter'
  seq-apps-german.events
  'shown menu=apps sorts=1 rows=["Ärztefinder","Dateien","Einstellungen","Öffentliche Ordner","Übersetzer","Uhr","Videos","Zeichnen"]'

  'a precomposed and a decomposed accent both sort under their base letter'
  seq-apps-decomposed.events
  'shown menu=apps sorts=1 rows=["Écrans","Éditeur","Editor","Files","Zed"]'

  'names that start with a symbol sort before digits and letters'
  seq-apps-symbols.events
  'shown menu=apps sorts=1 rows=["_Under","(beta) X","~Tilde","1Password","Alacritty","Zed"]'

  'with the default collation other scripts follow the Latin names'
  seq-apps-nonlatin.events
  'shown menu=apps sorts=1 rows=["Alacritty","Zed","Αριθμομηχανή","Терминал","الآلة الحاسبة","计算器"]'

  'with a Russian collation the Cyrillic name comes first'
  seq-apps-locale-ru.events
  'shown menu=apps sorts=1 rows=["Терминал","Alacritty","Zed","Αριθμομηχανή","计算器"]'

  'with a Greek collation the Greek name comes first'
  seq-apps-locale-el.events
  'shown menu=apps sorts=1 rows=["Αριθμομηχανή","Alacritty","Zed","Терминал","计算器"]'

  'with a Chinese collation the Chinese name comes first'
  seq-apps-locale-zh.events
  'shown menu=apps sorts=1 rows=["计算器","Alacritty","Zed","Αριθμομηχανή","Терминал"]'

  'equal names ignore case and keep their id order'
  seq-apps-case-tie.events
  'shown menu=apps sorts=1 rows=["Alacritty","alacritty","Zed","zed","ZED"]'

  'the plugin app list has the same order as the Apps menu'
  seq-apps-plugin-list.events
  'shown menu=apps sorts=1 rows=["Calculatrice","Écrans","Éditeur de texte","Fichiers","Übersetzer","Zed"]
plugin-list rows=["Calculatrice","Écrans","Éditeur de texte","Fichiers","Übersetzer","Zed"]'

  # The expected line holds a no-break space, a BOM inside "Zoomer" and two
  # U+FFFD, exactly as the harness prints them.
  'odd encodings sort by the collation; U+FFFD names stay last'
  seq-apps-encoding.events
  'shown menu=apps sorts=1 rows=[""," Notes","🎵 Musik","2048","alpha","İnternet","Straße","Ｚｅｄ","Zoom﻿er","��Broken"]'

  'plain ASCII names keep their order, and Enter launches the first row'
  seq-apps-ascii.events
  'shown menu=apps sorts=1 rows=["Alacritty","Btop","Firefox","Obsidian","zed"]
apps alacritty'

  'Enter on the first Apps row launches the accented name that now sorts first'
  seq-apps-first-row.events
  'shown menu=apps sorts=1 rows=["Écrans","Firefox","Zed"]
apps screens'

  # Both rows read "Éditeur": a.desktop has the composed É (U+00C9) and comes
  # first, z.desktop the decomposed E + U+0301, in the menu and the plugin list.
  'names that collate equal keep desktop id order in the menu and the plugin list'
  seq-apps-plugin-tie.events
  'shown menu=apps sorts=1 rows=["Éditeur","Éditeur"]
plugin-list rows=["Éditeur","Éditeur"]'

  # MCDC SW-REQ-261003-B7ZA: apps_rows_in_letter_order=F, apps_rows_rebuilt=F => TRUE [no-action: the same apps are installed but the root menu is summoned; the sort spy shows sorts=0, so the Apps comparator never runs and the root rows keep their item order]
  'a root summon does not run the Apps sort'
  seq-apps-root-control.events
  'shown menu=root sorts=0 rows=[null,"Apps"]'
)

for ((i = 0; i < ${#CASES[@]}; i += 3)); do
  description=${CASES[i]}
  expected=${CASES[i + 2]}
  got=$(LC_ALL=C.UTF-8 node "$HARNESS" "$ROOT" "$CORPUS/${CASES[i + 1]}" | grep -E '^(shown|plugin-list) |^apps [^-]')
  if [[ $got == "$expected" ]]; then
    pass "$description"
  else
    fail "$description" "expected: $expected
got:      $got"
  fi
done
