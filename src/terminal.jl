"""
Terminal-side helpers that Tachikoma does not already cover.

For v0.1 this is intentionally thin: Tachikoma brackets the
alternate screen, raw mode, and cursor state itself (see the v0.1
research notes on SIGINT). The only remaining responsibility is
mapping the Tachikoma Ctrl-C key message to the `ExitCode.SIGINT`
process exit code.

EARS coverage: UN7.
"""

"""
Detect whether `io` is connected to a real terminal.

Thin wrapper around `isopen` + `Base.isatty` so call sites read
cleanly and test helpers can override it.

EARS coverage: UN4.
"""
function is_terminal(io::IO)
    isopen(io) || return false
    # `Base.isatty` was moved / removed in Julia 1.12 and its
    # successor location is in flux. `io isa Base.TTY` is the one
    # check stable across 1.10 – 1.12+: the `TTY` type is reserved
    # for process-connected terminals, and redirected pipes,
    # `/dev/null`, and test `IOBuffer`s are not `TTY`s.
    return io isa Base.TTY
end

"""
Return `nothing` if the terminal attached to `io` is ≥ 40×10 or
reports a zero/unreadable size (fail-open). Return the
canonical "terminal too small" error string otherwise.

Called at the top of the selector dispatch BEFORE any alt-screen
or raw-mode toggling so a refusal leaves the terminal untouched.

EARS coverage: UN6 / FR-041.
"""
function check_min_terminal_size(io::IO=stdout)
    rows, cols = Base.displaysize(io)
    # Fail-open on unreadable dimensions (0×0 in sandboxed CI / headless).
    (rows <= 0 || cols <= 0) && return nothing
    (rows >= 10 && cols >= 40) && return nothing
    return "terminal too small (min 40×10)"
end

"""
Run `f` while routing the global stdout stream to the terminal.

The shell integration captures stdout and evaluates it after the Julia
process exits. Tachikoma normally renders through `/dev/tty`, but its
startup pixel-size probes are emitted on the global stdout stream before
that rendering channel is installed. Keeping stdout terminal-bound for
the whole TUI call prevents those escape sequences from being prepended
to the shell command.
"""
function _with_terminal_stdout(f::Function, io::IO)
    return redirect_stdout(f, io)
end

function _with_terminal_stdout(f::Function)
    @static if Sys.iswindows()
        return _with_terminal_stdout(f, stderr)
    else
        tty = try
            open("/dev/tty", "w")
        catch
            return _with_terminal_stdout(f, stderr)
        end
        try
            return _with_terminal_stdout(f, tty)
        finally
            close(tty)
        end
    end
end
