@testitem "config: the path follows XDG" begin
    using TryIt: config_path

    withenv("TRY_CONFIG" => nothing, "XDG_CONFIG_HOME" => "/xdg") do
        @test config_path() == joinpath("/xdg", "tryit", "config.toml")
    end
    withenv("TRY_CONFIG" => nothing, "XDG_CONFIG_HOME" => nothing,
        "HOME" => "/home/u") do
        @test config_path() == joinpath("/home/u", ".config", "tryit", "config.toml")
    end
    # An explicit override wins outright, so a test or a sandbox can
    # point somewhere harmless.
    withenv("TRY_CONFIG" => "/tmp/elsewhere.toml") do
        @test config_path() == "/tmp/elsewhere.toml"
    end
end

@testitem "config: reading a missing or broken file yields defaults" begin
    using TryIt: read_config

    mktempdir() do dir
        withenv("TRY_CONFIG" => joinpath(dir, "absent.toml")) do
            @test read_config() == Dict{String, Any}()
        end
        # A hand-edited file with a syntax error must not stop the CLI
        # from starting.
        broken = joinpath(dir, "broken.toml")
        write(broken, "theme = = nonsense\n")
        withenv("TRY_CONFIG" => broken) do
            @test read_config() == Dict{String, Any}()
        end
    end
end

@testitem "config: round-trips theme and animation" begin
    using TryIt: read_config, write_config

    mktempdir() do dir
        path = joinpath(dir, "nested", "config.toml")
        withenv("TRY_CONFIG" => path) do
            # Parent directories are created rather than erroring.
            @test write_config(Dict("theme" => "dracula", "animation" => "aurora"))
            @test isfile(path)
            cfg = read_config()
            @test cfg["theme"] == "dracula"
            @test cfg["animation"] == "aurora"
        end
    end
end

@testitem "config: the environment overrides the file" begin
    using TryIt: configured_theme, configured_animation

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "theme = \"gruvbox\"\nanimation = \"plasma\"\n")
        withenv("TRY_CONFIG" => path, "TRY_THEME" => nothing,
            "TRY_BACKGROUND" => nothing, "TRY_ANIMATION" => nothing) do
            @test configured_theme() == "gruvbox"
            @test configured_animation() == "plasma"
        end
        # Precedence: environment beats file beats default, matching
        # try-rs.
        withenv("TRY_CONFIG" => path, "TRY_THEME" => "nord",
            "TRY_ANIMATION" => "rain", "TRY_BACKGROUND" => nothing) do
            @test configured_theme() == "nord"
            @test configured_animation() == "rain"
        end
    end
end

@testitem "config: absent settings fall back to the defaults" begin
    using TryIt: configured_theme, configured_animation, DEFAULT_BACKGROUND

    mktempdir() do dir
        path = joinpath(dir, "empty.toml")
        write(path, "")
        withenv("TRY_CONFIG" => path, "TRY_THEME" => nothing,
            "TRY_BACKGROUND" => nothing, "TRY_ANIMATION" => nothing) do
            @test configured_theme() == ""            # keep the active theme
            @test configured_animation() == DEFAULT_BACKGROUND
        end
    end
end

@testitem "config: the background resolves through the file" begin
    using TryIt: background_from_env, AuroraBackground

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "animation = \"aurora\"\n")
        withenv("TRY_CONFIG" => path, "TRY_BACKGROUND" => nothing,
            "TRY_ANIMATION" => nothing) do
            @test background_from_env() isa AuroraBackground
        end
    end
end

@testitem "selector: Ctrl-W saves the current theme and animation" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    original = Tachikoma.theme().name
    try
        mktempdir() do cfgdir
            path = joinpath(cfgdir, "config.toml")
            withenv("TRY_CONFIG" => path) do
                with_tmp_tries() do dir
                    root = TryIt.TriesPath(positional=dir)
                    m = TryIt.open_session(root)
                    TryIt.apply_theme!("dracula")

                    press_keys!(m, "\x17")          # Ctrl-W
                    @test isfile(path)
                    cfg = TryIt.read_config()
                    @test cfg["theme"] == "dracula"
                    @test haskey(cfg, "animation")
                    # Saving is silent otherwise, so it has to say so.
                    @test !isempty(m.notice)
                end
            end
        end
    finally
        Tachikoma.set_theme!(Symbol(original))
    end
end
