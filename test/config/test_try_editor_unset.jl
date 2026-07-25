@testitem "config: TRY_EDITOR unset → v0.2 behaviour" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        # Make sure TRY_EDITOR is cleared regardless of parent ENV.
        (code, out, err) = run_cli_subprocess(
            "silent-test";
            env_overrides=Dict("TRY_EDITOR" => "")
        )
        @test code == 0
        @test occursin(r"^cd '[^']+'\n$", out)
        # No editor diag should appear on stderr.
        @test !occursin("tryit: editor:", err)
    end
end
