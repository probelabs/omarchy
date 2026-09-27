#!/opt/homebrew/bin/bash
# Reproducer for CRS-0014/C01: omarchy-menu-select done_file poll has no deadline.
# Reproduces: KI-MENU-SELECT-POLL-DEADLOCK
# Correct behavior (asserted): when the summoned menu never writes done_file
# (peer died), the script must exit within a bounded time.
# While the defect is present this FAILS: the poll loops forever.
set -u
STUB=$(mktemp -d)
trap 'rm -rf "$STUB"' EXIT

# Negative control (PoC rule 3/10): healthy peer writes the done file with an
# empty selection (user cancel path); the script MUST terminate promptly.
mkdir -p "$STUB/ctrl"
cat > "$STUB/ctrl/omarchy-shell" <<'SH'
#!/bin/bash
# summon "succeeds"; healthy menu writes the done file (cancel path, no selection)
payload="${@: -1}"
done_file=$(printf '%s' "$payload" | /usr/bin/python3 -c 'import json,sys; print(json.load(sys.stdin)["doneFile"])')
touch "$done_file"
exit 0
SH
chmod +x "$STUB/ctrl/omarchy-shell"
ctrl_out=$(PATH="$STUB/ctrl:$PATH" timeout 3 bin/omarchy-menu-select "Pick one" alpha beta 2>/dev/null)
ctrl_rc=$?
if [[ $ctrl_rc -eq 124 ]]; then
  echo "CONTROL FAILED: healthy path hung (rc=124); PoC cannot distinguish defect from design"; exit 2
fi
echo "control ok: healthy peer exits rc=$ctrl_rc within deadline"

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
