#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-MQ37, SW-REQ-260922-Y58B, SW-REQ-260922-W17G, SW-REQ-260922-RGCV, SW-REQ-260922-2JZT, SYS-REQ-260922-47T8
# Verifies: SW-REQ-261003-390Z
#mcdc:ignore:defensive SW-REQ-260922-MQ37: guards_declared=T, one_line_per_guard=F => FALSE -- guardLine is appended exactly once per declared guard; a guard answered by zero or two lines needs a broken string build [reviewed: REVIEW-M5]
#mcdc:ignore:defensive SW-REQ-260922-Y58B: empty_guard_script=F, no_guards_declared=T => FALSE -- guardScript returns "" exactly when the built guards string is empty; a non-empty script from guardless items needs broken concatenation [reviewed: REVIEW-M5]
#mcdc:ignore:defensive SW-REQ-260922-W17G: reader_read_once=F, reader_value_reused=T => FALSE -- the global substitution leaves no plain $(reader) call behind, so a reused reader has nothing left to read twice [reviewed: REVIEW-M5]
#mcdc:ignore:defensive SW-REQ-260922-2JZT: only_plain_form_substituted=F, plain_substitution_form=T => FALSE -- the substitution is a global replace of the exact plain form; an occurrence left behind needs a broken replace [reviewed: REVIEW-M5]
#mcdc:ignore:defensive SW-REQ-261003-390Z: remove_theme_row_hidden=F, remover_has_no_theme=T => FALSE -- the remove.theme when: is the find predicate omarchy-theme-remove lists with (non-symlink directories under ~/.config/omarchy/themes), less the dot-names it refuses; a shown row with nothing to remove needs the two predicates to diverge, which is the a85e29ab row with no when: [reviewed: REVIEW-261003-C7RT]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# Run generated guard scripts under the same bash that runs this suite: the
# prelude uses mapfile/assoc arrays (bash >=4), and a bare `bash` can resolve to
# /bin/bash 3.2 when PATH lacks homebrew (observed: parity assertion failing with
# an empty shadow inventory). Same pattern as menu-plugin-test.sh.
TEST_BASH="${OMARCHY_TEST_BASH:-$BASH}"

run_node_test <<'JS'
const menu = requireFromRoot('shell/plugins/menu/MenuModel.js')

const items = {
  'setup.default.browser.brave': { id: 'setup.default.browser.brave', when: 'omarchy-pkg-present brave-bin', checked: '[[ "$(omarchy-default-browser)" == "brave" ]]' },
  'setup.default.browser.zen': { id: 'setup.default.browser.zen', when: 'omarchy-pkg-present zen-browser-bin', checked: '[[ "$(omarchy-default-browser)" == "zen" ]]' },
  'install.browser.zen': { id: 'install.browser.zen', disabled: 'omarchy-pkg-present zen-browser-bin' },
  'plain': { id: 'plain', label: 'No guards' }
}
const script = menu.guardScript(items)
const browserSlot = `\${__omarchy_read_${menu.guardReaders.indexOf('omarchy-default-browser')}}`

// MCDC SW-REQ-260922-MQ37: guards_declared=T, one_line_per_guard=T => TRUE
// MCDC SW-REQ-260922-Y58B: empty_guard_script=F, no_guards_declared=F => TRUE [no-action: the script for guarded items is non-empty -- the empty-script guarantee is not invoked]
assert(
  script.includes('if { omarchy-pkg-present brave-bin; } >/dev/null 2>&1; then echo setup.default.browser.brave:w:1; else echo setup.default.browser.brave:w:0; fi'),
  'guard script reports a when: as <id>:w:<0|1>'
)
assert(
  script.includes('then echo setup.default.browser.zen:c:1; else echo setup.default.browser.zen:c:0; fi'),
  'guard script reports a checked: as <id>:c:<0|1>'
)
assert(
  script.includes('if { omarchy-pkg-present zen-browser-bin; } >/dev/null 2>&1; then echo install.browser.zen:d:1; else echo install.browser.zen:d:0; fi'),
  'guard script reports a disabled: as <id>:d:<0|1>'
)
assert(!/\bplain:[wcd]:/.test(script), 'guard script skips items with nothing to evaluate')
// MCDC SW-REQ-260922-Y58B: empty_guard_script=T, no_guards_declared=T => TRUE
// MCDC SW-REQ-260922-MQ37: guards_declared=F, one_line_per_guard=F => TRUE [no-action: the script is empty -- zero guard lines are emitted for guardless items]
// MCDC SYS-REQ-260922-47T8: guards_evaluated=F, system_state_reflected=F => TRUE [no-action: the empty batch evaluates zero guards -- nothing is asked of the system]
assertEqual(menu.guardScript({ plain: items.plain }), '', 'guard script is empty when no item carries a guard')

