@testitem "config: the fps display defaults to off" begin
    using TryIt: configured_show_fps

    mktempdir() do dir
        path = joinpath(dir, "empty.toml")
        write(path, "")
        withenv("TRY_SHOW_FPS" => nothing) do
            @test configured_show_fps(path) === false
        end
    end
end

@testitem "config: the fps display is configurable" begin
    using TryIt: configured_show_fps

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        withenv("TRY_SHOW_FPS" => nothing) do
            # TOML boolean and the truthy string spellings a hand-editor
            # might reach for all enable it.
            write(path, "show_fps = true\n")
            @test configured_show_fps(path) === true
            write(path, "show_fps = \"yes\"\n")
            @test configured_show_fps(path) === true
            write(path, "show_fps = \"1\"\n")
            @test configured_show_fps(path) === true
            write(path, "show_fps = false\n")
            @test configured_show_fps(path) === false
        end
        # Environment beats file, as everywhere else.
        write(path, "show_fps = false\n")
        withenv("TRY_SHOW_FPS" => "on") do
            @test configured_show_fps(path) === true
        end
        withenv("TRY_SHOW_FPS" => "0") do
            write(path, "show_fps = true\n")
            @test configured_show_fps(path) === false
        end
    end
end

@testitem "config: an unrecognised fps-display value is off" begin
    using TryIt: configured_show_fps

    mktempdir() do dir
        path = joinpath(dir, "config.toml")
        write(path, "show_fps = \"maybe\"\n")
        withenv("TRY_SHOW_FPS" => nothing) do
            # A typo should not silently turn a diagnostic overlay on.
            @test configured_show_fps(path) === false
        end
    end
end

@testitem "fps: the meter reports zero until it has a full window" begin
    using TryIt: FpsMeter, fps_tick!

    m = FpsMeter()
    # First tick only seeds the window start; no rate yet.
    @test fps_tick!(m, 100.0) == 0.0
    @test fps_tick!(m, 100.1) == 0.0
end

@testitem "fps: the meter computes the rate over its window" begin
    using TryIt: FpsMeter, fps_tick!

    m = FpsMeter()
    fps_tick!(m, 0.0; window=1.0)      # seed
    # 30 frames land within one second; the rate updates on the frame
    # that closes the window.
    for i in 1:30
        fps_tick!(m, i / 30; window=1.0)
    end
    @test m.value≈30.0 atol=1.0
end

@testitem "fps: the meter tracks a change in rate" begin
    using TryIt: FpsMeter, fps_tick!

    m = FpsMeter()
    fps_tick!(m, 0.0; window=0.5)
    # First window: 60 fps.
    for i in 1:30
        fps_tick!(m, i / 60; window=0.5)
    end
    @test m.value≈60.0 atol=2.0
    # Second window: 5 frames over 0.5s starting at t=0.5 → 10 fps.
    for k in 1:5
        fps_tick!(m, 0.5 + 0.1 * k; window=0.5)
    end
    @test m.value≈10.0 atol=1.0
end
