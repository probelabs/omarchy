#!/bin/bash
# Anchored evidence for Menu.qml mechanism claims (fixed-string greps):
#   PRV1 providerProc commits with no exit-code check
#   PRV2 providersLoaded set before the provider proves itself
#   PRV3 apps provider marked loaded unconditionally
#   PRV4 takenIds batch-local (static collisions not nudged)
#   FOLD1 foldedListHeight can return a height above the available cap
#   REV1 uninstantiated delegate aborts the peek adjustment
#   DET1 detail gate uses truthy (untrimmed) filterText
#   DME1 dmenu geometry via bare Number() (NaN possible)
#   SRT1 search sorts localeCompare, apps sort code-unit <
#   FV1  only the user FileView has onLoadFailed (default has none)
#   FV2  user-file failure wipes the last good items
#   PIM1 pendingInitialMenu is written but never read
# Each assertion greps the LIVE shell/plugins/menu/Menu.qml; a fix flips the
# corresponding assertion and this script exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
F="$REPO/shell/plugins/menu/Menu.qml"
[[ -f $F ]] || { echo "Menu.qml missing"; exit 2; }
fail=0

yes_no() { if [[ $3 == 0 ]]; then echo "  [$1] PRESENT: $2"; else echo "  [$1] ABSENT: $2 (fix present?)"; fail=1; fi; }

grep -qF 'providerProc.collected' "$F"
PRV1=$(sed -n '/id: providerProc/,/^  Process {/p' "$F" | grep -cF 'exitCode'); [[ $PRV1 == 0 ]]; yes_no PRV1 "providerProc.onExited has no exit-code check before committing" $?

grep -qF 'root.providersLoaded[id] = true' "$F"; yes_no PRV2 "providersLoaded committed before the process proves itself" $?
sed -n '/function startProviderForMenu/,/^  }/p' "$F" | grep -qF 'entry.provider === "apps"'; yes_no PRV3 "apps provider marked loaded unconditionally (no AppLibrary check)" $?
grep -qF 'var takenIds = ({})' "$F"; yes_no PRV4 "takenIds is batch-local (static-menu collisions not nudged)" $?

grep -qF 'return totals[full - 1] + root.rowSpacing + peek' "$F"; yes_no FOLD1 "foldedListHeight returns totals[k]+spacing+peek, which the full==1 path lets exceed available" $?

grep -qF 'if (!item) return' "$F"; yes_no REV1 "uninstantiated delegate aborts the peek adjustment" $?

grep -qF 'root.filterText || root.dmenuActive' "$F"; yes_no DET1 "detail gate uses truthy (untrimmed) filterText" $?

grep -qF 'Number(payload.width || 300)' "$F"; yes_no DME1 "dmenu width via bare Number() (NaN possible)" $?

grep -qF 'localeCompare' "$F"; S1=$?
grep -qF 'aLabel < bLabel' "$F"; S2=$?
if [[ $S1 == 0 && $S2 == 0 ]]; then st=0; else st=1; fi
yes_no SRT1 "search sorts localeCompare while apps sort uses code-unit <" $st

N=$(grep -cF 'onLoadFailed' "$F")
if [[ $N == 1 ]] && grep -qF 'id: defaultMenuFile' "$F"; then st=0; else st=1; fi
yes_no FV1 "only the user FileView has onLoadFailed; default file has none" $st

grep -qF 'onLoadFailed: { root.userMenuItems = [];' "$F"; yes_no FV2 "user-file failure wipes the last good items" $?

N=$(grep -cF 'pendingInitialMenu' "$F")
if [[ $N == 2 ]]; then st=0; else st=1; fi
yes_no PIM1 "pendingInitialMenu appears exactly twice (decl + write), never read" $st

if (( fail )); then
  echo "ANCHORED-EVIDENCE: a mechanism no longer matches - claims possibly fixed"
  exit 1
fi
echo "ANCHORED-EVIDENCE: all 12 Menu.qml mechanisms match the live code"
exit 0
