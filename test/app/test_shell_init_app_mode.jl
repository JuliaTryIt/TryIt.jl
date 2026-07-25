@testitem "app: shell init targets the binary when running as a compiled app" begin
    using TryIt: emit_shell_init, _APP_MODE, _shell_function_text

    previous = _APP_MODE[]
    try
        _APP_MODE[] = true
        io = IOBuffer()
        emit_shell_init(io, "/some/tries")
        out = String(take!(io))

        # A compiled app carries its own runtime — the emitted
        # function must not shell out through `julia` at all.
        @test !occursin("--project=@TryIt", out)
        @test !occursin("using TryIt", out)
        @test !occursin("--startup-file=no", out)

        # It still has to behave like the interpreted form: emit a
        # command on stdout that the caller's shell evals.
        @test occursin("tryit() {", out)
        @test occursin("__try_cmd", out)
        # The definition is nested inside a quoted `eval`, so single
        # quotes arrive escaped as `'\\''`. Assert the unwrapped text
        # instead of trying to spell the escaping out here.
        definition = _shell_function_text(
            "/bin/tryit", "'/bin/tryit'", "missing", "TRY_PATH='/some/tries' "
        )
        @test occursin("TRY_PATH='/some/tries'", definition)

        # Regression: the app bundle ships a `bin/julia` launcher
        # alongside `bin/tryit`, and `Base.julia_cmd()` reports the
        # former. Emitting that would drop the user into a REPL
        # instead of running the CLI.
        @test !occursin("/bin/julia'", out)
        @test occursin("/tryit'", out)
    finally
        _APP_MODE[] = previous
    end
end

@testitem "app: shell init keeps the julia form when not a compiled app" begin
    using TryIt: emit_shell_init, _APP_MODE

    previous = _APP_MODE[]
    try
        _APP_MODE[] = false
        io = IOBuffer()
        emit_shell_init(io, "/some/tries")
        out = String(take!(io))

        # Regression guard: the interpreted path is what `Pkg.develop`
        # users get, and it must be unchanged by app support.
        @test occursin("--project=@TryIt", out)
        @test occursin("using TryIt", out)
    finally
        _APP_MODE[] = previous
    end
end
