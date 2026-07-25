# The backend must activate for a process that only ever loads TryIt
# (OF7).
#
# This is the test the feature needed from the start and did not
# have. A package extension activates when its trigger package is
# *loaded*, not when it is installed, and the shell function `tryit
# init` emits runs `julia -e 'using TryIt; TryIt.main(ARGS)'`. Every
# other test in this directory says `using PluginGuard` first, so all
# of them passed while the feature was inert for every CLI user.
#
# Run in a subprocess on purpose: `@testitem` blocks share a process,
# and a sibling test that loaded PluginGuard would make an in-process
# version of this pass for the wrong reason.

@testitem "trust: the backend loads on demand, with no explicit import (OF7)" begin
    using TryIt

    # The test environment has PluginGuard as a dependency, which is
    # the situation of a user who installed it — installed, not
    # imported.
    project = Base.active_project()
    mktempdir() do dir
        write(joinpath(dir, "payload.jl"),
            "x = getfield(Base, Symbol(\"run\"))\n")

        script = """
        using TryIt
        println("SCANNER=", TryIt.TRUST_SCANNER[] isa TryIt.NoScanner ? "none" : "live")
        println("REPORTED=", TryIt._report_trust($(repr(dir))))
        """
        out = IOBuffer()
        err = IOBuffer()
        cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e $script`
        run(pipeline(cmd; stdout=out, stderr=err))
        stdout_text = String(take!(out))
        stderr_text = String(take!(err))

        # Installed but never imported: the scanner starts absent and
        # is pulled in by the scan itself.
        @test occursin("SCANNER=none", stdout_text)
        @test occursin("REPORTED=1", stdout_text)
        @test occursin("tryit: trust:", stderr_text)
        @test occursin("payload.jl", stderr_text)
    end
end

@testitem "trust: probing the backend is idempotent and never throws (OF8)" begin
    using TryIt

    # Called on every clone and every fetch; a second call must be a
    # no-op rather than a second `Base.require`.
    @test TryIt._ensure_trust_backend() === nothing
    @test TryIt._ensure_trust_backend() === nothing
    # Idempotency is now tracked per-extension in _ACTIVATION_TRIED
    # (replaced the old _TRUST_BACKEND_PROBED global flag).
    @test haskey(TryIt._ACTIVATION_TRIED, "pluginguard")
end
