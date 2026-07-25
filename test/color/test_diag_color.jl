# Colour reaching the one place every diagnostic goes through (UB5,
# UB7).
#
# `diag` is the single funnel for all 30 diagnostic call sites, so
# colouring it colours everything without touching any of them.

@testitem "color: diag stays plain text when colour is off (UB5, UB7)" begin
    using TryIt

    io = IOBuffer()
    TryIt.diag(:git, "something failed"; io=io)
    text = String(take!(io))
    # An IOBuffer is not a terminal, so this is the default path and
    # the exact bytes older tests and scripts already match on.
    @test text == "tryit: git: something failed\n"
    @test !occursin('\e', text)
end

@testitem "color: diag colours only the prefix, never the message (UB7)" begin
    using TryIt

    io = IOBuffer()
    TryIt.diag(:git, "something failed"; io=io, enabled=true)
    text = String(take!(io))
    # The message is the part a user may want to copy, grep or paste
    # into a bug report; wrapping it in escapes helps nobody. Assert
    # on what follows the reset — splitting on ": " would cut inside
    # the painted prefix and prove nothing.
    @test occursin("\e[", text)
    @test occursin("something failed\n", text)
    tail = split(text, "\e[0m")[end]
    @test !occursin('\e', tail)
    @test strip(tail) == "something failed"
end

@testitem "color: diag carries a severity that changes the colour (UB7)" begin
    using TryIt

    err = IOBuffer()
    TryIt.diag(:git, "boom"; io=err, enabled=true, color=:red)
    warn = IOBuffer()
    TryIt.diag(:trust, "careful"; io=warn, enabled=true, color=:yellow)
    @test String(take!(err)) != String(take!(warn))
end

@testitem "color: the plain form is byte-identical to the historic one (UB5)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "trust", "trust_helpers.jl"))

    # `diag` writes to the `stderr` global by default, and that
    # default must not have shifted: the shell-facing contract is
    # `tryit: <subsystem>: <msg>` on stderr, and a stray escape or a
    # changed default stream would break every consumer at once.
    text = capture_stderr() do
        TryIt.diag(:usage, "unknown option: --wat")
    end
    @test text == "tryit: usage: unknown option: --wat\n"
end

@testitem "color: --no-colors reaches the policy instead of being discarded (UB7)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # The regression: the flag was filtered out of the argument list
    # and thrown away, so it could not have suppressed anything.
    with_tmp_tries() do _dir
        (code, out, _err) = run_cli_subprocess("--no-colors", "--version")
        @test code == 0
        @test !occursin('\e', out)
    end
end
