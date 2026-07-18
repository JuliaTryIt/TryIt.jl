# TryIt.jl

[![CI](https://github.com/s-celles/TryIt.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/s-celles/TryIt.jl/actions/workflows/CI.yml)
[![Codecov](https://codecov.io/gh/s-celles/TryIt.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/s-celles/TryIt.jl)
[![Documenter (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://s-celles.github.io/TryIt.jl/stable)
[![Documenter (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://s-celles.github.io/TryIt.jl/dev)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

A Julia ephemeral-workspace manager for developers — a `tryit` command
that spins up, filters, and graduates dated scratch directories from
your terminal.

## Inspiration

TryIt.jl is a functional mirror of two prior tools, with a TUI built
on [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl):

- [`try-cli`](https://github.com/tobi/try-cli) — the original Ruby
  implementation by Tobi Lütke, also on
  [RubyGems](https://rubygems.org/gems/try-cli).
- [`try-rs`](https://github.com/tassiovirginio/try-rs) — a Rust port
  and re-imagination with a modern TUI.

All three share the same model: date-prefixed directories under a
tries root, an interactive fuzzy selector biased toward recently
touched entries, and a shell function that `eval`s a `cd` emitted on
stdout.

## Status

Pre-stable (0.x). The public surface is intentionally minimal — the
only exported entry point is `main`.

## Install

### As a Julia package (development)

```sh
julia --startup-file=no --project=@TryIt -e 'using Pkg; Pkg.develop(path="."); Pkg.precompile()'
```

Then wire the shell function into your `.bashrc` / `.zshrc`:

```sh
eval "$(julia --startup-file=no --project=@TryIt -e 'using TryIt; TryIt.main(["init"])')"
```

### As a standalone app

Build a self-contained `tryit` executable that carries its own Julia
runtime — no `julia` required on the target machine, and no
interpreter startup cost per invocation:

```sh
julia --startup-file=no --project=build build/build.jl
```

The bundle lands in `build/tryit-app/`, with the executable at
`build/tryit-app/bin/tryit`. Wire it up the same way:

```sh
eval "$(/path/to/build/tryit-app/bin/tryit init)"
```

`tryit init` detects which form it is running as and emits the
matching shell function, so the same command works for both.

## Configuration

| Variable         | Meaning                                           |
| ---------------- | ------------------------------------------------- |
| `TRY_PATH`     | Tries root (default`$HOME/src/tries`)           |
| `TRY_PROJECTS` | Graduation target (default`dirname($TRY_PATH)`) |
| `TRY_EDITOR`   | Editor launched on a try                          |
| `TRY_TEMPLATE` | Directory copied into each new try                |
| `TRY_THEME`    | Startup theme, any of 24 (`Ctrl-\` picks live)    |
| `TRY_BACKGROUND` | Animated background: `wash` (default), `dotwave`, `phylo`, `clado`, `off` |
| `TRY_BACKGROUND_PRESET` | Variant index for the glyph backgrounds |

## Documentation

Full walkthrough, key bindings, and API reference:
[stable](https://s-celles.github.io/TryIt.jl/stable) ·
[dev](https://s-celles.github.io/TryIt.jl/dev).

## License

MIT — see [`LICENSE`](LICENSE).
