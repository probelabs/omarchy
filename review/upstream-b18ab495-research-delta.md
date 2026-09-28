# Upstream delta research — de63134b..b18ab495 (2 commits)

Processed: 2026-09-28 (run 3). Merge: 7771c14e. Author: David Heinemeier Hansson (both).

## Commits

| Commit | Subject | Files | In audited surface? |
|---|---|---|---|
| b18ab495 | Add a no-animations mode, on by default in VMs (#13550) | 41 files: shell/Ui/* + shell/plugins/{panels,bar,notifications,osd,agents,background,polkit,services} animation gating, shell/Commons/Style.qml, bin/omarchy-{toggle-animations,hw-vm}, default/hypr/toggles/no-animations.lua, install/user/{all.sh,hardware/vm-no-animations.sh}, **default/omarchy/omarchy-menu.jsonc**, test/shell.d/toggle-test.sh | **YES** (omarchy-menu.jsonc only) |
| 97a9fce5 | Hand browser and web app launches to the running browser directly (#13530) | bin/omarchy-{cmd-browser-handoff,launch-browser,launch-webapp}, test/shell.d/{browser-handoff,launch-browser}-test.sh | no |

## In-surface change: default/omarchy-menu.jsonc (+1 row)

`trigger.toggle.animations`: `{"icon":"󰕟","label":"Animations","action":"omarchy-toggle-animations"}`
inserted between window-gaps and one-window-ratio trigger rows.

- **Parse verification (executed):** our string-aware stripJsonc scanner parses the merged
  file to 344 rows; the new entry normalizes correctly (kind=action, parent=trigger.toggle
  inferred, action bytes intact). menu-test.sh green post-merge.
- **Dispatch class:** plain exec action (not a summon) — routes through the unchanged bash
  execDetached path per SW-REQ-260928-8VJQ's grammar; identical in shape to the neighboring
  toggle rows (workspace-layout, window-gaps).
- **Summon inventory re-counted (CRS-0021/C03 freshness):** still exactly 4 summon actions
  (speedtest, disk-speedtest, image-picker+'{"source":"themes"}', wifiqr). Unchanged.

## Out-of-surface scan (menu/lock invariants)

- #13550's shell-wide animation gating reads a Hyprland toggle at runtime; the menu plugin
  (shell/plugins/menu/**) is NOT among the gated files — Menu.qml/MenuModel.js untouched.
  The lock plugin likewise untouched.
- bin/omarchy-toggle-animations: thin case-dispatch over omarchy-hyprland-toggle +
  notification; on/off swap semantics documented in its header comment (flag records
  animations OFF). Out of scope; no menu/lock contract interaction.
- #13530 browser handoff: launcher internals; menu dispatches actions as opaque argv -
  interface unchanged.
- Lock component, omarchy-menu-select, MenuModel.js/Menu.qml: untouched by both commits.

## KI hunt — no new defects

Suspicions examined and dismissed:

1. *New menu row mis-parses or corrupts neighbors* — disproved by execution: merged file
   parses to 344 rows with correct normalization (node replay against the real parser).
2. *New action accidentally matches the summon fast-path grammar* — disproved by reading:
   `omarchy-toggle-animations` does not match `omarchy-shell shell summon <id> ['<payload>']`;
   same class as the `omarchy-theme-set nord` battery case (8VJQ, stays on bash path).
3. *Summon-action inventory drift invalidating CRS-0021/C03* — disproved by re-count:
   4 summon actions, same ids as the dismissed claim's inventory.
4. *Toggle on/off inversion* (omarchy-toggle-animations swaps on/off because the flag
   records disabled-state) — reviewed: the swap is intentional and documented in the
   script header; out of audited scope regardless (bin/omarchy-toggle-* not in surface).
   Noted here only for completeness; no action.

## KI maintenance

- KI-MENU-SELECT-POLL-DEADLOCK re-executed at merge head 7771c14e: control exits rc=1
  within deadline, defect arm hangs past 3s (rc=124) — still present; evidence re-stamped
  2026-09-28T14:14:16Z. bin/omarchy-menu-select untouched by the delta.

## Verification plan

- Box: full suite + MC/DC re-measure + final proof audit --no-cache (target 0/0).
  No new in-scope test logic this delta; the parse verification above is the delta oracle.
