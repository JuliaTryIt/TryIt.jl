# Getting Started

## Install

TryIt is not yet on the General registry (v0.4 work). For now:

```julia
julia --startup-file=no --project=@TryIt -e '
  using Pkg
  Pkg.develop(path="path/to/TryIt.jl")
  Pkg.precompile()
'
```

## Wire the shell function

Add the following line to your `~/.bashrc` or `~/.zshrc`:

```sh
eval "$(julia --startup-file=no --project=@TryIt -e 'using TryIt; TryIt.main(["init"])')"
```

Open a fresh shell — `tryit` is now available as a function that
changes your working directory when it outputs a `cd` command.

## Daily workflow

### Create a scratch workspace

Run `tryit` with no arguments to open the selector. Type a name
and press Enter — if nothing matches, a dated directory
`YYYY-MM-DD-<slug>` is created and you land in it.

### Reopen an existing try

Same entry point: `tryit` opens the selector, type a substring of
the slug or the date, press Enter, and you're back inside.

### Cloning and worktrees *(v0.2)*

TryIt shells out to `git` for two common workflows:

```sh
# Clone a repository into a fresh try.
tryit clone https://github.com/JuliaLang/Example.jl.git

# Or pick a custom name.
tryit clone https://github.com/JuliaLang/Example.jl.git spike-1

# From inside any real git repository, spin up a worktree for a
# throwaway branch without stashing or branch-switching.
cd ~/path/to/some/repo
tryit worktree feature-spike
```

Both commands emit a `cd` command so your shell is repositioned
into the new try automatically.

**Exit codes** you may encounter:

| Code  | Meaning |
|-------|---------|
| `0`   | Success; `cd` emitted. |
| `2`   | `TRY_PATH` is not writable. |
| `64`  | Usage error (empty slug, destination exists, not inside a git repo). |
| `127` | `git` is not on your `PATH`. |
| other | Propagated verbatim from `git` when it rejects a URL. |

### Keybindings inside the selector *(v0.2)*

| Key | Action |
|-----|--------|
| Type chars | Case-insensitive substring filter. |
| ↑ / ↓ | Move cursor. |
| Page-Up / Page-Down | Jump by one viewport height. |
| Enter | `cd` into the highlighted try (or create today's `YYYY-MM-DD-<filter>` if nothing matches). |
| Esc | Exit without changing directory. |
| Ctrl-T | Create an empty placeholder try and stay in the selector. |
| Ctrl-C | Abort; terminal is restored. |

### Configuration

| Variable | Purpose | Default |
|----------|---------|---------|
| `TRY_PATH` | Directory under which tries live. | `$HOME/work/tries` |

More knobs (`TRY_EDITOR`, `TRY_PROJECTS`, `.try-template`) land in
v0.3.
