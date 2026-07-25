"""
Process exit statuses.

A dedicated module rather than loose constants: the names stay out of
`TryIt`, `ExitCode.<TAB>` completes, and `ExitCode.T` gives call sites
something to dispatch on.

The values are the wire format — a shell reads them from `\$?` — so
they are pinned explicitly rather than left to declaration order.

| Value        | Code | Meaning                                      |
|:------------ | ----:|:-------------------------------------------- |
| `SUCCESS`    | 0    | Completed normally.                          |
| `FAILURE`    | 1    | The operation failed (`fetch`, UN11).        |
| `PERMISSION` | 2    | `TRY_PATH` not creatable or writable (UN1).  |
| `USAGE`      | 64   | `EX_USAGE`: bad slug, subcommand, or non-TTY |
|              |      | run with no positional slug (UN4).           |
| `NOT_FOUND`  | 127  | A required dependency is absent from `PATH`  |
|              |      | (`git`, UN5).                                |
| `SIGINT`     | 130  | `128 + SIGINT`: Ctrl-C (UN7).                |

`FAILURE` is deliberately distinct from `NOT_FOUND`: overloading
`127` for an HTTP 404 would give scripts a status code that means two
different things. `clone` sidesteps the question entirely by
propagating git's own exit code (UN3).

`exit` takes an `Integer`, and an `@enum` is not one, so process-level
callers convert explicitly: `exit(Int(ExitCode.PERMISSION))`.

EARS coverage: UB6, UN1, UN4, UN5, UN7, UN11.
"""
module ExitCode

@enum T::Int32 begin
    SUCCESS = 0
    FAILURE = 1
    PERMISSION = 2
    USAGE = 64
    NOT_FOUND = 127
    SIGINT = 130
end

# Base defines the `Int(::Enum)` constructor but not `convert`, so
# without this a `::Int` return annotation on the CLI dispatchers
# would raise a MethodError instead of narrowing. Not piracy — `T`
# is ours.
Base.convert(::Type{I}, e::T) where {I <: Integer} = I(e)

end

"""
Write a single-line diagnostic to `stderr` in the canonical
`tryit: <subsystem>: <msg>` format. Never writes to stdout (stdout is
reserved for shell-evaluable output, UB4).

The single funnel for all diagnostic output, which is why colour is
applied here rather than at each of the thirty call sites. `color`
names the palette entry for the prefix; `enabled` overrides the
policy in [`color_enabled`](@ref) and exists for tests, which have no
terminal to offer.

EARS coverage: UB5, UB7.
"""
function diag(
        subsystem::Symbol,
        msg::AbstractString;
        io::IO=stderr,
        color::Symbol=:red,
        enabled::Union{Nothing, Bool}=nothing
)
    lit = enabled === nothing ? color_enabled(io) : enabled
    # Only the prefix is painted. The message is the part a user
    # copies, greps, or pastes into a bug report, and escape codes
    # wrapped around it help nobody.
    prefix = paint(string("tryit: ", subsystem, ":"), color; enabled=lit)
    println(io, prefix, " ", msg)
    return nothing
end
