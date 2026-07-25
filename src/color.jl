# Colour for non-TUI output.
#
# Two concerns, kept apart on purpose: `color_enabled` decides
# *whether* to colour, `paint` decides *how*. Fusing them would make
# the policy reachable only from a real terminal, which is exactly
# the condition a test cannot arrange.
#
# The TUI is not served from here — Tachikoma owns the screen while
# the selector is open, and its theming is a separate concern.

"""
Colour turned off by explicit request (`--no-colors`).

A `Ref` for the same reason `_APP_MODE` is one: the flag is
positional-agnostic and has to be visible to every dispatcher
without threading a parameter through eight signatures. It is set
once per process, from [`cli_main`](@ref).

EARS coverage: UB7.
"""
const COLOR_DISABLED = Ref(false)

"""
ANSI select-graphic-rendition codes, by name.

Deliberately small. This is a CLI writing a dozen kinds of line, not
a rendering library, and every name here has to earn a place in the
palette a user reads under stress.
"""
const _ANSI = Dict(
    :red => "\e[31m",
    :green => "\e[32m",
    :yellow => "\e[33m",
    :blue => "\e[34m",
    :magenta => "\e[35m",
    :cyan => "\e[36m",
    :dim => "\e[2m",
    :bold => "\e[1m"
)

const _ANSI_RESET = "\e[0m"

"""
Should output written to `io` carry colour?

Suppressed when any of three conditions holds:

  - `--no-colors` was passed, recorded in [`COLOR_DISABLED`](@ref);
  - `NO_COLOR` is present in the environment and non-empty, per
    no-color.org — an *empty* value is not "set", or `NO_COLOR=` would
    be unable to undo an inherited one;
  - `io` is not a terminal.

The last is the load-bearing one and the reason this is decided per
stream rather than once per process: stdout carries shell commands
under UB4, and an escape sequence wrapped around a `cd` would be
`eval`'d by the caller's shell. stdout and stderr are redirected
independently, so one may deserve colour while the other does not.

`istty` exists to be overridden in tests, which have no terminal to
offer.

EARS coverage: UB7.
"""
function color_enabled(io::IO=stderr; istty::Union{Nothing, Bool}=nothing)
    COLOR_DISABLED[] && return false
    no_color = get(ENV, "NO_COLOR", "")
    isempty(no_color) || return false
    istty === nothing || return istty
    return _stream_wants_color(io)
end

"""
Whether `io` is a stream Julia considers colour-capable.

`get(io, :color, false)` is Julia's own answer to this question, and
asking it has three advantages over probing the file descriptor
ourselves: it is per-stream, so a redirected stdout and a terminal
stderr are judged separately; it rides on `IOContext`, so a caller
can force either way; and it already honours `julia --color=yes|no`.

Measured both ways rather than assumed — `false` through a pipe,
`true` under a pty.

There is no `isatty` to reach for here: it is not in `Base` in Julia
1.12, and an earlier version of this function called it behind a
broad `catch`, which turned the resulting `UndefVarError` into
`false`. Colour was then suppressed unconditionally and the tests
covering suppression passed for the wrong reason. JET caught it.
"""
_stream_wants_color(io::IO) = get(io, :color, false) === true

"""
Wrap `text` in `color`, or return it unchanged.

Pure: the caller supplies `enabled`, so the decision and the
rendering can be tested apart. An unrecognised colour name yields
the text unpainted rather than raising — a typo in a palette name
must not take down the diagnostic it was decorating, and diagnostics
are usually already reporting something that went wrong.

EARS coverage: UB7.
"""
function paint(text::AbstractString, color::Symbol; enabled::Bool)
    enabled || return String(text)
    code = get(_ANSI, color, "")
    isempty(code) && return String(text)
    return string(code, text, _ANSI_RESET)
end
