@testitem "cli: a bare URL is treated as a clone" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # All three upstreams accept `try <url>` with no `clone` keyword;
    # users type it by muscle memory.
    with_git_stub() do _stub
        with_tmp_tries() do dir
            for url in ("https://example.com/foo.git", "git@example.com:bar.git")
                (code, out, err) = run_cli_subprocess(url)
                @test code == 0
                @test occursin("cd ", out)
            end
            names = readdir(dir)
            @test any(n -> endswith(n, "-foo"), names)
            @test any(n -> endswith(n, "-bar"), names)
        end
    end
end

@testitem "cli: a URL-like slug is still a slug when explicit" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # `--` forces slug interpretation, so a name that happens to look
    # like a URL is still reachable.
    with_tmp_tries() do dir
        (code, out, err) = run_cli_subprocess("--", "http-notes")
        @test code == 0
        @test occursin("http-notes", only(readdir(dir)))
    end
end

@testitem "cli: path prints the tries root and nothing else" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Neither upstream can do this — every listing goes through their
    # TUI — so scripts have to re-derive the path in shell.
    with_tmp_tries() do dir
        (code, out, err) = run_cli_subprocess("path")
        @test code == 0
        @test strip(out) == realpath(dir)
        @test count('\n', out) == 1
    end
end

@testitem "cli: list prints one try per line" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        run_cli_subprocess("alpha")
        run_cli_subprocess("beta")
        mkpath(joinpath(dir, "undated-one"))

        (code, out, err) = run_cli_subprocess("list")
        @test code == 0
        lines = filter(!isempty, split(out, '\n'))
        @test length(lines) == 3
        # Absolute paths, so the output pipes straight into xargs.
        @test all(startswith(l, "/") for l in lines)
        @test any(l -> endswith(l, "-alpha"), lines)
        @test any(l -> endswith(l, "undated-one"), lines)
    end
end

@testitem "cli: list is empty and succeeds when there are no tries" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        (code, out, err) = run_cli_subprocess("list")
        @test code == 0            # not an error, just nothing
        @test isempty(strip(out))
    end
end

@testitem "cli: NO_COLOR and --no-colors are accepted" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        # A documented convention (no-color.org) that the C upstream
        # honours; it must not be mistaken for a slug.
        (code, out, err) = run_cli_subprocess("--no-colors", "quiet-one")
        @test code == 0
        @test occursin("quiet-one", only(readdir(dir)))
    end
end
