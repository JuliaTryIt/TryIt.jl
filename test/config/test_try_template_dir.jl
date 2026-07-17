@testitem "config: .try-template as dir → stderr diag, non-fatal" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        mkpath(joinpath(dir, ".try-template"))

        (code, out, err) = run_cli_subprocess("tpl-dir")
        @test code == 0       # still succeeds
        @test occursin(r"^cd '[^']+'\n$", out)
        # Diag surfaced but non-fatal.
        @test occursin("tryit: template:", err)
        @test occursin("directory", err)
        # The new try was still created.
        path = String(match(r"^cd '([^']+)'\n$", out).captures[1])
        @test isdir(path)
        # No .try-template file copied (the source was a directory).
        @test !isfile(joinpath(path, ".try-template"))
    end
end
