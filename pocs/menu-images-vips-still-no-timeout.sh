#!/bin/bash
# Reproducer for KI-MENU-IMAGES-VIPS-NO-TIMEOUT: the vipsthumbnail still-image
# lane (bin/omarchy-menu-images, generate_thumbnail) has no timeout wrapper,
# unlike the video lane beside it (timeout -k 5 10 ffmpegthumbnailer). A
# stalled conversion wedges the fan-out lane indefinitely.
# Correct behavior (asserted): a stalled still conversion is bounded, like the
# video lane. RED reproducer: FAILS (exit 1) while the defect is present.
# Reproduces: KI-MENU-IMAGES-VIPS-NO-TIMEOUT
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

# The live converter dispatch, extracted verbatim from bin/omarchy-menu-images.
FUNCS="$(sed -n '/^is_video_path()/,/^}/p; /^generate_thumbnail()/,/^}/p' "$REPO/bin/omarchy-menu-images")"
[[ -n $FUNCS ]] || { echo "generate_thumbnail not found in bin/omarchy-menu-images (file changed?)"; exit 2; }

: > "$TMP/photo.jpg"   # still image: the non-video extension drives the vipsthumbnail lane

mk_stub() { # $1 dir, $2 mode (fast|stall)
  mkdir -p "$1"
  cat > "$1/vipsthumbnail" <<EOF
#!/bin/bash
prev=""
out=""
for arg do
  if [[ \$prev == "--path" ]]; then out="\${arg%%\[*}"; fi
  prev="\$arg"
done
if [[ ${2:-} == stall ]]; then
  exec sleep 30        # stalled conversion: never writes the output
fi
: > "\$out"            # healthy conversion: writes the requested output
EOF
  chmod +x "$1/vipsthumbnail"
}
mk_stub "$TMP/fast" fast
mk_stub "$TMP/stall" stall

run_lane() { # $1 stubdir, $2 thumbnail path
  FUNCS="$FUNCS" PATH="$1:/usr/bin:/bin" timeout 5 bash -c '
    eval "$FUNCS"
    generate_thumbnail "$1" "$2"
  ' gen "$TMP/photo.jpg" "$2"
}

# Negative control (PoC rules 3/10): a healthy vipsthumbnail completes and the
# thumbnail lands - the harness exercises the real converter dispatch.
ctrl="$TMP/ctrl.jpg"
run_lane "$TMP/fast" "$ctrl"
if [[ -f $ctrl ]]; then
  echo "control ok: healthy vipsthumbnail conversion completed and the thumbnail landed"
else
  echo "CONTROL FAILED: healthy conversion produced no thumbnail; PoC cannot distinguish defect from broken harness"
  exit 2
fi

# Defect arm: a stalled conversion is NOT bounded - the lane hangs until an
# external timeout kills it (rc=124), exactly the wedge the fan-out suffers.
start=$SECONDS
run_lane "$TMP/stall" "$TMP/defect.jpg"
rc=$?
elapsed=$((SECONDS - start))
if [[ $rc == 124 ]]; then
  echo "SYMPTOM: still-image lane still wedged inside vipsthumbnail at the external 5s kill (rc=124, ${elapsed}s) - no internal bound, unlike the video lane's timeout -k 5 10"
  exit 1
fi
echo "exit rc=$rc after ${elapsed}s - lane finished on its own (fix present?)"
[[ $rc -ne 0 ]]
