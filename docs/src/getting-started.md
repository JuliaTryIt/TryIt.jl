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


## Updating a development install

The shell function runs against the `@TryIt` shared environment. That
environment keeps its own `Manifest.toml`, which is *not* updated when
you pull a commit that changes the package's dependencies — so `tryit`
fails on the next invocation with:

```text
ERROR: Package TryIt does not have CommonMark in its dependencies
```

Re-resolve the shared environment after any dependency change:

```sh
julia --startup-file=no --project=@TryIt -e 'using Pkg; Pkg.resolve(); Pkg.precompile()'
```

The same applies to `docs/`, which has its own manifest.

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

### Fetching a single file

Not everything worth trying out is a repository. A snippet linked
from a forum post, a gist, a script someone sent you — `fetch`
downloads one file into a fresh try:

```sh
# The file keeps its name; the try is named after it.
tryit fetch https://example.com/snippets/benchmark.jl

# Or pick a custom name.
tryit fetch https://example.com/snippets/benchmark.jl perf-spike
```

The resource is stored **verbatim**. Archives are not extracted —
you get `archive.tar.gz` sitting in the try, not its contents.

#### How a bare URL is routed

`tryit <url>` picks between `clone` and `fetch` for you. Extension
alone cannot decide this in Julia, because the ecosystem names
repositories `Foo.jl` — so `github.com/s-celles/PluginGuard.jl` and
`cdn.example.com/3X/b/3/<hash>.jl` share a suffix while needing
opposite treatment. The rule looks at the whole URL instead:

| URL | Routed to |
|-----|-----------|
| `git@host:owner/repo`, `ssh://…`, `git://…` | `clone` |
| anything ending in `.git` | `clone` |
| `github.com` / `gitlab.com` / `codeberg.org` / `bitbucket.org` / `git.sr.ht` with an `owner/repo` path | `clone` |
| any other `http(s)` URL | `fetch` |

Two cases are worth knowing about. A **self-hosted forge** is routed
to `fetch` unless its URL ends in `.git`. And a **deep forge URL**
like `github.com/owner/repo/blob/main/file.jl` is routed to `fetch`,
which downloads the HTML page rather than the file it displays — use
the `raw.githubusercontent.com` link, or say `tryit clone` /
`tryit fetch` explicitly. Both keywords always override the guess.

**Exit codes** you may encounter:

| Code  | Meaning |
|-------|---------|
| `0`   | Success; `cd` emitted. |
| `1`   | A `fetch` failed: transport error, non-success status, or a response over 100 MiB. |
| `2`   | `TRY_PATH` is not writable. |
| `64`  | Usage error (empty slug, destination exists, not inside a git repo). |
| `127` | `git` is not on your `PATH`. |
| other | Propagated verbatim from `git` when it rejects a URL. |

A failed `fetch` leaves the tries path exactly as it found it: the
download lands outside it and is moved in only once complete, so
there is no half-written file in a try you are about to `cd` into.

### Optional: warn me about untrusted code

`clone` and `fetch` both take an arbitrary URL and leave its
contents in a directory you are about to `cd` into. TryIt never
executes any of it — but you might, and it cannot tell you anything
about what you just downloaded on its own.

Install [PluginGuard.jl](https://github.com/s-celles/PluginGuard.jl)
alongside TryIt and a package extension activates automatically:

```julia
pkg> add https://github.com/s-celles/PluginGuard.jl
```

From then on, every `clone` and `fetch` is statically scanned before
the `cd` is emitted, and high-severity findings are reported:

```
tryit: trust: …/photoabsorption.jl:74: Dynamic symbol resolution (hides real function names via getfield on Base)
tryit: trust: advisory only — 2 high-severity findings; nothing has been executed
```

Three things this deliberately does **not** do:

- It does not block. The `cd` is still emitted and the exit status is
  still `0`. A false positive stranding a legitimate download behind
  a scanner you cannot override would be worse than the warning is
  good.
- It does not execute anything, including to analyse it. PluginGuard's
  scanner reads source as text and never `include`s, `eval`s or
  imports what it inspects.
- It does not make anything safe. It informs you before *you* run
  something. Nothing more.

Without PluginGuard installed, both commands behave exactly as
before — no diagnostic, no added latency, and TryIt does not depend
on it.

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

| Variable                | Purpose                                                                | Default                               |
|-------------------------|------------------------------------------------------------------------|---------------------------------------|
| `TRY_PATH`              | Directory under which tries live.                                      | `$HOME/work/tries`                    |
| `TRY_PROJECTS`          | Target directory for graduation.                                       | `dirname($TRY_PATH)`                  |
| `TRY_EDITOR`            | Editor launched when opening a try.                                    |                                       |
| `TRY_TEMPLATE`          | Directory copied as a template into each new try.                      |                                       |
| `TRY_THEME`             | Startup theme.                                                         |                                       |
| `TRY_BACKGROUND`        | Animated background (`fog`, `wash`, `dotwave`, `phylo`, `clado`, `off`).| `fog`                                 |
| `TRY_BACKGROUND_PRESET` | Variant index for glyph backgrounds.                                   |                                       |
| `TRY_ANIMATION`         | Alias for `TRY_BACKGROUND`.                                            |                                       |
| `TRY_CONFIG`            | Configuration file path.                                               | `~/.config/tryit/config.toml`         |
| `TRY_FPS`               | Frame rate for the selector.                                           | `60`                                  |
| `TRY_SHOW_FPS`          | Show a frames-per-second readout.                                      |                                       |
| `TRY_TIMEZONE`          | Date zone: `local` or `utc`.                                           | `local`                               |
| `NO_COLOR`              | Disables colored output.                                               |                                       |

The tries root, theme, animation, and other settings can also be set in the configuration file:

```toml
# ~/.config/tryit/config.toml
tries_path = "~/src/tries"
theme = "dracula"
animation = "plasma"
timezone = "local"
fps = 60
show_fps = false
```

Resolution is environment, then file, then default — so `TRY_PATH` is
still available for a one-off override. A leading `~` is expanded,
matching the spelling `try-rs` uses in its own config, so pointing
both tools at one root is a copy of the same line.
