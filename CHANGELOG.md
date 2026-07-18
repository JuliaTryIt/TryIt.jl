# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Requirements traceability page documenting which EARS requirements
  are met, which have drifted, and what remains for v1.0.
- Drift guards in the test suite: every requirement ID in `spec.md`
  must be referenced from `src/` or `test/` or carry a written
  exemption, and every documented key binding must exist in the code
  and appear in the `?` overlay. Both were verified to fail on
  injected drift, not just to pass.

- The selector owns its keymap (`default_bindings=false`), matching
  `try-rs`: `Ctrl+T` theme picker, `Ctrl+A` About, `Ctrl+R` rename,
  `?` key-binding overlay. Creating a dated placeholder try moves
  from `Ctrl+T` to `Ctrl+N`. Tachikoma's settings overlay and
  clipboard copy are given up in the trade — its bindings are
  all-or-nothing apart from recording.
- Theme picker applying each theme live as the cursor moves, with
  `Esc` restoring the theme active when it opened.
- Help bar restyled after `try-rs` and made responsive: `StatusBar`
  clips rather than wraps, so a fixed list silently dropped
  `Esc Quit` at 100 columns and cut mid-word at 80.

- Open-or-create prompt. Filtering matches substrings of
  `"<date> <slug>"`, so typing the beginning of an existing name
  always opened that try and left no way to create the shorter name —
  with `2026-07-18-help-me` present, `help` was uncreatable, and
  since the date is in the haystack, `2026` matched everything from
  the year. `Enter` on an ambiguous filter now asks whether to open
  the highlighted try or create one named after the typed text.
  Opening is the default. Typing a full existing name still opens it
  in a single keystroke. This is the same gap as `try-rs` issue #44.

- Multi-panel selector TUI, modelled on the reference `try-rs`
  interface: bordered `Search/New`, `Folders`, `Disk`, `Preview`, and
  `Legends` panels, plus a key-binding help bar. The folder list now
  shows a project-type badge and a right-aligned `DDd HHh MMm` age
  column.
- Project-type detection (`detect_badges`) for Rust, Julia, Python,
  Go, Maven, Flutter, and Mise, plus lockfile, git repository, linked
  worktree, and submodule markers, each with its own legend colour.
- Preview panel listing the selected try's contents, directories
  first.
- `F9` toggles `.tach` screen recording, replacing the framework
  binding that collided with rename.
