# Proof Re-Audit — omacom/omarchy#12668 (menu-file follows symlink roots)

**Branch:** `review/pr-12668` (dogfood tree @ quattro `ce925cb` + PR diff)
**Diff source:** `https://github.com/omacom/omarchy/pull/12668.diff` (fetched 2026-09-24)
**Static audit:** `pr-12668-menu-file-symlinks.md` (verdict APPROVE-WITH-COMMENTS)
**Re-audit verdict: CONFIRMED — and improved upstream since the audit.** The PR now ships `test/shell.d/menu-file-symlink-root-test.sh`, which implements exactly the witness rows the static audit's §5 requested (symlinked-root positive, interior-loop negative). All five new witnesses pass on GNU find.

---

## 1. Application

| File | Diff base blob | Dogfood blob | Result |
|---|---|---|---|
| `bin/omarchy-menu-file` | `c26620607a4` | `ace4da4c533` (annotated) | applied, hunk offset +2 |
| `test/shell.d/menu-file-symlink-root-test.sh` | new file | — | added cleanly |

Verified post-merge: `find -H "${find_args[@]}"` with the load-bearing comment at bin/omarchy-menu-file:49-50. The one-liner is the whole production change.

**Proof-tree integration (this branch):** wired the new suite into `proof.yaml`'s `menu-shell` evidence job next to `menu-file-test.sh` (same GNU-find guard), so `tests_pass` now executes it — confirmed in the audit log.

## 2. Spec rows (verified against the applied diff)

| Req | Spec text (verbatim) | Re-audit finding |
|---|---|---|
| **SW-REQ-260922-HR29** | "The listing matches the requested formats case-insensitively, prunes dotfiles and dot-directories, and sorts rows by modification time descending; a nonexistent path is rejected on stderr with exit 1." | All four clauses preserved under `-H` — and the PR's new test proves the first clause now holds *through a symlink root* (format filter `webm mp4` drops `note.txt`, exit 0). Broken-symlink rejection still unwitnessed (gap below). |
| **SYS-REQ-260922-6642** | "Menu action scripts … perform their documented side effect or a loud, exit-coded refusal." | The PR's interior-loop witness (`sub/loop -> ..` under a followed root, forced pick, exit 0) directly pins the `-L`-regression the review thread caught: the loop→exit-1→pipefail abort-after-successful-pick cannot return. |

**Untracked-behavior finding stands (narrowed):** HR29 is still silent on symlinks — the recommended amendment ("symlinked path arguments are followed; interior symlinked directories are not descended") remains the right one-line spec companion. What changed since the static audit: the *behavior* is now witnessed by upstream tests; what is still missing is the requirement text those tests should be annotated to.

## 3. Suite & audit results (branch)

| Suite | Result |
|---|---|
| `menu-file-test.sh` | PASS (2/2) |
| `menu-file-symlink-root-test.sh` (new, from the PR) | **PASS 5/5**: symlink root listed; pick returned; format filter holds through the link; mixed symlink+real roots merge; interior loop stays exit 0 with a successful pick |
| `proof audit` tests_pass (all jobs, incl. the new suite) | PASS — 117 s |

Audit checks: `tests_pass` ✓, `code_mcdc_measure` ✓, `code_mcdc_coverage` ✓, `mcdc_coverage` ✓. **Errors: 0, Warnings: 0.**

## 4. MC/DC delta (quattro `ce925cb` → branch)

| Measure | Before | After | Delta |
|---|---|---|---|
| Spec witness rows (78 reqs) | 290/290, queue cleared | 290/290, queue cleared | unchanged — the new tests carry no `// Verifies:` annotations (upstream style), so they do not register as spec witness rows; they are behavioral witnesses for HR29-adjacent clauses |
| Code MC/DC aggregate | 40/102 decisions (39.2%), 63/147 conditions (42.9%) | identical | the diff adds no branches; note: the `menu-bash-file` MC/DC target exists but is `enabled: false` (macOS-era zero-observation note) — re-enabling it on Linux would give `omarchy-menu-file` its first instrumentation, and this PR's suite would drive it |

Net: the PR **adds witnesses** (5 assertions covering the audit's requested rows 1-2), breaks none, covers none of the spec rows formally.

## 5. Witness gaps (static audit §5 vs this branch)

| Witness requested by the static audit | Status on branch |
|---|---|
| Symlinked root dir with matching files → picker receives them, exit 0 | **present, passing** (PR's test, assertions 1-2) |
| Nested interior symlink loop under `-H` → exit 0, selection reaches caller | **present, passing** (assertion 5, with forced pick through the stub) |
| Broken symlink path argument → "Path not found" on stderr, exit 1 | still absent |
| Overlapping roots (symlink → sibling arg) → rows deduplicated | still absent — correctly so: the dedup (review comment 2) was not adopted, and the duplicate-rows edge stands (verified in the V4 evidence video: transcode default pair lists 6 rows for 3 files) |

## 6. Honesty caveats

- The proof.yaml wiring (§1) is a review-branch integration step, not PR content.
- The new suite skips cleanly without GNU find; all results above are GNU findutils on Arch.
- The duplicate-rows edge remains open and unwitnessed by design until a dedup decision is made; the static audit's comment 2 (`awk '!seen[$0]++'`) still applies.
- Code-MC/DC silence is structural: the changed file's instrumentation target is disabled, and a flag change adds no decisions.

---
*Re-audit: proof 0.1.0-dev+gfbfdcd400b15 (Linux x86_64), dogfood quattro @ ce925cb, node v24.15.0 userland. Branch log `reaudit-pr-12668.log`. Nothing pushed.*
