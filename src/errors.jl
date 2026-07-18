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
| `PERMISSION` | 2    | `TRY_PATH` not creatable or writable (UN1).  |
| `USAGE`      | 64   | `EX_USAGE`: bad slug, subcommand, or non-TTY |
|              |      | run with no positional slug (UN4).           |
| `NOT_FOUND`  | 127  | A required dependency is absent from `PATH`  |
|              |      | (`git`, UN5).                                |
| `SIGINT`     | 130  | `128 + SIGINT`: Ctrl-C (UN7).                |

`exit` takes an `Integer`, and an `@enum` is not one, so process-level
callers convert explicitly: `exit(Int(ExitCode.PERMISSION))`.

EARS coverage: UB6, UN1, UN4, UN5, UN7.
"""
module ExitCode

@enum T::Int32 begin
    SUCCESS = 0
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

EARS coverage: UB5.
"""
function diag(subsystem::Symbol, msg::AbstractString)
    println(stderr, "tryit: ", subsystem, ": ", msg)
    return nothing
end
