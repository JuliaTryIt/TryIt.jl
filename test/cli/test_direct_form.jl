@testitem "cli: non-TTY direct form creates and emits cd (UN4 sentence 3)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        (code, out, err) = run_cli_subprocess("my-slug")

        @test code == 0
        @test occursin(r"^cd '", out)
        @test occursin("my-slug", out)
        @test isempty(err) || occursin("Precompiling", err) # allow transient precompile logs
        # The cd path MUST be a single line ending with newline (UB4).
        @test endswith(out, "\n")
        @test count('\n', out) == 1
        # And the directory must exist.
        path = String(match(r"^cd '([^']*)'", out).captures[1])
        @test isdir(path)
        @test startswith(path, dir)
    end
end

@testitem "cli: non-TTY with no arg exits 64 (UN4)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        (code, out, err) = run_cli_subprocess()
        @test code == 64
        @test isempty(out)
        @test occursin("tryit:", err)
    end
end

@testitem "cli: empty-slug arg exits 64" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        (code, out, err) = run_cli_subprocess("!!!")
        @test code == 64
        @test isempty(out)
        @test occursin("tryit:", err)
    end
end

@testitem "cli: init emits a shell function (ED13)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    (code, out, err) = run_cli_subprocess("init")
    @test code == 0
    # Emitted shell function begins with `tryit()`.
    @test occursin(r"^tryit\(\)\s*\{", out)
    # Contains an eval line to apply the cd command.
    @test occursin("eval", out)
    # Contains the tries-path fallback when no arg was given.
    @test occursin("TRY_PATH:-", out)
    @test occursin("src/tries", out)
end

@testitem "cli: init with positional hard-codes the tries path" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    (code, out, _err) = run_cli_subprocess("init", "/custom/tries/path")
    @test code == 0
    @test occursin("/custom/tries/path", out)
    @test !occursin("TRY_PATH:-", out)
end
