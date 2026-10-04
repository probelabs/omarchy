#!/bin/bash
# Green tripwire for the atomic_write deferrals on SYS-REQ-260912-JW2J (password
# PAM stack) and SW-REQ-260912-Y0WT (fingerprint PAM stack).
# Reproduces: KI-APPLY-LOCK-PAM-NONATOMIC-WRITE
#
# Mechanism: bin/omarchy-apply-lock writes both lock-screen PAM stacks with
#   as_root tee /etc/pam.d/omarchy-lock-password    >/dev/null <<'EOF' ...
#   as_root tee /etc/pam.d/omarchy-lock-fingerprint >/dev/null <<'EOF' ...
# tee opens the live file with O_TRUNC and rewrites it in place: there is no
# write-temp-then-rename. From the moment tee opens the file until it finishes,
# the live path holds a truncated prefix of the new stack, and an interruption
# in that window (installer killed, session lost, power cut) leaves that torn
# prefix as the stack the lock screen authenticates against.
#
# Harness: a scratch copy of the REAL helper with its absolute paths retargeted
# into a temp dir - /etc/pam.d/, the /usr/bin/fprintd-list probe, and the
# fingerprint resume-recovery destinations under /usr/lib/systemd/system-sleep/
# and /etc/systemd/system/ - and the copy is checked to differ from the product
# file by nothing else (reverse substitution must reproduce it byte for byte).
# Side-effect commands are PATH stubs: sudo (runs the command unprivileged; drops
# install's -o/-g root; records systemctl daemon-reload, which the fingerprint
# branch runs before its tee since upstream omacom/omarchy#7158; and for the tee
# under test lets exactly N bytes of the stack through and then holds, freezing
# the write window), fprintd-list (reports an enrolled finger) and omarchy-shell.
# OMARCHY_PATH points at this checkout, so the real resume hook and drop-in are
# installed. The tee that writes the file is the real one. The run is then
# SIGKILLed at the hold, which is the interruption.
#
# GREEN TRIPWIRE: pins the buggy behavior, so it PASSES while the defect is
# present. Arms 1-2 (password stack, fingerprint stack) assert that after the
# interruption the live file is the torn N-byte prefix of the new stack, the
# previous complete stack is gone, and the inode is unchanged (in-place
# rewrite). Arm 0 is the control: an uninterrupted run leaves both stacks
# complete and byte-identical to the heredocs in the product file.
#
# tripwire_mutation: write each stack to a sibling temp file and rename it over
# the live path, e.g. in bin/omarchy-apply-lock
#   as_root tee /etc/pam.d/omarchy-lock-password.tmp >/dev/null <<'EOF' ... EOF
#   as_root mv -f /etc/pam.d/omarchy-lock-password.tmp /etc/pam.d/omarchy-lock-password
# (and the same for omarchy-lock-fingerprint). The interrupted write then tears
# only the temp file, the live path keeps the previous complete stack, the
# "previous stack gone" assertions fail, and the tripwire flips red. The control
# arm is unaffected.
set -u
REPO="$(cd "$(dirname "$0")/.." && pwd)"
HELPER="$REPO/bin/omarchy-apply-lock"
[[ -f $HELPER ]] || { echo "bin/omarchy-apply-lock missing"; exit 2; }
(( EUID != 0 )) || { echo "run unprivileged: as root the helper bypasses sudo and resets PATH"; exit 2; }
TMP="$(mktemp -d)"
TMP="$(cd "$TMP" && pwd -P)"
cleanup() {
  if [[ -f $TMP/stub.pids ]]; then
    while read -r pid; do kill -KILL "$pid" 2>/dev/null; done <"$TMP/stub.pids"
  fi
  [[ -n ${TMP:-} && -d $TMP && $(basename "$TMP") == tmp.* ]] && find "$TMP" -depth -delete 2>/dev/null
}
trap cleanup EXIT
mkdir -p "$TMP/bin" "$TMP/pam.d" "$TMP/sleep" "$TMP/units"
PAMD="$TMP/pam.d"
fail=0
N=60 # bytes of the new stack that reach the live file before the interruption

