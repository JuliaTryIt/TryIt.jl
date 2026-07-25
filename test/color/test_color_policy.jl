# When colour is emitted (UB7).
#
# The policy is separated from the rendering precisely so it can be
# tested without a terminal: `color_enabled` answers the question,
# `paint` does as it is told.

@testitem "color: suppressed when the stream is not a terminal (UB7)" begin
    using TryIt

    # The load-bearing case. stdout carries shell commands under UB4,
    # and an escape sequence wrapped around a `cd` would be `eval`'d
    # by the caller's shell.
    previous = TryIt.COLOR_DISABLED[]
    try
        TryIt.COLOR_DISABLED[] = false
        withenv("NO_COLOR" => nothing) do
            @test !TryIt.color_enabled(IOBuffer())
        end
    finally
        TryIt.COLOR_DISABLED[] = previous
    end
end

@testitem "color: enabled for a stream that declares itself colour-capable (UB7)" begin
    using TryIt

    # The gap that let the bug through: every suppression test passed
    # while colour was suppressed *unconditionally*, because the
    # terminal probe raised and was swallowed. Nothing asserted the
    # positive case. `IOContext(:color => true)` is what Julia itself
    # reports for a real terminal.
    previous = TryIt.COLOR_DISABLED[]
    try
        TryIt.COLOR_DISABLED[] = false
        withenv("NO_COLOR" => nothing) do
            tty_like = IOContext(IOBuffer(), :color => true)
            @test TryIt.color_enabled(tty_like)
            @test TryIt._stream_wants_color(tty_like)
            @test !TryIt._stream_wants_color(IOBuffer())
        end
    finally
        TryIt.COLOR_DISABLED[] = previous
    end
end

@testitem "color: diag paints for a colour-capable stream with no override (UB7)" begin
    using TryIt

    # End to end through the real policy, with no `enabled=` escape
    # hatch: this is the assertion that would have failed while the
    # probe was broken.
    previous = TryIt.COLOR_DISABLED[]
    try
        TryIt.COLOR_DISABLED[] = false
        withenv("NO_COLOR" => nothing) do
            buf = IOBuffer()
            TryIt.diag(:git, "boom"; io=IOContext(buf, :color => true))
            @test occursin("\e[", String(take!(buf)))
        end
    finally
        TryIt.COLOR_DISABLED[] = previous
    end
end

@testitem "color: suppressed by an explicit --no-colors request (UB7)" begin
    using TryIt

    previous = TryIt.COLOR_DISABLED[]
    try
        TryIt.COLOR_DISABLED[] = true
        withenv("NO_COLOR" => nothing) do
            # Even for a stream that would otherwise qualify.
            @test !TryIt.color_enabled(IOBuffer(); istty=true)
        end
    finally
        TryIt.COLOR_DISABLED[] = previous
    end
end

@testitem "color: NO_COLOR is honoured, empty NO_COLOR is not (UB7)" begin
    using TryIt

    previous = TryIt.COLOR_DISABLED[]
    try
        TryIt.COLOR_DISABLED[] = false
        # no-color.org: present and non-empty, whatever the value.
        withenv("NO_COLOR" => "1") do
            @test !TryIt.color_enabled(IOBuffer(); istty=true)
        end
        withenv("NO_COLOR" => "anything") do
            @test !TryIt.color_enabled(IOBuffer(); istty=true)
        end
        # An empty value is not "set" for this purpose, or exporting
        # NO_COLOR= to unset it would fail to unset it.
        withenv("NO_COLOR" => "") do
            @test TryIt.color_enabled(IOBuffer(); istty=true)
        end
        withenv("NO_COLOR" => nothing) do
            @test TryIt.color_enabled(IOBuffer(); istty=true)
        end
    finally
        TryIt.COLOR_DISABLED[] = previous
    end
end

@testitem "color: paint is pure and obeys its enabled flag (UB7)" begin
    using TryIt

    @test TryIt.paint("hello", :red; enabled=false) == "hello"
    painted = TryIt.paint("hello", :red; enabled=true)
    @test painted != "hello"
    @test occursin("hello", painted)
    @test startswith(painted, "\e[")
    @test endswith(painted, "\e[0m")
end

@testitem "color: an unknown colour name is returned unpainted (UB7)" begin
    using TryIt

    # Total by construction. A typo in a colour name must not raise
    # from inside a diagnostic — the diagnostic is usually already
    # reporting something that went wrong.
    @test TryIt.paint("hello", :chartreuse; enabled=true) == "hello"
end

@testitem "color: painting is not nested twice (UB7)" begin
    using TryIt

    once = TryIt.paint("x", :red; enabled=true)
    @test count(==('\e'), once) == 2
end
