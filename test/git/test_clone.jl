@testitem "git: clone happy path derives name from URL (ED5)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_git_stub() do _stub_dir
        with_tmp_tries() do dir
            (code, out, err) = run_cli_subprocess(
                "clone", "https://github.com/foo/bar.git"
            )
            @test code == 0
            @test occursin(r"^cd '[^']+'\n$", out)
            m = match(r"^cd '([^']+)'\n$", out)
            @test m !== nothing
            path = String(m.captures[1])
            @test isdir(path)
            @test occursin("-bar", basename(path))
            @test startswith(path, realpath(dir))
        end
    end
end

@testitem "git: clone happy path honours explicit <name> (ED5)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_git_stub() do _stub_dir
        with_tmp_tries() do dir
            (code, out, _err) = run_cli_subprocess(
                "clone", "https://github.com/foo/bar.git", "spike-one"
            )
            @test code == 0
            m = match(r"^cd '([^']+)'\n$", out)
            path = String(m.captures[1])
            @test isdir(path)
            @test occursin("-spike-one", basename(path))
            @test !occursin("-bar", basename(path))  # explicit name wins over URL basename
        end
    end
end

@testitem "git: clone strips .git suffix from URL basename (ED5)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_git_stub() do _stub_dir
        with_tmp_tries() do _dir
            (code, out, _err) = run_cli_subprocess(
                "clone", "git@github.com:foo/bar.git"
            )
            @test code == 0
            m = match(r"^cd '([^']+)'\n$", out)
            path = String(m.captures[1])
            # basename ends in "-bar", NOT "-bar-git" or similar.
            @test endswith(basename(path), "-bar")
        end
    end
end
