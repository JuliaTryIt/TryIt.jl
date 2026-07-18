@testitem "selector: Ctrl-N creates a new dated try" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Moved off Ctrl-T, which now opens the theme picker to match
    # try-rs.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)
        @test isempty(readdir(dir))

        press_keys!(m, "\x0e")          # Ctrl-N
        @test length(readdir(dir)) == 1
        @test m.mode === :normal
    end
end

@testitem "selector: Ctrl-T opens the theme picker" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    original = Tachikoma.theme().name
    try
        with_tmp_tries() do dir
            root = TryIt.TriesPath(positional=dir)
            TryIt.create_try(root, TryIt.slug("alpha"))
            m = TryIt.open_session(root)

            press_keys!(m, "\x14")      # Ctrl-T
            @test m.mode === :theme
            # Creating a try is no longer what this key does.
            @test length(readdir(dir)) == 1
        end
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end

@testitem "selector: the theme picker previews as you move" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    original = Tachikoma.theme().name
    try
        with_tmp_tries() do dir
            root = TryIt.TriesPath(positional=dir)
            m = TryIt.open_session(root)
            press_keys!(m, "\x14")

            start = Tachikoma.theme().name
            Tachikoma.update!(
                m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
            # Applying live is the point: you pick by seeing it.
            @test Tachikoma.theme().name != start

            press_keys!(m, "\r")
            @test m.mode === :normal
            @test Tachikoma.theme().name != start   # kept on confirm
        end
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end

@testitem "selector: Esc restores the theme the picker started with" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    original = Tachikoma.theme().name
    try
        with_tmp_tries() do dir
            root = TryIt.TriesPath(positional=dir)
            m = TryIt.open_session(root)
            before = Tachikoma.theme().name

            press_keys!(m, "\x14")
            Tachikoma.update!(
                m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
            @test Tachikoma.theme().name != before

            press_keys!(m, "\e")
            @test m.mode === :normal
            # Previewing must not be a one-way door.
            @test Tachikoma.theme().name == before
        end
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end

@testitem "selector: Ctrl-A opens About" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)

        press_keys!(m, "\x01")          # Ctrl-A
        @test m.mode === :about

        text = join(render_selector(m, 92, 24), "\n")
        @test occursin("TryIt", text)
        @test occursin("try-cli", text)
        @test occursin("try-rs", text)

        press_keys!(m, "\e")
        @test m.mode === :normal
        @test m.done === false
    end
end

@testitem "selector: the theme picker lists every built-in theme" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    original = Tachikoma.theme().name
    try
        with_tmp_tries() do dir
            root = TryIt.TriesPath(positional=dir)
            m = TryIt.open_session(root)
            press_keys!(m, "\x14")
            @test length(TryIt.theme_names()) == length(Tachikoma.ALL_THEMES)

            # The cursor cannot leave the list.
            for _ in 1:(length(Tachikoma.ALL_THEMES) + 5)
                Tachikoma.update!(
                    m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
            end
            @test m.theme_index == length(Tachikoma.ALL_THEMES)
            for _ in 1:(length(Tachikoma.ALL_THEMES) + 5)
                Tachikoma.update!(
                    m, Tachikoma.KeyEvent(:up, '\0', Tachikoma.key_press))
            end
            @test m.theme_index == 1
        end
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end
