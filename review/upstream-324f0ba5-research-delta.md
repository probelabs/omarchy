# Research delta — upstream/quattro 3faafba2 → 324f0ba5 (sync absorbs 235 commits since 31bd80da)

Date: 2026-09-28 · Agent: upstream-watch refresh · Branch: fix/jsonc-trailing-comma-in-strings @ merge 7cd0ec15

## Watched delta (the trigger): 1 commit

**324f0ba5 — "Add SSH Agent (gcr-ssh-agent) as an optional service install" (#9399)**, Carlos Sánchez, co-auth DHH + Claude.

| File | Scope | Assessment |
|---|---|---|
| `bin/omarchy-setup-security-ssh-agent` (new, 17 L) | out (not `*lock*`/`*menu*`) | Enables `gcr-ssh-agent.socket` --user, writes environment.d. Skimmed: no interaction with menu/lock surface beyond the menu entry that launches it. |
| `bin/omarchy-remove-service-ssh-agent` (new, 16 L) | out | Disables socket, deletes environment.d file BEFORE disable (order matters, commit msg documents why), clears SSH_AUTH_SOCK only when it points at gcr. Careful implementation. |
| `default/omarchy/omarchy-menu.jsonc` (+2) | **IN audited surface** | Adds `setup.security.ssh-agent` (`when: ! systemctl --user -q is-enabled gcr-ssh-agent.socket`) and `remove.service.ssh-agent` (positive form). |
| `test/shell.d/ssh-agent-service-remove-test.sh` (new) | out (not `*menu*`/`*lock*`-test) | Remove-path test; not in verification_scope. |

### Menu-entry mechanics verified

- `!`-prefixed `when` guards are pre-existing grammar (2 occurrences at 3faafba2, 3 now); `guardLine` wraps the expression in `if { …; }` so negation needs no new semantics. No spec change warranted.
- Replay parse of the new shipped config through our scanner: **343 entries, both ssh-agent keys present, zero field-level diffs** vs upstream's own `stripJsonc` (outputs differ only in comment-line whitespace handling, which is our documented inline-comment fix C8W1 behavior).
- New actions dispatch through `omarchy-launch-floating-terminal-with-presentation` — an existing, spec-covered action class. No new action semantics.

## Absorbed sync backlog in the audited surface (234 commits, 31bd80da..3faafba2)

State file init (2026-09-28 09:35) recorded 3faafba2 as processed baseline, so these are covered here as sync context rather than as the watched delta:

1. **`summonAction` (MenuModel.js +11, Menu.qml execAction +3)** — in-process fast path for `omarchy-shell shell summon <id> ['<payload>']` actions (c231097d). Edge battery 10/10 as expected: tight regex, anything exotic (semicolons, unbalanced quotes, extra args) falls back to the bash path. Injection surface: none new — the regex admits `[A-Za-z0-9._-]` ids and single-quoted payloads without embedded quotes only.
2. **Menu.qml PanelWindow → OverlayWindow** (48de7823) — surface stays mapped between opens; `visible`→`shown` semantics updated consistently (freezeCardTop, onShownChanged reset). State-reset discipline preserved.
3. **Lock: video wallpaper poster pipeline** (ab18321b/b423f499/387fcf59) — new `videoPosterPath`, `backgroundSignature` (mtime:size) so in-place wallpaper overwrite bumps the cache version; pre-decode `Variants` Image per screen; `readlinkProc` becomes a bash readlink+stat wrapper; new `poster.sh` (flock-serialized ffmpegthumbnailer cache, graceful non-zero → empty poster fallback). Failure paths all degrade to still-image lock.
4. **`omarchy-update` / `omarchy-update-stay-awake` rework** (update-security-foundation merges, ~700 L) — production code out of audited scope, but exercised by in-scope `update-lock-test.sh`, which upstream rewrote onto the sudo-boundary fixture. Our MC/DC witness blocks were re-anchored onto the fixture layout in the merge resolution (spy now execs a preserved sed-patched copy of `omarchy-update-lock`, keeping test lock-name isolation).
5. **`bin/omarchy-menu-images --print-rows`** (+14) — additive flag, early-exit printf; no change to existing flag semantics.

## KI hunt (step 6a) — results

- **No new defects found** in the watched delta or the absorbed surface changes. Hunt angles executed: summonAction edge battery (10/10), guard-grammar check for `! systemctl` entries, poster.sh race/failure review (flock timeout → exit 1 → graceful; mv -f atomic; find -delete only prunes other keys), readlinkProc empty-output path (degrades to backgroundPath="" as before), OverlayWindow state reset.
- **KI-MENU-SELECT-POLL-DEADLOCK re-run at merged head: STILL REPRODUCES** (control ok, poll hung past 3s deadline, rc=124). `bin/omarchy-menu-select` untouched upstream. Evidence refreshed.
- **Upstream still carries all 3 reported JSONC defects** (verified against stock `upstream/quattro` MenuModel.js, not our branch):
  - #13250: `mv f{.bak,}` → `mv f{.bak}` corruption reproduces verbatim.
  - #13493: inline `//` tail → JSON.parse failure reproduces.
  - #13492: top-level array root still accepted (phantom-row risk intact).
  - PRs #13255/#13511/#13512 all still OPEN, no upstream equivalent merged → keep our fixes, no annotation retirement.

## Conclusion

The watched delta is additive config + out-of-scope tooling; the only audited-surface touch is two menu entries using pre-existing guard/action grammar. The absorbed backlog changes lock internals and menu windowing but does not invalidate any existing requirement semantics (verified at parse/guard/trace level here; dynamic verification lands in the box phase).
