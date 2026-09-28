# Upstream delta research — 324f0ba5..de63134b (21 commits)

Processed: 2026-09-28 (run 2). Merge: 228a9073. Authors: David Heinemeier Hansson, Erik Melton, Afonso Oliveira.

## Commit groups

| Group | Commits | Files | In audited surface? |
|---|---|---|---|
| Notification collapse (#13522) | de63134b | shell/plugins/notifications/{Service.qml,NotificationLogic.js}, notifications-test.sh | no |
| Terminal launcher pid from Lua (#13521) | f8146395 | **bin/omarchy-menu-keybindings**, **test/shell.d/keybindings-menu-test.sh**, default/hypr/{helpers,bindings/applications}.lua, bin/omarchy-{cmd-terminal-cwd,launch-terminal}, terminal-cwd-test.sh | **YES** |
| Default browser from mimeapps.list (#13520) | fa729f13 | bin/omarchy-{cmd-default-browser,launch-browser,launch-webapp}, default-browser-lookup-test.sh | no |
| Fingerprint template cleanup (#13049) | 8273b6c2 merge + 5 | bin/omarchy-remove-security-fingerprint, security-fingerprint-remove-test.sh | no (lock-adjacent, reviewed below) |
| sshd firewall cleanup (#13048) | 091d65fc merge + 4 | bin/omarchy-remove-security-sshd, remove-security-sshd-firewall-test.sh | no |
| YT6801 DKMS→driver replace (#9682) | b2ffea57 merge + 5 | install/hardware/fix-yt6801-ethernet-adapter.sh, yt6801-driver-test.sh, install/omarchy-other.packages, migrations/1788279117.sh | no |
| Hunk theme nudge (#13518) | 4ba4a532 | bin/omarchy-{theme-set,theme-set-hunk} | no (menu-adjacent, reviewed below) |
| pkg-drop / keybindings misc | (in above) | bin/omarchy-pkg-drop, pkg-drop-test.sh, test/cli | no |

## In-surface change: bin/omarchy-menu-keybindings (f8146395)

Two hunks:

1. **Dispatch chain extension** (sandboxed Lua `hl.bind`, lines 213-215 merged): new
   `elseif o and o.bind_commands and o.bind_commands[bind_dispatcher]` branch resolving
   kind="exec", arg=mapped command. Fires only for dispatchers that are neither
   `__omarchy_dispatcher` tables nor non-empty strings — i.e. Lua **function** binders
   (Hyprland reports these only as `__lua`).
2. **Cache key v13→v14** (line 538): invalidates stale records; correct because output
   semantics changed for function binds (empty kind/arg → exec row).

Lua side (default/hypr/helpers.lua): `o.bind_commands = {}`; `o.launch_terminal()`
creates the launcher closure, registers `o.bind_commands[launch] = "omarchy-launch-terminal"`,
returns it; applications.lua now binds SUPER+RETURN via `o.launch_terminal()`.

### Interaction with owned specs

- **SW-REQ-260922-0W96** ("__lua binds shown with resolved keys and remain dispatchable"):
  the delta STRENGTHENS satisfaction. Pre-delta, a function dispatcher fell through the
  chain with kind="" (rendered but not dispatchable); post-delta, registered function
  binds dispatch as exec rows. Spec prose remains accurate; header Implements (line 8)
  and trace citation (:8) unmoved. Upstream's new test (keybindings-menu-test.sh tail)
  witnesses exactly the 0W96 T,T row scenario with the new mechanism.
- **SW-REQ-260922-9DMS** (keycode→symbol resolution): untouched; cited region
  (parse_keycodes, lines 13-46) precedes the insertion point.
- Menu plugin (MenuModel.js/Menu.qml), omarchy-menu.jsonc, lock component: untouched.

### KI hunt (in-surface) — no new defects

Suspicions examined and dismissed:

1. *Unregistered function binds render with empty kind/arg* — pre-existing fall-through,
   unchanged by the delta; the delta shrinks the affected set (registered functions now
   resolve). Cosmetic, upstream-known pattern; not a new defect.
2. *Stale cache serving v13 semantics* — dismissed: cache-key version bumped to v14,
   verified by reading keybindings_cache_key.
3. *`o` scope inside the sandboxed hl.bind closure* — dismissed by upstream's new test
   exercising exactly this path (queued for box execution this campaign); Lua `t[nil]`
   read semantics make the chain nil-safe for absent/unregistered dispatchers.
4. *bind_commands value type confusion* — only writable via o.launch_terminal (string
   value); a user registering a non-string is config error, table.concat error is
   attributable and local. Not a shipped-config defect.

## Out-of-surface interaction scan (menu/lock invariants)

- **Fingerprint removal** (bin/omarchy-remove-security-fingerprint): deletes saved
  fingerprint templates for the invoking user on package removal. Lock's fingerprint
  *auth* path (lock-fingerprint-indicator/blank-fingerprint tests) does not depend on
  template persistence semantics changed here; removal-time cleanup is disjoint from
  lock runtime. No spec assumption invalidated.
- **theme-set / theme-set-hunk**: menu action `omarchy-theme-set` is exec'd by the menu
  as an opaque subprocess (WC89/8VJQ surface); internal hunk nudge does not change the
  argv contract. No interaction.
- **Notifications collapse**: separate quickshell plugin; menu/lock shells untouched.
- **Launchers**: menu dispatches actions via execDetached by string; launcher internals
  changed, interfaces (argv) unchanged.
- **omarchy-menu-select deadlock surface** (KI-MENU-SELECT-POLL-DEADLOCK):
  bin/omarchy-menu-select untouched by this delta; reproducer re-run below.

## KI maintenance

- KI-MENU-SELECT-POLL-DEADLOCK reproducer re-executed at merged head 228a9073:
  control ok, defect arm hangs past 3s deadline (rc=124) — still present, evidence refreshed.
- Upstream PRs #13255/#13511/#13512, issues #13250/#13492/#13493: all still OPEN (gh, 2026-09-28).

## Verification plan for this delta

- Box: keybindings-menu-test.sh (has `lua` dependency, mac-skipped) + full suite,
  mcdc re-measure (0W96/9DMS rows + all), final proof audit --no-cache, target 0/0.
- Trace review re-record for 0W96 (mechanism extension; citations unchanged).
