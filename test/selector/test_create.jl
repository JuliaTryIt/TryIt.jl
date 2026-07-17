@testitem "selector: create path (ED4)" begin
    using TryIt: TriesPath, SelectorSession, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    session = open_session(root)

    press_keys!(session, "my-new-idea\r")

    @test session.done === true
    @test session.exit_action === :cd
    @test !isempty(session.exit_path)
    @test isdir(session.exit_path)
    @test basename(session.exit_path) == string(session.exit_path |> basename)
    @test occursin("my-new-idea", session.exit_path)
end

@testitem "selector: filter + reopen (ED3)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    apple = create_try(root, slug("apple"), Date(2026, 4, 19))
    banana = create_try(root, slug("banana"), Date(2026, 4, 19))

    session = open_session(root)
    press_keys!(session, "app\r")

    @test session.done === true
    @test session.exit_action === :cd
    @test session.exit_path == apple.path
    # Directory should exist and we should not have created a new one.
    @test isdir(banana.path)
    @test length(readdir(dir)) == 2
end

@testitem "selector: Esc exits quietly (ED12)" begin
    using TryIt: TriesPath, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    session = open_session(root)

    press_keys!(session, "something\e")

    @test session.done === true
    @test session.exit_action === :quit
    @test session.exit_path == ""
end

@testitem "selector: Ctrl-C maps to interrupted (UN7)" begin
    using TryIt: TriesPath, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    session = open_session(root)

    press_keys!(session, "\x03")

    @test session.done === true
    @test session.exit_action === :interrupted
end

@testitem "selector: empty-filter Enter is a no-op" begin
    using TryIt: TriesPath, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    session = open_session(root)

    press_keys!(session, "\r")

    @test session.done === false
    @test session.exit_action === :none
end
