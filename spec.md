
# TryIt.jl — Specification (EARS)

An ephemeral-workspace manager written in Julia. Functional mirror of
the Ruby [`try-cli`](https://rubygems.org/gems/try-cli), with a
TUI powered by [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl)
(Elm-inspired architecture, built-in headless virtual-terminal
testing, pure Julia).

Requirements below follow **EARS** (Easy Approach to Requirements
Syntax). Each requirement carries a stable ID so downstream tests,
changelogs, and traceability matrices can reference them.

---

## 1. Glossary

| Term                    | Meaning                                                                                                      |
| ----------------------- | ------------------------------------------------------------------------------------------------------------ |
| **Try**           | A named, date-prefixed directory (`YYYY-MM-DD-<slug>`) under the *tries path*.                           |
| **Slug**          | The lowercased kebab-case form of a user-supplied name (`My New Try` → `my-new-try`).                   |
| **Tries path**    | Root directory that contains every try. Defaults to`$HOME/work/tries`. Settable via `TRY_PATH`.          |
| **Projects path** | Destination when a try is graduated. Defaults to the parent of the tries path. Settable via`TRY_PROJECTS`. |
| **Graduation**    | Moving a try out of the tries path into the projects path, dropping the date prefix.                         |
| **Selector**      | The interactive full-screen TUI that lists tries, filters, and receives keyboard commands.                   |

---

## 2. Ubiquitous requirements (always-on)

- **UB1.** The system shall create tries in the directory identified by the `TRY_PATH` environment variable, defaulting to `$HOME/work/tries`. (Amended 2026-07-18: was `$HOME/src/tries`. The two reference implementations disagree — `try-cli` documents `~/src/tries`, `try-rs` documents and implements `~/work/tries` — and this project follows `try-rs`.)
- **UB2.** The system shall name each *new* try `YYYY-MM-DD-<slug>` using the current date in the configured zone — local by default, or UTC where `timezone = "utc"`. Dates written and dates displayed shall be read from the same clock. (Amended 2026-07-18: was unconditionally local, while dates *shown* for undated directories were computed in UTC, so a directory touched shortly after midnight was listed under the previous day.) (Reaffirmed 2026-07-18: `try-rs` makes the prefix optional, defaults it *off*, allows an arbitrary `chrono` format, and separates with a **space** (`extract_prefix_date` splits on `' '`). This project deliberately keeps a mandatory hyphen-separated ISO date: it is what `_parse_try_basename`, the filter haystack, rename and graduate are all built on, and changing it would make every existing try unlistable. Divergence accepted.)
- **UB3.** The system shall derive the slug by lowercasing the input, replacing every run of non-alphanumeric characters with a single `-`, and trimming leading or trailing `-`.
- **UB4.** The system shall emit a single shell-compatible command on stdout when it needs to change the caller's working directory (the shell function defined by `tryit init` will `eval` it).
- **UB5.** The system shall write all diagnostic output to stderr, never to stdout. (Amended 2026-07-18: **exception** — while the selector is open, Tachikoma redirects stderr for the whole session so that stray output cannot corrupt the display. A diagnostic written from inside a key handler therefore reaches nobody, and a failing `Ctrl-G` presented as a dead key. Selector-internal failures shall instead be rendered in the help bar until the next keystroke. Outside the TUI, UB5 is unchanged.)
- **UB6.** The system shall exit with an explicit status code that distinguishes success (`0`), usage error (`64`, `EX_USAGE`), permission error (`2`), and missing-dependency error (`127`).

---

## 3. Event-driven requirements

- **ED1.** When invoked as `tryit` with no argument, the system shall open the selector listing **every** directory under the tries path, sorted by most-recently-modified first. (Amended 2026-07-18: previously only directories matching `YYYY-MM-DD-<slug>` were listed, so a cloned or hand-made folder was invisible — 8 of 12 directories in a real tries path. A directory without a date prefix is dated from its filesystem mtime. See SD7.)
- **ED2.** When the user types a printable character in the selector, the system shall filter the visible tries by case-insensitive substring match against the slug and the date prefix.
- **ED3.** When the user presses **Enter** on a filter string that is the exact slug of the highlighted try, or on an empty filter, the system shall emit the `cd` command for that try's directory and exit with status `0`. (Amended 2026-07-18: previously this applied to *any* filter that matched. Because filtering is a substring match over `"<date> <slug>"`, that made a name which is a substring of an existing one impossible to create — with `2026-07-18-help-me` present, `help` always opened it, and since the date is in the haystack, `2026` matched every try of the year. See ED14.)
- **ED4.** When the user presses **Enter** on a filter string that matches no existing try, the system shall create the dated directory for that slug, emit the `cd` command for it, and exit with status `0`.
- **ED5.** When invoked as `tryit clone <url> [<name>]`, the system shall clone the remote repository into a new try. The slug is `<name>` if supplied, otherwise the basename of `<url>` with any `.git` suffix stripped.
- **ED6.** When invoked as `tryit worktree <name>`, the system shall create a `git worktree` of the current repository at a new try named `<name>` and emit the `cd` command for it.
- **ED7.** When the user presses **Ctrl-R** on a highlighted try, the system shall enter rename mode, read a new slug from the input line, and rename the directory in place while preserving its date prefix.
- **ED8.** When the user presses **Ctrl-G** on a highlighted try, the system shall move the directory into the projects path, dropping the date prefix, and exit emitting the `cd` command for the new location.
- **ED9.** When the user presses **Ctrl-D** on a highlighted try, the system shall mark the try for deletion and display a `✗` marker on its line, without deleting it yet.
- **ED10.** When the user exits the selector (Enter, Esc, or Ctrl-C) with at least one try marked for deletion, the system shall show a summary and prompt `Delete N tries? [y/N]`; on `y` it shall delete the marked directories and then continue with the original exit action.
- **ED11.** When the user presses **Ctrl-N** in the selector, the system shall create an empty try with a placeholder slug `new-try` (plus a numeric suffix if a same-day collision exists), highlight it, and stay in the selector. (Amended 2026-07-18: was **Ctrl-T**, which now opens the theme picker to match `try-rs`.)
- **ED12.** When the user presses **Esc** in the selector, the system shall exit with status `0` and emit no `cd` command.
- **ED13.** When invoked as `tryit init [<path>]`, the system shall write a POSIX-shell function definition to stdout that wraps the Julia binary and evaluates its stdout in the caller's shell. The function shall read its tries path from the first argument if given, otherwise from `$TRY_PATH`, otherwise from the default.

- **ED14.** When the user presses **Enter** on a non-empty filter that matches at least one try but is not the highlighted try's exact slug, the system shall present a choice between opening the highlighted try and creating a try named after the filter text, defaulting to opening. (Added 2026-07-18.)
- **ED15.** When the user presses **Ctrl-T** in the selector, the system shall open a theme picker that applies each theme as the cursor moves, keeps the highlighted theme on **Enter**, and restores the theme active when the picker opened on **Esc**. (Added 2026-07-18.)
- **ED16.** When the user presses **Ctrl-A** in the selector, the system shall display an About overlay naming the project, its version, and its two reference implementations. (Added 2026-07-18.)
- **ED17.** When the user presses **?** in the selector, the system shall display the full key map as an overlay, dismissed by any key. (Added 2026-07-18. Safe to bind unconditionally: a try whose slug portion falls outside `[a-z0-9-]` is not listed at all, so a filter containing `?` can never match.)
- **ED18.** When the user presses **F9** in the selector, the system shall start or stop a `.tach` screen recording, written to the tries path, and shall flush any recording still running when the selector exits by any route. (Added 2026-07-18. The framework's own `Ctrl-R` recording binding is disabled so that `Ctrl-R` can remain rename; `Ctrl+Shift+R` is not expressible, as `KeyEvent` carries no modifier fields and legacy terminals transmit the same byte for both.)
- **ED19.** When the user presses **Ctrl-P** on a highlighted directory, the system shall toggle its date prefix in place — adding `YYYY-MM-DD-` when absent and removing it when present. When adding, the system shall ask which date to stamp — the folder's own, inferred from its filesystem mtime and already shown in the row, or today's — defaulting to the former. The question shall be skipped when the two dates are equal — preserving the rest of the name verbatim and staying in the selector. (Amended 2026-07-18 twice: adding was originally one-way and refused on an already-dated try, and originally stamped the mtime date without asking. Which date is right varies per folder — an old clone picked up today wants today, an archive being filed wants its own — so it is a question, not a default.) (Added 2026-07-18: ED1 lists undated directories, so there has to be a way to adopt one into the dated scheme from the interface. The name is not re-slugged — that would turn `LibPARI.jl` into `libpari-jl` — and the date shown is committed rather than today's, so the row does not appear to jump.)
- **ED20.** When the user presses **F1** in the selector, the system shall open a documentation browser rendering the project's own manual, paging with **Tab**, scrolling with the arrow keys, and closing with **Esc**. Documenter `@docs` directives shall be expanded against the package so the Reference page carries the same API documentation in the terminal that Documenter produces for the web. (Added 2026-07-18. The pages are embedded at precompile time, not read from disk: a PackageCompiler bundle contains no `.md` files at all, and `pkgdir` inside one resolves to the path of the machine that built it — so a disk-reading implementation would work for whoever ran the build and fail for every other user.)
- **ED21.** When the user presses **Ctrl-B** in the selector, the system shall open an animation picker applying each choice as the cursor moves, keeping the highlighted one on **Enter**, and restoring the animation playing when the picker opened on **Esc**. (Added 2026-07-18. Mirrors ED15: an animation can only be judged by watching it.)
- **ED22.** When the user presses **Ctrl-W** in the selector, the system shall persist the active theme and animation to the configuration file and report the outcome. (Added 2026-07-18.)

---

## 4. State-driven requirements

- **SD1.** While the selector is open, the system shall redraw on every keystroke and on every resize of the terminal window.
- **SD2.** While rename mode is active, the system shall disable every global shortcut except **Enter** (commit) and **Esc** (cancel) and shall echo only printable characters and **Backspace** into the input line.
- **SD3.** While the selector has more tries than visible rows, the system shall keep the highlighted try within the visible viewport, scrolling as arrow keys move selection out of view.

- **SD4.** While the selector is open on a terminal at least 64 columns wide, the system shall display panels for the filter input, the try list, filesystem usage of the tries path, a listing of the highlighted try, and a legend of project-type badges. Below that width the right-hand column shall be dropped so the list stays usable. (Added 2026-07-18.)
- **SD5.** While the selector is open, the help bar shall drop bindings as the terminal narrows, in reverse order of expected use, always retaining the help and quit bindings. (Added 2026-07-18: `StatusBar` clips rather than wraps, so a fixed list silently lost its tail.)
- **SD7.** While the selector lists a directory that carries no date prefix, the system shall render it dimmed, to distinguish a date the user chose from one inferred from the filesystem. (Added 2026-07-18.)
- **SD6.** While the selector is open, the system shall own the entire key map; the TUI framework's default bindings shall be disabled. (Added 2026-07-18: the framework claimed `Ctrl-A` and `Ctrl-R` and intercepted them before the selector's reducer ran, and only its recording binding has a per-model opt-out.)

---

## 5. Optional-feature requirements

- **OF1.** Where the `TRY_EDITOR` environment variable is set to a non-empty command, the system shall spawn that command with the selected try's path as its argument after emitting the `cd` command.
- **OF2.** Where the current working directory is inside a git repository, the system shall accept `tryit worktree`; otherwise it shall print `not inside a git repository` to stderr and exit `64`.
- **OF3.** Where a file named `.try-template` exists in the tries path, the system shall copy its contents into every newly created try's directory.
- **OF4.** Where `TRY_THEME` names one of the bundled themes, the system shall activate it at startup; an unrecognised name shall be ignored rather than fatal.
- **OF6.** Where a configuration file exists at `$TRY_CONFIG`, `$XDG_CONFIG_HOME/tryit/config.toml`, or `~/.config/tryit/config.toml`, the system shall read the `theme`, `animation` and `timezone` settings from it, with precedence environment > file > default. A missing, unreadable or malformed file shall yield defaults rather than preventing startup. (Added 2026-07-18. Partially addresses backlog B1; the remaining `try-rs` config keys are still unimplemented.) (Added 2026-07-18.)
- **OF5.** Where `TRY_BACKGROUND` or `TRY_ANIMATION` is set, the system shall render the named animation behind the selector, defaulting to a drifting colour fog and accepting an opt-out. The animation shall be selectable independently of the theme, deriving its palette from whichever theme is active. (Amended 2026-07-18: one effect became a family of five.) The background shall be skipped entirely whenever the framework's motion setting is off. (Added 2026-07-18.)

---

## 6. Unwanted-behaviour requirements

- **UN1.** If `TRY_PATH` resolves to a location that cannot be created or is not writable by the current user, then the system shall fail on startup with exit code `2` and a single stderr line naming the path and the underlying error.
- **UN2.** If a try with the requested slug and today's date already exists, then the system shall re-use that directory and emit no error.
- **UN3.** If `tryit clone` is given a URL that git rejects, then the system shall leave the tries path untouched and propagate git's exit code.
- **UN4.** If the controlling terminal is not a TTY, then the system shall refuse to open the selector; if invoked without a positional slug it shall exit with code `64`; if invoked with one it shall behave like `tryit <slug>` without the selector.
- **UN5.** If `git` is not on the user's `PATH`, then `tryit clone` and `tryit worktree` shall each fail with exit code `127` and the message `git not found`.
- **UN6.** If the terminal width is below 40 columns or the height is below 10 rows, then the system shall abort the selector with exit code `64` and message `terminal too small (min 40×10)`.
- **UN7.** If `Ctrl-C` is pressed at any point, then the system shall restore the terminal to its original mode before exiting with code `130`.
- **UN8.** If the directory the selector chose no longer exists when the `cd` is about to be emitted, then the system shall suppress the `cd` and report why. (Added 2026-07-18: deletions are deferred until after the selector exits but run before the `cd` is written, so confirming a deletion for the highlighted try made the caller's shell fail its `eval`.)
- **UN10.** If a try being deleted is a linked git worktree, then the system shall unregister it from its parent repository before removing the directory, and shall remove the directory even if that unregistration fails. (Added 2026-07-18: an unconditional `rm -rf` left the worktree in `git worktree list` marked `prunable`, with its admin directory still under `.git/worktrees`. Matches `try-rs`, which branches on the same condition.)
- **UN9.** If an alias named `tryit` already exists in the caller's shell, then the shell function emitted by `tryit init` shall still install. (Added 2026-07-18: zsh expands aliases while *parsing* a function definition, so the definition was a syntax error and the whole `eval` aborted, silently leaving the previous command in place.)

---

## 7. Non-functional requirements

### 7.1 Runtime

- **NF1.** The system shall depend only on `Tachikoma.jl`, `PrecompileTools.jl`, and packages in Julia's standard library for its runtime behaviour; no network calls are made outside `git clone`. (Amended 2026-04-19: was `Term.jl` at initial ratification; superseded by the v0.1 clarification in `specs/001-walking-skeleton/spec.md` §Clarifications. Tachikoma.jl ships an Elm-inspired architecture and built-in headless virtual-terminal testing that the project relies on for NF4. Amended 2026-04-19 again as part of v0.3: `PrecompileTools.jl` added because NF17 requires `@compile_workload`; reconciled here per Constitution §Governance. Amended 2026-07-18: `DocStringExtensions.jl` added, required by NF7. `CommonMark.jl` added 2026-07-18, required by ED20: it is the weak dependency behind Tachikoma's `MarkdownPane`, so the manual is rendered by the same parser that renders it for the web rather than by a hand-rolled substitute. `PackageCompiler.jl` is *not* a runtime dependency — it lives in `build/Project.toml` so that installing the package does not pull in the compiler toolchain.)
- **NF2.** Once its package is precompiled, the system shall reach first-frame render in under 250 ms on a modern x86_64 Linux system. Julia's own startup time is measured separately.
- **NF3.** The system shall render the selector at no less than 30 Hz on a terminal of at least 30×80 characters.
- **NF4.** The system shall run its interactive test suite without a TTY (CI environment) by injecting keypresses through a mock I/O channel rather than raw `stdin`.

### 7.2 Source code style (SciML standards)

- **NF5.** The system shall follow SciML coding standards: type-stable functions, concrete type annotations where it aids dispatch, no globals outside `const`.
- **NF6.** The system's code shall be formatted by `JuliaFormatter.jl` with the `sciml` style, configured via `.JuliaFormatter.toml`.
- **NF7.** Each public function and public type shall carry a docstring generated with `DocStringExtensions` templates (`$(TYPEDSIGNATURES)`, `$(TYPEDFIELDS)`), never a `raw""` string (which blocks template expansion).
- **NF8.** Line length shall be ≤ 92 characters; no trailing whitespace; a final newline on every source file.

### 7.3 Packaging

- **NF9.** The system shall be scaffolded with `PkgTemplates.jl` rather than hand-rolled, with the reference plugin set: `License(MIT)`, `Git(ssh=true, manifest=false)`, `GitHubActions`, `Codecov`, `Documenter{GitHubActions}`, `Dependabot`, `TagBot`, `RegisterAction`, `Formatter(style="sciml")`, `Citation`.
- **NF10.** The system shall be distributed as a registered Julia package `TryIt` and be installable via `Pkg.add("TryIt")`.
- **NF11.** The system shall pin a minimum Julia version `v"1.10"` (current LTS) in `[compat]`, and shall ship a `[compat]` entry for every direct dependency.
- **NF12.** The system shall ship a binary trampoline — either a `PackageCompiler.jl`-built executable or a Julia script with `#!/usr/bin/env julia` — so the `tryit init` shell function can invoke it without an explicit `julia -e` dance.

### 7.4 Testing & quality gates

- **NF13.** The system shall use `TestItemRunner` with `@testitem` blocks, grouped by component (`test/slug/`, `test/selector/`, `test/git/`), and shall include quality tests under `test/Aqua.jl` and `test/JET.jl`.
- **NF14.** The system shall pass `Aqua.test_all(TryIt; stale_deps=true, deps_compat=true, piracies=true, ambiguities=true)` with no broken checks.
- **NF15.** The system shall pass `JET.@test_call` and `JET.@test_opt` on every public API entry point to catch runtime errors and type instabilities statically.
- **NF16.** The system shall provide 100 % line coverage of the slug generator (UB3) and at least 80 % coverage of the rest of the codebase, measured by `Coverage.jl` and reported to Codecov.
- **NF17.** The system shall precompile its hot paths with `PrecompileTools.@compile_workload`, covering the selector cold-start and at least one `tryit clone` invocation.

### 7.5 CI / release automation

- **NF18.** The system shall run CI on GitHub Actions across Linux, macOS, and Windows, on Julia `1.10`, `1` (current stable), and `nightly`, and shall upload coverage to Codecov.
- **NF19.** The system shall auto-tag and create GitHub releases via `TagBot`, with `DOCUMENTER_KEY` set so the stable documentation rebuilds on each release.
- **NF20.** The system shall be registerable through the `Register.yml` workflow dispatched from the GitHub UI, bumping patch / minor / major via input. (Clarified 2026-07-18: `julia-actions/RegisterAction` accepts only `token` and `registrator` — it has no version input — so the workflow performs the bump against `Project.toml` itself and commits it before triggering Registrator.)
- **NF21.** The system shall have dependency updates automated by `Dependabot` (PkgTemplates default since Dec 2025).

### 7.6 Documentation

- **NF22.** The system shall ship `Documenter.jl` docs, built by the workflow generated by `Documenter{GitHubActions}`, deployed to `gh-pages`, with separate `stable` and `dev` versions.
- **NF23.** The system's `README.md` shall display badges for CI status, Codecov coverage, Documenter stable & dev, and Aqua QA.
- **NF24.** The system's docs shall include: a Getting Started page with the shell-integration one-liner, a Reference page auto-generated from docstrings, and a Rationale page explaining the shell-function wrapper design.

---

## 8. Out of scope (explicit non-goals)

- **NG1.** The system shall not manage branches, commits, or remote push within tries. `git` is used only for `clone` and `worktree`; every other git operation is left to the user.
- **NG2.** The system shall not synchronise tries across machines.
- **NG3.** The system shall not hide the underlying filesystem. Tries are plain directories; the user may move, delete, or inspect them with any external tool.
- **NG4.** The system shall not expose its internals as a Julia library API in v1. A later major version may formalise the package API; until then the only supported entry points are the CLI commands.

---

## 9. Reference package layout (produced by PkgTemplates)

```
TryIt.jl/
├── .github/
│   └── workflows/
│       ├── CI.yml              # matrix: {linux, macos, windows} × {1.10, 1, nightly}
│       ├── Documenter.yml      # builds & deploys to gh-pages
│       ├── TagBot.yml
│       ├── Register.yml
│       └── dependabot.yml
├── .JuliaFormatter.toml        # style = "sciml"
├── src/
│   ├── TryIt.jl               # module + exports + @compile_workload
│   ├── slug.jl                 # UB3
│   ├── paths.jl                # UB1, UB2, TRY_PATH / TRY_PROJECTS resolution
│   ├── selector.jl             # SD1–SD3, Tachikoma.jl Elm Model/update/view
│   ├── actions/
│   │   ├── clone.jl            # ED5
│   │   ├── worktree.jl         # ED6
│   │   ├── rename.jl           # ED7
│   │   ├── graduate.jl         # ED8
│   │   └── delete.jl           # ED9–ED10
│   ├── shell_init.jl           # ED13 — emits bash/zsh/fish wrapper
│   └── docstrings.jl           # DocStringExtensions templates
├── test/
│   ├── runtests.jl
│   ├── Project.toml            # Aqua, JET, TestItemRunner only here
│   ├── Aqua.jl
│   ├── JET.jl
│   ├── slug/test_slug.jl
│   ├── selector/test_keys.jl
│   └── git/test_clone.jl
├── docs/
│   ├── make.jl
│   ├── Project.toml
│   └── src/
│       ├── index.md
│       ├── getting-started.md
│       ├── reference.md
│       └── rationale.md
├── Project.toml                # [deps], [compat], no Manifest committed
├── LICENSE                     # MIT
├── CITATION.bib
└── README.md                   # badges + quick-start
```

---

## 10. Release milestones

| Version | Scope (EARS IDs)                                                               |
| ------- | ------------------------------------------------------------------------------ |
| v0.1    | UB1–UB6, ED1–ED4, ED12, ED13, SD1, UN1, UN4, UN7, NF1–NF8, NF13, NF18, NF22 |
| v0.2    | ED5, ED6, ED11, SD3, UN3, UN5, OF2, NF14, NF15, NF23                           |
| v0.3    | ED7–ED10, SD2, OF1, OF3, UN6, NF16, NF17, NF24                                |
| v0.4    | ED14–ED18, SD4–SD6, OF4, OF5, UN8, UN9, NF12                                   |
| v1.0    | NF9–NF11, NF19–NF21 + polish pass and General-registry registration          |

---

## 11. Pre-publish checklist (gate for v1.0)

- [ ] `Pkg.test()` green locally and on CI (3 OS × 3 Julia versions).
- [ ] `Aqua.test_all` passes with no `broken=true` annotations.
- [ ] JET `@test_call` / `@test_opt` green on every public entry point.
- [ ] `docs/make.jl` builds locally with zero dead cross-refs.
- [ ] `DOCUMENTER_KEY` configured on the GitHub repo (else stable docs silently fail).
- [ ] `JuliaTagBot` GitHub App installed on the repo / org.
- [ ] `Project.toml` has `[compat]` entries for **every** dep including `julia`.
- [ ] Version = `0.1.0` at first registration (SemVer pre-1.0).
- [ ] README badges present: CI, Codecov, Documenter stable+dev, Aqua QA.
- [ ] `LICENSE` matches `Project.toml` metadata (MIT).

---

## 12. Backlog — gaps against `try-rs` (not yet scheduled)

Identified 2026-07-18 by auditing `tassiovirginio/try-rs`. These are
recorded rather than specified: they carry `B`-prefixed handles and
are deliberately written in a form the traceability test does not
match, so unbuilt work cannot masquerade as a requirement. Promote a
row to a real requirement ID when it is picked up.

| ID  | Gap | Notes |
| --- | --- | ----- |
| B1  | `config.toml` layer | try-rs has 12 keys with XDG discovery and CLI > env > file > defaults precedence. We are env-var only. Most other rows depend on this. |
| B2  | Multiple tries paths + tab bar | Comma-separated roots, `←`/`→` switches. Our spec assumes exactly one root throughout. |
| B3  | `Alt+M` move between tries paths | Distinct from graduate (ED8), which targets the projects path. |
| B4  | `Ctrl+E` open in editor | Emits `<editor> '<path>'` *instead of* `cd`. OF1 only spawns an editor after `cd`, with no per-selection choice. |
| B5  | Fuzzy matching with ranking | try-rs scores with `SkimMatcherV2`, sorts by score, and highlights matched characters. ED2 is unranked substring. A behavioural divergence, not just a missing extra. |
| B6  | Inline (non-fullscreen) picker | `--inline-picker`, rendering in place rather than the alternate screen. |
| B7  | Multi-shell setup and completions | `--setup <shell>` and `--completions` for bash/zsh/fish/PowerShell/Nushell, plus dynamic directory completion. ED13 emits one POSIX function and has no Windows story. |
| B8  | Panel visibility toggles | `Alt+P` at runtime plus `--show-*/--hide-*` flags and `right_panel_width`. SD4 fixes the layout. |
| B9  | Transparent background | try-rs defaults to inheriting the terminal background, toggled with `Space` in the theme picker. OF5 has no transparency notion. |
| B10 | Persist theme choice from the TUI | try-rs prompts to save after `Ctrl+T` and writes the config file. ED15 is runtime-only. |
| B11 | Shallow clone by default | try-rs uses `--depth 1` with `--full-clone` to opt out, and always `--recurse-submodules`. ED5 specifies neither. |
| B12 | Branch-aware worktree creation | try-rs probes `git show-ref` and uses `worktree add -b` only for a new branch. ED6 does not distinguish. |
| B13 | General status-message channel | try-rs sets a status line on every notable operation, not only failures. The UB5 amendment covers errors only. |
| B14 | Broader packaging | crates.io, AUR, an APT repository, `.deb`, Homebrew, Nix flake. NF12 covers only a PackageCompiler trampoline. |

Two try-rs keys conflict with ours and are deliberately not adopted:
`Ctrl+N` (move down there, create a try here, ED11) and `Ctrl+J` /
`Ctrl+K` navigation. `Ctrl+G` graduate, `?` help (ED17) and `F9`
recording (ED18) have no try-rs counterpart.
