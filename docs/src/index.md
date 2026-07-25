# TryIt.jl

![TryIt.jl Banner](assets/banner.png)
An ephemeral-workspace manager for Julia developers. `tryit` spins
up a dated scratch directory, drops you into it, and lets you
clone repositories or take a `git worktree` of the repo you're in
without polluting your working tree.

TryIt.jl is a functional mirror of Tobi Lütke's
[`try`](https://github.com/tobi/try) — also reimplemented in C as
[`tobi/try-cli`](https://github.com/tobi/try-cli) and in Rust as
[`try-rs`](https://github.com/tassiovirginio/try-rs) — with a TUI
built on [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl).

## Contents

- [Getting Started](getting-started.md) — install, shell
  integration, daily workflow (`tryit`, `tryit clone`, `tryit worktree`).
- [Selector Interface](interface.md) — the panel layout, badges,
  and key bindings.
- [Standalone App](standalone-app.md) — build a self-contained
  `tryit` executable with PackageCompiler.
- [Reference](reference.md) — auto-generated API documentation.
- [Development](development.md) — gates, drift guards, and the
  environments a dependency change breaks.
- [Requirements](requirements.md) — EARS traceability and the path
  to v1.0.
