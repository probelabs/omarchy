# omarchy: a proof layer for Omarchy's menu and lock screen

This is [probelabs/omarchy](https://github.com/probelabs/omarchy), a public fork of
[omacom/omarchy](https://github.com/omacom/omarchy) maintained by [ProbeLabs](https://github.com/probelabs). It does not change how Omarchy works. On top of an unchanged copy
of upstream's code it adds a **proof layer**: written requirements for the menu and lock-screen components,
tests that check the code against those requirements, and an audit record of the result. We use it to check
upstream issues and pull requests against what the code is supposed to do.

The proof layer lives in `proof/`, `specs/`, `test/`, `pocs/`, `review/`, `docs/proof/`, `proof.yaml` and this file.
Outside those paths, the only differences from upstream are comments (such as `// Implements: <requirement>`
markers), blank lines, QML `id:` attributes and one `.gitignore` line.
`python3 review/check-clean-product-diff.py 393a43d HEAD` checks this.

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

- **Upstream code covered:** `393a43d` (upstream `quattro` tip, merged into `quattro-proof`).
- **Latest audit of this branch:** 0 errors, 0 warnings (ReqProof engine `8cac9cf`, full run without cache).
  - The remaining notes are advisory: functions still waiting for property-based tests, and lint suggestions.
  - Test results are part of the run: every suite in `proof.yaml` writes one JUnit report
    (`test/junit/junit.sh`), and the audit links each test case to the requirements it verifies. No test fails.
  - Deferred obligations are no longer open debt: each one (missing timeouts around `hyprctl`, `xkbcli` and the
    menu guard batch; the non-atomic PAM stack write) is a known issue with a test that pins the current
    behaviour and turns red when it is fixed.
  - The run record is the `refs/notes/proof/runs` note on this branch's tip commit, on this repository.
- **Review mode:** advisory. We audit upstream pull requests; only omacom maintainers decide on them.
- **Portal:** [portal.reqproof.com/projects/omarchy](https://portal.reqproof.com/projects/omarchy) (public, no
  login needed).

### Upstream issues found or checked

Each issue reproduces on upstream `393a43d` unless stated otherwise, and has a known-issue record in
`proof/known-issues/` and a reproducer in `test/reports/` or `pocs/`.

| Upstream | Problem | Status |
|---|---|---|
| [#13250](https://github.com/omacom/omarchy/issues/13250) | A menu label or action that contains `, ]` or `, }` is silently changed: the comma is dropped. | Reproduces. Fixed by [#13968](https://github.com/omacom/omarchy/pull/13968) (open). |
| [#13492](https://github.com/omacom/omarchy/issues/13492) | A menu file whose top level is an array is read as entries with ids `0`, `1`, …; elements with an `action` show up in the menu, label-only ones stay hidden. | Reproduces. Fixed by [#13968](https://github.com/omacom/omarchy/pull/13968). |
| [#13493](https://github.com/omacom/omarchy/issues/13493) | A `//` comment after a value on the same line empties every entry in that menu file (the whole menu, for the default file). | Reproduces. Fixed by [#13968](https://github.com/omacom/omarchy/pull/13968). |
| — | A no-break space or another non-ASCII space between tokens empties every entry in that menu file (`KI-MENU-JSONC-UNICODE-WHITESPACE`). | Reproduces, found by stating the parser's input domain. Fixed by [#13968](https://github.com/omacom/omarchy/pull/13968). |
| — | In a file with CR-only line endings, a whole-line comment swallows the rest of the file (`KI-MENU-JSONC-CR-LINE-ENDINGS`). | Reproduces. Not changed by #13968. |
| [#10601](https://github.com/omacom/omarchy/issues/10601) | Opening the menu takes time quadratic in its row count (232 layout passes and 27,027 row visits for 231 rows). | Reproduces. [#10631](https://github.com/omacom/omarchy/pull/10631) does not change the counts. |
| [#9057](https://github.com/omacom/omarchy/issues/9057) | Opening a picker menu again before the first one is answered leaves the first caller waiting forever. | Reproduces. [#9056](https://github.com/omacom/omarchy/pull/9056) fixes the re-summon trigger; if the menu process dies mid-request the caller still waits forever (see the comment on [#9057](https://github.com/omacom/omarchy/issues/9057)). |
| [#13012](https://github.com/omacom/omarchy/pull/13012) (PR) | Restores the selected row when you go back from a submenu. | The PR has one regression. Search, open a deeper submenu from the results, then go back: the cursor lands on an unrelated row (`Learn`). |

[#13255](https://github.com/omacom/omarchy/pull/13255), [#13511](https://github.com/omacom/omarchy/pull/13511) and
[#13512](https://github.com/omacom/omarchy/pull/13512) were closed in favour of #13968.
[#10340](https://github.com/omacom/omarchy/issues/10340) (search ranks a menu action above an installed app) was
checked too. It reproduces (typing `chro` and pressing Enter changes the default browser instead of
launching Chrome), but the ranking follows the documented rule, so changing it is a ranking-policy decision
(a feature request) rather than a defect fix. [#12223](https://github.com/omacom/omarchy/pull/12223) implements it.

## How to verify

```sh
git clone https://github.com/probelabs/omarchy && cd omarchy        # default branch: quattro-proof
git fetch origin 'refs/notes/proof/*:refs/notes/proof/*'

# 1. The product code is upstream's: every non-proof difference is an annotation.
python3 review/check-clean-product-diff.py 393a43d HEAD

# 2. The audit record of this commit (verdict, every check, test results).
git notes --ref=proof/runs show HEAD | python3 -m json.tool | less

# 3. Re-run the tests yourself (see "How to reproduce"), or the whole audit with the ReqProof
#    `proof` tool: `proof audit --no-cache`. It runs every suite and measures coverage.
```

## How to reproduce

You need `bash`, Node.js 18 or later and `perl`. The #10601 reproducer also needs the Qt 6 `qml` runtime
(`qt6-declarative`). Some menu tests need Linux (`flock`, `/proc`, GNU `find`); they print `SKIP` elsewhere.

```sh
# Menu test suites (from a clone, see "How to verify")
bash test/shell.d/menu-test.sh
node --test test/node/menumodel-replay.test.mjs

# Live menu suites (menu-live): the menu inside a running shell, driven by real IPC calls and key
# presses. Linux only; needs sway, quickshell, wtype and socat. Each test starts its own private
# headless sway; without those tools the tests are recorded as skipped, with the missing tool named.
bash test/junit/live-session.sh menu-live test/shell.d/menu-compositor-test.sh test/shell.d/menu-acceptance-test.sh

# Behaviour-diff harness used for pull-request compatibility checks (see test/bdiff/README.md)
node test/bdiff/harness.mjs . default/omarchy/omarchy-menu.jsonc

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

## Evidence clips

Five short screen recordings show upstream bugs before and after a fix: #13493, #13250 and #13492 (menu
JSONC parsing) and PR #13012 (the cursor position after going back from a search, as model output and as
the live menu UI). They are in [`review/media/`](../review/media/); [`review/media/MANIFEST.md`](../review/media/MANIFEST.md)
lists each clip's exact BEFORE and AFTER commits and how it was recorded. The scripts and input files behind
them are in [`pocs/reproducers/`](../pocs/reproducers/). `pocs/reproducers/run-at-rev.sh <sha>` runs them
against any commit, and that directory's README records their output on each commit.
[`docs/proof/headless-gui-testing.md`](../docs/proof/headless-gui-testing.md) explains how to run
and record the real shell on a Linux machine with no display.

## How syncing with upstream works

1. Fast-forward `quattro` to upstream `quattro`.
2. Merge `quattro` into `quattro-proof`. Upstream code always wins; the proof layer adapts to it.
3. Run the audit on `quattro-proof`. Fix whatever it reports (requirements, trace links, tests) until it is
   back to 0 errors.
4. Publish the run record (a git note on the new tip) and rebuild the `pr/*` mirrors on the new tip.
