# Shared helper for the trust tests. Not a `@testitem` file, so it
# can be `include`d from inside test items without recursing — same
# arrangement as `test/spec/spec_helpers.jl`.

"""
Capture everything written to `stderr` while running `f`, and return
it as a `String`.

`diag` writes to the `stderr` global, which `redirect_stderr`
rebinds. A temp file is used rather than an `IOBuffer` because the
redirect goes through a file descriptor, which an `IOBuffer` cannot
provide.
"""
function capture_stderr(f)
    path, io = mktemp()
    try
        redirect_stderr(io) do
            f()
        end
        close(io)
        return read(path, String)
    finally
        isopen(io) && close(io)
        rm(path; force=true)
    end
end
