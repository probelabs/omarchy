#!/bin/bash
# PoC for claim CRS-260930-K02D/C02 (spec SW-REQ-260922-Q6ZS)
# Mechanism: bin/omarchy-menu-select:91 executes
# `omarchy-shell shell summon omarchy.menu "$payload"` with no timeout
# wrapper. If omarchy-shell never returns (IPC hang), the caller blocks
# inside the external binary forever - the external-call leg of the
# bounded-wait obligation, separate from the done_file poll
# (KI-MENU-SELECT-POLL-DEADLOCK covers the poll side only).
# Both-ways: stubs omarchy-shell to hang; asserts the script is still inside
# the summon when an external 2s timeout kills it (exit 124, no diagnostic
# of its own - exit 0 = defect present). With a fix that bounds the summon
# internally (bound < 2s), the script exits non-zero with its own error
# before the external kill and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
cat > "$TMP/bin/omarchy-shell" <<'EOF'
#!/bin/bash
# IPC hang: the summon never returns
sleep 30
EOF
chmod +x "$TMP/bin/omarchy-shell"

OUT="$(PATH="$TMP/bin:$PATH" timeout 2 "$REPO/bin/omarchy-menu-select" Pick one alpha beta 2>"$TMP/err")"
RC=$?

echo "exit=$RC stderr=[$(cat "$TMP/err")]"

if [[ $RC == 124 ]]; then
  echo "SYMPTOM: script was still blocked inside the unbounded summon when the external timeout killed it (defect present)"
  exit 0
elif [[ $RC != 0 && -s "$TMP/err" ]]; then
  echo "PASS-REFUTED: script aborted the hung summon on its own with a diagnostic - defect fixed"
  exit 1
else
  echo "UNEXPECTED: rc=$RC"; exit 2
fi
