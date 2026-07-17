@testitem "git: missing git rejects clone (UN5)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        # Empty PATH → `Sys.which("git")` inside the subprocess returns
        # nothing, regardless of what `git` the parent process found.
        (code, out, err) = run_cli_subprocess(
            "clone", "https://example.com/foo.git";
            env_overrides=Dict("PATH" => "")
        )
        @test code == 127
        @test isempty(out)
        @test occursin("git not found", err)
        @test isempty(readdir(dir))
    end
end

@testitem "git: missing git rejects worktree (UN5)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        (code, out, err) = run_cli_subprocess(
            "worktree", "anything";
            env_overrides=Dict("PATH" => "")
        )
        @test code == 127
        @test isempty(out)
        @test occursin("git not found", err)
        @test isempty(readdir(dir))
    end
end
