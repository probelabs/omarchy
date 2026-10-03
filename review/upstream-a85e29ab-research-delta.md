# Upstream delta research — 821ae589..a85e29ab (19 commits)

Processed: 2026-10-03. Merge: `Merge upstream quattro a85e29ab into quattro-proof`.
Upstream merges in the range: #11925 (third-party plugin `__sourceDir`), #13296 (OpenClaw self-updating
install) and #14049 (agent usage: Codex limits, Claude counting, fallback).

## Files and the audited surface

31 files: `bin/omarchy-agent-usage-{claude,codex,fireworks,grok}`, `bin/omarchy-default-agent`,
`bin/omarchy-{install-ai-openclaw,install-openclaw-cli,openclaw-onboard,remove-ai-openclaw}`,
`manual/17-ai.md`, `migrations/1790397381.sh`, `shell/plugins/agents/{Agent,Main,Panel}.qml`,
`shell/plugins/agents/README.md`, `shell/shell.qml` and 15 tests under `test/shell.d/`
(agent usage, agents panel, default agent, OpenClaw, plugins, remove-ai).

None of them is in the verification scope (`proof scope`: lock and menu binaries, `omarchy-menu.jsonc`,
`shell/plugins/{lock,menu}/**`, the bdiff/junit/node/qml-lock tests and the `*lock*`/`*menu*` shell tests).
`default/omarchy/omarchy-menu.jsonc`, `shell/plugins/menu/**`, `shell/plugins/lock/**` and every
`bin/omarchy-menu*` / `bin/omarchy-*lock*` file are byte-identical across the merge. None of the new tests
is run by the audit's test commands (they run named lock and `menu-*` suites only).

## Contact points checked

- **`shell/shell.qml` (#11925).** `publicPluginManifest()` now keeps `__sourceDir` on the copy it gives a
  third-party plugin; only `__isFirstParty` and `__hostCapabilities` are withheld. A first-party manifest
  (the menu and lock plugins) is returned before the copy is made, so their behaviour is unchanged.
  The change adds one line at line 322, so every later line moves by one. The proof layer cites two
  later lines by number: the shell IPC `summon` handler (was `shell.qml:1840`, now `:1841`) and
  `function summon(pluginId, payloadJson)` (was `:1143`, now `:1144`). Both citations are updated in
  `proof/surfaces/threat-surface.yaml` and in SW-REQ-260928-8VJQ's domain-obligation rationale. The
  convergence argument they support is unchanged: both dispatch paths still end in the same
  `shell.summon`.
- **`bin/omarchy-default-agent`.** Comment-only change. The menu's `setup.default.agent.*` rows call it as
  an opaque exec action with an agent name; the arguments and the `checked` query are unchanged.
- **OpenClaw install/remove scripts and the migration.** Not reached from the menu or the lock.
- **Agents panel (`shell/plugins/agents/*`).** A separate plugin; it does not import or call the menu or
  lock plugins.

## Requirements, traces and known issues

- No skeleton adds or retires: the delta adds no menu or lock behaviour.
- `proof trace suspect`: no suspect links after the merge. No annotated file changed.
- `proof validate` and `proof lint`: clean.
- KI sweep: no known issue names a changed file. No new suspicion survived reading the delta; the
  only shared code (`shell.qml`) changes a third-party path the audited plugins never take.
