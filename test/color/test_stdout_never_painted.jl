# Architectural invariant, not a behaviour test (UB4, UB7).
#
# stdout is a command channel: the caller's shell `eval`s it. An
# escape sequence wrapped around a `cd` would be evaluated as part of
# the command. Colour therefore belongs to stderr and to nothing
# else, and the policy already refuses a non-terminal stream — but a
# future call site could paint stdout while it happens to be a
# terminal, which is precisely the case a piped test never exercises.

@testitem "architecture: nothing paints stdout (UB4, UB7)" begin
    using TryIt

    src = joinpath(pkgdir(TryIt), "src")
    offenders = String[]
    for (dir, _, files) in walkdir(src)
        for file in files
            endswith(file, ".jl") || continue
            for (n, line) in enumerate(eachline(joinpath(dir, file)))
                code = first(split(line, '#'))
                # A write to stdout that also paints on the same line.
                if occursin("stdout", code) && occursin("paint(", code)
                    push!(offenders, string(file, ":", n))
                end
            end
        end
    end
    @test offenders == String[]
end

@testitem "architecture: diag defaults to stderr, never stdout (UB4, UB5)" begin
    using TryIt

    # The default matters more than it looks: 30 call sites rely on
    # it, and a changed default would move every diagnostic onto the
    # channel the shell evaluates.
    #
    # A temp file, not an `IOBuffer`: the redirect goes through a
    # file descriptor, which an `IOBuffer` cannot provide.
    path, io = mktemp()
    try
        redirect_stdout(io) do
            TryIt.diag(:probe, "to stderr please")
        end
        close(io)
        @test isempty(read(path, String))
    finally
        isopen(io) && close(io)
        rm(path; force=true)
    end
end
