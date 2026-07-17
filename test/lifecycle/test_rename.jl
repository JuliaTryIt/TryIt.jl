@testitem "lifecycle: rename commits in place (ED7)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session, try_basename
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    today = Dates.today()
    old = create_try(root, slug("old-name"), today)

    session = open_session(root)
    # Preserve cursor position on the try we want to rename.
    session.cursor = 1

    press_keys!(session, "\x12")       # Ctrl-R
    @test session.mode === :rename
    @test session.rename_buf == "old-name"

    # Backspace to clear the buffer, type new name, commit with Enter.
    press_keys!(session, "\x7f"^length("old-name"))
    press_keys!(session, "rename-demo\r")

    @test session.mode === :normal
    @test session.done === false        # selector stays open
    # New directory exists, old is gone.
    new_base = try_basename(today, slug("rename-demo"))
    @test isdir(joinpath(dir, new_base))
    @test !isdir(old.path)
    # Cursor lands on the renamed row.
    @test session.visible[session.cursor].slug.value == "rename-demo"
end
