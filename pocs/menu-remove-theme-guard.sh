#!/bin/bash
# Reproduces: KI-MENU-REMOVE-THEME-NO-THEMES
# Red reproducer: Remove > Theme must show only when omarchy-theme-remove has
# a theme to offer. The row runs the remover with no terminal, so on a HOME
# with no extra theme it prints "No extra themes installed." to nowhere and
# the row only closes the menu.
# For each HOME shape it runs the row's when: from the shipped menu through
# the real guard batch (MenuModel.js guardScript, then isVisible), and it runs
# bin/omarchy-theme-remove with a stub picker. It asserts the CORRECT
# behaviour: the row shows exactly when the remover asks the picker. So it
# exits 1 while the defect is present.
# Control: a HOME with one copied theme, where the row shows and the remover
# offers the theme.
#   exit 0 = correct, 1 = DEFECT, 2 = SETUP.
set -u
ROOT=$(cd "$(dirname "$0")/.." && pwd) || { echo "SETUP: cannot locate the repository root"; exit 2; }
command -v node >/dev/null 2>&1 || { echo "SETUP: node is required"; exit 2; }
BASH4=${OMARCHY_TEST_BASH:-bash}
"$BASH4" -c '((BASH_VERSINFO[0] >= 4))' 2>/dev/null || { echo "SETUP: bash 4 or later is required (mapfile)"; exit 2; }
find /dev/null -maxdepth 0 -xtype f -printf '' >/dev/null 2>&1 || { echo "SETUP: GNU find is required (-xtype, -printf)"; exit 2; }

tmp=$(mktemp -d) || { echo "SETUP: mktemp failed"; exit 2; }
cleanup() { [[ -n $tmp && -d $tmp && $tmp != / ]] && rm -r -- "$tmp"; }
trap cleanup EXIT

# The row and its guard, as the menu loads them.
row=$(MODEL="$ROOT/shell/plugins/menu/MenuModel.js" MENU="$ROOT/default/omarchy/omarchy-menu.jsonc" node -e '
  const fs = require("fs")
  const m = require(process.env.MODEL)
  const items = m.parseMenuJsonc(fs.readFileSync(process.env.MENU, "utf8"))
  const row = items.find(item => item.id === "remove.theme")
  if (!row) process.exit(3)
  process.stdout.write(JSON.stringify({ row, script: m.guardScript({ "remove.theme": row }) }))
') || { echo "SETUP: the shipped menu has no remove.theme row"; exit 2; }

# A picker stub that records that it was asked and picks nothing.
mkdir -p "$tmp/stub"
cat >"$tmp/stub/omarchy-menu-select" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"$SELECT_CALLS"
exit 1
STUB
chmod +x "$tmp/stub/omarchy-menu-select"

mkdir -p "$tmp/empty/.config/omarchy/themes"
mkdir -p "$tmp/linked/.config/omarchy/themes" "$tmp/checkout"
ln -s "$tmp/checkout" "$tmp/linked/.config/omarchy/themes/in-progress"
mkdir -p "$tmp/copied/.config/omarchy/themes/handmade"

# shown: what the menu does with the guard batch's answer for this HOME.
shown() {
  local home=$1 answer
  answer=$(HOME="$home" PATH="$tmp/stub:$ROOT/bin:$PATH" "$BASH4" -c "$(ROW="$row" node -e 'process.stdout.write(JSON.parse(process.env.ROW).script)')" 2>/dev/null)
  ROW="$row" ANSWER="$answer" MODEL="$ROOT/shell/plugins/menu/MenuModel.js" node -e '
    const m = require(process.env.MODEL)
    const { row } = JSON.parse(process.env.ROW)
    const when = {}
    for (const line of process.env.ANSWER.split("\n")) {
      const r = /^(.*):w:([01])$/.exec(line.trim())
      if (r) when[r[1]] = r[2] === "1"
    }
    const items = { [row.id]: row }
    process.stdout.write(m.isVisible(items, [row.id], when, row) ? "1" : "0")
  '
}

# offered: whether the remover asked the picker for this HOME.
offered() {
  local home=$1 calls="$tmp/calls"
  : >"$calls"
  HOME="$home" SELECT_CALLS="$calls" PATH="$tmp/stub:$ROOT/bin:$PATH" "$BASH4" "$ROOT/bin/omarchy-theme-remove" >/dev/null 2>&1
  [[ -s $calls ]] && echo 1 || echo 0
}

when_text=$(ROW="$row" node -e 'process.stdout.write(JSON.parse(process.env.ROW).row.when || "")')
[[ -n $when_text ]] && echo "info: remove.theme when: $when_text" || echo "info: remove.theme has no when:, so the menu always shows it"

c_shown=$(shown "$tmp/copied") c_offered=$(offered "$tmp/copied")
if [[ $c_shown != 1 || $c_offered != 1 ]]; then
  echo "SETUP: control (one copied theme): shown=$c_shown offered=$c_offered, expected 1 and 1"
  exit 2
fi
echo "ok: control: one copied theme: the row shows and the remover offers it"

defect=0
for shape in empty linked; do
  s=$(shown "$tmp/$shape") o=$(offered "$tmp/$shape")
  if [[ $s == "$o" ]]; then
    echo "ok: $shape themes directory: shown=$s offered=$o"
  else
    echo "DEFECT: $shape themes directory: the row shows (shown=$s) but the remover has no theme to offer (offered=$o); Enter only closes the menu"
    defect=1
  fi
done
exit $defect
