@testitem "lifecycle: Ctrl-G graduates to TRY_PROJECTS (ED8)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    parent = mktempdir()
    tries_dir = joinpath(parent, "tries")
    mkpath(tries_dir)
    projects_dir = joinpath(parent, "projects")
    mkpath(projects_dir)

    withenv("TRY_PROJECTS" => projects_dir) do
        root = TriesPath(positional=tries_dir)
        src = create_try(root, slug("my-thing"), Dates.today())

        session = open_session(root)
        session.cursor = 1
        press_keys!(session, "\x07")      # Ctrl-G

        @test session.done === true
        @test session.exit_action === :cd
        @test session.exit_path == joinpath(projects_dir, "my-thing")
        @test !isdir(src.path)
        @test isdir(session.exit_path)
    end
end
