# omarchy-dogfood: a proof layer for Omarchy's menu and lock screen

This is a private fork of [omacom/omarchy](https://github.com/omacom/omarchy), maintained by
[ProbeLabs](https://github.com/probelabs). It does not change how Omarchy works. On top of an unchanged copy
of upstream's code it adds a **proof layer**: written requirements for the menu and lock-screen components,
tests that check the code against those requirements, and an audit record of the result. We use it to check
upstream issues and pull requests against what the code is supposed to do.

The proof layer lives in `proof/`, `specs/`, `test/`, `pocs/`, `review/`, `proof.yaml` and this file. Outside
those paths, the only differences from upstream are comments (such as `// Implements: <requirement>` markers), blank
lines, QML `id:` attributes and one `.gitignore` line. `review/check-clean-product-diff.py e332dc97 HEAD` checks this.

Upstream's own `README.md` is unchanged. GitHub shows this file instead because it is in `.github/`.

## Branches

| Branch | What it is | Who changes it |
|---|---|---|
| `quattro` | An exact copy of upstream's `quattro` branch. It has no proof layer. | Fast-forward from upstream only. Nobody commits to it. |
| `quattro-proof` (default) | Upstream code plus the proof layer. | We do, through the sync described below. |
| `pr/<number>` | A mirror of one upstream pull request: `quattro-proof`, plus the PR's code change, plus any proof work that the PR needs (for example, a changed requirement or a new test). | We do. Rebuilt when `quattro-proof` or the PR moves. |
| `report/<id>` | A script that reproduces one reported upstream issue. | We do. |
| `prep/*` | Outbox: changes we plan to propose upstream. | We prepare them here. Only the fork owner submits them upstream, from a public fork. Nothing is pushed upstream from this repository. |
| `archive/<date>/<branch>` | The old tip of a branch, saved before that branch was rebuilt. | Never changed or deleted. |

Audit results are stored as git notes next to the commits they describe (`refs/notes/proof/runs`, `packages`,
`reviews` and `report-validations`). Fetch them with
`git fetch origin 'refs/notes/proof/*:refs/notes/proof/*'`.

## Current state

- **Upstream code covered:** `e332dc97` (upstream `quattro`, 28 Sep 2026).
- **Upstream is ahead by 3 commits** (`quattro` at `8b4eae66`). None of them touch the menu or the lock screen.
- **Latest audit of this branch:** 0 errors, 2 warnings, 1 note.
  - Both warnings are known, tracked debt, not new failures. Some required checks (obligations) are
    deferred: for example, missing timeouts around external commands and non-atomic PAM file writes.
    Others are accepted as known issues, each guarded by a test that turns red when the behaviour changes.
  - The note: 18 functions are still waiting for property-based tests.
  - The run record is the `refs/notes/proof/runs` note on this branch's tip commit.
- **Portal:** [portal.reqproof.com/projects/omarchy](https://portal.reqproof.com/projects/omarchy)
  (access is currently private).

### Upstream issues found or checked

Each issue reproduces on upstream `e332dc97` unless stated otherwise, and has a known-issue record in
`proof/` and a reproducer in `test/reports/`.

| Upstream | Problem | Status |
|---|---|---|
| [#13250](https://github.com/omacom/omarchy/issues/13250) | A menu label that contains `, ]` or `, }` is silently changed. | Reproduces. Fix proposed in [#13255](https://github.com/omacom/omarchy/pull/13255). |
| [#13492](https://github.com/omacom/omarchy/issues/13492) | A menu file whose top level is an array shows extra rows named `0`, `1`, … | Reproduces. Fix proposed in [#13511](https://github.com/omacom/omarchy/pull/13511). |
| [#13493](https://github.com/omacom/omarchy/issues/13493) | A `//` comment after a value on the same line empties the whole menu. | Reproduces. [#13512](https://github.com/omacom/omarchy/pull/13512) fixes it, but a trailing comma followed by a comment line then empties the menu. The three fixes above are being combined into one PR that avoids this. |
| [#10601](https://github.com/omacom/omarchy/issues/10601) | Opening the menu takes time quadratic in its row count (232 layout passes and 27,027 row visits for 231 rows). | Reproduces. [#10631](https://github.com/omacom/omarchy/pull/10631) does not change the counts. |
| [#9057](https://github.com/omacom/omarchy/issues/9057) | Opening a picker menu again before the first one is answered leaves the first caller waiting forever. | Reproduces. [#9056](https://github.com/omacom/omarchy/pull/9056) fixes it; the `pr/9056` mirror checks this. |
| [#13012](https://github.com/omacom/omarchy/pull/13012) (PR) | Restores the selected row when you go back from a submenu. | The PR has one regression. Search, open a deeper submenu from the results, then go back: the cursor lands on an unrelated row (`Learn`). Reproducer: `pocs/pr13012-back-from-search.js` on `pr/13012`. |

[#10340](https://github.com/omacom/omarchy/issues/10340) (search ranks a menu action above an installed app) was
checked too. The ranking follows the documented rule, so it is a feature request rather than a defect.

## How to reproduce

You need `bash`, Node.js 18 or later and `perl`. The #10601 reproducer also needs the Qt 6 `qml` runtime
(`qt6-declarative`). Some menu tests need Linux (`flock`, `/proc`, GNU `find`); they print `SKIP` elsewhere.

```sh
git clone https://github.com/probelabs/omarchy-dogfood && cd omarchy-dogfood   # default branch: quattro-proof

# Menu test suites
bash test/shell.d/menu-test.sh
node --test test/node/menumodel-replay.test.mjs

# Issue reproducers (menu-reports). This suite passes while the defects exist:
# each reproducer is expected to fail, and the test goes red once upstream fixes it.
node --test test/node/report-reproducers.test.mjs

# One reproducer at a time. Exit 1 = defect reproduced, 0 = correct, 2 = a required tool is missing.
sh test/reports/report-cmulr8l6h0i461gw40vqqv64c.sh   # #13250
sh test/reports/report-cmulr8j7z0hy31gw4pne8v6u4.sh   # #13492
sh test/reports/report-cmulr8j7w0hy01gw4menggvbx.sh   # #13493
sh test/reports/report-cmulr8ysi0jwr1gw4fjmt9khq.sh   # #10601 (needs Qt 6 qml)
sh test/reports/report-cmulr95nw0kqr1gw46i7f50xj.sh   # #9057
sh test/reports/report-cmulr908f0k131gw4hy0pcx08.sh   # #10340 (exit 0: not a defect)
```

The full suite list, including the other menu and lock-screen tests, is under `tests:` in `proof.yaml`.
The full audit uses the ReqProof `proof` tool (`proof audit`). It runs every suite
and measures coverage, so it takes several minutes.

## How syncing with upstream works

1. Fast-forward `quattro` to upstream `quattro`.
2. Merge `quattro` into `quattro-proof`. Upstream code always wins; the proof layer adapts to it.
3. Run the audit on `quattro-proof`. Fix whatever it reports (requirements, trace links, tests) until it is
   back to 0 errors.
4. Publish the run record (a git note on the new tip) and rebuild the `pr/*` mirrors on the new tip.
