@testitem "selector: Ctrl-W persists the *active* theme" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # `save_settings` is core and takes the theme name as data, so
    # reading it off the live UI is the view layer's job. That wiring
    # is what this covers — test/config/ owns the writing itself.
    original = Tachikoma.theme().name
    prev_cfg = get(ENV, "TRY_CONFIG", nothing)
    try
        with_tmp_tries() do dir
            path = joinpath(dir, "config.toml")
            ENV["TRY_CONFIG"] = path
            root = TryIt.TriesPath(positional=dir)
            TryIt.create_try(root, TryIt.slug("alpha"))
            m = TryIt.open_session(root)

            TryIt.apply_theme!("dracula")
            press_keys!(m, "\x17")          # Ctrl-W

            @test isfile(path)
            @test TryIt.read_config(path)["theme"] == "dracula"
        end
    finally
        prev_cfg === nothing ? delete!(ENV, "TRY_CONFIG") :
        (ENV["TRY_CONFIG"] = prev_cfg)
        Tachikoma.set_theme!(Symbol(original))
    end
end
