#!/usr/bin/bash
# Green witness for KI-MENU-SELECT-POLL-DEADLOCK (fixed on branch
# fix/issue-9057-menu-select-poll): the done_file poll in
# bin/omarchy-menu-select is bounded per SW-REQ-260924-AK4Z.
# Correct behavior (asserted): when the summoned menu never writes done_file
# (peer died), the script exits 1 with a stderr diagnostic within the
# OMARCHY_MENU_SELECT_TIMEOUT deadline. Pre-fix this test FAILED: the poll
# looped forever and the outer 3s timeout killed it (rc=124).
# Verifies: SW-REQ-260924-AK4Z
# MCDC SW-REQ-260924-AK4Z: caller_exits_bounded=T, peer_unresponsive=T => TRUE
#mcdc:ignore:defensive SW-REQ-260924-AK4Z: caller_exits_bounded=F, peer_unresponsive=T => FALSE -- the deadline arm exits 1 unconditionally once SECONDS passes the deadline; an unbounded wait needs that arm removed [reviewed: REVIEW-M2]
set -u
STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT
cat > "$STUB/omarchy-shell" <<'SH'
#!/bin/bash
exit 0   # summon "succeeds"; nothing ever writes the done file (menu dead)
SH
chmod +x "$STUB/omarchy-shell"
export PATH="$STUB:$PATH"
export OMARCHY_MENU_SELECT_TIMEOUT=1   # keep the witness fast; shipped default is 30s
start=$SECONDS
# Run the real script; the outer 3s timeout kills it only if the poll is
# still unbounded (the defect).
out=$(timeout 3 bin/omarchy-menu-select "Pick one" alpha beta 2>&1)
rc=$?
elapsed=$((SECONDS - start))
if [[ $rc -eq 124 ]]; then
  echo "DEFECT PRESENT: poll hung past 3s deadline (rc=124 timeout kill)"; exit 1
fi
echo "exit rc=$rc after ${elapsed}s: $out"
[[ $rc -eq 1 ]] || { echo "expected exit 1 (bounded refusal), got $rc"; exit 1; }
[[ $elapsed -lt 3 ]] || { echo "exit took ${elapsed}s -- not bounded by the 1s deadline"; exit 1; }
[[ $out == *"did not answer"* ]] || { echo "missing stderr diagnostic, got: $out"; exit 1; }
