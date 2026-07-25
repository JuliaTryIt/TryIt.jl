@testitem "config: TRY_EDITOR spawns editor with try path (OF1)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))
    if Sys.iswindows()
        @test_skip "TRY_EDITOR stub is sh-based; Windows variant is v0.4 scope."
    else
        stub_dir = mktempdir()
        sentinel = joinpath(stub_dir, "argv.txt")
        stub_path = joinpath(stub_dir, "fake-editor")
        write(stub_path, """
        #!/bin/sh
        printf '%s\\n' \"\$@\" > $(sentinel)
        """)
        chmod(stub_path, 0o755)

        with_tmp_tries() do tries_dir
            (code, out, _err) = run_cli_subprocess(
                "my-slug";
                env_overrides=Dict("TRY_EDITOR" => stub_path)
            )
            @test code == 0
            # Editor is fire-and-forget; wait up to 2s for the sentinel.
            for _ in 1:40
                isfile(sentinel) && break
                sleep(0.05)
            end
            @test isfile(sentinel)
            path_from_cd = String(match(r"^cd '([^']+)'\n$", out).captures[1])
            argv = strip(read(sentinel, String))
            @test argv == path_from_cd
        end
    end
end