// The cost the menu is paying is per fork, not per expression, so what makes
// the batch fast is asking each command once however many rows want it.
// MCDC SW-REQ-260922-W17G: reader_read_once=T, reader_value_reused=T => TRUE
assertEqual(
  (script.match(/^__omarchy_read_\d+=\$\(omarchy-default-browser /gm) || []).length,
  1,
  'guard script reads a value command once for the whole batch'
)
// MCDC SW-REQ-260922-2JZT: only_plain_form_substituted=T, plain_substitution_form=T => TRUE
assert(
  script.includes(`[[ "${browserSlot}" == "brave" ]]`) && !script.includes('"$(omarchy-default-browser)"'),
  'guard script substitutes the captured answer into the expression'
)
assert(
  script.indexOf('__omarchy_read_') < script.indexOf('if { omarchy-pkg-present'),
  'guard script captures readers before any guard runs, since $() would trap a lazy memo in its subshell'
)

// Substitution is confined to the plain `$(reader)` form on purpose. A
// function shadowing the name would also catch these, and answer them wrong.
const untouched = menu.guardScript({
  a: { id: 'a', when: 'command -v omarchy-dns' },
  b: { id: 'b', when: '[[ "$(OMARCHY_PATH=/usr/share/omarchy omarchy-channel-current)" == "stable" ]]' },
  c: { id: 'c', when: '(( $(omarchy-default-browser | wc -l) == 1 ))' }
})
// MCDC SW-REQ-260922-2JZT: only_plain_form_substituted=F, plain_substitution_form=F => TRUE [no-action: every non-plain form is left to run the real command -- the substitution path is not taken]
assert(
  untouched.includes('command -v omarchy-dns')
    && untouched.includes('$(OMARCHY_PATH=/usr/share/omarchy omarchy-channel-current)')
    && untouched.includes('$(omarchy-default-browser | wc -l)'),
  'guard script leaves every form but the plain substitution to run the real command'
)
// MCDC SW-REQ-260922-W17G: reader_read_once=F, reader_value_reused=F => TRUE [no-action: no reader slot appears in the script -- nothing is captured, so nothing is reused]
assert(
  !/^__omarchy_read_/m.test(untouched),
  'guard script captures nothing when no guard uses the plain substitution'
)

// Every reader named in the shipped menu has to be listed, or it silently
// keeps forking once per row that reads it.
const fs = require('fs')
const defaultItems = menu.parseMenuJsonc(fs.readFileSync(path.join(root, 'default/omarchy/omarchy-menu.jsonc'), 'utf8'))
const guardText = defaultItems.map(item => `${item.when}\n${item.checked}\n${item.disabled}`).join('\n')
const repeated = [...new Set(
  (guardText.match(/\$\((omarchy-[a-z0-9-]+)\)/g) || []).map(match => match.slice(2, -1))
)].filter(command => guardText.split(`$(${command})`).length > 2)
assertDeepEqual(
  repeated.filter(command => !menu.guardReaders.includes(command)),
  [],
  'guard readers cover every command the shipped menu reads from more than one row'
)
JS

prelude() {
  node -e '
    const path = require("path")
    const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
    process.stdout.write(menu.guardScript({ probe: { id: "probe", when: "true" } }))
  ' | command grep -v '^if {'
}

# The prelude shadows the real commands for the length of the batch, so it has
# to answer exactly as they do -- including for arguments no shipped guard
# passes today, which an extension is free to write tomorrow.
stub_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir"' EXIT

# `pacman -Q` resolves a name through what installed packages provide, so gvim
# answers for vim and bash answers for sh. A set built from `pacman -Qq` alone
# would miss both and offer to install what is already there.
#
# `-Qi` wraps a long list onto indented continuation lines whenever COLUMNS is
# set, so gvim's provides arrive the way a wrapped terminal would emit them.
cat >"$stub_dir/pacman" <<'STUB'
#!/bin/bash
printf '%s\n' "$*" >>"${PACMAN_CALLS:-/dev/null}"
case "$1" in
-Qq)
  printf '%s\n' bash gvim
  ;;
-Qi)
  cat <<'INFO'
