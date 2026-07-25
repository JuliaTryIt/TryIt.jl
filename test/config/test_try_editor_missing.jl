@testitem "config: TRY_EDITOR pointing at missing binary is non-fatal (OF1)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        (code, out, err) = run_cli_subprocess(
            "missing-editor-test";
            env_overrides=Dict("TRY_EDITOR" => "/nonexistent/editor")
        )
        # `cd` still emitted, exit code is still 0.
        @test code == 0
        @test occursin(r"^cd '[^']+'\n$", out)
        # Editor failure surfaces as a stderr diag.
        @test occursin("tryit: editor:", err)
    end
end
