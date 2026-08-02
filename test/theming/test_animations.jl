@testitem "theming: every animation name resolves" begin
    using TryIt: resolve_background, ColorBackground, ANIMATION_NAMES
    using Tachikoma

    for name in ANIMATION_NAMES
        @test resolve_background(name) isa ColorBackground
    end
    # Case and stray whitespace are typos, not choices.
    @test resolve_background("  Aurora ") isa ColorBackground
end

@testitem "theming: wash is still accepted as an alias for fog" begin
    using TryIt: resolve_background, FogBackground

    # `wash` was the documented name before the family existed.
    @test resolve_background("wash") isa FogBackground
    @test resolve_background("fog") isa FogBackground
end

@testitem "theming: colour animations tint without drawing glyphs" begin
    using TryIt: resolve_background, render_selector_background!, ANIMATION_NAMES
    using Tachikoma

    # The whole point of the colour family: text drawn over it keeps
    # its own foreground and inherits the cell background, so nothing
    # competes with the content.
    for name in ANIMATION_NAMES
        rect = Tachikoma.Rect(1, 1, 24, 8)
        buf = Tachikoma.Buffer(rect)
        render_selector_background!(resolve_background(name), buf, rect, 7)

        for y in 1:8, x in 1:24
            cell = buf.content[Tachikoma.buf_index(buf, x, y)]
            @test cell.char == ' '
            @test !(cell.style.bg isa Tachikoma.NoColor)
        end
    end
end

@testitem "theming: the animations differ from one another" begin
    using TryIt: resolve_background, render_selector_background!, ANIMATION_NAMES
    using Tachikoma

    function fingerprint(name)
        rect = Tachikoma.Rect(1, 1, 24, 8)
        buf = Tachikoma.Buffer(rect)
        render_selector_background!(resolve_background(name), buf, rect, 7)
        return [buf.content[Tachikoma.buf_index(buf, x, y)].style.bg
                for y in 1:8, x in 1:24]
    end

    prints = Dict(n => fingerprint(n) for n in ANIMATION_NAMES)
    # A family whose members render identically would be a menu of
    # one effect under several names.
    for a in ANIMATION_NAMES, b in ANIMATION_NAMES
        a == b && continue
        @test prints[a] != prints[b]
    end
end

@testitem "theming: the animations actually animate" begin
    using TryIt: resolve_background, render_selector_background!, ANIMATION_NAMES
    using Tachikoma

    for name in ANIMATION_NAMES
        rect = Tachikoma.Rect(1, 1, 24, 8)
        frames = map((1, 40)) do tick
            buf = Tachikoma.Buffer(rect)
            render_selector_background!(resolve_background(name), buf, rect, tick)
            [buf.content[Tachikoma.buf_index(buf, x, y)].style.bg
             for y in 1:8, x in 1:24]
        end
        # A static "animation" would be a gradient with extra steps.
        @test frames[1] != frames[2]
    end
end

@testitem "theming: pulse limits full-screen colour churn" begin
    using TryIt: PulseBackground, render_selector_background!
    using Tachikoma

    background = PulseBackground()
    rect = Tachikoma.Rect(1, 1, 24, 8)
    fingerprints = Set{UInt}()
    for tick in 1:background.period
        buf = Tachikoma.Buffer(rect)
        render_selector_background!(background, buf, rect, tick)
        colours = [buf.content[Tachikoma.buf_index(buf, x, y)].style.bg
                   for y in 1:8, x in 1:24]
        push!(fingerprints, hash(colours))
    end

    # Pulse repaints every cell at once. A bounded number of visual levels
    # keeps its three-second cycle smooth without flooding a real terminal.
    @test 3 <= length(fingerprints) <= 25
end

@testitem "theming: TRY_ANIMATION is accepted alongside TRY_BACKGROUND" begin
    using TryIt: background_from_env, ColorBackground, FogBackground

    withenv("TRY_BACKGROUND" => nothing, "TRY_ANIMATION" => "aurora") do
        @test background_from_env() isa ColorBackground
        @test !(background_from_env() isa FogBackground)
    end
    # TRY_BACKGROUND keeps working and wins, being the older name.
    withenv("TRY_BACKGROUND" => "fog", "TRY_ANIMATION" => "aurora") do
        @test background_from_env() isa FogBackground
    end
    withenv("TRY_BACKGROUND" => nothing, "TRY_ANIMATION" => "off") do
        @test background_from_env() === nothing
    end
end
