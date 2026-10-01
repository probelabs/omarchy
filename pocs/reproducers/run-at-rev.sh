#!/bin/bash
# Run the four model-level clip reproducers against the menu code of one or
# more git revisions, without touching the working tree.
#
#   pocs/reproducers/run-at-rev.sh <rev> [<rev> ...]
#
# For each rev, shell/plugins/menu/{MenuModel.js,Menu.qml} are read from the
# git object store into a temporary tree next to a copy of these reproducers,
# so every driver resolves "the shipped code" to that rev's code.
# Needs bash, git and Node.js 18+.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(git -C "$HERE" rev-parse --show-toplevel)
[[ $# -ge 1 ]] || { echo "usage: $0 <rev> [<rev> ...]" >&2; exit 2; }
for rev in "$@"; do
  sha=$(git -C "$REPO" rev-parse --short=8 "$rev^{commit}")
  T=$(mktemp -d "${TMPDIR:-/tmp}/menu-repro.XXXXXX")
  mkdir -p "$T/shell/plugins/menu" "$T/pocs"
  for f in MenuModel.js Menu.qml; do
    git -C "$REPO" show "$sha:shell/plugins/menu/$f" > "$T/shell/plugins/menu/$f"
  done
  cp -R "$HERE" "$T/pocs/reproducers"
  R="$T/pocs/reproducers"
  echo "##### rev $sha"
  for c in menu-jsonc-comment-tail:menu.jsonc menu-jsonc-comment-tail:omarchy-menu.jsonc menu-jsonc-comment-tail:fullline-control.jsonc menu-jsonc-comma-in-string:strings.jsonc menu-jsonc-array-root:array.jsonc; do
    d=${c%%:*}; fx=${c#*:}
    echo "--- $d"
    (cd "$R/$d" && node check-menu.js "$fx") 2>&1 || echo "(exit $?)"
  done
  echo "--- menu-back-from-search"
  node "$R/menu-back-from-search/back-from-search.js" 2>&1 || echo "(exit $?)"
  rm -r "$T"
done
