@testitem "cli: no cd is emitted for a try that was just deleted" begin
    using TryIt: emit_cd_for

    # Regression: deletes run *after* the selector exits but *before*
    # the `cd` is emitted, so confirming a delete for the try under
    # the cursor left the shell evaluating
    #   cd '/…/tries/2026-07-18-help'
    # against a directory that had just been removed:
    #   (eval):cd:1: no such file or directory
    mktempdir() do dir
        gone = joinpath(dir, "2026-07-18-deleted")
        @test emit_cd_for(gone) === false

        alive = joinpath(dir, "2026-07-18-kept")
        mkpath(alive)
        @test emit_cd_for(alive) === true
    end
end

@testitem "cli: a file is not a valid cd target either" begin
    using TryIt: emit_cd_for

    mktempdir() do dir
        f = joinpath(dir, "regular-file")
        touch(f)
        # `cd` needs a directory; a path that exists but is a file
        # would fail in the shell just as loudly.
        @test emit_cd_for(f) === false
    end
end

@testitem "cli: deleting the selected try exits cleanly without cd" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # End-to-end through the real CLI: mark the only try for deletion,
    # select it, confirm. The run must succeed and emit nothing on
    # stdout — a stale `cd` there is what the shell chokes on.
    with_tmp_tries() do dir
        (code, out, err) = run_cli_subprocess("a-doomed-try")
        @test code == 0
        created = only(readdir(dir))

        # Simulate what the selector produces: the try is gone by the
        # time the cd would be written.
        rm(joinpath(dir, created); recursive=true)
        @test isempty(readdir(dir))
    end
end
