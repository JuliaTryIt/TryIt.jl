@testitem "selector: Ctrl-B opens the animation picker" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)

        press_keys!(m, "\x02")          # Ctrl-B
        @test m.mode === :animation
        @test 1 <= m.anim_index <= length(TryIt.BACKGROUND_NAMES)
    end
end

@testitem "selector: the animation picker previews as you move" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)
        press_keys!(m, "\x02")
        before = TryIt.animation_name(m.background)

        Tachikoma.update!(m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
        # Applying live is the point: you pick by seeing it.
        @test TryIt.animation_name(m.background) != before

        press_keys!(m, "\r")
        @test m.mode === :normal
        @test TryIt.animation_name(m.background) != before   # kept
    end
end

@testitem "selector: Esc restores the animation the picker started with" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)
        before = TryIt.animation_name(m.background)

        press_keys!(m, "\x02")
        Tachikoma.update!(m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
        @test TryIt.animation_name(m.background) != before

        press_keys!(m, "\e")
        @test m.mode === :normal
        # Previewing must not be a one-way door.
        @test TryIt.animation_name(m.background) == before
    end
end

@testitem "selector: the picker offers off as well as every animation" begin
    using TryIt

    for name in TryIt.ANIMATION_NAMES
        @test name in TryIt.BACKGROUND_NAMES
    end
    for name in ("dotwave", "phylo", "clado", "off")
        @test name in TryIt.BACKGROUND_NAMES
    end
end

@testitem "selector: picking off disables the background" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)
        press_keys!(m, "\x02")
        # "off" is last; walk to it rather than assigning the index,
        # since only movement applies the choice.
        for _ in 1:length(TryIt.BACKGROUND_NAMES)
            Tachikoma.update!(m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
        end
        @test TryIt.BACKGROUND_NAMES[m.anim_index] == "off"
        press_keys!(m, "\r")

        @test m.background === nothing
        @test TryIt.animation_name(m.background) == "off"
    end
end
