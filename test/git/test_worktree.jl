@testitem "git: worktree against a real fixture repo (ED6)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    if Sys.which("git") === nothing
        @test_skip "git not installed"
    else
        with_real_git_repo() do repo
            with_tmp_tries() do dir
                # Change into the fixture repo so `git rev-parse --show-toplevel`
                # (inside `current_repo_root`) resolves correctly.
                cd(repo) do
                    (code, out, err) = run_cli_subprocess(
                        "worktree", "feature-spike"
                    )
                    @test code == 0
                    m = match(r"^cd '([^']+)'\n$", out)
                    @test m !== nothing
                    path = String(m.captures[1])
                    @test isdir(path)
                    @test occursin("-feature-spike", basename(path))
                    @test startswith(path, realpath(dir))
                    # Worktree leaves a .git file/dir in the destination.
                    @test ispath(joinpath(path, ".git"))
                end
            end
        end
    end
end
