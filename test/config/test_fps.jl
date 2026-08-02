@testitem "config: the frame rate defaults to 60" begin
    using TryIt: configured_fps, DEFAULT_FPS

    mktempdir() do dir
        path = joinpath(dir, "empty.toml")
        write(path, "")
        withenv("TRY_FPS" => nothing) do
            @test configured_fps(path) == DEFAULT_FPS
            @test configured_fps(path) == 60
        end
    end
end

@testitem "config: the frame rate is configurable" begin
    using TryIt: configured_fps

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "fps = 20\n")
        withenv("TRY_FPS" => nothing) do
            @test configured_fps(path) == 20
        end
        # Environment beats file, as everywhere else.
        withenv("TRY_FPS" => "15") do
            @test configured_fps(path) == 15
        end
    end
end

@testitem "config: the frame rate accepts a quoted or fractional value" begin
    using TryIt: configured_fps

    mktempdir() do dir
        # TOML has no coercion, so a hand-edited file may hold either
        # form. Both name a frame rate and neither should be ignored.
        quoted = joinpath(dir, "quoted.toml")
        write(quoted, "fps = \"24\"\n")
        fractional = joinpath(dir, "fractional.toml")
        write(fractional, "fps = 29.5\n")
        withenv("TRY_FPS" => nothing) do
            @test configured_fps(quoted) == 24
            @test configured_fps(fractional) == 30
        end
    end
end

@testitem "config: the frame rate is clamped into range" begin
    using TryIt: configured_fps, MIN_FPS, MAX_FPS

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        withenv("TRY_FPS" => nothing) do
            # Zero would divide by zero in Tachikoma's frame pacing and
            # a negative rate has no meaning; both floor at MIN_FPS.
            write(path, "fps = 0\n")
            @test configured_fps(path) == MIN_FPS
            write(path, "fps = -30\n")
            @test configured_fps(path) == MIN_FPS
            write(path, "fps = 100000\n")
            @test configured_fps(path) == MAX_FPS
        end
        withenv("TRY_FPS" => "0") do
            @test configured_fps(path) == MIN_FPS
        end
    end
end

@testitem "config: an unusable frame rate falls back" begin
    using TryIt: configured_fps, DEFAULT_FPS

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        withenv("TRY_FPS" => nothing) do
            # A typo should cost a wrong frame rate at worst, not a
            # crash — the file is hand-edited.
            write(path, "fps = \"fast\"\n")
            @test configured_fps(path) == DEFAULT_FPS
            # `true` is a Real in Julia; a boolean names no frame rate.
            write(path, "fps = true\n")
            @test configured_fps(path) == DEFAULT_FPS
            write(path, "fps = nan\n")
            @test configured_fps(path) == DEFAULT_FPS
        end
        # An unparseable override falls through to the file rather than
        # all the way to the default, so the file still has a say.
        write(path, "fps = 20\n")
        withenv("TRY_FPS" => "quickly") do
            @test configured_fps(path) == 20
        end
    end
end

@testitem "config: save_settings preserves a hand-written frame rate" begin
    using TryIt: configured_fps, read_config, save_settings

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "fps = 20\ntries_path = \"~/src/tries\"\n")
        withenv("TRY_FPS" => nothing) do
            save_settings("nord", "pulse", 0.25, path)
            cfg = read_config(path)
            @test cfg["theme"] == "nord"
            @test cfg["animation"] == "pulse"
            # Ctrl-W knows nothing about `fps`; merging must keep it.
            @test configured_fps(path) == 20
            @test cfg["tries_path"] == "~/src/tries"
        end
    end
end
