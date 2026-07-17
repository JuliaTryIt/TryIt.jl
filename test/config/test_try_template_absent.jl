@testitem "config: no template → v0.2 behaviour" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do _dir
        # No .try-template present.
        (code, out, err) = run_cli_subprocess("no-tpl")
        @test code == 0
        path = String(match(r"^cd '([^']+)'\n$", out).captures[1])
        @test !isfile(joinpath(path, ".try-template"))
        @test !occursin("tryit: template:", err)
    end
end