Name            : bash
Provides        : sh
Version         : 5.3.0-1
Name            : gvim
Provides        : vim=9.2.0849-1
                  xxd
Version         : 9.2-1
INFO
  ;;
-Q)
  if [[ $2 == "--" ]]; then
    shift 2
  else
    shift
  fi
  for want in "$@"; do
    case "${want%%[<>=]*}" in bash | gvim | sh | vim | xxd) ;; *) exit 1 ;; esac
  done
  ;;
esac
exit 0
STUB
chmod +x "$stub_dir/pacman"
printf '#!/bin/bash\nexit 0\n' >"$stub_dir/gvim"
chmod +x "$stub_dir/gvim"

guard_prelude=$(prelude)

# Arguments reach both sides as argv. Interpolating them into the shadow's
# script text would let `bash>=1` parse as a redirection, so the case that
# exists to prove constraints work would quietly test `bash` instead.
assert_helper_agrees() {
  local description="$1" helper="$2"
  shift 2

  local real=0 shadowed=0
  PATH="$stub_dir:$PATH" "$ROOT/bin/$helper" "$@" >/dev/null 2>&1 || real=$?
  PATH="$stub_dir:$PATH" "$TEST_BASH" -c "$guard_prelude"$'\n'"$helper \"\$@\"" "$helper" "$@" >/dev/null 2>&1 || shadowed=$?
  ((real == shadowed)) || fail "$description" "$helper $*: real=$real shadowed=$shadowed"
}

# vim, sh and xxd are provided rather than installed, and xxd only appears on a
# wrapped continuation line; bash>=1 is a version constraint no set can answer.
pkg_cases=("bash" "vim" "sh" "xxd" "absent" "bash vim" "bash absent" "bash>=1" "vim>=1" "")
export PACMAN_CALLS="$stub_dir/pacman-calls"
for helper in omarchy-pkg-present omarchy-pkg-missing; do
  for case in "${pkg_cases[@]}"; do
    read -r -a argv <<<"$case"
        # SW-REQ-260922-RGCV:error_handling:nominal
assert_helper_agrees "guard prelude resolves packages as pacman does" "$helper" "${argv[@]}"
  done
done
# MCDC SW-REQ-260922-RGCV: pkg_presence_asked=T, shadow_matches_pacman=T => TRUE
pass "guard prelude resolves packages through provides, wrapping, and constraints as pacman does"

# The parity above holds because both sides read the same pacman. A pacman
# whose -Qq/-Qi inventory drops an installed package leaves the shadow
# disagreeing with -Q -- which is exactly the drift the parity assertion
# exists to catch, so prove the assertion can fail.
broken_dir=$(mktemp -d)
trap 'rm -rf "$stub_dir" "$broken_dir"' EXIT
printf '#!/bin/bash\ncase "$1" in -Q) exit 0 ;; *) exit 0 ;; esac\n' >"$broken_dir/pacman"
chmod +x "$broken_dir/pacman"
b_real=0 b_shadowed=0
PATH="$broken_dir:$PATH" "$ROOT/bin/omarchy-pkg-present" bash >/dev/null 2>&1 || b_real=$?
PATH="$broken_dir:$PATH" PACMAN_CALLS=/dev/null "$TEST_BASH" -c "$guard_prelude"$'\n'"omarchy-pkg-present bash" >/dev/null 2>&1 || b_shadowed=$?
# SW-REQ-260922-RGCV:error_handling:negative
[[ $b_real -eq 0 && $b_shadowed -eq 1 ]] ||
  fail "a shadow built from a stale inventory disagrees with pacman -Q" "real=$b_real shadowed=$b_shadowed"
