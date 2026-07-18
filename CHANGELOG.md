# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

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

- README: removed links to `ROADMAP.md`, `SPEC.md`, and
  `specs/001-walking-skeleton/quickstart.md`, none of which are
  present in the repository; added `try-rs` alongside `try-cli` as
  acknowledged inspiration, and documented the configuration
  environment variables.
- Documentation: dropped the remaining dead links to `SPEC.md` and
  `specs/` from `index.md`, `rationale.md`, and the module docstring.

[Unreleased]: https://github.com/s-celles/TryIt.jl/compare/v0.1.0...HEAD
