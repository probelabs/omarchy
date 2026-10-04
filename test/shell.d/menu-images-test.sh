#!/bin/bash

set -euo pipefail

# Verifies: SW-REQ-260922-43HQ, SW-REQ-260922-MH9B, SW-REQ-260929-THMB, SW-REQ-260929-REJT
#mcdc:ignore:defensive SW-REQ-260922-43HQ: cached_rows_reused=F, dirs_unchanged=T => FALSE -- a matching fast signature loads the rows file before any rebuild path runs, and rows plus signatures are published together under one lock; unchanged dirs with the reuse skipped needs a broken signature compare [reviewed: REVIEW-M6]
#mcdc:ignore:defensive SW-REQ-260922-MH9B: rows_rebuilt_and_cached=F, signature_mismatch=T => FALSE -- a full-signature mismatch falls unconditionally into the rebuild branch that rewrites and re-signs the rows; a mismatch without a rebuild needs a broken branch [reviewed: REVIEW-M6]
#mcdc:ignore:defensive SW-REQ-260929-THMB: thumbnail_generated=F, thumbnail_missing=T => FALSE -- the directory scan is the pipeline entry and every scanned file routes through thumbnail_for; a missing thumbnail that generates nothing needs a broken branch [reviewed: REVIEW-260930-WJQK]
#mcdc:ignore:defensive SW-REQ-260929-REJT: rejection_marker_recorded=F, media_rejected=T => FALSE -- a refused video either writes its marker in the fan-out child or is honored through the standing marker; a rejection with neither needs a broken branch [reviewed: REVIEW-260930-WJQK]
# mcdc:witness-out-of-process

source "$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)/base-test.sh"

require_command flock
require_command setsid

