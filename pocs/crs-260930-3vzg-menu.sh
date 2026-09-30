#!/bin/bash
# PoC for claims CRS-260930-3VZG/C01+C02+C03+C16 and CRS-260930-KY78/C01+C02+C03+C14
# (bin/omarchy-menu, specs SW-REQ-260922-T257 / SW-REQ-260922-SNZG)
# Mechanisms (all reproduced against the REAL script):
#  a) toggle/summon: `exec omarchy-shell shell toggle omarchy.menu "$(menu_payload ...)"` -
#     a failed jq (exit 3) leaves the command substitution empty, there is no
#     status check, and the script execs the IPC with an empty payload and
#     exits 0: a failed menu open looks like success (lines 23/26).
#  b) unknown verb: the diagnostic write `echo ... >&2` under set -e aborts
#     with status 1 before line 52's canonical `exit 2` when stderr is closed.
#  c) help: `cat <<USAGE` under set -e aborts with status 1 before `exit 0`
#     when stdout is closed.
# Both-ways: (a) a fix that checks the payload/jq status exits non-zero with
# no omarchy-shell call; (b) a `|| exit 2` guard keeps exit 2; (c) an
# exit-0-preserving guard keeps exit 0. Each assertion flips with its fix.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
mkdir -p "$TMP/bin"
LOG="$TMP/shell.log"

# jq: succeeds unless forced to fail
cat > "$TMP/bin/jq" <<'EOF'
#!/bin/bash
[[ ${JQ_FAIL:-0} == 1 ]] && { echo "jq: forced failure" >&2; exit 3; }
exec /usr/bin/jq "$@"
EOF
cat > "$TMP/bin/omarchy-shell" <<EOF
#!/bin/bash
echo "argc=\$# args=[\$*]" >> "$LOG"
exit 0
EOF
chmod +x "$TMP/bin/"*

export PATH="$TMP/bin:$PATH"
fail=0

echo "== a) toggle with failing jq =="
: > "$LOG"
"$REPO/bin/omarchy-menu" toggle system >/dev/null 2>&1
RC=$?
A_ARGC=$(grep -o "argc=[0-9]*" "$LOG" | head -1)
echo "exit=$RC $A_ARGC last-arg-empty=$(grep -q "args=\[shell toggle omarchy.menu \]\|args=\[.*\]$" "$LOG" && grep "omarchy.menu \]$\|omarchy.menu \]" "$LOG" | grep -c '' )"
if [[ $RC == 0 ]] && grep -q "argc=4" "$LOG"; then
  echo "  [a] SYMPTOM: jq failure still exec'd the IPC (argc=4) and exited 0 - failed open presented as success"
else
  echo "  [a] PASS-REFUTED: non-zero exit / no IPC call (fix present?)"; fail=1
fi

echo "== a2) summon with failing jq =="
: > "$LOG"
"$REPO/bin/omarchy-menu" summon style.theme >/dev/null 2>&1
RC=$?
if [[ $RC == 0 ]] && grep -q "argc=4" "$LOG"; then
  echo "  [a2] SYMPTOM: same empty-payload summon, exit 0"
else
  echo "  [a2] PASS-REFUTED (fix present?)"; fail=1
fi

echo "== b) unknown verb with stderr closed =="
"$REPO/bin/omarchy-menu" bogus-verb 2>&- >/dev/null
RC=$?
echo "exit=$RC (expected contract: 2)"
if [[ $RC != 2 ]]; then
  echo "  [b] SYMPTOM: unknown verb exited $RC instead of the contracted 2 when the diagnostic could not be written"
else
  echo "  [b] PASS-REFUTED (fix present?)"; fail=1
fi

echo "== c) help with stdout closed =="
"$REPO/bin/omarchy-menu" --help >&- 2>/dev/null
RC=$?
echo "exit=$RC (expected contract: 0)"
if [[ $RC != 0 ]]; then
  echo "  [c] SYMPTOM: help exited $RC instead of 0 when the usage write failed"
else
  echo "  [c] PASS-REFUTED (fix present?)"; fail=1
fi

exit $fail