# MCDC SW-REQ-260922-RGCV: pkg_presence_asked=T, shadow_matches_pacman=F => FALSE
pass "package parity fails when the shadow inventory misses what pacman -Q resolves"

# cd is a shell builtin `command -v` finds and a PATH search does not.
: >"$PACMAN_CALLS"
cmd_cases=("gvim" "cd" "absent" "gvim absent" "gvim cd" "")
for helper in omarchy-cmd-present omarchy-cmd-missing; do
  for case in "${cmd_cases[@]}"; do
    read -r -a argv <<<"$case"
    assert_helper_agrees "guard prelude resolves commands as the real helper does" "$helper" "${argv[@]}"
  done
done
pass "guard prelude resolves commands as omarchy-cmd-present and omarchy-cmd-missing do"
# The prelude snapshots the package inventory up front, so -Qq/-Qi lines are
# expected; what command presence must never issue is a -Q package query.
if command grep -q '^-Q ' "$PACMAN_CALLS"; then
  fail "command presence never asks pacman" "calls: $(cat "$PACMAN_CALLS")"
fi
# MCDC SW-REQ-260922-RGCV: pkg_presence_asked=F, shadow_matches_pacman=F => TRUE [no-action: the pacman stub call log across the command-presence loop holds only -Qq/-Qi inventory snapshots -- zero package queries]
pass "command presence never asks pacman"