tmp=$(mktemp -d)
lazy_groups=()
cleanup() {
  local status=$? gate group running attempt
  trap - EXIT
  # Release every fixture gate, including on an assertion failure. Each lazy
  # invocation owns a private process group, so its detached pool is tracked.
  for gate in "$tmp"/lazy-state*/gate; do
    [[ ! -d ${gate%/*} ]] || touch "$gate"
  done
  for attempt in {1..500}; do
    running=false
    for group in "${lazy_groups[@]}"; do
      if kill -0 -- "-$group" 2>/dev/null; then running=true; fi
    done
    [[ $running == "true" ]] || break
    sleep 0.02
  done
  for group in "${lazy_groups[@]}"; do
    kill -TERM -- "-$group" 2>/dev/null || true
    wait "$group" 2>/dev/null || true
  done
  rm -rf "$tmp"
  exit "$status"
}
trap cleanup EXIT

# Under an MC/DC measurement the menu is an instrumented copy that carries its
# trace recorder above its own first line. Its thumbnail generators run in
# xargs bash -c children, which import the exported functions but not the
# recorder. BASH_ENV hands the recorder to each child bash, so the children
# convert and record as the menu itself would. Plain runs are unchanged.
if [[ -n ${PROOF_MCDC_TRACE_DIR:-} ]] &&
  sed -n 2p "$ROOT/bin/omarchy-menu-images" | grep -q '^# ReqProof Bash MC/DC runtime recorder' &&
  grep -q '^# omarchy:summary=' "$ROOT/bin/omarchy-menu-images"; then
  awk 'NR == 1 { next } /^# omarchy:summary=/ { exit } { print }' "$ROOT/bin/omarchy-menu-images" >"$tmp/mcdc-recorder.sh"
  export BASH_ENV="$tmp/mcdc-recorder.sh"
fi

cache_home="$tmp/cache"
images="$tmp/images"
media="$tmp/media"
stub_bin="$tmp/bin"
mkdir -p "$images" "$media" "$stub_bin"

cat >"$stub_bin/vipsthumbnail" <<'EOF'
#!/bin/bash

image="$1"
shift

while (( $# > 0 )); do
  if [[ $1 == "--path" ]]; then
    output=${2%%\[*}
    break
  fi
  shift
done

if [[ -f ${VIPSTHUMBNAIL_FAIL_FILE:-} ]] && grep -Fxq "$image" "$VIPSTHUMBNAIL_FAIL_FILE"; then
  exit 1
fi

[[ -z ${VIPSTHUMBNAIL_CALLS_FILE:-} ]] || printf '%s\n' "$image" >>"$VIPSTHUMBNAIL_CALLS_FILE"
[[ -z ${VIPSTHUMBNAIL_DELAY:-} ]] || sleep "$VIPSTHUMBNAIL_DELAY"
printf 'thumbnail' >"$output"
EOF
chmod +x "$stub_bin/vipsthumbnail"

cat >"$stub_bin/ffmpegthumbnailer" <<'EOF'
#!/bin/bash

image=""
output=""

while (( $# > 0 )); do
  case "$1" in
    -i) image="$2"; shift 2 ;;
    -o) output="$2"; shift 2 ;;
    *) shift ;;
  esac
done

if [[ -f ${FFMPEG_FAIL_FILE:-} ]] && grep -Fxq "$image" "$FFMPEG_FAIL_FILE"; then
  exit "${FFMPEG_FAIL_STATUS:-1}"
fi

[[ -z ${FFMPEG_CALLS_FILE:-} ]] || printf '%s\n' "$image" >>"$FFMPEG_CALLS_FILE"
printf 'video-thumbnail' >"$output"
EOF
chmod +x "$stub_bin/ffmpegthumbnailer"

for name in one two three; do
  printf 'image-%s' "$name" >"$images/$name.png"
done

cache_dir="$cache_home/omarchy/image-selector"
mkdir -p "$cache_dir"

# The cache keys a thumbnail by path and file signature, exactly as the menu
# does, so a scenario can seed or inspect a single image's cache entry.
thumbnail_hash() {
  local signature
  signature=$(stat -Lc '%s:%Y' "$1")
  printf '%s\t%s' "$1" "$signature" | md5sum | cut -d ' ' -f 1
}

# Lazy rows hand generation to one detached worker pool that outlives the menu,
# so the run answers before the pixels land; wait them out.
wait_for_thumbnails() {
  local expected="$1"

  for _ in {1..200}; do
    (( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) >= expected )) && return 0
    sleep 0.05
  done
  return 1
}

# The pool outlives the lazy run that started it. It is idle once no queue
# file waits and no pool holds its lock, so a scenario waits for that before
# it clears the cache under a running converter. The lock is probed only
# once the queue is empty, so the probe never turns a starting pool away.
wait_for_pools() {
  local path idle

  for _ in {1..200}; do
    idle=true
    for path in "$cache_dir"/*.rows.thumbnails.pending; do
      if [[ -e $path ]]; then idle=false; fi
    done
    for path in "$cache_dir"/*.rows.thumbnails.lock; do
      if [[ $idle == true && -e $path ]] && ! flock -n "$path" true; then idle=false; fi
    done
    if [[ $idle == true ]]; then return 0; fi
    sleep 0.05
  done
  return 1
}

run_images() {
  PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
    "$ROOT/bin/omarchy-menu-images" "$@"
}

cache_key=$(printf '%s' "$images" | md5sum | cut -d ' ' -f 1)

stale_tmp=""
for image in "$images"/*; do
  hash=$(thumbnail_hash "$image")
  mkdir "$cache_dir/$hash.jpg.lock"
  touch -m -d '10 minutes ago' "$cache_dir/$hash.jpg.lock"
  stale_tmp="$cache_dir/$hash.jpg.4242.jpg"
done
printf 'partial' >"$stale_tmp"

# A picker opens lazily: the rows answer with the media files while the
# detached pool generates. The aged legacy locks are the generators' own to
# reap, and the partial thumbnails a killed generator left behind go with them.
rows=$(run_images --print-rows --lazy-thumbnails "$images")

(( $(wc -l <<<"$rows") == 3 )) || fail "the lazy menu offers every image while thumbnails generate" "$rows"
wait_for_thumbnails 3 || fail "the lazy menu's pool generates every thumbnail" "$(ls "$cache_dir")"
(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) == 3 )) ||
  fail "image menu recovers thumbnails from stranded locks"
(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg.lock' -type d | wc -l) == 0 )) ||
  fail "image menu reaps the aged legacy locks it replaces"
[[ ! -e $stale_tmp ]] ||
  fail "image menu clears partial thumbnails left by killed generators"
pass "image menu recovers stranded locks and stale rows"

# A stale row cache left behind by an older release is invalid the moment its
# signature no longer describes the directory: the next cache-only pass
# rebuilds every row and re-signs.
printf '%s\t%s' "$images/one.png" "$cache_dir/missing.jpg" >"$cache_dir/$cache_key.rows"
printf 'v2\n%s:%s\n' "$images" "$(stat -Lc '%Y' "$images")" >"$cache_dir/$cache_key.signature"
printf 'v1\n%s:%s\n' "$images" "$(stat -Lc '%Y' "$images")" >"$cache_dir/$cache_key.fast-signature"

run_images --cache-only "$images"

(( $(awk 'END { print NR }' "$cache_dir/$cache_key.rows") == 3 )) ||
  fail "image menu rebuilds every row after cache invalidation"
[[ $(head -n 1 "$cache_dir/$cache_key.signature") == "v4" ]] ||
  fail "image menu invalidates stale row caches"
# MCDC SW-REQ-260922-MH9B: rows_rebuilt_and_cached=T, signature_mismatch=T => TRUE
# MCDC SW-REQ-260922-43HQ: cached_rows_reused=F, dirs_unchanged=F => TRUE [no-action: every row is rebuilt and re-signed after the stale signature -- the reuse path is never entered]
pass "image menu rebuilds and signs the rows after the stale cache is dropped"

# A lost fast signature sends the next open through the full-signature
# compare, which vouches for the same rows without a rebuild.
before=$(<"$cache_dir/$cache_key.rows")
rm -f "$cache_dir/$cache_key.fast-signature"
run_images --cache-only "$images"
[[ $(<"$cache_dir/$cache_key.rows") == "$before" ]] ||
  fail "image menu keeps the rows a full-signature match vouches for"
[[ -f $cache_dir/$cache_key.fast-signature ]] ||
  fail "image menu re-signs the fast signature after a full-signature reuse"
pass "image menu keeps the rows across a full-signature reuse"

# A legacy generator that started recently may still own its lock, so its
# thumbnail is left entirely alone while the others are served from the cache
# entries the earlier run already published.
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_dir"
locked_hash=$(thumbnail_hash "$images/two.png")
mkdir "$cache_dir/$locked_hash.jpg.lock"
for name in one three; do
  printf 'thumbnail' >"$cache_dir/$(thumbnail_hash "$images/$name.png").jpg"
done

run_images --cache-only "$images"

(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) == 2 )) ||
  fail "image menu skips a thumbnail whose fresh legacy lock may still be owned"
[[ -d $cache_dir/$locked_hash.jpg.lock ]] ||
  fail "image menu leaves a fresh legacy lock directory alone"
[[ ! -e $cache_dir/$cache_key.rows ]] ||
  fail "image menu does not cache rows while a legacy generator holds a lock"

# The same fresh lock stops a lazy generator too: it refuses the lock file it
# cannot create and leaves the row to a later open.
run_images --print-rows --lazy-thumbnails "$images" >/dev/null
(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) == 2 )) ||
  fail "a fresh legacy lock stops a lazy generator as well" "$(ls "$cache_dir")"
[[ -d $cache_dir/$locked_hash.jpg.lock ]] ||
  fail "a fresh legacy lock survives a lazy run" "$(ls "$cache_dir")"
pass "image menu respects a live legacy generator's lock"

wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"
printf '%s\n' "$images/two.png" >"$tmp/failures"

VIPSTHUMBNAIL_FAIL_FILE="$tmp/failures" run_images --cache-only "$images"

[[ ! -e $cache_dir/$cache_key.rows ]] || fail "image menu does not cache incomplete rows"
[[ ! -e $cache_dir/$cache_key.signature ]] || fail "image menu does not sign incomplete rows"
[[ ! -e $cache_dir/$cache_key.fast-signature ]] || fail "image menu does not fast-cache incomplete rows"
# SW-REQ-260929-REJT:error_handling:negative
pass "image menu leaves failed thumbnail batches uncached"

rm "$tmp/failures"
# The next open retries the thumbnail that failed: a lazy open queues it for
# the pool, and the cache-only pass that follows caches the complete rows.
run_images --print-rows --lazy-thumbnails "$images" >/dev/null
wait_for_thumbnails 3 || fail "the lazy menu retries a previously failed thumbnail"
run_images --cache-only "$images"

(( $(find "$cache_dir" -maxdepth 1 -name '*.jpg' -type f | wc -l) == 3 )) ||
  fail "image menu retries a previously failed thumbnail"
(( $(awk 'END { print NR }' "$cache_dir/$cache_key.rows") == 3 )) ||
  fail "image menu caches every row after retry"
# The missing thumbnail entered the pipeline and settled: the lazy lane
# regenerated it, and the cache-only pass signed the complete rows.
# MCDC SW-REQ-260929-THMB: thumbnail_generated=T, thumbnail_missing=T => TRUE
pass "image menu completes and caches a later retry"

# With the cache warm and the directory untouched, the next run answers from
# the rows file alone: the fast signature matches, so no thumbnail generator
# runs at all.
: >"$tmp/calls"
VIPSTHUMBNAIL_CALLS_FILE="$tmp/calls" run_images --cache-only "$images"

[[ ! -s $tmp/calls ]] ||
  fail "image menu reuses cached rows without regenerating thumbnails" "calls: $(cat "$tmp/calls")"
(( $(awk 'END { print NR }' "$cache_dir/$cache_key.rows") == 3 )) ||
  fail "image menu keeps the cached rows across a reuse run"
# MCDC SW-REQ-260922-43HQ: cached_rows_reused=T, dirs_unchanged=T => TRUE
# MCDC SW-REQ-260922-MH9B: rows_rebuilt_and_cached=F, signature_mismatch=F => TRUE [no-action: the vipsthumbnail spy log is empty across the whole run -- no rebuild happens while the signature matches]
pass "image menu reuses cached rows for unchanged directories"

wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"
: >"$tmp/calls"

# The delay keeps both runs inside the generation window. Both runs queue the
# same three jobs for the shared pool, so the duplicate jobs reach each
# thumbnail's lock while the first generator still holds it.
pids=()
for run in 1 2; do
  VIPSTHUMBNAIL_CALLS_FILE="$tmp/calls" VIPSTHUMBNAIL_DELAY=0.25 \
    run_images --print-rows --lazy-thumbnails "$images" >/dev/null &
  pids+=($!)
done
for pid in "${pids[@]}"; do
  wait "$pid" || fail "concurrent image menu runs exit cleanly"
done
wait_for_thumbnails 3 || fail "concurrent image menu runs generate every thumbnail"

(( $(wc -l <"$tmp/calls") == 3 )) || fail "image menu serializes concurrent thumbnail generators" "$(cat "$tmp/calls")"

rm -f "$cache_dir"/*.jpg
rm -f "$cache_dir/$cache_key.rows" "$cache_dir/$cache_key.signature" "$cache_dir/$cache_key.fast-signature"
VIPSTHUMBNAIL_CALLS_FILE="$tmp/calls" \
  run_images --print-rows --lazy-thumbnails "$images" >/dev/null
wait_for_thumbnails 3 || fail "the released locks let every thumbnail regenerate"

(( $(wc -l <"$tmp/calls") == 6 )) || fail "image menu releases thumbnail locks after generation" "$(cat "$tmp/calls")"
pass "image menu owns locks for exactly one generator lifetime"

wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"

# Rows are what the shell holds onto, so printing them hands back one row per
# image with its generated thumbnail behind it.
run_images --print-rows --lazy-thumbnails "$images" >/dev/null
wait_for_thumbnails 3 || fail "the lazy menu's pool generates the rows it prints"
rows=$(run_images --print-rows "$images")

(( $(wc -l <<<"$rows") == 3 )) || fail "image menu prints one row per image"
while IFS=$'\t' read -r row_image row_thumbnail; do
  [[ $row_image == "$images"/* && -f $row_thumbnail ]] ||
    fail "image menu prints each image with its generated thumbnail" "$rows"
done <<<"$rows"
pass "image menu prints its rows for the shell to hold"

# A queue lock the menu cannot open leaves its jobs unpublished. The menu
# still answers with every row and exits cleanly, but starts no pool.
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_dir"
mkdir "$cache_dir/$cache_key.rows.thumbnails.queue.lock"
: >"$tmp/calls"
rows=$(VIPSTHUMBNAIL_CALLS_FILE="$tmp/calls" run_images --print-rows --lazy-thumbnails "$images" 2>/dev/null) ||
  fail "an unopenable queue lock still lets the lazy menu answer"
(( $(wc -l <<<"$rows") == 3 )) || fail "an unopenable queue lock keeps every lazy row" "$rows"
[[ ! -e $cache_dir/$cache_key.rows.thumbnails.pending ]] ||
  fail "an unopenable queue lock publishes no jobs" "$(ls "$cache_dir")"
[[ ! -s $tmp/calls ]] || fail "an unopenable queue lock starts no converter" "$(cat "$tmp/calls")"
pass "an unopenable queue lock keeps the rows and starts no pool"

# A directory with a video exercises the other half of the queue: pictures go
# lazy, the video is queued for the fan-out, and the rows never block on it.
printf 'still' >"$media/pic.png"
printf 'video' >"$media/clip.mp4"
pic_hash=$(thumbnail_hash "$media/pic.png")
video_hash=$(thumbnail_hash "$media/clip.mp4")
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"

rows=$(run_images --print-rows --lazy-thumbnails "$media")
grep -q "^$media/pic.png" <<<"$rows" ||
  fail "the lazy menu offers the picture while the video is queued" "$rows"
while IFS=$'\t' read -r row_image row_thumbnail; do
  [[ -f $row_thumbnail ]] || fail "every offered row points at a readable file" "$rows"
done <<<"$rows"
[[ -f $cache_dir/$video_hash.jpg ]] ||
  fail "the fan-out generates the video thumbnail before the rows print" "$(ls "$cache_dir")"
wait_for_thumbnails 2 || fail "the lazy menu's pool generates the picture"
[[ -f $cache_dir/$pic_hash.jpg ]] || fail "the picture's thumbnail lands in the cache"
# SW-REQ-260929-REJT:error_handling:nominal
# SW-REQ-260929-REJT:malformed_input:nominal
# MCDC SW-REQ-260929-REJT: rejection_marker_recorded=F, media_rejected=F => TRUE [no-action: both files convert, no marker is written or honored, and every row offers its pixels -- no refusal happens]
pass "the lazy menu serves pictures while the video queues"

# With every thumbnail already on disk there is nothing left to queue.
printf 'thumbnail' >"$cache_dir/$video_hash.jpg"
run_images --print-rows --lazy-thumbnails "$media" >/dev/null
# MCDC SW-REQ-260929-THMB: thumbnail_generated=F, thumbnail_missing=F => TRUE [no-action: the thumbnail already sits at its content-hash path, so the row serves from cache and no lane runs -- nothing generates]
pass "a queued video that already has its thumbnail queues nothing"

# A single converter lane still drains a queued video. Dropping the thumbnail
# alone is not enough -- cached rows are trusted on the directory's mtime, and
# a same-second touch would not change it -- so the directory gets an
# unambiguous mtime to send the next open through the rebuild.
rm -f "$cache_dir/$video_hash.jpg"
touch -d '2 days ago' "$media"
OMP_NUM_THREADS=1 run_images --print-rows --lazy-thumbnails "$media" >/dev/null
[[ -f $cache_dir/$video_hash.jpg ]] ||
  fail "a single video lane still drains the queue" "$(ls "$cache_dir")"
pass "a single video lane still drains the queue"

# A video the converter rejected is remembered, so it costs nothing on the
# next open and the rows stay uncached over its absence.
media_cache_key=$(printf '%s' "$media" | md5sum | cut -d ' ' -f 1)
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_dir"
: >"$cache_dir/$video_hash.jpg.failed"

rows=$(run_images --print-rows --lazy-thumbnails "$media")
(( $(wc -l <<<"$rows") == 1 )) || fail "a rejected video keeps no row" "$rows"
grep -q "^$media/pic.png" <<<"$rows" ||
  fail "the picture stays while the rejected video drops" "$rows"
[[ ! -e $cache_dir/$media_cache_key.rows ]] ||
  fail "a rejected video leaves the rows uncached"
# SW-REQ-260929-REJT:malformed_input:negative
# MCDC SW-REQ-260929-REJT: rejection_marker_recorded=T, media_rejected=T => TRUE
pass "a rejected video keeps no row and leaves the rows uncached"

# The marker comes from the converter itself: a refused video records one, so
# the next open drops its row without running the converter again.
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_dir"
printf '%s\n' "$media/clip.mp4" >"$tmp/video-failures"
rows=$(FFMPEG_FAIL_FILE="$tmp/video-failures" run_images --print-rows --lazy-thumbnails "$media")
! grep -q "^$media/clip.mp4" <<<"$rows" || fail "a refused video offers no row" "$rows"
[[ -f $cache_dir/$video_hash.jpg.failed ]] ||
  fail "a refused video leaves a rejection marker" "$(ls "$cache_dir")"
: >"$tmp/ffmpeg-calls"
FFMPEG_CALLS_FILE="$tmp/ffmpeg-calls" run_images --print-rows --lazy-thumbnails "$media" >/dev/null
[[ ! -s $tmp/ffmpeg-calls ]] ||
  fail "a recorded rejection spares the converter on the next open" "$(cat "$tmp/ffmpeg-calls")"
pass "a refused video records its rejection and is skipped on the next open"

# A timeout (124) or a kill (137) is no verdict on the file: the row drops for
# this open, but no marker is left, so the next open tries again.
for status in 124 137; do
  wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
  rm -rf "$cache_home"
  mkdir -p "$cache_dir"
  rows=$(FFMPEG_FAIL_FILE="$tmp/video-failures" FFMPEG_FAIL_STATUS="$status" \
    run_images --print-rows --lazy-thumbnails "$media")
  ! grep -q "^$media/clip.mp4" <<<"$rows" || fail "a video stopped with $status offers no row" "$rows"
  [[ ! -e $cache_dir/$video_hash.jpg.failed ]] ||
    fail "a video stopped with $status leaves no rejection marker" "$(ls "$cache_dir")"
  : >"$tmp/ffmpeg-calls"
  FFMPEG_CALLS_FILE="$tmp/ffmpeg-calls" run_images --print-rows --lazy-thumbnails "$media" >/dev/null
  grep -Fxq "$media/clip.mp4" "$tmp/ffmpeg-calls" ||
    fail "a video stopped with $status is retried on the next open" "$(cat "$tmp/ffmpeg-calls")"
done
rm -f "$tmp/video-failures" "$tmp/ffmpeg-calls"
pass "a timed-out or killed video converter leaves the video to retry"

# A converter that fails under a lazy open leaves nothing behind: no partial
# file, no thumbnail, and no failure marker, since only videos get one.
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"
faildir="$tmp/faildir"
mkdir -p "$faildir"
printf 'doomed' >"$faildir/doomed.png"
printf '%s\n' "$faildir/doomed.png" >"$tmp/failures"

rows=$(VIPSTHUMBNAIL_FAIL_FILE="$tmp/failures" run_images --print-rows --lazy-thumbnails "$faildir")
grep -q "^$faildir/doomed.png" <<<"$rows" ||
  fail "a failing picture still offers itself lazily" "$rows"
wait_for_pools || fail "the failed lazy converter's pool finishes"
(( $(find "$cache_dir" -maxdepth 1 \( -name '*.jpg' -o -name '*.failed' \) | wc -l) == 0 )) ||
  fail "a failed lazy converter leaves nothing behind" "$(ls "$cache_dir")"
rm -rf "$faildir" "$tmp/failures"
pass "a failed lazy converter leaves nothing behind"

# The flag surface: every documented flag is accepted, and the ones that shape
# the menu take effect without disturbing the rows.
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"

run_images --help >/dev/null
usage_status=0
run_images >/dev/null 2>&1 || usage_status=$?
[[ $usage_status -eq 1 ]] || fail "the menu without an image directory prints usage and exits one" "status: $usage_status"
arg_status=0
run_images --selected >/dev/null 2>&1 || arg_status=$?
[[ $arg_status -eq 1 ]] || fail "--selected without a value prints usage and exits one" "status: $arg_status"
pass "the menu refuses to run without an image directory or a value for --selected"

run_images --print-name --show-labels --filterable --preload --print-rows "$media" >/dev/null
pass "the menu accepts its display flags together with --print-rows"

# The selected image is resolved within the directory it belongs to, by path,
# by content, or not at all -- and a directory that does not exist is skipped
# on the way.
rows=$(run_images --print-rows --selected "$media/pic.png" --lazy-thumbnails "$media")
grep -q "^$media/pic.png" <<<"$rows" ||
  fail "a selected image inside the directory resolves to its row" "$rows"

ln "$media/pic.png" "$tmp/pic-elsewhere.png"
rows=$(run_images --print-rows --selected "$tmp/pic-elsewhere.png" --lazy-thumbnails "$tmp/not-a-dir" "$media")
grep -q "^$media/pic.png" <<<"$rows" ||
  fail "a selected file outside the directory still resolves by content" "$rows"
rm "$tmp/pic-elsewhere.png"

rows=$(run_images --print-rows --selected "$tmp/nowhere.png" --lazy-thumbnails "$media")
grep -q "^$media/pic.png" <<<"$rows" ||
  fail "a selection that matches nothing still prints the rows" "$rows"
pass "the selected image resolves by directory, content, or not at all"

# A directory prepared without generating anything leaves the picture's
# thumbnail out of the cache: prepare answers without spending a converter.
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"
run_images --print-rows --prepare-only --lazy-thumbnails "$media" >/dev/null
[[ ! -f $cache_dir/$pic_hash.jpg ]] ||
  fail "a prepared directory generates nothing" "$(ls "$cache_dir")"
pass "a prepared directory offers its media without generating anything"

# Several directories at once are all scanned, and one that does not exist is
# skipped rather than fatal.
wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"
extra="$tmp/extra-media"
mkdir -p "$extra"
printf 'more' >"$extra/more.png"

rows=$(run_images --print-rows --lazy-thumbnails "$media" "$extra" "$tmp/not-a-dir")
grep -q "^$media/pic.png" <<<"$rows" && grep -q "^$extra/more.png" <<<"$rows" ||
  fail "the menu scans every directory it is given" "$rows"
wait_for_thumbnails 2 || fail "both directories generate their thumbnails"
pass "the menu scans every directory it is given, skipping missing ones"

# The interactive tail talks to the shell's image selector over its IPC. A
# stub stands in for it: it accepts the open, publishes the pick into the
# selection file, marks the done file, and answers.
cat >"$stub_bin/omarchy-shell" <<'STUB'
#!/bin/bash

case "$1 $2" in
  "image-selector preload")
    printf '%s\n' "$*" >>"${OMARCHY_SHELL_LOG:-/dev/null}"
    exit "${OMARCHY_SHELL_STATUS:-0}"
    ;;
  "image-selector open")
    if [[ -n ${OMARCHY_SHELL_DELAY:-} ]]; then
      # The done mark lands while the menu is already waiting, the way the
      # real selector answers after it has rendered. The marker job lets go of
      # the caller's pipes so the open answers before it fires.
      ( sleep "$OMARCHY_SHELL_DELAY"; : >"$7" ) </dev/null >/dev/null 2>&1 &
    else
      : >"$7"
    fi
    if [[ -n ${PICKED_SELECTION:-} ]]; then
      printf '%s\n' "$PICKED_SELECTION" >"$6"
    fi
    printf '%s\n' "${OMARCHY_SHELL_ANSWER:-ok}"
    exit "${OMARCHY_SHELL_STATUS:-0}"
    ;;
  *)
    exit 9
    ;;
esac
STUB
chmod +x "$stub_bin/omarchy-shell"

run_picker() {
  PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$cache_home" \
    "$ROOT/bin/omarchy-menu-images" "$@"
}

wait_for_pools || fail "the lazy thumbnail pool finishes before the cache is cleared"
rm -rf "$cache_home"
mkdir -p "$cache_home"

# Preloading hands the rows to the shell and stops there.
: >"$tmp/shell-log"
OMARCHY_SHELL_LOG="$tmp/shell-log" run_picker --preload --lazy-thumbnails "$media"
grep -q "image-selector preload" "$tmp/shell-log" ||
  fail "a preloading menu hands its rows to the shell" "$(cat "$tmp/shell-log" 2>/dev/null)"
pass "a preloading menu hands its rows to the shell and stops"

# A normal open waits for the pick and prints it back.
selection=$(PICKED_SELECTION="$media/pic.png" OMARCHY_SHELL_DELAY=0.05 \
  run_picker --lazy-thumbnails "$media")
[[ $selection == "$media/pic.png" ]] ||
  fail "the menu waits for the picker and prints the pick" "$selection"
pass "the menu waits for the picker and prints the pick"

# With --print-name the pick comes back as the bare image name.
selection=$(PICKED_SELECTION="$media/pic.png" \
  run_picker --print-name --lazy-thumbnails "$media")
[[ $selection == "pic" ]] ||
  fail "--print-name answers with the bare image name" "$selection"
pass "--print-name answers with the bare image name"

# An empty pick is a closed picker: the menu answers with nothing.
selection=$(run_picker --lazy-thumbnails "$media")
[[ -z $selection ]] || fail "a closed picker answers with nothing" "$selection"
pass "a closed picker answers with nothing"

# A selector that took the request but answered oddly is refused loudly.
status=0
OMARCHY_SHELL_ANSWER=unexpected run_picker --lazy-thumbnails "$media" >/dev/null 2>&1 || status=$?
[[ $status -eq 1 ]] || fail "an odd selector answer refuses the menu" "status: $status"
pass "an odd selector answer refuses the menu"

# A selector that never accepted the request is refused loudly too.
status=0
OMARCHY_SHELL_STATUS=9 run_picker --lazy-thumbnails "$media" >/dev/null 2>&1 || status=$?
[[ $status -eq 1 ]] || fail "a selector that refuses the open fails the menu" "status: $status"
pass "a selector that refuses the open fails the menu"

# Block converters behind a gate: printing lazy rows must neither await them
# nor start one process per image. Repeated refreshes share one worker pool.
lazy_images="$tmp/lazy-images"
lazy_state="$tmp/lazy-state"
mkdir -p "$lazy_images" "$lazy_state"
for (( i = 0; i < 40; i++ )); do
  printf 'image' >"$lazy_images/$i.png"
done
printf '0\n' >"$lazy_state/active"
printf '0\n' >"$lazy_state/peak"
cat >"$stub_bin/nproc" <<'EOF'
#!/bin/bash
echo "${FAKE_CORES:-2}"
EOF
cat >"$stub_bin/vipsthumbnail" <<'EOF'
#!/bin/bash
while (( $# > 0 )); do
  if [[ $1 == "--path" ]]; then output=${2%%\[*}; break; fi
  shift
done
exec 9>"$LAZY_STATE/lock"
priority=$(ps -o ni= -p "$$")
(( priority >= 10 )) || : >"$LAZY_STATE/priority-failed"
[[ $(ionice -p "$$") == "idle" ]] || : >"$LAZY_STATE/priority-failed"
flock 9
active=$(<"$LAZY_STATE/active")
active=$((active + 1))
printf '%s\n' "$active" >"$LAZY_STATE/active"
(( active <= $(<"$LAZY_STATE/peak") )) || printf '%s\n' "$active" >"$LAZY_STATE/peak"
flock -u 9
while [[ ! -f $LAZY_STATE/gate ]]; do sleep 0.02; done
printf 'thumbnail' >"$output"
flock 9
active=$(<"$LAZY_STATE/active")
printf '%s\n' "$((active - 1))" >"$LAZY_STATE/active"
echo done >>"$LAZY_STATE/completed"
EOF
chmod +x "$stub_bin/nproc" "$stub_bin/vipsthumbnail"

lazy_rows() {
  setsid env PATH="$stub_bin:$PATH" XDG_CACHE_HOME="$tmp/lazy-cache-$cores" LAZY_STATE="$lazy_state" FAKE_CORES="$cores" \
    timeout --foreground 10 "$ROOT/bin/omarchy-menu-images" --lazy-thumbnails --print-rows "$lazy_images" >"$lazy_state/rows" &
  local group=$!
  lazy_groups+=("$group")
  wait "$group" || fail "lazy image menu returns rows without waiting for its pool"
  rows=$(<"$lazy_state/rows")
}

for cores in 1 2 8; do
  rm -f "$lazy_images/new.png"
  printf 'image' >"$lazy_images/0.png"
  lazy_state="$tmp/lazy-state-$cores"
  mkdir -p "$lazy_state"
  printf '0\n' >"$lazy_state/active"
  printf '0\n' >"$lazy_state/peak"
  expected_workers=1
  (( cores < 4 )) || expected_workers=2
  for run in 1 2; do
    lazy_rows
    (( $(wc -l <<<"$rows") == 40 )) || fail "lazy image menu returns all rows before conversion"
  done
  for attempt in {1..100}; do
    (( $(<"$lazy_state/active") == expected_workers )) && break
    sleep 0.02
  done
  (( $(<"$lazy_state/active") == expected_workers && $(<"$lazy_state/peak") == expected_workers )) ||
    fail "lazy image menu bounds repeated refreshes to $expected_workers workers on $cores cores"
  [[ ! -e $lazy_state/completed ]] || fail "lazy image menu does not wait for conversion"
  [[ ! -e $lazy_state/priority-failed ]] || fail "lazy image menu reserves CPU and I/O priority for the UI"
  pass "lazy image menu opens with at most $expected_workers workers on $cores cores"

  # This job did not exist in the pool's first batch. A contended refresh must
  # retain it, along with a replacement for an image changed during conversion.
  printf 'new-image' >"$lazy_images/new.png"
  printf 'changed-image-with-new-size' >"$lazy_images/0.png"
  lazy_rows
  (( $(wc -l <<<"$rows") == 41 )) || fail "contended refresh returns the added image"
  for changed in new 0; do
    signature=$(stat -Lc '%s:%Y' "$lazy_images/$changed.png")
    hash=$(printf '%s\t%s' "$lazy_images/$changed.png" "$signature" | md5sum | cut -d ' ' -f 1)
    [[ ! -e $tmp/lazy-cache-$cores/omarchy/image-selector/$hash.jpg ]] ||
      fail "contended refresh does not start another converter pool"
  done

  touch "$lazy_state/gate"
  for attempt in {1..500}; do
    if [[ -f $lazy_state/completed ]] && (( $(wc -l <"$lazy_state/completed") == 42 )); then break; fi
    sleep 0.02
  done
  (( $(wc -l <"$lazy_state/completed") == 42 && $(<"$lazy_state/peak") == expected_workers )) ||
    fail "lazy image menu completes the queue after its parent and queue path are gone"
  for changed in new 0; do
    signature=$(stat -Lc '%s:%Y' "$lazy_images/$changed.png")
    hash=$(printf '%s\t%s' "$lazy_images/$changed.png" "$signature" | md5sum | cut -d ' ' -f 1)
    [[ -f $tmp/lazy-cache-$cores/omarchy/image-selector/$hash.jpg ]] ||
      fail "lazy image menu retains new and changed jobs while its pool is busy"
  done
  pass "lazy image menu workers finish every queued thumbnail after the caller exits"
done

# Exercise the same cleanup handler on both successful and failing exits,
# with a detached, gated fixture still running when the EXIT trap fires.
run_node_test <<'JS'
const fs = require('fs')
const { spawnSync } = require('child_process')
const script = fs.readFileSync(path.join(root, 'test/shell.d/menu-images-test.sh'), 'utf8')
const cleanupHandler = script.match(/cleanup\(\) \{[\s\S]*?\n\}/)[0]
for (const status of [0, 31]) {
  const result = spawnSync('bash', ['-c', `
set -euo pipefail
tmp=$(mktemp -d)
lazy_groups=()
${cleanupHandler}
trap cleanup EXIT
mkdir -p "$tmp/lazy-state-probe"
setsid bash -c ': >"$1/ready"; while [[ ! -e $1/gate ]]; do sleep 0.02; done; sleep 0.05' _ "$tmp/lazy-state-probe" &
lazy_groups+=("$!")
while [[ ! -e $tmp/lazy-state-probe/ready ]]; do sleep 0.02; done
printf '%s\\n%s\\n' "$tmp" "$!"
exit ${status}
`], { encoding: 'utf8', timeout: 15000 })
  const [directory, group] = result.stdout.trim().split('\n')
  const removed = !fs.existsSync(directory)
  let alive = false
  try {
    try { process.kill(-Number(group), 0); alive = true } catch (error) {
      if (error.code !== 'ESRCH') throw error
    }
  } finally {
    if (group) { try { process.kill(-Number(group), 'SIGKILL') } catch (_) {} }
    if (directory) fs.rmSync(directory, { recursive: true, force: true })
  }
  assertEqual(result.status, status, `fixture cleanup preserves exit status ${status}`)
  assert(removed, `fixture cleanup removes its directory on exit ${status}`)
  assert(!alive, `fixture cleanup finishes its detached workers on exit ${status}`)
}
JS
