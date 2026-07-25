@testitem "cli: the shell function does not eval informational output" begin
    using TryIt
    using TryIt: emit_shell_init

    # Regression: everything on stdout is eval'd, so `tryit --help`
    # made the shell try to execute each line of the help text —
    # "command not found: usage:", and so on down the page.
    io = IOBuffer()
    emit_shell_init(io, "/some/tries")
    out = String(take!(io))

    @test occursin("case \"\$1\" in", out)
    for sub in ("--help", "--version", "path", "list")
        @test occursin(sub, out)
    end
    # The bypass must come before the capture, or it never runs.
    @test findfirst("case \"\$1\" in", out) < findfirst("__try_cmd=", out)
end

@testitem "cli: informational subcommands run under a real shell" begin
    using TryIt
    using TryIt: emit_shell_init

    shell = something(Sys.which("zsh"), Sys.which("bash"), Some(nothing))
    shell === nothing && return

    # Drives the emitted function end to end: this failure only
    # appears once a shell actually evaluates stdout, so every unit
    # test passed while `tryit --help` was unusable.
    mktempdir() do dir
        io = IOBuffer()
        # `_APP_MODE` is a process-global Ref that `_app_main` sets and
        # never clears, so an earlier test item can leave it true and
        # make this emit the compiled-app form — pointing at a binary
        # that does not exist here. Pin it for the duration.
        previous = TryIt._APP_MODE[]
        TryIt._APP_MODE[] = false
        try
            emit_shell_init(io, dir)
            # `pkgdir` rather than a relative path — the repository can be
            # moved, and a relative --project silently resolves elsewhere.
            snippet = replace(String(take!(io)), "@TryIt" => pkgdir(TryIt))

            script = joinpath(dir, "probe.sh")
            write(script, string(snippet, "\ntryit --help\n"))

            out = IOBuffer()
            # `Pkg.test` sets JULIA_LOAD_PATH for its own sandbox, and the
            # julia the shell function spawns inherits it — leaving the
            # child unable to resolve the package's own dependencies.
            # Clear both so the child sees only `--project`.
            proc = withenv("JULIA_LOAD_PATH" => nothing, "JULIA_PROJECT" => nothing) do
                # `ignorestatus` and a merged stream: a throwing `read`
                # would hide the very output the assertions need.
                run(pipeline(ignorestatus(`$(shell) $(script)`);
                    stdout=out, stderr=out))
            end
            text = String(take!(out))

            @test proc.exitcode == 0
            @test occursin("usage", lowercase(text))
            # The tell-tale of the bug: the shell reporting the help text
            # back as commands it could not find.
            @test !occursin("command not found", text)
            @test !occursin("no such file or directory", lowercase(text))
        finally
            TryIt._APP_MODE[] = previous
        end
    end
end