# --- scratch copy of the real helper, retargeted and verified -------------------
COPY="$TMP/omarchy-apply-lock"
sed -e "s|/etc/pam\.d/|$PAMD/|g" -e "s|/usr/bin/fprintd-list|$TMP/fprintd-list|g" \
    -e "s|/usr/lib/systemd/system-sleep/|$TMP/sleep/|g" -e "s|/etc/systemd/system/|$TMP/units/|g" "$HELPER" >"$COPY"
chmod +x "$COPY"
if sed -e "s|$PAMD/|/etc/pam.d/|g" -e "s|$TMP/fprintd-list|/usr/bin/fprintd-list|g" \
       -e "s|$TMP/sleep/|/usr/lib/systemd/system-sleep/|g" -e "s|$TMP/units/|/etc/systemd/system/|g" "$COPY" | cmp -s - "$HELPER"; then
  echo "ok: scratch copy differs from bin/omarchy-apply-lock only by the retargeted absolute paths"
else
  echo "HARNESS ERROR: retargeted copy differs from the product file beyond the path substitutions"; exit 2
fi
grep -q "tee $PAMD/omarchy-lock-password" "$COPY" && grep -q "tee $PAMD/omarchy-lock-fingerprint" "$COPY" ||
  echo "note: the helper no longer writes the stacks with a direct tee to the live path"

# The new stacks exactly as the product file declares them (heredoc bodies).
heredoc() { awk -v t="$1" 'f && /^EOF$/ {exit} f {print} index($0, "tee /etc/pam.d/" t) {f=1}' "$HELPER"; }
heredoc omarchy-lock-password >"$TMP/new-password"
heredoc omarchy-lock-fingerprint >"$TMP/new-fingerprint"
[[ -s $TMP/new-password && -s $TMP/new-fingerprint ]] || { echo "HARNESS ERROR: could not read the PAM heredocs from the helper"; exit 2; }

# --- stubs ------------------------------------------------------------------------
cat >"$TMP/bin/sudo" <<EOF
#!/bin/bash
echo "sudo \$*" >>"$TMP/calls.log"
case \$1 in
  systemctl) exit 0 ;;                       # no system manager in the harness
  install)                                   # unprivileged: drop the root owner/group
    args=(); skip=0
    for a in "\${@:2}"; do
      if (( skip )); then skip=0; continue; fi
      case \$a in -o|-g) skip=1 ;; *) args+=("\$a") ;; esac
    done
    exec install "\${args[@]}" ;;
esac
if [[ \$1 == tee && -n \${PAUSE_TARGET:-} && " \$* " == *"\$PAUSE_TARGET"* ]]; then
  # Let exactly PAUSE_BYTES of the stack through to the real tee, then hold:
  # the write is frozen mid-way until the harness interrupts the run.
  { dd bs=1 count="\$PAUSE_BYTES" 2>/dev/null; : >"$TMP/paused"; echo "\$BASHPID" >>"$TMP/stub.pids"; exec sleep 300; } | "\$@"
  exit
fi
exec "\$@"
EOF
cat >"$TMP/fprintd-list" <<'EOF'
#!/bin/bash
printf 'Fingerprints for user %s on Tripwire Reader (press):\n - #0: right-index-finger\n' "${1:-}"
EOF
printf '#!/bin/bash\nexit 1\n' >"$TMP/bin/omarchy-shell"   # no running shell to report to
chmod +x "$TMP/bin/sudo" "$TMP/fprintd-list" "$TMP/bin/omarchy-shell"

OLD=$'#%PAM-1.0\n# previous complete stack (seeded by the tripwire)\nauth       include                     system-local-login\naccount    include                     system-local-login\n'
seed() { printf '%s' "$OLD" >"$PAMD/omarchy-lock-password"; printf '%s' "$OLD" >"$PAMD/omarchy-lock-fingerprint"; }
inode() { ls -i "$1" | awk '{print $1}'; }

run_helper() { # foreground, uninterrupted
  OMARCHY_INSTALL_USER=tripwire OMARCHY_PATH="$REPO" PATH="$TMP/bin:$PATH" "$COPY" >/dev/null 2>&1
}

