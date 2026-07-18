@testitem "selector: ? opens help" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Safe to bind unconditionally: `_parse_try_basename` only accepts
    # slugs matching ^[a-z0-9]+(-[a-z0-9]+)*$, so no listed try can
    # contain '?' and a filter holding one can never match anything.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)

        press_keys!(m, "?")
        @test m.mode === :help
        @test isempty(m.filter)   # not typed into the search box
    end
end

@testitem "selector: any key closes help" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)

        press_keys!(m, "?")
        press_keys!(m, "\e")
        @test m.mode === :normal
        @test m.done === false

        # A second route out, so the overlay can never trap the user.
        press_keys!(m, "?")
        press_keys!(m, "\r")
        @test m.mode === :normal
        @test m.done === false
    end
end

@testitem "selector: help lists the whole keymap" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)
        press_keys!(m, "?")

        text = join(render_selector(m, 92, 26), "\n")
        # The selector owns the keymap now (default_bindings=false),
        # so the overlay is the only place these are written down.
        for key in ("Enter", "Ctrl-N", "Ctrl-T", "Ctrl-A", "Ctrl-R",
            "Ctrl-G", "Ctrl-D", "F9", "?")
            @test occursin(key, text)
        end
    end
end

@testitem "selector: graduate failures are shown, not swallowed" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Regression: `_handle_ctrl_g!` reported errors with `diag`, which
    # writes to stderr — and Tachikoma redirects stderr for the whole
    # TUI session (app.jl:1000). A failed graduate therefore looked
    # like a dead key.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("collide"))
        m = TryIt.open_session(root)
        m.cursor = 1

        # Pre-create the graduation target so the move must fail.
        projects = TryIt.resolve_projects_path(root)
        mkpath(joinpath(projects, "collide"))

        press_keys!(m, "\a")     # Ctrl-G
        @test m.done === false
        @test !isempty(m.notice)
        @test occursin("exists", lowercase(m.notice))

        # And it reaches the screen.
        @test occursin("exists", lowercase(join(render_selector(m, 92, 24), "\n")))
    end
end

@testitem "selector: a notice clears on the next keystroke" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("collide"))
        m = TryIt.open_session(root)
        m.cursor = 1
        projects = TryIt.resolve_projects_path(root)
        mkpath(joinpath(projects, "collide"))

        press_keys!(m, "\a")
        @test !isempty(m.notice)

        # Stale errors must not linger over unrelated later actions.
        press_keys!(m, "x")
        @test isempty(m.notice)
    end
end
