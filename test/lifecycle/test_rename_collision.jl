@testitem "lifecycle: rename to existing same-day slug fails cleanly" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session, try_basename
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    today = Dates.today()
    a = create_try(root, slug("alpha"), today)
    b = create_try(root, slug("bravo"), today)

    session = open_session(root)
    # Cursor on `alpha` (the most-recently-created is `bravo`; pick whichever
    # is index 1 deterministically after refresh).
    session.cursor = findfirst(t -> t.slug.value == "alpha", session.visible)

    # Capture stderr so we can confirm the diag surfaced.
    captured_stderr = mktemp() do path, io
        redirect_stderr(io) do
            press_keys!(session, "\x12")                          # Ctrl-R
            press_keys!(session, "\x7f"^length("alpha"))          # clear buffer
            press_keys!(session, "bravo\r")                       # collide
        end
        flush(io)
        read(path, String)
    end

    @test session.mode === :rename        # stayed in rename for retry
    @test occursin("destination exists", captured_stderr)
    @test isdir(a.path)
    @test isdir(b.path)
    @test length(readdir(dir)) == 2
end
