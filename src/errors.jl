"""
Process exit status — success.

EARS coverage: UB6.
"""
const EXIT_SUCCESS = 0

"""
Process exit status — permission / access error.

Emitted when `TRY_PATH` cannot be created or written to.

EARS coverage: UB6, UN1.
"""
const EXIT_PERMISSION = 2

"""
Process exit status — usage / `EX_USAGE` error.

Emitted for empty slugs, unknown subcommands, or non-TTY runs with
no positional slug.

EARS coverage: UB6, UN4.
"""
const EXIT_USAGE = 64

"""
Process exit status — required dependency not found on `PATH`.

Reserved for `git` (v0.2). Declared here so `cli_main` can use the
stable name.

EARS coverage: UB6, UN5.
"""
const EXIT_NOT_FOUND = 127

"""
Process exit status — received SIGINT (Ctrl-C).

EARS coverage: UB6, UN7.
"""
const EXIT_SIGINT = 130

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
