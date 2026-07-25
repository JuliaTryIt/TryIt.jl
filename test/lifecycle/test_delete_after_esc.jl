@testitem "lifecycle: post-selector delete flow honours 'y' (ED10)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session,
                 confirm_delete, execute_deletes!
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    a = create_try(root, slug("alpha"), Dates.today())
    b = create_try(root, slug("beta"), Dates.today())
    c = create_try(root, slug("gamma"), Dates.today())

    session = open_session(root)
    # Mark alpha + gamma.
    session.cursor = findfirst(t -> t.slug.value == "alpha", session.visible)
    press_keys!(session, "\x04")
    session.cursor = findfirst(t -> t.slug.value == "gamma", session.visible)
    press_keys!(session, "\x04")
    # Exit via Esc.
    press_keys!(session, "\e")
    @test session.exit_action === :quit
    @test length(session.marked_for_delete) == 2

    # Emulate the post-selector delete flow (what cli.jl now does).
    stderr_sink = IOBuffer()
    yes = confirm_delete(
        length(session.marked_for_delete);
        stdin_io=IOBuffer("y\n"),
        stderr_io=stderr_sink
    )
    @test yes === true
    n = execute_deletes!(collect(session.marked_for_delete))
    @test n == 2

    # alpha + gamma gone, beta still here.
    @test !isdir(a.path)
    @test !isdir(c.path)
    @test isdir(b.path)
    @test occursin("Delete 2 tries?", String(take!(stderr_sink)))
end

@testitem "lifecycle: post-selector delete flow respects 'n'" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, open_session,
                 confirm_delete, execute_deletes!
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    dir = mktempdir()
    root = TriesPath(positional=dir)
    a = create_try(root, slug("alpha"), Dates.today())

    session = open_session(root)
    session.cursor = 1
    press_keys!(session, "\x04\x03")    # mark + Ctrl-C (interrupted)

    yes = confirm_delete(
        length(session.marked_for_delete);
        stdin_io=IOBuffer("n\n"),
        stderr_io=IOBuffer()
    )
    @test yes === false
    # Nothing should be deleted when the user says no.
    @test isdir(a.path)
end
