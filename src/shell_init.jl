"""
Write the POSIX-shell `tryit` function definition to `io`.

The emitted text, when sourced by bash (≥ 4.0) or zsh (≥ 5.0), sets
up a function that invokes the Julia CLI and `eval`s its stdout so
`cd` actually changes the caller's working directory.

`positional`, when non-`nothing`, is hard-coded into the function
as the tries root. When `nothing`, the function resolves the root
from `\$TRY_PATH` at call time (with `\$HOME/src/tries` as the
fallback).

When running as a compiled PackageCompiler app (see
[`_APP_MODE`](@ref)), the emitted function calls the `tryit`
executable directly instead of booting `julia`.

EARS coverage: UB4, ED13.
"""
function emit_shell_init(
        io::IO,
        positional::Union{Nothing, AbstractString}=nothing
)
    tries = if positional === nothing
        # Keep this as a shell-syntax literal — resolved by the shell
        # at call time, not by Julia at `tryit init` time.
        raw"${TRY_PATH:-$HOME/src/tries}"
    else
        _shell_quote(String(positional))
    end

    # A compiled app bundles its own runtime, so it is invoked
    # directly; the interpreted form has to boot julia against the
    # `@TryIt` shared environment. Everything else is identical.
    exe, invocation, missing_msg = if _APP_MODE[]
        binary = _app_binary()
        (binary, _shell_quote(binary), "tryit: tryit binary not found")
    else
        julia = _julia_binary()
        (
            julia,
            string(
                _shell_quote(julia),
                " --startup-file=no --project=@TryIt",
                " -e 'using TryIt; TryIt.main(ARGS)' --"
            ),
            "tryit: julia not found"
        )
    end

    # NB: we deliberately emit a plain POSIX function (no `function`
    # keyword) so bash and zsh both accept it unchanged.
    print(
        io,
        """
        tryit() {
          if ! command -v $(_shell_quote(exe)) >/dev/null 2>&1; then
            echo "$(missing_msg)" >&2
            return 127
          fi
          local __try_cmd
          __try_cmd=\$(TRY_PATH=$(tries) $(invocation) "\$@") || return \$?
          [ -n "\$__try_cmd" ] && eval "\$__try_cmd"
        }
        """
    )
    return nothing
end

"""
Absolute path to the `julia` executable running this process.

We bake this into the emitted shell function so subsequent `tryit`
invocations use the same Julia binary the user had on PATH when
they ran `tryit init`.
"""
function _julia_binary()
    exe = Base.julia_cmd().exec[1]
    return String(exe)
end

"""
Quote `s` for inclusion in POSIX shell — single-quote, with any
literal single quotes escaped as `'\\''`.
"""
function _shell_quote(s::AbstractString)
    escaped = replace(s, "'" => "'\\''")
    return string("'", escaped, "'")
end
