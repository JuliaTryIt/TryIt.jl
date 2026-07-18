@testitem "selector: finish_recording! stops an active recorder" begin
    using TryIt: finish_recording!
    using Tachikoma

    rec = Tachikoma.CastRecorder()
    rec.active = true
    rec.filename = "somewhere.tach"

    # No captured frames, so `stop_recording!` returns the filename
    # without writing anything — the flush path is exercised without
    # touching the filesystem.
    name = finish_recording!(rec)
    @test rec.active === false
    @test name == "somewhere.tach"
end

@testitem "selector: finish_recording! is a no-op when idle" begin
    using TryIt: finish_recording!
    using Tachikoma

    rec = Tachikoma.CastRecorder()
    @test rec.active === false
    @test finish_recording!(rec) == ""
    @test rec.active === false
end

@testitem "selector: cleanup! flushes a recording left running on exit" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Regression: `stop_recording!` is what writes the .tach file, so
    # selecting a try (Enter → :cd → done) while recording used to end
    # the session with the capture silently discarded. Only a second
    # F9 ever wrote a file.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        session = TryIt.open_session(root)

        # No terminal attached — cleanup! must not dereference nothing.
        @test Tachikoma.cleanup!(session) === nothing
    end
end

@testitem "selector: recording filename lands in the tries root" begin
    using TryIt: recording_path
    using Tachikoma

    mktempdir() do dir
        path = recording_path(dir)
        # A predictable, writable home rather than whatever directory
        # the user happened to run `tryit` from.
        @test dirname(path) == dir
        @test startswith(basename(path), "tryit_")
        @test endswith(path, ".tach")
    end
end
