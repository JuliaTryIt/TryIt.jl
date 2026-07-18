# TryIt.jl

An ephemeral-workspace manager for Julia developers. `tryit` spins
up a dated scratch directory, drops you into it, and lets you
clone repositories or take a `git worktree` of the repo you're in
without polluting your working tree.

TryIt.jl is a functional mirror of
[`try-cli`](https://github.com/tobi/try-cli) (Ruby, by Tobi Lütke)
and [`try-rs`](https://github.com/tassiovirginio/try-rs) (Rust), with a TUI built on [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl).

## Contents

- [Getting Started](getting-started.md) — install, shell
  integration, daily workflow (`tryit`, `tryit clone`, `tryit worktree`).
- [Selector Interface](interface.md) — the panel layout, badges,
  and key bindings.
- [Standalone App](standalone-app.md) — build a self-contained
  `tryit` executable with PackageCompiler.
- [Reference](reference.md) — auto-generated API documentation.
