@testitem "lifecycle: SD2 masks shortcuts in rename mode" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    create_try(root, slug("sample"), Dates.today())

    session = open_session(root)
    press_keys!(session, "\x12")    # enter rename mode
    @test session.mode === :rename
    before = deepcopy(session.rename_buf)

    # Ctrl-R / Ctrl-G / Ctrl-D / Ctrl-T / ↑ / ↓ are all no-ops in rename mode.
    press_keys!(session, "\x12\x07\x04\x14\x1b[A\x1b[B")
    @test session.mode === :rename
    @test session.rename_buf == before
    @test session.done === false
    @test session.exit_action === :none
    @test isempty(session.marked_for_delete)
end
