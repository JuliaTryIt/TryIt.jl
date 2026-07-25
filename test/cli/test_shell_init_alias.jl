@testitem "cli: shell init clears a conflicting alias first" begin
    using TryIt: emit_shell_init

    io = IOBuffer()
    emit_shell_init(io, "/some/tries")
    out = String(take!(io))

    # zsh refuses to define a function whose name is an existing
    # alias ("defining function based on alias"), so the snippet must
    # drop the alias before the definition, not after.
    unalias_at = findfirst("unalias tryit", out)
    define_at = findfirst("tryit() {", out)
    @test unalias_at !== nothing
    @test define_at !== nothing
    @test first(unalias_at) < first(define_at)

    # It must not fail under `set -e` when no alias exists.
    @test occursin("unalias tryit 2>/dev/null || true", out)
end

@testitem "cli: emitted shell init survives a pre-existing alias" begin
    # Regression: a user with `alias tryit='try-rs'` in their rc could
    # never install the shell function — the eval aborted with a parse
    # error and their old `tryit` kept running.
    using TryIt: emit_shell_init

    for shell in ("zsh", "bash")
        which_shell = Sys.which(shell)
        which_shell === nothing && continue

        mktempdir() do dir
            io = IOBuffer()
            emit_shell_init(io, dir)
            snippet = String(take!(io))

            script = joinpath(dir, "probe.sh")
            # Define the conflicting alias first, exactly as a user's
            # rc would, then install our function over it.
            write(
                script,
                """
                alias tryit='echo WRONG-BINARY'
                $(snippet)
                type tryit
                """
            )
            out = read(`$(which_shell) $(script)`, String)
            @test occursin("function", out)
            @test !occursin("WRONG-BINARY", out)
        end
    end
end

@testitem "cli: shell init does not pin TRY_PATH when no root is given" begin
    using TryIt: emit_shell_init

    # Injecting `TRY_PATH=${TRY_PATH:-$HOME/work/tries}` made the
    # environment branch of _resolve_tries_root always win, so the
    # `tries_path` config setting could never be reached — the setting
    # existed but was unreachable through the shell function, which is
    # the only way anyone actually invokes TryIt.
    io = IOBuffer()
    emit_shell_init(io)
    out = String(take!(io))
    @test !occursin("TRY_PATH=", out)

    # An explicit root is still pinned: that is the whole point of
    # `tryit init <dir>`.
    io = IOBuffer()
    emit_shell_init(io, "/somewhere/tries")
    out = String(take!(io))
    @test occursin("TRY_PATH=", out)
    @test occursin("/somewhere/tries", out)
end
