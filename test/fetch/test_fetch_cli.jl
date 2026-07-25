# `tryit fetch` end to end (ED26), and the routing that decides
# between clone and fetch for a bare URL (ED27).

@testitem "fetch: the subcommand emits a cd for the new try (ED26)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        source = joinpath(mktempdir(), "snippet.jl")
        write(source, "f(x) = x + 1\n")

        (code, out, _err) = run_cli_subprocess("fetch", "file://" * source)
        @test code == 0
        m = match(r"^cd '([^']+)'\n$", out)
        @test m !== nothing
        path = String(m.captures[1])
        @test isdir(path)
        @test isfile(joinpath(path, "snippet.jl"))
        @test startswith(path, realpath(dir))
    end
end

@testitem "fetch: an explicit name reaches the CLI (ED26)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        source = joinpath(mktempdir(), "snippet.jl")
        write(source, "x = 1\n")

        (code, out, _err) = run_cli_subprocess(
            "fetch", "file://" * source, "my-spike"
        )
        @test code == 0
        m = match(r"^cd '([^']+)'\n$", out)
        path = String(m.captures[1])
        @test occursin("-my-spike", basename(path))
        @test isfile(joinpath(path, "snippet.jl"))
    end
end

@testitem "fetch: a failed download exits 1 with no cd and no residue (UN11)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        (code, out, err) = run_cli_subprocess(
            "fetch", "file:///definitely/not/here/missing.jl"
        )
        # UB6: generic operation failure, distinct from usage (64),
        # permission (2) and missing dependency (127).
        @test code == 1
        @test isempty(out)          # nothing for the shell to eval
        @test occursin("tryit: fetch:", err)
        @test isempty(readdir(dir))
    end
end

@testitem "fetch: wrong argument counts are usage errors (ED26)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        (code_none, out_none, err_none) = run_cli_subprocess("fetch")
        @test code_none == 64
        @test isempty(out_none)
        @test occursin("tryit: usage:", err_none)

        (code_many, _out, _err) = run_cli_subprocess(
            "fetch", "https://example.com/a.jl", "name", "extra"
        )
        @test code_many == 64
    end
end

@testitem "fetch: a bare forge URL still clones (ED25, ED27)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Regression guard on the routing change: the bare-URL form that
    # already worked must keep working, and must not be diverted into
    # the new download path.
    with_git_stub() do _stub
        with_tmp_tries() do _dir
            (code, out, _err) = run_cli_subprocess("https://github.com/foo/bar")
            @test code == 0
            m = match(r"^cd '([^']+)'\n$", out)
            @test m !== nothing
            @test occursin("-bar", basename(String(m.captures[1])))
        end
    end
end

@testitem "fetch: help mentions the subcommand (ED26)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    (code, out, _err) = run_cli_subprocess("--help")
    @test code == 0
    @test occursin("fetch", out)
end
