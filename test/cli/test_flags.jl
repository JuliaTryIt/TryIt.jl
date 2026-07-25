@testitem "cli: --help prints usage and creates nothing" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Regression: every flag was treated as a slug. `slug("--help")`
    # strips to "help", so `tryit --help` silently created
    # `2026-07-18-help` and exited 0 — the opposite of what every CLI
    # does, and it littered the user's real tries directory.
    with_tmp_tries() do dir
        for flag in ("--help", "-h")
            (code, out, err) = run_cli_subprocess(flag)
            @test code == 0
            @test occursin("usage", lowercase(out))
            @test isempty(readdir(dir))
        end
    end
end

@testitem "cli: --version prints a version and creates nothing" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        for flag in ("--version", "-V")
            (code, out, err) = run_cli_subprocess(flag)
            @test code == 0
            @test occursin(r"\d+\.\d+", out)
            @test isempty(readdir(dir))
        end
    end
end

@testitem "cli: an unknown flag is a usage error, not a directory" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        for flag in ("--nope", "-x", "--dry-run")
            (code, out, err) = run_cli_subprocess(flag)
            @test code == 64                 # EX_USAGE
            @test isempty(out)               # stdout is eval'd by the shell
            @test occursin("unknown", lowercase(err))
            @test isempty(readdir(dir))
        end
    end
end

@testitem "cli: -- forces the next argument to be a slug" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Without an escape hatch, a try whose name begins with a dash
    # would be uncreatable from the CLI.
    with_tmp_tries() do dir
        (code, out, err) = run_cli_subprocess("--", "--weird-name")
        @test code == 0
        @test occursin("cd ", out)
        @test length(readdir(dir)) == 1
        @test occursin("weird-name", only(readdir(dir)))
    end
end

@testitem "cli: help output names every subcommand" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        (code, out, err) = run_cli_subprocess("--help")
        for token in ("init", "clone", "worktree", "TRY_PATH")
            @test occursin(token, out)
        end
    end
end
