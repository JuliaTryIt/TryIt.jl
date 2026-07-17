@testitem "lifecycle: Ctrl-G refuses on existing destination (ED8)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    parent = mktempdir()
    tries_dir = joinpath(parent, "tries")
    mkpath(tries_dir)
    projects_dir = joinpath(parent, "projects")
    mkpath(projects_dir)
    # Pre-create the destination so the graduate must collide.
    existing = joinpath(projects_dir, "collision")
    mkpath(existing)
    write(joinpath(existing, "sentinel"), "pre-existing")

    withenv("TRY_PROJECTS" => projects_dir) do
        root = TriesPath(positional=tries_dir)
        src = create_try(root, slug("collision"), Dates.today())

        session = open_session(root)
        session.cursor = 1

        captured_stderr = mktemp() do path, io
            redirect_stderr(io) do
                press_keys!(session, "\x07")
            end
            flush(io)
            read(path, String)
        end

        # Selector stays open; no exit action on collision.
        @test session.done === false
        @test session.exit_action === :none
        @test occursin("destination exists", captured_stderr)
        # Source try untouched.
        @test isdir(src.path)
        # Destination untouched — sentinel still present.
        @test isfile(joinpath(existing, "sentinel"))
    end
end
