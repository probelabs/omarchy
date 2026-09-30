#!/bin/bash
# PoC for claims CRS-260930-G166/C07 + CRS-260930-G166/C09 (spec SW-REQ-260912-EKJP, trusted_path_only)
# Mechanism: the EUID==0 PATH pin (bin/omarchy-apply-lock:15) replaces PATH
# but not the environment: exported bash functions (BASH_FUNC_grep%%,
# BASH_FUNC_command_not_found_handle%%, ...) survive and function lookup
# precedes PATH in bash. A caller-supplied grep runs instead of /usr/bin/grep
# inside the fingerprint gate (line 48), and a command_not_found_handle that
# returns 0 makes `if omarchy-shell lock status` (line 62) TRUE when the
# binary is absent (chroot install). Caller-supplied code executes as root -
# the hostile-PATH case the PATH pin exists to refuse is reachable anyway.
# Both-ways: runs the script's LIVE decision expressions (extracted verbatim)
# under the hostile environment. A hijack marker proves caller code executed.
# A fix that unsets exported functions / uses `command` makes the markers
# absent and this exits 1.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT
MARK="$TMP/HIJACK-MARKER"

# hostile functions, exactly what a malicious caller's imported BASH_FUNC_*
# variables become in the shell's function table (bash imports them as
# functions before the first command runs, so defining them here models the
# inherited state faithfully)
HIJACK_GREP='grep() { touch '"$MARK"'; /usr/bin/grep "$@"; }'
HANDLER='command_not_found_handle() { touch '"$MARK"'; return 0; }'

# gate condition (line 48) with the absolute path pointed at the stub
COND="$(sed -n '48p' "$REPO/bin/omarchy-apply-lock" | sed "s#/usr/bin/fprintd-list#$TMP/fprintd-list#; s/; *then\$//")"
rm -f "$MARK"
( export PATH="$TMP:/usr/bin:/bin"; eval "$HIJACK_GREP"; target_user="alice"; eval "$COND" >/dev/null 2>&1 )
if [[ -f $MARK ]]; then
  echo "vector grep: imported grep() executed inside the fingerprint gate instead of the pinned /usr/bin/grep"
  V1=0
else
  echo "vector grep: pinned grep used (fix present?)"
  V1=1
fi

# omarchy-shell-missing branch (line 62) with the imported handler
LINE62="$(sed -n '62p' "$REPO/bin/omarchy-apply-lock" | sed 's/^if //; s/; *then$//')"
rm -f "$MARK" "$MARK.62"
( export PATH="/usr/bin:/bin"   # pinned PATH without omarchy-shell
  eval "$HANDLER"
  eval "$LINE62" >/dev/null 2>&1
  [[ $? == 0 ]] && touch "$MARK.62" )
if [[ -f $MARK.62 && -f $MARK ]]; then
  echo "vector cnfh: imported command_not_found_handle executed in place of the missing omarchy-shell and returned 0 - the if-branch ran with no binary present"
  V2=0
else
  echo "vector cnfh: missing binary failed closed (fix present?)"
  V2=1
fi

if (( V1 == 0 || V2 == 0 )); then
  echo "SYMPTOM: exported bash functions execute inside the root helper's decision points despite the trusted-PATH replacement (caller code runs as root - defect present)"
  exit 0
fi
echo "PASS-REFUTED: exported functions no longer execute - defect fixed"
exit 1
