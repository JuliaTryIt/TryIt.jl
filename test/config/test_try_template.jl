@testitem "config: .try-template copied into new tries (OF3)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        template_content = "FROM_TEMPLATE=true\nsome scaffolding\n"
        write(joinpath(dir, ".try-template"), template_content)

        (code, out, _err) = run_cli_subprocess("new-try-from-tpl")
        @test code == 0
        path = String(match(r"^cd '([^']+)'\n$", out).captures[1])
        copied = joinpath(path, ".try-template")
        @test isfile(copied)
        @test read(copied, String) == template_content
    end
end
