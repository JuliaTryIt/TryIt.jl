@testitem "lifecycle: rename Esc cancels without change" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    today = Dates.today()
    t = create_try(root, slug("keep-me"), today)

    session = open_session(root)
    press_keys!(session, "\x12foo\e")     # Ctrl-R + type + Esc

    @test session.mode === :normal
    @test session.rename_buf == ""
    @test session.done === false
    @test isdir(t.path)                    # original untouched
    @test length(readdir(dir)) == 1
end
