# Selector Interface

Running `tryit` with no arguments opens the interactive selector.
The layout follows the reference
[`try-rs`](https://github.com/tassiovirginio/try-rs) interface:

```text
╭─ Search/New ───────────────────────────╮╭─ Disk ──────────────────╮
│> ▌                                     ││Used: 504.6 GB │ Free: … │
╰────────────────────────────────────────╯╰─────────────────────────╯
╭─ Folders ───────────────────────── 1/5 ╮╭─ Preview ───────────────╮
│▸ ● 2026-07-17 tachikoma-jl (00d 13h 5… ││▸ src                    │
│  ● 2026-07-12 kaimon       (05d 14h 1… ││  README.md              │
╰────────────────────────────────────────╯╰─────────────────────────╯
                                          ╭─ Legends ───────────────╮
                                          │● Rust      ● Julia      │
                                          ╰─────────────────────────╯
 ↑↓ Nav Enter Select Ctrl-R Rename …                        Esc Quit
```

## Panels

**Search/New** — filters the list as you type. If nothing matches,
pressing `Enter` creates a try with what you typed as the slug. In
rename mode (`Ctrl-R`) the same box becomes the rename prompt, marked
with `✎` and a highlighted border.

**Folders** — every directory under the tries root, most recently
modified first. That includes folders with no date prefix, such as a
repository cloned in by hand: they are listed **dimmed**, dated from
their filesystem mtime, to distinguish a date you chose from one
inferred for you. A dated folder keeps its own date even when the
rest of its name is not a valid slug, so `2026-04-15-MyPkg.jl` is
listed under April, not today.

`Ctrl-P` toggles a folder's date prefix, renaming it in place.
Pressing it on a dated folder removes the prefix immediately — there
is nothing to decide. Pressing it on an undated one asks which date
to use:

```text
┏━ Which date? ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃          Add a date prefix to "LibPARI.jl".         ┃
┃    [ Its own  2026-04-15 ]  [ Today  2026-07-18 ]   ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

Both dates are spelled out, because the whole reason to ask is that
they differ. "Its own" is the mtime-derived date already shown in the
row and is the default; "Today" suits a folder whose mtime says more
about when it was last touched than when you started working on it.
The choice is not remembered — the right answer genuinely varies per
folder.

The name is preserved in both directions: `LibPARI.jl` becomes
`2026-04-15-LibPARI.jl`, never `2026-04-15-libpari-jl`. It commits the date already shown —
the mtime-derived one — rather than today's, so the row does not jump
after the rename, and it prepends the prefix without re-slugging, so
`LibPARI.jl` becomes `2026-07-18-LibPARI.jl` rather than
`2026-07-18-libpari-jl`. Each row carries a coloured project-type badge, the creation
date, the slug, and a right-aligned age in `DDd HHh MMm`. The counter
in the top border shows cursor position within the filtered list.

**Preview** — contents of the selected try, directories first
(prefixed `▸`), then files, each sorted by name.

**Disk** — used and free space for the filesystem holding the tries
root. `df` is unavailable on Windows, where this panel reads
`unavailable` rather than failing.

**Legends** — the badge colour key.

On terminals narrower than 64 columns the right-hand column is
dropped entirely so the folder list stays usable.

## Badges

A try is tagged by the marker files it contains:

| Badge       | Detected by                                          |
| ----------- | ---------------------------------------------------- |
| `Rust`      | `Cargo.toml`                                         |
| `Julia`     | `Project.toml`, `JuliaProject.toml`                  |
| `Python`    | `pyproject.toml`, `requirements.txt`, `setup.py`     |
| `Go`        | `go.mod`                                             |
| `Maven`     | `pom.xml`                                            |
| `Flutter`   | `pubspec.yaml`                                       |
| `Mise`      | `.mise.toml`, `.mise.local.toml`                     |
| `Locked`    | any lockfile (`Cargo.lock`, `uv.lock`, `go.sum`, …)  |
| `Worktree`  | `.git` is a *file* (a `git worktree` gitdir pointer) |
| `Submodule` | `.gitmodules`                                        |
| `Git`       | `.git` is a *directory*                              |

`Git` and `Worktree` are mutually exclusive: `git worktree add`
writes a `.git` file pointing at the parent repository rather than a
full `.git` directory, which is exactly how the two are told apart.

Badge order is fixed rather than derived from `readdir`, so a
directory's badges do not change position between frames.

## Key bindings

| Key            | Action                                     |
| -------------- | ------------------------------------------ |
| `↑` / `↓`      | Move the cursor                            |
| `Enter`        | `cd` into the selected try, or create one  |
| `Ctrl-N`       | Create a new dated try                     |
| `Ctrl-T`       | Theme picker                               |
| `Ctrl-B`       | Animation picker                           |
| `Ctrl-W`       | Save theme and animation to the config file |
| `Ctrl-A`       | About                                      |
| `?`            | Key-binding overlay                        |
| `F1`           | Documentation browser                      |
| `Ctrl-R`       | Rename the selected try                    |
| `Ctrl-D`       | Flag the selected try for deletion         |
| `Ctrl-G`       | Graduate the try to the projects directory |
| `Ctrl-P`       | Add or remove the date prefix              |
| `F9`           | Start / stop `.tach` screen recording      |
| `Esc`          | Quit without changing directory            |
| `Ctrl-C`       | Abort                                      |

### The keymap is ours

TryIt runs the event loop with `default_bindings=false`, so the keys
above are the whole keymap — Tachikoma's own shortcuts are not
active.

That is a consequence of matching `try-rs`. The framework claimed
`Ctrl+A` for its animation toggle and `Ctrl+R` for screen recording,
intercepting both before the selector's `update!` ran, and only the
recording binding has a per-model opt-out
(`recording_enabled`). Taking `Ctrl+A` for About therefore meant
taking all of them, and providing our own theme picker, About, and
`?` help overlays in exchange.

Two framework features are given up by that trade: the settings
overlay (background brightness, saturation, speed) and clipboard copy
of the visible region. Neither has a TryIt equivalent yet.

`Ctrl+R` is rename, as in `try-cli` and `try-rs`. Screen recording
moved to `F9` — it is not on the help bar, only in `?`. Ctrl+Shift+R
was not an option: `KeyEvent` carries no modifier fields, and legacy
terminals transmit the same byte for `Ctrl+R` and `Ctrl+Shift+R`. See
`upstream-bugs.md`.

### The help bar adapts to width

`StatusBar` clips rather than wraps, so bindings are dropped as the
terminal narrows — in reverse order of how often they are reached
for. `?` and `Esc` survive every width, because `?` is where
everything dropped is still written down.

| Width  | Shown                                             |
| ------ | ------------------------------------------------- |
| ≥ 118  | All seven, plus `? Help`                          |
| ≥ 100  | Through `Ctrl+G Graduate`                         |
| ≥ 78   | Through `Ctrl+R Rename`                           |
| < 78   | `↑↓ Nav`, `Enter Select`, `? Help`                |

## Shell integration

`tryit init` emits a snippet that drops any conflicting `tryit` alias
and then defines the shell function through a nested `eval`:

```sh
unalias tryit 2>/dev/null || true
eval 'tryit() { ... }'
```

Both halves are load-bearing. Users migrating from `try-cli` or
`try-rs` often have an `alias tryit=...` in their rc, and zsh expands
aliases while *parsing* a function definition — the definition
becomes a syntax error and the whole `eval` aborts, leaving the old
command in place. Nesting the definition in its own `eval` defers its
parsing until after the `unalias` has actually run; emitting the
`unalias` on a preceding line does not work, because zsh parses the
entire outer `eval` string before executing any of it.

## Themes

Tachikoma ships 24 themes. Pick one at startup with `TRY_THEME`:

```sh
export TRY_THEME=dracula
```

Dark: `kokaku` (default), `esper`, `motoko`, `kaneda`, `neuromancer`,
`catppuccin`, `solarized`, `dracula`, `outrun`, `zenburn`, `iceberg`,
`gruvbox`, `horizon`, `dusk`.
Light: `paper`, `latte`, `solaris`, `sakura`, `ayu`, `frost`,
`meadow`, `dune`, `lavender`, `overcast`.

`Ctrl+T` opens the theme picker. Moving the cursor applies each
theme immediately — the only way to judge one is to see it — so `Esc`
restores whatever was active when the picker opened, and `Enter`
keeps the highlighted one. It overrides `TRY_THEME` for the rest of
the session. An unknown `TRY_THEME` is ignored rather than fatal.

## Animated background

On by default. Configure with `TRY_BACKGROUND`:

Which animation plays is independent of which theme is active: every
colour animation derives its palette from the theme, so the two
compose.

| Value                             | Effect                                |
| --------------------------------- | ------------------------------------- |
| `fog` (default)                   | Drifting fractal noise                |
| `aurora`                          | Undulating horizontal bands           |
| `plasma`                          | Interfering sine fields               |
| `rain`                            | Falling columns with decaying tails   |
| `pulse`                           | A single slow brightness breath       |
| `dotwave`                         | Braille terrain, full-bleed           |
| `phylo`                           | Phylogenetic tree, full-bleed         |
| `clado`                           | Cladogram, full-bleed                 |
| `none`, `off`, `no`, `0`, `false` | Disabled                              |

`TRY_ANIMATION` is an alias for `TRY_BACKGROUND`, which keeps
precedence. `wash` is still accepted as the former name of `fog`.

The first five paint cell *background colours*; the three from
Tachikoma paint braille glyphs in the foreground and so render
full-bleed through the panels.

`TRY_BACKGROUND_PRESET` selects a variant for the glyph backgrounds
(clamped into range; a non-numeric value is ignored).

The default is deliberately not one of Tachikoma's own backgrounds.
Those draw braille glyphs in the *foreground*, and since panels only
paint the rows they actually fill, the glyphs show through panel
interiors as noise. Blanking the interiors is not a fix either — it
erases them outright, because there is no background colour
underneath to preserve.

`wash` instead paints spaces with an animated background *colour*
derived from the active theme. Text drawn over it keeps its own
foreground and inherits the cell's background, so the frame animates
without competing with the content, and panels can be blanked over it
safely. The glyph backgrounds remain available and render full-bleed,
matching Tachikoma's own demos.

The background is skipped entirely when Tachikoma's motion setting
is off, re-checked every frame, so a reduced-motion preference always
wins over the default.

!!! note
    Nothing in TryIt currently *toggles* that setting: `Ctrl+A` used
    to, and now opens About. Until a replacement binding exists, use
    `TRY_BACKGROUND=off` to disable the animation.

## Documentation in the terminal

`F1` opens this manual inside the selector. `Tab` pages through it,
the arrow keys scroll, `Esc` closes.

The pages are the same markdown that builds the website, embedded
into the package at precompile time and rendered with CommonMark
through Tachikoma's `MarkdownPane`. Documenter `@docs` directives are
expanded against the package, so the Reference page shows real
docstrings in the terminal rather than the directive that stands for
them.

They are embedded rather than read from `docs/src` because a
PackageCompiler bundle contains no markdown files — there are zero in
it — and `pkgdir` inside a compiled app resolves to the path of the
machine that built the binary. Reading from disk would have worked
for whoever ran the build and failed for everyone else.

## Configuration file

`Ctrl-W` writes the active theme and animation to a TOML file:

```toml
theme = "dracula"
animation = "plasma"
```

It is looked for at `$TRY_CONFIG`, then
`$XDG_CONFIG_HOME/tryit/config.toml`, then
`~/.config/tryit/config.toml`. XDG is honoured on every platform,
macOS included, so one dotfile repository behaves the same
everywhere.

Precedence is **environment > file > default**, so a one-off
`TRY_THEME=nord tryit` still works without touching the file. A
missing, unreadable or malformed config yields defaults rather than
stopping the CLI — a typo in a hand-edited file should cost you the
wrong theme, not your tool.

`Ctrl-B` picks the animation the same way `Ctrl-T` picks the theme:
each choice applies as the cursor moves, `Enter` keeps it, `Esc`
restores what was playing before.

## Screen recording

`F9` starts and stops a `.tach` screen recording. A `● REC` indicator
appears in the help bar while capture is running.

Recordings are written to the **tries root** as
`tryit_<timestamp>.tach`, not to the directory `tryit` was invoked
from — the selector is run from wherever you happen to be, and
Tachikoma's default would scatter files across the filesystem.

The recording is flushed on every exit path, including selecting a
try, quitting with `Esc`, and aborting with `Ctrl-C`. Writing the file
is what `stop_recording!` does, so a capture left running would
otherwise be discarded.

## Open or create

Typing in **Search/New** filters the list. Pressing `Enter` then does
one of three things:

| Typed text                              | `Enter` does                  |
| --------------------------------------- | ----------------------------- |
| Nothing                                  | Opens the highlighted try     |
| The highlighted try's exact name         | Opens it                      |
| Matches something, but is not its name   | **Asks** open or create       |
| Matches nothing                          | Creates a try with that name  |

The prompt exists because filtering matches *substrings* of
`"<date> <slug>"`. Without it, typing the beginning of an existing
name always opened that try, so a shorter name could never be
created: with `2026-07-18-help-me` present, `help` was uncreatable.
The date is part of the haystack too, so `2026` matched every try of
the year and no name starting with the year could be made either.

```text
┏━ Open or create? ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┓
┃                "help" matches 2 tries.                 ┃
┃              Choose what Enter should do.              ┃
┃    [ Open  2026-07-18-help-desk ]  [ Create  help ]    ┃
┗━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━┛
```

`←` / `→` (or `↑` / `↓`, or `Tab`) move between the actions, `Enter`
confirms, `Esc` returns to editing with the typed text intact.
Opening is the default and sits on the left. "Open" always names the
*highlighted* try, so moving the cursor before pressing `Enter`
changes which try the prompt offers.

Typing a full existing name is treated as unambiguous, so the common
type-then-open flow stays a single `Enter`.

## Deleting and `cd`

Deleting a try that is a linked git worktree runs `git worktree
remove` first, so the parent repository stops listing it and its
admin directory under `.git/worktrees` is cleaned up. Removing the
directory alone would leave the worktree registered and `prunable`.
If the unregistration fails — the parent repository may be gone, or
`git` may be absent — the directory is still removed.


`Ctrl-D` flags a try; the deletion itself is deferred until the
selector exits, so the confirmation prompt can be answered on a
restored terminal. That ordering means the `cd` target may have been
removed in between — flagging the try under the cursor and confirming
is the easy way to get there.

When that happens the `cd` is suppressed and a diagnostic is written
to stderr instead. Emitting it anyway would make the caller's shell
fail the `eval` with `no such file or directory`, which reads like a
crash in TryIt rather than the deletion you asked for. The same guard
covers a try removed by another process while the selector is open.

## Performance notes

The view is re-rendered on every frame, so the panels avoid repeating
filesystem work:

- Badges are memoised per try path for the lifetime of the session.
- The preview listing is recomputed only when the cursor moves to a
  different try.
- Disk stats are resolved once per session — the tries root does not
  change while the selector is open.

Every panel helper degrades to an empty or `nothing` result instead
of throwing. A try can be deleted out from under the selector between
refreshes, and an exception raised mid-frame would take down the TUI.
