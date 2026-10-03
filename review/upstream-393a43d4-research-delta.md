# Upstream delta research — a85e29ab..393a43d4 (1 commit)

Processed: 2026-10-03. Merge: `Merge upstream quattro 393a43d4 into quattro-proof`.

| Commit | Subject | Files | In the audited surface? |
|---|---|---|---|
| 393a43d4 | Pin root= before the packages that can drop it (#6951) | `bin/omarchy-upgrade-to-quattro`, `test/shell.d/upgrade-to-quattro-test.sh` | no |

- Neither file is in the verification scope. No menu or lock file changed.
- `bin/omarchy-upgrade-to-quattro` still calls `configure_lock_authentication` as before; the change only moves the
  `root=` pin earlier in the upgrade. The lock plugin and the lock binaries are byte-identical.
- No requirement, trace, surface or known issue names either file. `proof trace suspect`: 0 links after the merge.
- The audit's test commands do not run `upgrade-to-quattro-test.sh`.
