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

    # Paths are passed explicitly, never via TRY_CONFIG: `withenv`
    # mutates the process-global ENV, so with test items running
    # concurrently one item's cleanup can clear another's override.
    mktempdir() do dir
        @test read_config(joinpath(dir, "absent.toml")) == Dict{String, Any}()
        broken = joinpath(dir, "broken.toml")
        write(broken, "theme = = nonsense\n")
        @test read_config(broken) == Dict{String, Any}()
    end
end

@testitem "config: round-trips theme and animation" begin
    using TryIt: read_config, write_config

    mktempdir() do dir
        path = joinpath(dir, "nested", "config.toml")
        # Parent directories are created rather than erroring.
        @test write_config(Dict("theme" => "dracula", "animation" => "aurora"), path)
        @test isfile(path)
        cfg = read_config(path)
        @test cfg["theme"] == "dracula"
        @test cfg["animation"] == "aurora"
    end
end

@testitem "config: the environment overrides the file" begin
    using TryIt: configured_theme, configured_animation

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "theme = \"gruvbox\"\nanimation = \"plasma\"\n")
        withenv("TRY_THEME" => nothing, "TRY_BACKGROUND" => nothing,
            "TRY_ANIMATION" => nothing) do
            @test configured_theme(path) == "gruvbox"
            @test configured_animation(path) == "plasma"
        end
        # Precedence: environment beats file beats default, as try-rs.
        withenv("TRY_THEME" => "nord", "TRY_ANIMATION" => "rain",
            "TRY_BACKGROUND" => nothing) do
            @test configured_theme(path) == "nord"
            @test configured_animation(path) == "rain"
        end
    end
end

@testitem "config: absent settings fall back to the defaults" begin
    using TryIt: configured_theme, configured_animation, DEFAULT_BACKGROUND

    mktempdir() do dir
        path = joinpath(dir, "empty.toml")
        write(path, "")
        withenv("TRY_THEME" => nothing, "TRY_BACKGROUND" => nothing,
            "TRY_ANIMATION" => nothing) do
            @test configured_theme(path) == ""        # keep the active theme
            @test configured_animation(path) == DEFAULT_BACKGROUND
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

@testitem "config: save_settings persists theme and animation" begin
    using TryIt: save_settings, read_config

    # Driven directly with a path rather than through Ctrl-W and
    # TRY_CONFIG: an ENV-based override is not safe when test items
    # run concurrently, and a fallback to the default path writes into
    # the developer's home directory.
    #
    # No Tachikoma here any more: `save_settings` takes the theme name
    # as data. Reading it off the active UI is the view layer's job,
    # covered by the Ctrl-W test in test/selector/.
    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        msg = save_settings("dracula", "plasma", path)

        @test isfile(path)
        @test occursin(path, msg)          # says where it went
        cfg = read_config(path)
        @test cfg["theme"] == "dracula"
        @test cfg["animation"] == "plasma"
    end
end

@testitem "config: save_settings preserves keys it does not own" begin
    using TryIt: save_settings, read_config

    # `tries_path` is written by hand and never by the app. Saving the
    # theme with Ctrl-W must not take it with it — losing it silently
    # sends every try back into hiding, which is the exact failure the
    # setting exists to prevent.
    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, """
        tries_path = "~/src/tries"
        timezone = "utc"
        theme = "old"
        animation = "old"
        """)

        save_settings("dracula", "plasma", path)

        cfg = read_config(path)
        @test cfg["theme"] == "dracula"        # overwritten
        @test cfg["animation"] == "plasma"     # overwritten
        @test cfg["tries_path"] == "~/src/tries"   # preserved
        @test cfg["timezone"] == "utc"             # preserved
    end
end
