@testitem "lifecycle: Ctrl-D toggles marks (ED9)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    create_try(root, slug("alpha"), Dates.today())
    create_try(root, slug("beta"), Dates.today())
    create_try(root, slug("gamma"), Dates.today())

    session = open_session(root)
    session.cursor = 1
    row1 = session.visible[1].path

    # Toggle on.
    press_keys!(session, "\x04")
    @test row1 in session.marked_for_delete
    @test length(session.marked_for_delete) == 1
    @test isdir(row1)      # not deleted yet — just marked

    # Toggle off.
    press_keys!(session, "\x04")
    @test !(row1 in session.marked_for_delete)
    @test isempty(session.marked_for_delete)

    # Mark two rows.
    session.cursor = 1
    press_keys!(session, "\x04")
    session.cursor = 2
    press_keys!(session, "\x04")
    @test length(session.marked_for_delete) == 2
    # All three directories still exist on disk.
    @test length(readdir(dir)) == 3
end
