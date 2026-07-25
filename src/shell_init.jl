"""
Write the POSIX-shell `tryit` function definition to `io`.

The emitted text, when sourced by bash (≥ 4.0) or zsh (≥ 5.0), sets
up a function that invokes the Julia CLI and `eval`s its stdout so
`cd` actually changes the caller's working directory.

`positional`, when non-`nothing`, is hard-coded into the function as
`TRY_PATH` for the call. When `nothing`, the function sets nothing at
all and leaves resolution to `_resolve_tries_root`: the caller's
environment, then `tries_path` in the configuration file, then
`\$HOME/work/tries`.

Everything the emitted function sends through `eval` comes from
stdout, so subcommands whose stdout is *output* rather than a command
— `--help`, `--version`, `path`, `list` — are run directly instead of
being captured.

When running as a compiled PackageCompiler app (see
[`_APP_MODE`](@ref)), the emitted function calls the `tryit`
executable directly instead of booting `julia`.

EARS coverage: UB4, ED13, UN9.
"""
function emit_shell_init(
        io::IO,
        positional::Union{Nothing, AbstractString}=nothing
)
    # Prefix assigning TRY_PATH for the call, or nothing at all.
    #
    # With no explicit root the function must stay out of the way and
    # let `_resolve_tries_root` do its job: environment, then
    # `tries_path` in the config file, then the default. Emitting
    # `TRY_PATH=${TRY_PATH:-$HOME/work/tries}` here defeated that —
    # the variable was then always set, the environment branch always
    # won, and the config setting was unreachable through the very
    # function that is the only way anyone invokes TryIt.
    tries_prefix = if positional === nothing
        ""
    else
        string("TRY_PATH=", _shell_quote(String(positional)), " ")
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

    definition = _shell_function_text(exe, invocation, missing_msg, tries_prefix)

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
        tries_prefix::AbstractString
)
    return """
    tryit() {
      if ! command -v $(_shell_quote(exe)) >/dev/null 2>&1; then
        echo "$(missing_msg)" >&2
        return 127
      fi
      # Informational subcommands write to stdout for the caller, not
      # for the shell. Running them through the capture-and-eval path
      # below would make the shell execute their output — `tryit
      # --help` literally tried to run each line of the help text.
      case "\$1" in
        -h|--help|-V|--version|path|list|extension)
          $(tries_prefix)$(invocation) "\$@"
          return \$?
          ;;
      esac
      local __try_cmd
      __try_cmd=\$($(tries_prefix)$(invocation) "\$@") || return \$?
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
