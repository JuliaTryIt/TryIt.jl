@testitem "theming: resolve_background maps names to backgrounds" begin
    using TryIt: resolve_background
    using TryIt
    using Tachikoma

    @test resolve_background("wash") isa TryIt.FogBackground
    @test resolve_background("dotwave") isa Tachikoma.DotWaveBackground
    @test resolve_background("phylo") isa Tachikoma.PhyloTreeBackground
    @test resolve_background("clado") isa Tachikoma.CladogramBackground

    # Case and surrounding whitespace are user typos, not choices.
    @test resolve_background("  DotWave ") isa Tachikoma.DotWaveBackground
end

@testitem "theming: resolve_background honours the opt-out spellings" begin
    using TryIt: resolve_background

    # The background is on by default, so the off switch has to accept
    # whatever a user is likely to reach for.
    for off in ("none", "off", "no", "0", "false", "")
        @test resolve_background(off) === nothing
    end
end

@testitem "theming: resolve_background falls back on an unknown name" begin
    using TryIt: resolve_background
    using TryIt
    using Tachikoma

    # A typo in a config variable must not disable the UI or throw
    # mid-render; it falls back to the default rather than to nothing,
    # which would silently look like an intentional opt-out.
    @test resolve_background("not-a-background") isa TryIt.FogBackground
end

@testitem "theming: resolve_background clamps the preset" begin
    using TryIt: resolve_background
    using Tachikoma

    # Out-of-range presets would index past the end of DOTWAVE_PRESETS
    # inside the render loop.
    for p in (-5, 0, 1, 2, 999)
        @test resolve_background("dotwave", p) isa Tachikoma.DotWaveBackground
    end
    @test resolve_background("dotwave", 1).preset_idx == 1
    @test resolve_background("dotwave", 0).preset_idx == 1
    @test resolve_background("dotwave", 999).preset_idx ==
          length(Tachikoma.DOTWAVE_PRESETS)
end

@testitem "theming: background_from_env reads TRY_BACKGROUND" begin
    using TryIt: background_from_env
    using TryIt
    using Tachikoma

    withenv("TRY_BACKGROUND" => nothing, "TRY_BACKGROUND_PRESET" => nothing,
        "TRY_ANIMATION" => nothing, "TRY_CONFIG" => "/nonexistent/tryit.toml") do
        # Unset means on, per the opt-out default.
        @test background_from_env() isa TryIt.FogBackground
    end
    withenv("TRY_BACKGROUND" => "off") do
        @test background_from_env() === nothing
    end
    withenv("TRY_BACKGROUND" => "clado") do
        @test background_from_env() isa Tachikoma.CladogramBackground
    end
    withenv("TRY_BACKGROUND" => "dotwave", "TRY_BACKGROUND_PRESET" => "2") do
        @test background_from_env().preset_idx == 2
    end
    # A non-numeric preset is ignored rather than fatal.
    withenv("TRY_BACKGROUND" => "dotwave", "TRY_BACKGROUND_PRESET" => "abc") do
        @test background_from_env().preset_idx == 1
    end
end

@testitem "theming: apply_theme! accepts every built-in theme" begin
    using TryIt: apply_theme!
    using Tachikoma

    original = Tachikoma.theme().name
    try
        for t in Tachikoma.ALL_THEMES
            @test apply_theme!(t.name) === true
            @test Tachikoma.theme().name == t.name
        end
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end

@testitem "theming: apply_theme! rejects an unknown name without throwing" begin
    using TryIt: apply_theme!
    using Tachikoma

    original = Tachikoma.theme().name
    try
        @test apply_theme!("no-such-theme") === false
        # The active theme is left alone rather than reset.
        @test Tachikoma.theme().name == original
        # Empty / unset is a no-op, not an error.
        @test apply_theme!("") === false
        @test Tachikoma.theme().name == original
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end

@testitem "theming: apply_theme_from_env! is case and space tolerant" begin
    using TryIt: apply_theme_from_env!
    using Tachikoma

    original = Tachikoma.theme().name
    try
        withenv("TRY_THEME" => " Dracula ",
            "TRY_CONFIG" => "/nonexistent/tryit.toml") do
            @test apply_theme_from_env!() === true
            @test Tachikoma.theme().name == "dracula"
        end
        withenv("TRY_THEME" => nothing,
            "TRY_CONFIG" => "/nonexistent/tryit.toml") do
            @test apply_theme_from_env!() === false
        end
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end

@testitem "theming: only the colour family survives panel blanking" begin
    using TryIt: blanks_panels, FogBackground, resolve_background
    using Tachikoma

    # The wash lives in each cell's *background colour*, which
    # `set_char!` preserves when the incoming style has none — so
    # panels can be blanked over it. Tachikoma's backgrounds draw
    # foreground braille, which blanking would erase outright, so they
    # render full-bleed instead.
    @test blanks_panels(FogBackground()) === true
    @test blanks_panels(nothing) === true
    @test blanks_panels(resolve_background("dotwave")) === false
    @test blanks_panels(resolve_background("phylo")) === false
    @test blanks_panels(resolve_background("clado")) === false
end

@testitem "theming: fog tints cells without drawing glyphs" begin
    using TryIt: FogBackground, render_selector_background!
    using Tachikoma

    rect = Tachikoma.Rect(1, 1, 20, 6)
    buf = Tachikoma.Buffer(rect)
    render_selector_background!(FogBackground(), buf, rect, 1)

    for y in 1:6, x in 1:20
        cell = buf.content[Tachikoma.buf_index(buf, x, y)]
        # Blank glyph, coloured cell: text drawn on top stays legible.
        @test cell.char == ' '
        @test !(cell.style.bg isa Tachikoma.NoColor)
    end
end
