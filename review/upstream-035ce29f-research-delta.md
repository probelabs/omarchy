# Upstream delta research — 393a43d4..035ce29f (60 commits)

Processed: 2026-10-04. Merge: `Merge upstream quattro 035ce29f into quattro-proof`.

## In the audited surface

| Commit | Subject | Files in scope | Effect on the proof layer |
|---|---|---|---|
| 879d6583 (#7158) | Fix fingerprint enrollment and lock-screen recovery | `bin/omarchy-apply-lock`, `shell/plugins/lock/{Service.qml,LockView.qml}`, new `shell/plugins/lock/FingerprintModel.js`, new tests `lock-fingerprint-retry-test.sh`, `lock-fingerprint-service-test.sh` (+ fixture), `apply-lock-test.sh` | Behaviour change in two lock requirements and four new ones (below). Fixes two of our lock known issues (see "Known issues"). |
| 72c152a2 (#14260) | Retry systemd reload in the fingerprint recovery migration | migration only | Not in scope. |
| 00cee6d3 (#7806) / 6e15d76a | Drop key auto-repeat in the lock screen password field | `shell/plugins/lock/LockView.qml`, new `lock-autorepeat-test.sh` (+ fixture) | New requirement SW-REQ-261004-VVN2. |
| 2ba1015e, 520e4bca, a8e09b9c (#14117) | Keep image picker work bounded / retain lazy thumbnail jobs | `bin/omarchy-menu-images`, `test/shell.d/menu-images-test.sh` | Lazy thumbnails now go through one shared, serialized, lower-priority worker pool. |
| 27a3feff | Fix icon spacing | `shell/plugins/menu/BarWidget.qml` (one property) | None (trace re-reviewed). |
| 035ce29f (#10367) | Install > Service > Microsoft | `default/omarchy/omarchy-menu.jsonc` (two data rows) | None (trace re-reviewed). |
| 0e7d6c27 (#14259) | Update test fixtures to current runtime contracts | `test/shell.d/fixtures/lock-fingerprint-indicator/shell.qml`, network fixtures | Fixture only. |
| cb865c2f / 8a13eac8 (#9873) | polkit stack defers to system-auth | `test/shell.d/security-polkit-faillock-test.sh` (matches the `*lock*-test.sh` scope glob; it tests setup scripts outside the lock component) | Not run by the lock suites. |

The other 50 commits touch no menu or lock file.

## Requirement changes (recorded by agent:claude-code under the owner's delegation)

| Requirement | Change | Why |
|---|---|---|
| SYS-REQ-260912-JW2J | FRETish: each run takes exactly one fingerprint step (install, remove or keep) | #7158 keeps the configuration when the enrollment probe fails. |
| SW-REQ-260912-Y0WT | Description narrowed: "not enrolled" is fprintd's explicit empty-enrollment answer or a missing fprintd-list; removal also removes the resume hook | #7158 classifies the probe answer. |
| SW-REQ-260912-S154 | Hazard rationale only | The probe's exit status is ignored; only its answer is classified. |
| SW-REQ-260912-41VV | Description: the unavailable state (crossed-out icon and notice) | #7158. |
| SW-REQ-261004-SP65 (new) | A failed probe keeps the fingerprint configuration | #7158. |
| SW-REQ-261004-YNBG (new) | The resume hook and the stop-timeout drop-in are installed before the PAM fingerprint stack | #7158. |
| SW-REQ-261004-V813 (new) | The lock screen classifies the probe answer; an unknown answer keeps the state and asks again | #7158. |
| SW-REQ-261004-296X (new) | Reader availability and attempt pacing (backoff, reach timeout, resume grace, nudge) | #7158 (FingerprintModel.js). |
| SW-REQ-261004-VVN2 (new) | The password field drops auto-repeated key presses except Backspace and Delete | #7806. |

## Verification additions

- `shell/plugins/lock/FingerprintModel.js` enters the lock component with code_mcdc target `lock-js-fingerprintmodel`
  (test command `lock-node`; `test/node/fingerprintmodel-replay.test.mjs` replays upstream's
  `lock-fingerprint-retry-test.sh` body under node:test).
- `lock-shell` runs the three new upstream lock tests; their fixtures and the fprintd resume hook / drop-in that
  `apply-lock-test.sh` copies joined the verification scope.

## Known issues

Every lock known issue was re-run on the merge and on the previous baseline (upstream 393a43d4). A known issue is
marked fixed only when its reproducer shows the defect absent on the merge and present on 393a43d4.

| Known issue | Before | After | Deciding output (merge / 393a43d4) |
|---|---|---|---|
| KI-APPLY-LOCK-FPRINT-GATE-FAIL-OPEN | open | fixed by #7158 | only an enrolled `- #N:` row installs fingerprint PAM / the substring gate installs it for an empty or failed probe |
| KI-LOCK-FPRINT-PROBE-FAIL-OPEN | open | fixed by #7158 | zero enrollment reads fingerprintConfigured=false / true |
| KI-LOCK-FPRINT-START-FAIL-NO-RETRY | reviewed | fixed by #7158 | a failed start arms the retry (1000 ms) / no retry armed |
| other lock known issues (11) | open/reviewed | unchanged | reproduce on both; citations moved to the new lines |
| KI-MENU-IMAGES-VIPS-NO-TIMEOUT | reviewed | unchanged | still no internal bound on vipsthumbnail; with the new shared pool a stalled still also holds back later stills |

Four apply-lock reproducers now run a copy of the real helper end to end (they had depended on the old probe
shape). Upstream references: the known issues that match an upstream report carry an `upstream_report` block or,
where the submission gates do not apply, a notes sentence. KI-MENU-SEARCH-SCORE-RANKING no longer counts the
app-first order as a defect: the code comment and upstream #6383 chose it.
