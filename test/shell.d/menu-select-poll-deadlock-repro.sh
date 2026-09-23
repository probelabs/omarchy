#!/opt/homebrew/bin/bash
# Reproducer for CRS-0014/C01: omarchy-menu-select done_file poll has no deadline.
# Reproduces: KI-MENU-SELECT-POLL-DEADLOCK
# Correct behavior (asserted): when the summoned menu never writes done_file
# (peer died), the script must exit within a bounded time.
# While the defect is present this FAILS: the poll loops forever.
set -u
STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/omarchy-shell" <<'SH'
#!/bin/bash
exit 0   # summon "succeeds"; nothing ever writes the done file (menu dead)
SH
chmod +x "$STUB/omarchy-shell"
export PATH="$STUB:$PATH"
start=$SECONDS
# Run the real script; give it 3s to prove it can hang.
timeout 3 bin/omarchy-menu-select "Pick one" alpha beta 2>/dev/null
rc=$?
elapsed=$((SECONDS - start))
if [[ $rc -eq 124 ]]; then
  echo "DEFECT PRESENT: poll hung past 3s deadline (rc=124 timeout kill)"; exit 1
fi
echo "exit rc=$rc after ${elapsed}s"
[[ $elapsed -lt 3 ]]
