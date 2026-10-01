Reproduces `review/media/menu-back-from-search-gui.mp4` (upstream PR #13012, live UI): the full production
`shell/shell.qml` on a private headless sway (sway 1.12, wlroots headless + pixman, output `HEADLESS-1`);
the menu is summoned over the shell IPC (`omarchy-shell shell summon omarchy.menu {"menu":"style"}`);
real keystrokes via `wtype` (search "font", Enter, Backspace); captured as timed `grim -o HEADLESS-1`
stills assembled at 25 fps with ffmpeg. Revisions: BEFORE `d3cfd53b` (PR base) -> AFTER `7a7fb10c`
(PR #13012 head), with `shell/plugins/menu/Menu.qml` swapped off-camera between takes.

What the clip shows (checked frame by frame): the BEFORE take ends with the Style menu's cursor on
Theme; the AFTER take ends with it on Font. This matches the model-level driver in
`../menu-back-from-search/` at the same two revisions. Upstream `e332dc97` (this branch's code) behaves
like BEFORE.

Note: the recording session ran these steps as ad-hoc shell lines and kept no script. `gui-drive.sh` is
a reconstruction of them (2026-10-01), not the file that ran. It needs a harness sway config
(`HEADLESS_CONF`; pattern: `test/qml/lock/sway-headless.conf`) and the environment described in
`agents/skills/headless-gui-testing.md`, so treat it as the documented recipe; the model-level driver
runs standalone. Tool paths fall back to `${PROOF_ENV_DIR:-$HOME/proof-env}`.