- Theme selection via `TRY_THEME`, covering all 24 Tachikoma themes.
  `Ctrl-\` still opens the in-app picker, which wins for the rest of
  the session. An unknown name is ignored rather than fatal.
- Animated background, on by default, configured with
  `TRY_BACKGROUND` (`wash`, `dotwave`, `phylo`, `clado`, or an
  opt-out spelling) and `TRY_BACKGROUND_PRESET`. Skipped when
  Tachikoma's global motion switch is off.
- `WashBackground`, the default: an animated colour gradient derived
  from the active theme. Tachikoma's own backgrounds draw braille in
  the *foreground*, which shows through panel interiors as noise;
  blanking the interiors erases them entirely, since no background
  colour sits underneath. The wash paints cell background colours
  instead, so text over it stays legible and panels can be blanked
  safely. The glyph backgrounds remain available, rendered full-bleed.
- Disk panel showing used and free space for the filesystem holding
  the tries root. Degrades to "unavailable" on Windows, where `df`
  does not exist.

- Standalone application build via
  [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl).
  `julia --project=build build/build.jl` produces a self-contained
  `tryit` executable in `build/tryit-app/` that bundles its own Julia
  runtime, removing interpreter startup cost per invocation.
- `julia_main` entry point (`Cint`, zero-argument) as required by
  PackageCompiler's `create_app`, with `_app_main` as the testable
  seam that accepts explicit arguments.
- `tryit init` now detects whether it is running as a compiled app
  and emits a shell function that calls the executable directly,
  instead of booting `julia` against the `@TryIt` shared environment.
- Documentation page covering the standalone app build.
- This changelog.

### Fixed

- Deleting the try under the cursor emitted a `cd` into the removed
  directory, so the caller's shell failed with
  `(eval):cd:1: no such file or directory`. Deletes run after the
  selector picks its target but before the `cd` is written, so the
  target could already be gone. The `cd` is now suppressed with a
  diagnostic when its target is no longer a directory — which also
  covers a try removed by another process while the selector is open.

- Building the standalone app created warm-up directories inside the
  building user's *real* tries root. `build/precompile_app.jl` drove
  the direct form, which takes no path argument and so resolved
  `TriesPath()` to the default rather than to the script's temporary
  directory. `TRY_PATH` is now set for the whole workload.

- `tryit init` could not install its shell function for users with an
  existing `alias tryit=...` (common when migrating from `try-cli` or
  `try-rs`). zsh expands aliases while *parsing* a function
  definition, so the definition was a syntax error and the whole
  `eval` aborted, silently leaving the old command in place — the
  selector appeared to ignore selections because a different `tryit`
  was running. The snippet now drops any conflicting alias and
  defines the function through a nested `eval`, which is parsed only
  after the `unalias` has executed. Emitting the `unalias` on a
  preceding line is not sufficient: zsh parses the entire `eval`
  string before running any of it.
- Switching animations off with `Ctrl-A` did not stop the background
  until the next launch: the motion setting was read once at
  `open_session` and cached. The selector now re-checks it every
  frame, so a reduced-motion preference takes effect immediately.
- A `.tach` recording left running when the selector closed was
  silently discarded — `stop_recording!` performs the write, and
  selecting a try, quitting, or aborting never passed through the F9
  toggle. The recording is now flushed from `cleanup!`, which covers
  every exit path. Recordings are written to the tries root rather
  than the process's working directory.
- Ctrl-R opened Tachikoma's `.tach` screen recorder instead of
  renaming. The framework claims Ctrl+R in its default bindings and
  intercepts it before `update!` runs. Recording is now disabled for
  the selector and re-offered on `F9`, with a `● REC` indicator in
  the help bar. See `upstream-bugs.md`.
- `TriesPath` now resolves symlinks via `realpath` after ensuring the
  root exists. Previously it used only `abspath(normpath(...))`, so on
  macOS — where `/var` and `/tmp` are symlinks into `/private` — two
  spellings of the same root compared unequal, which could mislead the
  graduate and rename collision checks. This also fixes three
  pre-existing test failures that were latent on Linux CI.

- Documentation build: `docs/make.jl` failed on an unresolvable
  `@ref` to `emit_shell_init`, which was referenced from a docstring
  but never included in the manual. It now has an entry on the
  Reference page.

### Changed

- The default tries root moved from `$HOME/src/tries` to
  `$HOME/work/tries`, following `try-rs`. The two upstreams disagree:
  `try-cli` documents `~/src/tries`, `try-rs` documents and
  implements `~/work/tries`. `TRY_PATH` overrides it either way.
  **Existing users with tries under `~/src/tries` should set
  `TRY_PATH=~/src/tries` or move the directory.**

- Exit statuses moved from loose `const EXIT_*` integers to a
  module-scoped enum, `ExitCode.T`, per the project's Julia enum
  convention. Call sites read `ExitCode.USAGE` instead of
  `EXIT_USAGE`, and the names no longer leak into `TryIt`. The
  numeric values are unchanged — they are the process wire format.
  The CLI dispatchers narrow to `::Int` rather than `::ExitCode.T`,
  because `tryit clone` propagates git's own exit code verbatim
  (FR-029) and that is an arbitrary integer outside the enum; the
  enum names only the statuses TryIt itself originates.
- README: removed links to `ROADMAP.md`, `SPEC.md`, and
  `specs/001-walking-skeleton/quickstart.md`, none of which are
  present in the repository; added `try-rs` alongside `try-cli` as
  acknowledged inspiration, and documented the configuration
  environment variables.
- Documentation: dropped the remaining dead links to `SPEC.md` and
  `specs/` from `index.md`, `rationale.md`, and the module docstring.

[Unreleased]: https://github.com/s-celles/TryIt.jl/compare/v0.1.0...HEAD
