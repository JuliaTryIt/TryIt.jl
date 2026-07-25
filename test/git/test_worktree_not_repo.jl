@testitem "git: worktree refuses non-repo CWD (OF2)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Use a tempdir that we control so we know for certain it is not
    # inside any git repository. `mktempdir` returns a path under
    # `$TMPDIR`, which is never a git repo on any supported platform.
    outside = mktempdir()
    try
        with_tmp_tries() do _dir
            cd(outside) do
                (code, out, err) = run_cli_subprocess(
                    "worktree", "anything"
                )
                @test code == 64
                @test isempty(out)
                @test occursin("not inside a git repository", err)
            end
        end
    finally
        rm(outside; recursive=true, force=true)
    end
end
