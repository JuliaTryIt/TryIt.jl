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

    definition = _shell_function_text(exe, invocation, missing_msg, tries)

    # Users migrating from try-cli or try-rs commonly have an
    # `alias tryit=...` in their rc, and zsh expands aliases while
    # *parsing* a function definition — "defining function based on
    # alias" — which aborts the whole `eval` and silently leaves the
    # old command in place.
    #
    # Dropping the alias on a preceding line does not help: zsh parses
    # the entire `eval` string before running any of it, so the alias
    # is still live when the definition is parsed. The definition
    # therefore goes through a nested `eval`, whose argument is parsed
    # only after the `unalias` has actually executed.
    #
    # `|| true` keeps the `unalias` from tripping `set -e` when no
    # alias exists.
    print(
        io,
        """
        unalias tryit 2>/dev/null || true
        eval $(_shell_quote(definition))
        """
    )
    return nothing
end

"""
The `tryit` shell function itself, unwrapped.

Split out from [`emit_shell_init`](@ref) so the function body can be
asserted on directly: the emitted snippet nests this inside a quoted
`eval`, where every single quote becomes `'\\''` and the text is no
longer readable.

A plain POSIX function (no `function` keyword) so bash and zsh both
accept it unchanged.
"""
function _shell_function_text(
        exe::AbstractString,
        invocation::AbstractString,
        missing_msg::AbstractString,
        tries::AbstractString
)
    return """
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
