@testitem "paths: tries_path is read from the config file" begin
    using TryIt: TriesPath

    # Driven with an explicit config path rather than TRY_CONFIG: an
    # ENV-based override is not safe when test items run concurrently.
    mktempdir() do dir
        cfg = joinpath(dir, "config.toml")
        root = joinpath(dir, "tries")
        write(cfg, string("tries_path = \"", root, "\"\n"))

        withenv("TRY_PATH" => nothing) do
            r = TriesPath(config=cfg)
            @test r.root == realpath(root)
            @test r.source === :config
            @test isdir(r.root)
        end
    end
end

@testitem "paths: tries_path expands a leading tilde" begin
    using TryIt: TriesPath

    # try-rs writes `tries_path = "~/src/tries"` in its own config, so
    # anyone aligning the two by hand will copy that spelling. Storing
    # it unexpanded would create a literal `./~` directory next to
    # wherever the shell happened to be.
    home = mktempdir()
    mktempdir() do dir
        cfg = joinpath(dir, "config.toml")
        write(cfg, "tries_path = \"~/src/tries\"\n")

        withenv("TRY_PATH" => nothing, "HOME" => home) do
            r = TriesPath(config=cfg)
            @test r.root == realpath(joinpath(home, "src", "tries"))
            @test r.source === :config
        end
    end
end

@testitem "paths: TRY_PATH beats the config file, which beats the default" begin
    using TryIt: TriesPath

    home = mktempdir()
    mktempdir() do dir
        cfg = joinpath(dir, "config.toml")
        from_file = joinpath(dir, "from-file")
        from_env = joinpath(dir, "from-env")
        write(cfg, string("tries_path = \"", from_file, "\"\n"))

        # Environment over file — the same precedence every other
        # setting follows.
        withenv("TRY_PATH" => from_env, "HOME" => home) do
            r = TriesPath(config=cfg)
            @test r.root == realpath(from_env)
            @test r.source === :env
        end

        # Positional over everything.
        withenv("TRY_PATH" => from_env, "HOME" => home) do
            explicit = mktempdir()
            r = TriesPath(positional=explicit, config=cfg)
            @test r.root == realpath(explicit)
            @test r.source === :arg
        end
    end

    # File absent or without the key — the default still applies.
    mktempdir() do dir
        cfg = joinpath(dir, "config.toml")
        write(cfg, "theme = \"dracula\"\n")
        withenv("TRY_PATH" => nothing, "HOME" => home) do
            r = TriesPath(config=cfg)
            @test r.root == realpath(joinpath(home, "work", "tries"))
            @test r.source === :default
        end
    end
end
