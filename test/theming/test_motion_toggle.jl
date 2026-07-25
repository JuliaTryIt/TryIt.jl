@testitem "theming: Ctrl-A stops the background mid-session" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Regression: the background used to be resolved once in
    # `open_session`, which read `animations_enabled()` at that moment
    # and cached the result. Toggling animations off with Ctrl-A left
    # the wash animating until the next launch, contradicting the
    # documented reduced-motion behaviour.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))

        was_enabled = Tachikoma.animations_enabled()
        try
            withenv("TRY_BACKGROUND" => "wash") do
                m = TryIt.open_session(root)
                @test m.background !== nothing

                rect = Tachikoma.Rect(1, 1, 80, 12)

                function tinted_cells()
                    buf = Tachikoma.Buffer(rect)
                    f = Tachikoma.Frame(
                        buf, rect,
                        Tachikoma.GraphicsRegion[], Tachikoma.PixelSnapshot[]
                    )
                    Tachikoma.view(m, f)
                    count(
                        !(buf.content[Tachikoma.buf_index(buf, x, y)].style.bg
                          isa
                          Tachikoma.NoColor)
                    for y in 1:12, x in 1:80
                    )
                end

                was_enabled || Tachikoma.toggle_animations!()
                @test Tachikoma.animations_enabled()
                @test tinted_cells() > 0

                # The live toggle, as Ctrl-A performs it.
                Tachikoma.toggle_animations!()
                @test !Tachikoma.animations_enabled()
                @test tinted_cells() == 0
            end
        finally
            Tachikoma.animations_enabled() == was_enabled ||
                Tachikoma.toggle_animations!()
        end
    end
end
