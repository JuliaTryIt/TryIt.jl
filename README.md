# TryIt.jl

[![CI](https://github.com/s-celles/TryIt.jl/actions/workflows/CI.yml/badge.svg)](https://github.com/s-celles/TryIt.jl/actions/workflows/CI.yml)
[![Codecov](https://codecov.io/gh/s-celles/TryIt.jl/branch/main/graph/badge.svg)](https://codecov.io/gh/s-celles/TryIt.jl)
[![Documenter (stable)](https://img.shields.io/badge/docs-stable-blue.svg)](https://s-celles.github.io/TryIt.jl/stable)
[![Documenter (dev)](https://img.shields.io/badge/docs-dev-blue.svg)](https://s-celles.github.io/TryIt.jl/dev)
[![Aqua QA](https://raw.githubusercontent.com/JuliaTesting/Aqua.jl/master/badge.svg)](https://github.com/JuliaTesting/Aqua.jl)

Ephemeral-workspace manager for Julia developers — a `tryit` command
that spins up, filters, and graduates dated scratch directories from
your terminal.

A functional mirror of the Ruby [`try-cli`](https://rubygems.org/gems/try-cli),
with a TUI built on [Tachikoma.jl](https://github.com/kahliburke/Tachikoma.jl).

## Status

Pre-stable (0.x). See [`ROADMAP.md`](ROADMAP.md) for the milestone
plan and [`SPEC.md`](SPEC.md) for the EARS behavioural spec.

## Install (development)

```sh
julia --startup-file=no --project=@TryIt -e 'using Pkg; Pkg.develop(path="."); Pkg.precompile()'
```

Then wire the shell function into your `.bashrc` / `.zshrc`:

```sh
eval "$(julia --startup-file=no --project=@TryIt -e 'using TryIt; TryIt.main(["init"])')"
```

See [`specs/001-walking-skeleton/quickstart.md`](specs/001-walking-skeleton/quickstart.md)
for the full walkthrough.

## License

MIT — see [`LICENSE`](LICENSE).
