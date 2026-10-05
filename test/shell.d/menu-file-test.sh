#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-HR29
#mcdc:ignore:defensive SW-REQ-260922-HR29: listing_shape=F, paths_given=T => FALSE -- the find pipeline (prune dotdirs, drop dotfiles, match formats, print mtime+path, sort newest first, cut to the path) is built unconditionally once the paths validate; a misshapen listing from valid paths needs a broken find arg build [reviewed: REVIEW-M7]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

# The listing is built with GNU find's -printf.
find /dev/null -printf '' >/dev/null 2>&1 ||
  fail "required command is available: GNU find (-printf)"

tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

stub_bin="$tmp/bin"
mkdir -p "$stub_bin"

# The listing pipes into omarchy-menu-select, so a spy there observes exactly
# what the picker would show.
cat >"$stub_bin/omarchy-menu-select" <<'STUB'
#!/bin/bash
cat >"$SELECT_LOG"
exit "${SELECT_STATUS:-0}"
STUB
chmod +x "$stub_bin/omarchy-menu-select"

tree="$tmp/tree"
mkdir -p "$tree/sub" "$tree/.config"
printf 'a' >"$tree/a.jpg"
printf 'b' >"$tree/b.PNG"
printf 'c' >"$tree/c.txt"
printf 'h' >"$tree/.hidden.jpg"
printf 'd' >"$tree/.config/d.jpg"
printf 'e' >"$tree/sub/e.jpg"

# Oldest to newest: sub/e.jpg, a.jpg, b.PNG -- the listing sorts newest first.
touch -t 202001010000 "$tree/sub/e.jpg"
touch -t 202101010000 "$tree/a.jpg"
touch -t 202201010000 "$tree/b.PNG"

# SW-REQ-260922-HR29:external_call_timeout_bounded:nominal -- the picker returns as soon as omarchy-menu-select returns
SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-menu-file" "Pick a file" "$tree" "jpg png"

expected=$(printf '%s\n' "$tree/b.PNG" "$tree/a.jpg" "$tree/sub/e.jpg")
[[ $(<"$tmp/selected") == "$expected" ]] ||
  fail "file picker lists matching files newest first, hiding dotfiles and dotdirs" "got: $(cat "$tmp/selected")"
# MCDC SW-REQ-260922-HR29: listing_shape=T, paths_given=T => TRUE
pass "file picker lists matching files newest first, hiding dotfiles and dotdirs"

# Missing arguments are a usage error before any listing is built.
: >"$tmp/selected"
status=0
SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-menu-file" "Pick a file" "$tree" 2>"$tmp/err" || status=$?
[[ $status -eq 1 ]] || fail "file picker without formats exits one" "status: $status"
[[ $(<"$tmp/err") == Usage:* ]] ||
  fail "file picker without formats prints usage" "err: $(cat "$tmp/err")"
[[ ! -s $tmp/selected ]] ||
  fail "file picker without formats never reaches the menu" "selected: $(cat "$tmp/selected")"
# MCDC SW-REQ-260922-HR29: listing_shape=F, paths_given=F => TRUE [no-action: the omarchy-menu-select spy captured nothing -- no listing is produced for a missing-arguments call]
pass "file picker rejects missing arguments before listing"

# The wait for the menu is bounded inside omarchy-menu-select (it gives up
# with exit one when the shell that took the request exits; witnessed in
# menu-dmenu-test.sh). That failure reaches the picker's caller at once.
: >"$tmp/selected"
status=0
start=$SECONDS
SELECT_STATUS=1 SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-menu-file" "Pick a file" "$tree" "jpg png" >/dev/null 2>&1 || status=$?
# SW-REQ-260922-HR29:external_call_timeout_bounded:negative -- a failed select (what a shell that exits now produces) ends the picker with its exit one
[[ $status -eq 1 ]] || fail "file picker passes a failed menu through as exit one" "status: $status"
(( SECONDS - start < 5 )) || fail "file picker returns promptly after a failed menu" "took $(( SECONDS - start ))s"
pass "file picker returns a failed menu as exit one"
