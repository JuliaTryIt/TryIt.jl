# Standalone App

TryIt.jl can be compiled into a self-contained `tryit` executable
using [PackageCompiler.jl](https://github.com/JuliaLang/PackageCompiler.jl).
The result bundles its own Julia runtime, so the target machine does
not need Julia installed, and each `tryit` invocation skips
interpreter startup entirely.

This matters more here than for a typical package: `tryit` runs on
every directory change, interactively, so a per-call startup penalty
is felt directly.

## Building

From the repository root:

```sh
julia --startup-file=no --project=build build/build.jl
```

The bundle lands in `build/tryit-app/`, with the executable at
`build/tryit-app/bin/tryit`. Pass a different destination as the
first argument:

```sh
julia --startup-file=no --project=build build/build.jl /opt/tryit
```

The destination is always replaced (`force=true`).

!!! note
    PackageCompiler is declared in `build/Project.toml`, not in the
    package's own `[deps]`. Installing TryIt.jl as a library never
    pulls in the compiler toolchain.

## Shell integration

Identical to the interpreted install, but invoking the executable:

```sh
eval "$(/path/to/tryit-app/bin/tryit init)"
```

`tryit init` detects at runtime which form it is running as and emits
the matching shell function — one that calls the binary directly for
a compiled app, or one that boots `julia --project=@TryIt` otherwise.
The rest of the emitted function is identical in both cases, so the
`cd`-on-stdout contract is unchanged.

Add the `eval` line to your `.bashrc` or `.zshrc` to make it
permanent.

## Entry point

`create_app` requires a zero-argument function named `julia_main`
returning `Cint`. TryIt.jl splits this in two so the behaviour stays
testable:

```@docs
TryIt.julia_main
TryIt._app_main
TryIt._APP_MODE
```

`julia_main` reads the process-global `ARGS` and delegates to
`_app_main`, which takes arguments explicitly — the test suite drives
`_app_main` directly rather than mutating `ARGS`.

Note that `_app_main` returns the exit code rather than calling
`exit`, because PackageCompiler's launcher performs the exit itself.
This is the one behavioural difference from [`main`](@ref
TryIt.main), which does call `exit`.

## Caveats

- **Size.** The bundle vendors the Julia runtime and is on the order
  of a few hundred megabytes. It is deliberately git-ignored.
- **Platform-specific.** The bundle runs only on the OS and
  architecture it was built on. Build once per target platform.
- **Rebuild after changes.** The executable is a snapshot; edits to
  `src/` require a rebuild to take effect.
