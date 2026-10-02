#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-HR29, SW-REQ-261002-FFTQ, SW-REQ-261002-9H5Y
#mcdc:ignore:defensive SW-REQ-261002-FFTQ: symlink_root_given=T, symlink_root_listed=F => FALSE -- every start point goes to find -H, which follows a start point that is a symbolic link; listing nothing under a link root needs -H removed (the base behaviour), and a loop below the root can only fail the run if -H is widened to -L [reviewed: REVIEW-261002-6P46]
#mcdc:ignore:defensive SW-REQ-261002-9H5Y: same_file_reached_twice=T, file_listed_once=F => FALSE -- find prints %D:%i first on every row and awk keeps only the first row per key, so a second row for one file needs the awk filter or the %D:%i field removed [reviewed: REVIEW-261002-VZ1K]
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

# ------------------------------------------------ symbolic link roots (PR #13197)
# omacom/omarchy#13197: a given path that is a symbolic link to a directory is
# followed (find -H), a link below a root is not descended, and a file reached
# through two given paths is listed once (device:inode). The PR's own test is
# test/shell.d/menu-file-symlink-root-test.sh; these rows add the MC/DC
# witnesses and fail on the base, where find skips a link start point and a
# file reached twice is listed twice.
media="$tmp/media"
links="$tmp/links"
mkdir -p "$media/sub" "$links"
printf 'v' >"$media/clip.webm"
ln -s "$media" "$links/Videos"
ln -s "$media" "$media/sub/loop"

: >"$tmp/selected"
status=0
SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-menu-file" "Pick a video" "$links/Videos" "webm" || status=$?
[[ $status -eq 0 ]] || fail "file picker follows a symbolic link root and keeps exit 0 with a link loop below it" "status: $status"
[[ $(<"$tmp/selected") == "$links/Videos/clip.webm" ]] ||
  fail "file picker lists the files under a symbolic link root, not the loop below it" "got: $(cat "$tmp/selected")"
# MCDC SW-REQ-261002-FFTQ: symlink_root_given=T, symlink_root_listed=T => TRUE
pass "file picker lists the files under a symbolic link root and does not descend a link below it"

: >"$tmp/selected"
SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-menu-file" "Pick a video" "$media" "webm"
[[ $(<"$tmp/selected") == "$media/clip.webm" ]] ||
  fail "file picker lists a real directory root without link handling" "got: $(cat "$tmp/selected")"
# MCDC SW-REQ-261002-FFTQ: symlink_root_given=F, symlink_root_listed=F => TRUE [no-action: the only root is a real directory, so there is no link start point to follow; its one file is listed as at the base]
# MCDC SW-REQ-261002-9H5Y: same_file_reached_twice=F, file_listed_once=F => TRUE [no-action: one root and one file, so no file is reached through two paths and the dedup removes no row]
pass "file picker lists a real directory root as before"

: >"$tmp/selected"
SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-menu-file" "Pick a video" "$links/Videos:$media" "webm"
[[ $(grep -c 'clip\.webm$' "$tmp/selected") -eq 1 ]] ||
  fail "file picker lists a file reached through a link root and its target once" "got: $(cat "$tmp/selected")"
# MCDC SW-REQ-261002-9H5Y: same_file_reached_twice=T, file_listed_once=T => TRUE
pass "file picker lists a file reached through a link root and its target once"

: >"$tmp/selected"
SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
  "$ROOT/bin/omarchy-menu-file" "Pick a video" "$media:$media" "webm"
[[ $(grep -c 'clip\.webm$' "$tmp/selected") -eq 1 ]] ||
  fail "file picker lists a file of a root given twice once" "got: $(cat "$tmp/selected")"
pass "file picker lists a file of a root given twice once"

# ------------------------------------------------ missing paths are refused
# A path that does not exist is refused on stderr with exit 1 before any
# listing (HR29). The same holds for a symbolic link root whose target is gone
# (FFTQ) and for a missing path given next to a real root, which leaves no
# partial listing behind (9H5Y: the dedup step never sees a row).
refuse() {
  : >"$tmp/selected"
  status=0
  SELECT_LOG="$tmp/selected" PATH="$stub_bin:$PATH" \
    "$ROOT/bin/omarchy-menu-file" "Pick a video" "$1" "webm" 2>"$tmp/err" || status=$?
  [[ $status -eq 1 ]] || fail "$2 exits one" "status: $status"
  [[ $(<"$tmp/err") == "Path not found: $3" ]] || fail "$2 names the missing path" "err: $(cat "$tmp/err")"
  [[ ! -s $tmp/selected ]] || fail "$2 never reaches the menu" "selected: $(cat "$tmp/selected")"
}

# SW-REQ-260922-HR29:error_handling:negative
refuse "$tmp/gone" "file picker with a missing path" "$tmp/gone"
pass "file picker refuses a missing path before listing"

ln -s "$tmp/gone" "$links/Broken"
# SW-REQ-261002-FFTQ:error_handling:negative
refuse "$links/Broken" "file picker with a symbolic link root whose target is gone" "$links/Broken"
pass "file picker refuses a symbolic link root whose target is gone"

# SW-REQ-261002-9H5Y:error_handling:negative
refuse "$media:$tmp/gone" "file picker with a real root and a missing path" "$tmp/gone"
pass "file picker refuses a missing path given next to a real root, with no partial listing"
