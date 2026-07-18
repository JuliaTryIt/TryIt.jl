"""
Whether this process is a compiled, standalone `tryit` app.

Set by [`_app_main`](@ref) — which only ever runs as the entry point
of a [PackageCompiler](https://github.com/JuliaLang/PackageCompiler.jl)
app — and read by [`emit_shell_init`](@ref) to decide which form of
the `tryit` shell function to emit.

A flag beats sniffing the environment: `Base.julia_cmd()` and
`Sys.BINDIR` both still resolve inside a bundled app, so there is no
reliable negative test for "am I interpreted?".
"""
const _APP_MODE = Ref(false)

"""
Compiled-app entry point, split from [`julia_main`](@ref) so it can
be driven with explicit `args` under test rather than through the
process-global `ARGS`.

Returns the exit code as `Cint` instead of calling `exit`, because
PackageCompiler's launcher does the exiting.
"""
function _app_main(args::AbstractVector{<:AbstractString})::Cint
    _APP_MODE[] = true
    return Cint(cli_main(args))
end

"""
PackageCompiler entry point.

`create_app` requires exactly this name, arity, and return type; see
[`_app_main`](@ref) for the testable form and [`main`](@ref) for the
interpreted equivalent.
"""
julia_main()::Cint = _app_main(ARGS)

"""
Name of the compiled executable, as declared in `build/build.jl`'s
`executables` mapping. Kept in one place so the two must be changed
together.
"""
const APP_EXECUTABLE_NAME = "tryit"

"""
Absolute path to the running `tryit` executable.

Deliberately *not* `Base.julia_cmd()`: a PackageCompiler bundle ships
a `bin/julia` launcher next to `bin/tryit`, and `julia_cmd` reports
the former. Emitting that into the shell function would drop the user
into a REPL instead of running the CLI. `Sys.BINDIR` points at the
bundle's `bin/`, so we join the known executable name onto it.
"""
_app_binary() = joinpath(Sys.BINDIR, APP_EXECUTABLE_NAME)
