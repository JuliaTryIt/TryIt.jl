@testitem "selector: ambiguous filter offers open-or-create" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # `filter_tries` matches substrings, so typing the beginning of an
    # existing name used to make that name uncreatable: Enter always
    # opened the match. Same gap as try-rs #44.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)

        m.filter = "help"
        TryIt.refresh_visible!(m)
        @test length(m.visible) == 1

        press_keys!(m, "\r")
        # Neither action taken yet — the user is asked first.
        @test m.mode === :choose
        @test m.done === false
        @test m.choice === :open      # entering is the default
    end
end

@testitem "selector: choosing open enters the matched try" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        existing = TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.filter = "help"
        TryIt.refresh_visible!(m)

        press_keys!(m, "\r")          # opens the prompt
        press_keys!(m, "\r")          # confirms the default
        @test m.done === true
        @test m.exit_action === :cd
        @test m.exit_path == existing.path
    end
end

@testitem "selector: choosing create makes a try named after the filter" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.filter = "help"
        TryIt.refresh_visible!(m)

        press_keys!(m, "\r")
        Tachikoma.update!(m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
        @test m.choice === :create
        press_keys!(m, "\r")

        @test m.done === true
        @test m.exit_action === :cd
        @test endswith(m.exit_path, "-help")
        @test isdir(m.exit_path)
        # The existing try is untouched.
        @test m.exit_path != joinpath(dir, only(filter(
            n -> endswith(n, "-help-me"), readdir(dir))))
    end
end

@testitem "selector: Esc returns to editing without acting" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.filter = "help"
        TryIt.refresh_visible!(m)
        before = readdir(dir)

        press_keys!(m, "\r")
        @test m.mode === :choose
        press_keys!(m, "\e")

        @test m.mode === :normal
        @test m.done === false
        @test m.filter == "help"       # the typed text survives
        @test readdir(dir) == before   # nothing created
    end
end

@testitem "selector: an exact name opens directly, with no prompt" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        existing = TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.filter = "help-me"
        TryIt.refresh_visible!(m)

        # Typing a full name is unambiguous — asking would be friction.
        press_keys!(m, "\r")
        @test m.mode === :normal
        @test m.done === true
        @test m.exit_path == existing.path
    end
end

@testitem "selector: no match still creates directly" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.filter = "something-else"
        TryIt.refresh_visible!(m)
        @test isempty(m.visible)

        press_keys!(m, "\r")
        @test m.mode === :normal
        @test m.done === true
        @test endswith(m.exit_path, "-something-else")
    end
end

@testitem "selector: an empty filter opens the highlighted try" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.cursor = 1

        # Pure navigation: nothing typed, so nothing to disambiguate.
        press_keys!(m, "\r")
        @test m.mode === :normal
        @test m.done === true
        @test m.exit_action === :cd
    end
end

@testitem "selector: the date prefix does not make names uncreatable" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # The filter haystack includes the date, so "2026" matches every
    # try from this year. Without the prompt, no name starting with
    # the year could ever be created.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("anything"))
        m = TryIt.open_session(root)
        m.filter = "2026"
        TryIt.refresh_visible!(m)
        @test !isempty(m.visible)

        press_keys!(m, "\r")
        @test m.mode === :choose
    end
end

@testitem "selector: arrow keys move between the two choices" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.filter = "help"
        TryIt.refresh_visible!(m)
        press_keys!(m, "\r")

        @test m.choice === :open
        Tachikoma.update!(m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
        @test m.choice === :create
        Tachikoma.update!(m, Tachikoma.KeyEvent(:up, '\0', Tachikoma.key_press))
        @test m.choice === :open
        # Movement is a toggle, not a wrapping list.
        Tachikoma.update!(m, Tachikoma.KeyEvent(:up, '\0', Tachikoma.key_press))
        @test m.choice === :open
    end
end

@testitem "selector: the default action is the left button" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Modal renders `cancel_label` first. If "Open" were the confirm
    # slot it would draw on the right while Left still selected it,
    # so the arrow keys would contradict the layout.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("help-me"))
        m = TryIt.open_session(root)
        m.filter = "help"
        TryIt.refresh_visible!(m)
        press_keys!(m, "\r")

        rows = render_selector(m, 92, 20)
        btn = findfirst(l -> occursin("Open", l) && occursin("Create", l), rows)
        @test btn !== nothing
        line = rows[btn]
        @test findfirst("Open", line) < findfirst("Create", line)
    end
end
