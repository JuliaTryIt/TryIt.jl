@testitem "selector: Ctrl-N creates placeholder and stays open (ED11)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)

    # Seed one existing try so `all_tries` is non-empty at open.
    existing = create_try(root, slug("apple"), Date(2026, 4, 19))

    session = open_session(root)
    prev_count = length(session.all_tries)

    press_keys!(session, "\x0e")          # Ctrl-N

    @test session.done === false          # selector stays open
    @test session.exit_action === :none
    @test length(session.all_tries) == prev_count + 1
    # A new directory ending in "-new-try" exists on disk.
    @test any(
        isdir(joinpath(dir, name)) && endswith(name, "-new-try")
    for name in readdir(dir)
    )
    # The cursor is positioned on the newly-created placeholder.
    @test 1 <= session.cursor <= length(session.visible)
    @test endswith(session.visible[session.cursor].slug.value, "new-try")
end

@testitem "selector: second Ctrl-N makes new-try-1 (ED11)" begin
    using TryIt: TriesPath, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    session = open_session(root)

    press_keys!(session, "\x0e\x0e")      # Ctrl-N twice

    slugs = [t.slug.value for t in session.all_tries]
    @test "new-try" in slugs
    @test "new-try-1" in slugs
    @test session.done === false
end
