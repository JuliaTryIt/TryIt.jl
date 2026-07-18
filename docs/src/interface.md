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

**Folders** — every try under the tries root, most recently modified
first. Each row carries a coloured project-type badge, the creation
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
| `Ctrl-R`       | Rename the selected try                    |
| `Ctrl-D`       | Flag the selected try for deletion         |
| `Ctrl-G`       | Graduate the try to the projects directory |
| `Esc`          | Quit without changing directory            |
| `Ctrl-C`       | Abort                                      |

Ctrl-R is claimed by Tachikoma's default bindings for screen
recording, which intercepts it before the selector sees it. TryIt
disables that binding so Ctrl-R renames — matching `try-cli` and
`try-rs` — and moves recording to `F9`, shown as `● REC` in the help
bar while active. Ctrl+Shift+R was not an option: `KeyEvent` carries
no modifier fields, and legacy terminals transmit the same byte for
Ctrl+R and Ctrl+Shift+R. See `upstream-bugs.md`.

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

`Ctrl-\` opens the in-app theme picker, which overrides `TRY_THEME`
for the rest of the session and is persisted by Tachikoma across
runs. An unknown `TRY_THEME` is ignored rather than fatal.

## Animated background

On by default. Configure with `TRY_BACKGROUND`:

| Value                                     | Effect                                |
| ----------------------------------------- | ------------------------------------- |
| `wash` (default)                          | Animated colour gradient              |
| `dotwave`                                 | Braille terrain, full-bleed           |
| `phylo`                                   | Phylogenetic tree, full-bleed         |
| `clado`                                   | Cladogram, full-bleed                 |
| `none`, `off`, `no`, `0`, `false`         | Disabled                              |

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

The background is also skipped when Tachikoma's global motion switch
is off, so a reduced-motion preference wins over our default.

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
