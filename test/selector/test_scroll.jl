@testitem "selector: viewport follows cursor down (SD3)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    # Seed 40 tries. Mtimes differ enough for list_tries to sort them.
    for i in 1:40
        create_try(root, slug("t$(lpad(i, 2, '0'))"), Date(2026, 4, 19))
        sleep(0.001)
    end

    session = open_session(root)
    # Simulate a 24-row terminal: VR = 24 - 4 = 20 visible rows.
    session.terminal_size = (24, 80)

    @test length(session.visible) == 40
    @test session.cursor == 1
    @test session.viewport_top == 1

    # Press Down 25 times — cursor should be at 26 (was 1, move to 26).
    press_keys!(session, "\x1b[B"^25)

    @test session.cursor == 26
    # Viewport must have scrolled so the cursor is inside the window.
    vr = 20
    @test session.viewport_top <= session.cursor
    @test session.cursor <= session.viewport_top + vr - 1
    @test session.viewport_top > 1
end

@testitem "selector: viewport returns to top on scroll up (SD3)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    for i in 1:40
        create_try(root, slug("t$(lpad(i, 2, '0'))"), Date(2026, 4, 19))
        sleep(0.001)
    end

    session = open_session(root)
    session.terminal_size = (24, 80)

    # Drive the cursor to the bottom, then back to the top.
    press_keys!(session, "\x1b[B"^39)    # cursor = 40
    press_keys!(session, "\x1b[A"^39)    # cursor = 1

    @test session.cursor == 1
    @test session.viewport_top == 1
end

@testitem "selector: Page-Down jumps by viewport height (SD3)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    for i in 1:40
        create_try(root, slug("t$(lpad(i, 2, '0'))"), Date(2026, 4, 19))
        sleep(0.001)
    end

    session = open_session(root)
    session.terminal_size = (24, 80)    # VR = 20

    press_keys!(session, "\x16")        # one Page-Down
    @test session.cursor == 1 + 20      # cursor advanced by VR

    press_keys!(session, "\x15")        # one Page-Up
    @test session.cursor == 1
end

@testitem "selector: empty visible list has viewport_top = 0" begin
    using TryIt: TriesPath, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    session = open_session(root)
    @test isempty(session.visible)
    @test session.viewport_top == 0
    @test session.cursor == 0
end
