# Rationale

Why `TryIt` looks the way it does. Short prose explainer for
contributors, covering the non-obvious design calls.

## The `chdir` problem

A child process cannot change its parent's current working
directory. When you run `cd /tmp` in bash, bash changes its own
CWD. When you run `some-program cd-me /tmp`, `some-program`'s
`chdir(2)` affects only `some-program` — bash's CWD is
unaffected.

This is a hard Unix invariant. Every shell navigation tool has to
work around it somehow: `z`, `autojump`, `fasd`, `zoxide`, and the
Ruby `try-cli` all converge on the same trick.

## The `eval` trick

The standard answer is to print a shell command on stdout and let
the user's shell `eval` it. Concretely, `TryIt` prints

```text
cd '/home/user/src/tries/2026-04-19-my-idea'
```

and `tryit init`'s shell function wraps the invocation in
`eval "$(...)"`:

```sh
tryit() {
  local __try_cmd
  __try_cmd=$(julia ... -- "$@") || return $?
  [ -n "$__try_cmd" ] && eval "$__try_cmd"
}
```

The `eval` runs in the parent shell's context, so the `cd` actually
moves the user.

## Why stdout is reserved

Because the shell function `eval`s whatever we print, every byte
on stdout matters. A stray `println("hello")` during selector
rendering would become a syntax error — or worse, an executed
command — when the shell tried to `eval` it.

Principle I of the project constitution nails this down: stdout
carries *only* the final `cd` line (or nothing, if the user
cancels). Diagnostics, prompts, progress, error messages — all go
to stderr. The selector's full-screen UI draws through an
alternate-screen buffer, which the TUI library (`Tachikoma.jl`)
sets up and tears down; it never competes with the UB4 channel.

## Why exit codes matter

Shell users often chain invocations:

```sh
tryit "$idea" && code .
```

If `tryit` returns non-zero, the user expects the `&&` branch to be
skipped. We therefore adopt POSIX-like codes:

- `0` — success; a `cd` line was emitted (or the user voluntarily
  cancelled with Esc).
- `2` — permission error (e.g., `TRY_PATH` is not writable).
- `64` — usage error (empty slug, no TTY in a non-TTY context,
  unknown argv).
- `127` — a required external dependency is missing (typically
  `git`).
- `130` — SIGINT received.

Non-zero codes are documented per command, and the test suite
asserts them. Downstream scripts can rely on the distinction
between "the user said no" and "the tool said no".

## Why `git` (the binary), not `LibGit2.jl`

v0.2 added `tryit clone` and `tryit worktree`. We shell out to the
user's installed `git` rather than linking a Julia git library for
three reasons:

1. **Credential forwarding.** The user's SSH agent, Git Credential
   Manager, and hosting-provider PATs are already wired up for the
   `git` binary. Reimplementing that surface in Julia is a
   losing battle.
2. **Worktree semantics.** `git worktree` is a first-class CLI
   feature and stable across git versions; libgit2's equivalent
   has trailing edges.
3. **Runtime-dep budget.** SPEC NF1 pins the runtime graph to
   `Tachikoma.jl`, `PrecompileTools.jl`, and stdlib. A git library
   would mean either a heavy binary (libgit2) or a broader Julia
   dep graph — neither justified by the thin surface we actually
   need.

Because `git` is an external binary, the FR-030 / UN5 contract
("missing git → exit 127 with the canonical error line") protects
scripted users from mysterious failures.

## Why Tachikoma.jl (not Term.jl)

v0.1 briefly considered Term.jl before swapping to Tachikoma.jl.
Two properties mattered:

- **Elm-inspired Model/update/view.** Our `SelectorSession` is a
  pure-data `Model` we mutate via `update!(model, event)`. This
  maps cleanly onto property-based tests (feed scripted key
  events, inspect the resulting `Model` state) without needing a
  real TTY at test time.
- **Built-in virtual-terminal testing.** Tachikoma ships a
  headless backend. For `TryIt`'s contract (stdout reserved for
  the `cd` line, all rendering in the alt-screen), this means CI
  tests can exercise the full selector loop without stdin/stdout
  gymnastics.

## Why precompile

SPEC NF17 mandates `PrecompileTools.@compile_workload` — without
it, a fresh shell's first `tryit` invocation pays the full Julia
module-inference cost on top of whatever work the user actually
asked for. Our workload warms the pure paths (slug, TriesPath,
`SelectorSession` construction + one `update!`). We deliberately
do **not** precompile `clone_into` or `worktree_at` — they spawn
`git`, which is brittle inside precompile sandboxes.

PrecompileTools.jl is the one runtime-dep addition beyond
Tachikoma.jl, reconciled into SPEC NF1 in the v0.3 change set.