# A reader is replaced by what it printed, which has to compare identically to
# the substitution it stood in for -- including the trailing newline $() drops.
reader_script=$(node -e '
  const path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  process.stdout.write(menu.guardScript({
    hit: { id: "hit", checked: "[[ \"$(omarchy-dns)\" == \"Cloudflare\" ]]" },
    miss: { id: "miss", checked: "[[ \"$(omarchy-dns)\" == \"Google\" ]]" }
  }))
')
reader_result=$("$TEST_BASH" -c '
omarchy-dns() { printf "Cloudflare\n"; }
export -f omarchy-dns
'"$reader_script")
[[ $reader_result == $'hit:c:1\nmiss:c:0' ]] ||
  fail "guard prelude compares a captured reader as the substitution did" "got: $reader_result"
pass "guard prelude compares a captured reader exactly as the substitution it replaced"

# The batch inherits whatever a login shell left set. A reader that exits
# nonzero must not take the rest of the menu's rows down with it.
errexit_result=$("$TEST_BASH" -e -c '
omarchy-dns() { printf "Cloudflare\n"; return 3; }
export -f omarchy-dns
'"$reader_script"'
printf "survived\n"' 2>/dev/null)
[[ $errexit_result == $'hit:c:1\nmiss:c:0\nsurvived' ]] ||
  fail "guard batch survives a failing reader under errexit" "got: $errexit_result"
pass "guard batch survives a reader that exits nonzero under errexit"

# Update > Extra Themes runs omarchy-theme-update, which pulls the themes that
# came from a git clone and skips everything else, so the guard has to answer
# for the same set: a row that appears over a symlinked theme or a worktree's
# `.git` file opens a terminal that prints nothing and closes. Both sides ask
# omarchy-theme-extras today; the shapes below are what would tell us if one
# of them stopped.
themes_guard=$(node -e '
  const fs = require("fs")
  const path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  const items = menu.parseMenuJsonc(fs.readFileSync(path.join(process.env.ROOT, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
  process.stdout.write(items.find(item => item.id === "update.themes").when)
')

cat >"$stub_dir/git" <<'STUB'
#!/bin/bash
: "${GIT_CALLS:=/dev/null}"
{ printf '<%s>' "$@"; printf '\n'; } >>"$GIT_CALLS"
STUB
chmod +x "$stub_dir/git"

# The updater names each theme it pulls, so what it printed is what the row
# would have been for. Run the guard the way the batch does, braces and all,
# and say which shapes are meant to show it rather than only that the two
# agree: they read the same command now, and agreement alone would hold even
# if both went wrong together.
assert_themes_guard_agrees() {
  local description="$1" home="$2" expected="$3"
  local guarded=0 updated=0

  HOME="$home" PATH="$ROOT/bin:$PATH" "$TEST_BASH" -e -c "{ $themes_guard; } >/dev/null 2>&1" || guarded=$?
  # bash explicitly, not the shebang: the script needs bash 4 mapfile and the
  # host's /bin/bash can be older (macOS ships 3.2; Arch, the target, ships 5).
  [[ -n $(HOME="$home" PATH="$ROOT/bin:$stub_dir:$PATH" "$TEST_BASH" "$ROOT/bin/omarchy-theme-update" 2>/dev/null) ]] || updated=1
  ((guarded == expected)) || fail "$description" "$home: guard=$guarded expected=$expected"
  ((updated == expected)) || fail "$description" "$home: update=$updated expected=$expected"
}

themes_home=$(mktemp -d)
trap 'rm -rf "$stub_dir" "$themes_home"' EXIT

# A theme copied by hand has nothing to pull, a symlinked one is someone's
# working copy, and a `.git` file is a worktree living elsewhere.
mkdir -p "$themes_home/missing"
mkdir -p "$themes_home/empty/.config/omarchy/themes"
mkdir -p "$themes_home/copied/.config/omarchy/themes/handmade"
mkdir -p "$themes_home/cloned/.config/omarchy/themes/tokyo-night/.git"
mkdir -p "$themes_home/linked/.config/omarchy/themes" "$themes_home/checkout/.git"
ln -s "$themes_home/checkout" "$themes_home/linked/.config/omarchy/themes/in-progress"
mkdir -p "$themes_home/worktree/.config/omarchy/themes/branch"
printf 'gitdir: /elsewhere\n' >"$themes_home/worktree/.config/omarchy/themes/branch/.git"

for shape in missing:1 empty:1 copied:1 cloned:0 linked:1 worktree:1; do
  assert_themes_guard_agrees \
    "Extra Themes shows exactly when omarchy-theme-update has something to pull" \
    "$themes_home/${shape%:*}" "${shape#*:}"
done
# MCDC SYS-REQ-260922-47T8: guards_evaluated=T, system_state_reflected=T => TRUE
pass "Extra Themes shows exactly when omarchy-theme-update has something to pull"

# And the violation arm is drivable: evaluate the same guard with its reader
# off PATH. The capture comes back empty, the guard hides the row, and the
# clone on disk says it should show -- the answer no longer reflects the
# system. `command -v bash` first: the stripped PATH must still find a bash 4.
bash4=$(command -v bash)
no_reader=0
HOME="$themes_home/cloned" PATH="$stub_dir:/usr/bin:/bin" "$bash4" -e -c "{ $themes_guard; } >/dev/null 2>&1" || no_reader=$?
[[ $no_reader -ne 0 ]] ||
  fail "guard hides Extra Themes when its reader cannot run" "guard=$no_reader want=nonzero (hidden) over a cloned theme"
# MCDC SYS-REQ-260922-47T8: guards_evaluated=T, system_state_reflected=F => FALSE
pass "guard batch reflects nothing when its reader cannot run"

# Which themes get pulled, not just that something did: a name with a space in
# it is the one that goes missing the moment a path is split rather than passed
# whole, and it would still print an Updating: line on its way to the wrong
# directory.
many="$themes_home/many/.config/omarchy/themes"
mkdir -p "$many/tokyo night/.git" "$many/zen/.git" "$many/handmade"
ln -s "$themes_home/checkout" "$many/in-progress"

listed=$(HOME="$themes_home/many" LC_ALL=C "$ROOT/bin/omarchy-theme-extras")
[[ $listed == "$many/tokyo night"$'\n'"$many/zen" ]] ||
  fail "omarchy-theme-extras lists every clone and nothing else" "got: $listed"
pass "omarchy-theme-extras lists every clone and nothing else"

git_calls=$(mktemp)
trap 'rm -rf "$stub_dir" "$themes_home" "$git_calls"' EXIT
HOME="$themes_home/many" LC_ALL=C GIT_CALLS="$git_calls" PATH="$ROOT/bin:$stub_dir:$PATH" \
  "$TEST_BASH" "$ROOT/bin/omarchy-theme-update" >/dev/null 2>&1
pulled=$(<"$git_calls")
[[ $pulled == "<-C><$many/tokyo night><pull>"$'\n'"<-C><$many/zen><pull>" ]] ||
  fail "omarchy-theme-update pulls each clone by its whole path" "got: $pulled"
pass "omarchy-theme-update pulls each clone by its whole path"

# Remove > Theme runs omarchy-theme-remove, which offers the themes under
# ~/.config/omarchy/themes. With none there it prints "No extra themes
# installed." to a terminal the menu never opened, so the row only closes the
# menu. Most machines have only the bundled themes, so the row has to stay
# hidden until the remover has a theme it can remove: one copied or cloned
# there, but not a symlinked working copy, which it never lists, and not a
# dot-directory, which it refuses.
remove_theme_batch=$(node -e '
  const fs = require("fs")
  const path = require("path")
  const menu = require(path.join(process.env.ROOT, "shell/plugins/menu/MenuModel.js"))
  const items = menu.parseMenuJsonc(fs.readFileSync(path.join(process.env.ROOT, "default/omarchy/omarchy-menu.jsonc"), "utf8"))
  const row = items.find(item => item.id === "remove.theme")
  process.stdout.write(menu.guardScript({ [row.id]: row }))
')

# The remover hands its list to the picker, one argument per theme after the
# prompt. Picking nothing keeps every theme.
cat >"$stub_dir/omarchy-menu-select" <<'STUB'
#!/bin/bash
: "${SELECT_CALLS:=/dev/null}"
printf '%s\n' "$@" >>"$SELECT_CALLS"
exit 1
STUB
chmod +x "$stub_dir/omarchy-menu-select"

# Run the guard as the menu does, through the whole generated batch, and ask
# whether the remover then offered a theme it would actually remove.
assert_remove_theme_guard_agrees() {
  local description="$1" home="$2" expected="$3"
  local guarded=0 offered=1 calls answer name

  # A row with no when: is always shown.
  if [[ -n $remove_theme_batch ]]; then
    answer=$(HOME="$home" PATH="$ROOT/bin:$PATH" bash -c "$remove_theme_batch" 2>/dev/null | command grep '^remove\.theme:w:')
    [[ $answer == remove.theme:w:1 ]] || guarded=1
  fi
  calls=$(mktemp)
  HOME="$home" SELECT_CALLS="$calls" PATH="$stub_dir:$ROOT/bin:$PATH" "$ROOT/bin/omarchy-theme-remove" >/dev/null 2>&1 || true
  while IFS= read -r name; do
    [[ $name == -- ]] && break
    [[ $name == .* ]] || offered=0
  done < <(tail -n +2 "$calls")
  rm -f "$calls"
  ((guarded == expected)) || fail "$description" "$home: guard=$guarded expected=$expected"
  ((offered == expected)) || fail "$description" "$home: remove offered=$offered expected=$expected"
}

mkdir -p "$themes_home/dotted/.config/omarchy/themes/.git"

# Reproduces: KI-MENU-REMOVE-THEME-NO-THEMES
# MCDC SW-REQ-261003-390Z: remove_theme_row_hidden=T, remover_has_no_theme=T => TRUE
# MCDC SW-REQ-261003-390Z: remove_theme_row_hidden=F, remover_has_no_theme=F => TRUE [no-action: a copied, cloned or worktree theme gives the remover a theme to offer, so the guarantee is not invoked and the row shows]
for shape in missing:1 empty:1 copied:0 cloned:0 linked:1 worktree:0 dotted:1; do
  assert_remove_theme_guard_agrees \
    "Remove > Theme shows exactly when omarchy-theme-remove has a theme to offer" \
    "$themes_home/${shape%:*}" "${shape#*:}"
done
pass "Remove > Theme shows exactly when omarchy-theme-remove has a theme to offer"
