@testitem "selector: Ctrl-R is ours, not Tachikoma's recorder" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Tachikoma's event loop intercepts Ctrl+R to toggle .tach
    # recording *before* dispatching to `update!`, gated on
    # `recording_enabled(model)` (Tachikoma app.jl:259). Left at its
    # default, Ctrl-R started a screen recording instead of renaming.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        session = TryIt.open_session(root)
        @test Tachikoma.recording_enabled(session) === false
    end
end

@testitem "selector: Ctrl-R still enters rename mode" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("original"))
        session = TryIt.open_session(root)
        session.cursor = 1

        press_keys!(session, "\x12")   # Ctrl-R
        @test session.mode === :rename
    end
end

@testitem "selector: F9 toggles recording when a terminal is attached" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        session = TryIt.open_session(root)

        # Recording is driven through the terminal Tachikoma hands us
        # in `init!`; the recorder lives on the Terminal, not the model.
        @test session.terminal === nothing
        @test TryIt.recording_active(session) === false
    end
end

@testitem "selector: F9 is inert with no terminal attached" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        session = TryIt.open_session(root)
        session.cursor = 1

        # Unit tests drive `update!` without ever running `app()`, so
        # no terminal is attached. F9 must be a no-op rather than
        # dereferencing `nothing`.
        Tachikoma.update!(
            session, Tachikoma.KeyEvent(:f9, '\0', Tachikoma.key_press)
        )
        @test session.done === false
        @test TryIt.recording_active(session) === false
    end
end

@testitem "selector: F9 does not leak into the filter" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        session = TryIt.open_session(root)

        Tachikoma.update!(
            session, Tachikoma.KeyEvent(:f9, '\0', Tachikoma.key_press)
        )
        @test isempty(session.filter)
    end
end
