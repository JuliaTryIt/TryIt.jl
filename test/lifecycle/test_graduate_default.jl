@testitem "lifecycle: Ctrl-G default projects path = dirname(TRY_PATH)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    parent = mktempdir()
    tries_dir = joinpath(parent, "tries")
    mkpath(tries_dir)

    # Unset TRY_PROJECTS → default = dirname(TRY_PATH) = parent
    withenv("TRY_PROJECTS" => nothing) do
        root = TriesPath(positional=tries_dir)
        create_try(root, slug("default-target"), Dates.today())

        session = open_session(root)
        session.cursor = 1
        press_keys!(session, "\x07")

        @test session.done === true
        @test session.exit_action === :cd
        @test session.exit_path == joinpath(realpath(parent), "default-target")
        @test isdir(session.exit_path)
    end
end