interrupt_run() { # $1 live file basename: freeze its write after N bytes, then SIGKILL the run
  local target="$PAMD/$1" i pgid
  rm -f "$TMP/paused"
  set -m
  OMARCHY_INSTALL_USER=tripwire OMARCHY_PATH="$REPO" PAUSE_TARGET="$target" PAUSE_BYTES=$N PATH="$TMP/bin:$PATH" \
    "$COPY" >/dev/null 2>&1 &
  pgid=$!
  set +m
  for ((i = 0; i < 60; i++)); do
    [[ -e $TMP/paused && $(wc -c <"$target") -ge $N ]] && break
    sleep 0.05
  done
  if [[ -e $TMP/paused ]]; then sleep 0.1; fi # let tee flush the N bytes it was handed
  kill -KILL -- "-$pgid" 2>/dev/null
  wait "$pgid" 2>/dev/null
  [[ -e $TMP/paused ]]
}

assert_torn() { # $1 arm label, $2 live basename, $3 expected-new-stack file, $4 inode before
  local live="$PAMD/$2" got_inode
  got_inode=$(inode "$live")
  if cmp -s <(head -c "$N" "$3") "$live"; then
    echo "ok: $1 - live file is the torn ${N}-byte prefix of the new stack ($(wc -c <"$3" | tr -d ' ') bytes expected)"
  else
    echo "FAIL: $1 - live file is not the torn prefix ($(wc -c <"$live" | tr -d ' ') bytes)"; fail=1
  fi
  if [[ $(cat "$live") != "$(printf '%s' "$OLD")" ]] && ! grep -q 'previous complete stack' "$live"; then
    echo "ok: $1 - the previous complete stack is gone (no fallback left on the live path)"
  else
    echo "FAIL: $1 - the previous complete stack survived the interrupted write"; fail=1
  fi
  if [[ $got_inode == "$4" ]]; then
    echo "ok: $1 - same inode before and after (rewritten in place, no rename)"
  else
    echo "FAIL: $1 - inode changed $4 -> $got_inode (replaced by rename)"; fail=1
  fi
  echo "    torn content: $(od -An -c "$live" | tr -s ' ' | tr -d '\n' | head -c 200)"
}

echo "== arm 0: control - uninterrupted run =="
seed
run_helper
if cmp -s "$PAMD/omarchy-lock-password" "$TMP/new-password" && cmp -s "$PAMD/omarchy-lock-fingerprint" "$TMP/new-fingerprint"; then
  echo "ok: control - both stacks written complete and byte-identical to the helper's heredocs"
else
  echo "FAIL: control - stacks incomplete after an uninterrupted run"; fail=1
fi
grep -q "sudo tee $PAMD/omarchy-lock-password" "$TMP/calls.log" && grep -q "sudo tee $PAMD/omarchy-lock-fingerprint" "$TMP/calls.log" &&
  echo "ok: control - both writes went through as_root (sudo stub) to the retargeted live paths" ||
  { echo "FAIL: control - the as_root writes were not observed"; fail=1; }

echo "== arm 1: password stack (SYS-REQ-260912-JW2J) interrupted mid-write =="
seed
before=$(inode "$PAMD/omarchy-lock-password")
if interrupt_run omarchy-lock-password; then
  assert_torn "password stack" omarchy-lock-password "$TMP/new-password" "$before"
  if cmp -s <(head -c "$N" "$TMP/new-password") "$PAMD/omarchy-lock-password" && ! grep -q 'pam_unix' "$PAMD/omarchy-lock-password"; then
    echo "    impact: the torn password stack carries no pam_unix line - no password path to unlock"
  fi
else
  echo "FAIL: arm 1 - the password write never reached the hold point (helper no longer tees the live path?)"; fail=1
fi

echo "== arm 2: fingerprint stack (SW-REQ-260912-Y0WT) interrupted mid-write =="
seed
before=$(inode "$PAMD/omarchy-lock-fingerprint")
if interrupt_run omarchy-lock-fingerprint; then
  assert_torn "fingerprint stack" omarchy-lock-fingerprint "$TMP/new-fingerprint" "$before"
else
  echo "FAIL: arm 2 - the fingerprint write never reached the hold point (helper no longer tees the live path?)"; fail=1
fi

if (( fail == 0 )); then
  echo "TRIPWIRE GREEN: both lock PAM stacks are rewritten in place - an interruption leaves a torn stack on the live path and the previous stack is gone"
  exit 0
fi
echo "TRIPWIRE RED: an interrupted write no longer tears the live stack (write-temp-rename present?) or the control broke"
exit 1
