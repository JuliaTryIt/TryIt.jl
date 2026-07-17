@testitem "config: check_min_terminal_size returns nothing on ≥ 40×10" begin
    using TryIt: check_min_terminal_size

    io = IOBuffer()
    # IOBuffer's displaysize reports 24×80 by default — well above 40×10.
    @test check_min_terminal_size(io) === nothing
end

@testitem "config: check_min_terminal_size rejects too-small sizes (UN6)" begin
    # Simulate size reporting via LINES/COLUMNS env — Julia's
    # `displaysize` consults these when stdout is not a real TTY.
    withenv("LINES" => "8", "COLUMNS" => "40") do
        # For non-TTY IO (like IOBuffer), displaysize reads env.
        io = IOBuffer()
        result = TryIt.check_min_terminal_size(io)
        @test result !== nothing
        @test occursin("terminal too small", result)
    end
    withenv("LINES" => "10", "COLUMNS" => "39") do
        io = IOBuffer()
        result = TryIt.check_min_terminal_size(io)
        @test result !== nothing
    end
    # Exactly 40×10 is inclusive → nothing (OK).
    withenv("LINES" => "10", "COLUMNS" => "40") do
        io = IOBuffer()
        @test TryIt.check_min_terminal_size(io) === nothing
    end
end

@testitem "config: check_min_terminal_size fails open on 0×0" begin
    # displaysize returning 0×0 is the "unknown" signal from CI sandboxes.
    # Fail-open: behave as if the terminal is big enough.
    withenv("LINES" => "0", "COLUMNS" => "0") do
        io = IOBuffer()
        @test TryIt.check_min_terminal_size(io) === nothing
    end
end
