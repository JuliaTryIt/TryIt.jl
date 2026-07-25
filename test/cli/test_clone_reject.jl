@testitem "cli: clone rejection leaves no residue, propagates exit (UN3)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # `clone_exit = -128` tells the stub to exit 128 WITHOUT creating
    # the destination directory — the same shape a real `git clone`
    # takes when it rejects a URL.
    with_git_stub(clone_exit=-128) do _stub_dir
        with_tmp_tries() do dir
            (code, out, err) = run_cli_subprocess(
                "clone", "file:///nonexistent.git"
            )
            @test code == 128          # git's own code propagated (FR-029)
            @test isempty(out)         # UB4 channel stayed clean on failure
            # Tries path is byte-for-byte unchanged.
            @test isempty(readdir(dir))
        end
    end
end

@testitem "cli: clone rejection after partial dir removes residue (UN3)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Positive clone_exit tells the stub to CREATE the destination
    # before exiting non-zero — simulating a git that got partway
    # before hitting a fatal error. UN3 says we must clean up.
    with_git_stub(clone_exit=128) do _stub_dir
        with_tmp_tries() do dir
            (code, _out, _err) = run_cli_subprocess(
                "clone", "https://example.com/broken.git"
            )
            @test code == 128
            @test isempty(readdir(dir))  # clone_into clean-up fired
        end
    end
end
