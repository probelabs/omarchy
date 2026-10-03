# Behaviour-diff harness (menu plugin)

`proof change behavior-diff --base <rev> --head <rev>` runs this harness at the
base and at the head, each in a throwaway git worktree, over the same inputs,
and records every input whose output differs. The base's behaviour is the
reference oracle. Configuration: `project.review.behavior_diff` in `proof.yaml`.

```
node test/bdiff/harness.mjs <rev-worktree> <input>
```

| Input | What runs | Output |
|---|---|---|
| `*.jsonc` (also `*.json`) | `<rev>/shell/plugins/menu/MenuModel.js`, loaded in a `node:vm` context like the repo's tests load it (CommonJS `module.exports`) | `summary rows=<n> strip_parse=<kind>`, then `parseMenuJsonc(text)` rows and `JSON.parse(stripJsonc(text))` (or `ERR`) as JSON in insertion order |
| `*.events` | the real bodies of `open`, `close`, `cancel`, `finishRequest`, `openDmenu`, `openExistingMenu`, `openRoute`, `activateIndex`, `applyDmenuSelection`, `applySelected` and the `resultProc` `onExited` handler, extracted from `<rev>/shell/plugins/menu/Menu.qml` and run under `node:vm` | each caller's outcome (`STRANDED`, `<cancel>` or the value written), the final `opened` / `mode` / `requestActive` / done-file owner, actions run, apps launched, stray writes |
| anything else | nothing | a usage message, exit 2 |

The input file is decoded the way Quickshell `FileView.text()` gives it to QML
(checked live under Quickshell 0.3.1): invalid UTF-8 becomes U+FFFD, a leading
byte-order mark is dropped, and every other character is kept. Output is deterministic. A revision that lacks `MenuModel.js`,
`Menu.qml` or one of the functions prints a `MISSING` / `MISSING-FUNCTION`
marker and exits 0. Product code runs with
no `require`/`process`, and every process spawn (`Quickshell.execDetached`,
`Util.execDetached`, `resultProc.running = true`) is recorded, not executed.
The one exception is the `G` event, which runs the revision's guard and theme
remover under bash in a throwaway HOME; nothing in the repository or the real
HOME is written.

## Event files (`corpus/lifecycle/*.events`)

Whitespace-separated tokens; `#` starts a comment; `S*20` (or `Sx20`) repeats a
token; `@slow` switches to slow-user timing (every answer write finishes before
the next event).

| Token | Event |
|---|---|
| `S` / `I` | select / input summon by a caller polling its own done file |
| `N` | select summon without a done file (no caller) |
| `M` / `A` | menu summon / action-alias summon |
| `P` / `R` | activate row 0 / row 1 |
| `C` | close |
| `X` | the shared answer `Process` exits (fires the revision's `onExited`) |
| `G` | Remove > Theme guard: the revision's `remove.theme` row (from its own `default/omarchy/omarchy-menu.jsonc`) through its guard batch (`guardScript` under bash) and `isVisible`, and its `bin/omarchy-theme-remove` with a stub picker, in a throwaway HOME (under the system temp directory, removed afterwards) of the shape set by `@home:<shape>`: `missing`, `empty` (default), `copied`, `cloned`, `linked` (symlink only), `worktree` (`.git` file), `dotted` (only a `.git` directory, a name the remover refuses). Prints `guard remove.theme home=<shape> shown=<bool> remover=<offers …\|none> agree=<yes\|NO>` (agree: the row shows exactly when the remover offers a name without a leading dot); needs GNU find and bash 4, else an `UNAVAILABLE` line on both sides |

The shared QML `Process` is modelled as it behaves live: `running = true` while
it is still running is ignored, and it stays busy until an `X`. After the last
event every still-running write is drained. The method is the one used for the
#9056 review.

## Partitions

| Partition | Kind | Inputs |
|---|---|---|
| `data` | data, `builtin_data` | every JS `\s` character at the start and before each line, BOM, CRLF, CR, no final newline, empty, whitespace-only, huge (1 MiB) and invalid UTF-8 variants of three seeds: the shipped menu, the shipped sample extension, and `corpus/jsonc/u-issue-11211-1.jsonc` |
| `corpus` | corpus | `default/omarchy/omarchy-menu.jsonc`, `config/omarchy/extensions/omarchy-menu.jsonc`, `pocs/reproducers/**/*.jsonc`, `corpus/jsonc/*.jsonc` |
| `lifecycle` | corpus | every `corpus/lifecycle/*.events` sequence, run once |
| `scale` | scale, n 8 | `corpus/lifecycle/burst-*.events` (bursts of 1, 2 and 20 select summons, then an answer) |
| `timing` | timing, n 8, 2 ms | `corpus/lifecycle/interleave-*.events` (summons interleaved with alias / menu summons and process exits) |

What the scale and timing partitions measure: the engine's scale mode runs N
concurrent invocations of the harness on one input, and its timing mode starts
N invocations 2 ms apart. Each invocation is a separate deterministic
simulation, so those modes only check that the harness gives the same output
under load. The race that matters for the menu request lifecycle (summon bursts
while an answer write is still running, #9056 / #9057) is encoded in the event
file and replayed inside one invocation. The engine uses only the first three
files (sorted by path) of a scale or timing partition as seeds, so each of those
globs matches exactly three files. The `lifecycle` partition runs every sequence.

`corpus/jsonc/u-*.jsonc` are user snippets copied verbatim from public omarchy
issues and PRs (the number is in the file name). `u-pr-13511-*` and
`u-pr-13512-11` are transcript excerpts from PR descriptions, not valid JSONC.
They are kept as real-world malformed input.

## Which revision's harness runs

The engine runs the command through `sh -c` with the revision's worktree as the
working directory, so `test/bdiff/harness.mjs` is the copy at that revision. A
base without the harness exits 127 for every input, and the engine records the
run as `unavailable`. It is never recorded as compatible. To diff against an
older base, point `OMARCHY_BDIFF_HARNESS` at an absolute copy of the harness:
the corpus and the configuration come from the checkout that runs `proof`, not
from either revision.

## Classifying differences

```
proof change behavior-diff --base <base> --head <head>
proof change behavior-diff classify --id bd-… --as intended --requirement SW-REQ-…
```
