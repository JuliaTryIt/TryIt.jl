# The PluginGuard package extension.
#
# PluginGuard is a hard dependency of the *test* environment (see
# `test/Project.toml`) though only a weak one of the package. That is
# deliberate: the extension has to be exercised somewhere, and the
# only environment allowed to demand it is this one.
#
# These run in-process rather than through `run_cli_subprocess`,
# because that helper launches julia with `--project=<package root>`,
# where PluginGuard is absent and the extension correctly stays
# dormant. The subprocess tests in `test_clone_guard.jl` cover that
# half; these cover the backend actually working.

@testitem "trust: loading PluginGuard registers the scanner (OF7)" begin
    using TryIt
    using PluginGuard

    ext = Base.get_extension(TryIt, :TryItPluginGuardExt)
    @test ext !== nothing
    # `__init__` swaps the default `NoScanner` for the real backend.
    # Were this to regress, the feature would silently become a no-op
    # while every other test in this file still passed.
    @test !(TryIt.TRUST_SCANNER[] isa TryIt.NoScanner)
end

@testitem "trust: the extension flags an obfuscated payload (OF7)" begin
    using TryIt
    using PluginGuard

    mktempdir() do dir
        # Modelled on the file that prompted this feature: a
        # plausible-looking module that never spells `run` or `Cmd`,
        # reconstructing both from data at runtime. Kept inert and
        # never executed — it is scanned as text.
        write(joinpath(dir, "photoabsorption.jl"), """
        module Photoabsorption
        const RAMP = String(collect(' ':'~'))
        function flush_record(field)
            sink    = getfield(Base, Symbol(String(field[1:3])))
            wrapper = getfield(Base, Symbol(String(field[4:6])))
            sink(wrapper([String(field[7:10]), String(field[11:end])]))
        end
        end
        """)
        write(joinpath(dir, "harmless.jl"), "y = 1 + 1\n")

        r = TryIt.scan_try(dir)
        @test r.available
        @test isempty(r.error)
        @test TryIt.trust_max_severity(r) === :high
        @test any(f -> occursin("photoabsorption.jl", f.file), r.findings)
        @test !any(f -> occursin("harmless.jl", f.file), r.findings)

        # A finding must carry a usable location, or the warning tells
        # the user something is wrong without saying where.
        bad = first(filter(f -> occursin("photoabsorption.jl", f.file), r.findings))
        @test bad.line >= 1
        @test !isempty(bad.description)
    end
end

@testitem "trust: the extension reports a clean tree as clean (OF7)" begin
    using TryIt
    using PluginGuard

    mktempdir() do dir
        write(joinpath(dir, "ok.jl"), "module Ok\ngreet() = \"hi\"\nend\n")
        r = TryIt.scan_try(dir)
        # Available *and* empty — the distinction the core types exist
        # to preserve, and the one a caller must not collapse.
        @test r.available
        @test isempty(r.findings)
        @test TryIt.trust_max_severity(r) === nothing
    end
end

@testitem "trust: the backend's severities are mapped, not leaked (OF7)" begin
    using TryIt
    using PluginGuard

    mktempdir() do dir
        write(joinpath(dir, "payload.jl"),
            "x = getfield(Base, Symbol(\"run\"))\n")
        r = TryIt.scan_try(dir)
        @test !isempty(r.findings)
        for f in r.findings
            # PluginGuard's `Severity` enum must not reach the core:
            # every finding carries one of TryIt's own three symbols.
            @test f isa TryIt.TrustFinding
            @test f.severity in (:low, :med, :high)
        end
    end
end

@testitem "trust: a fetched payload is reported before the cd (OF7)" begin
    using TryIt
    using PluginGuard
    include(joinpath(@__DIR__, "trust_helpers.jl"))
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # The end-to-end shape of the motivating case, with the real
    # backend: fetch drops a single file of somebody else's code into
    # a try, and the user is warned before being sent into it.
    with_tmp_tries() do dir
        source = joinpath(mktempdir(), "photoabsorption.jl")
        write(source, "x = getfield(Base, Symbol(\"run\"))\n")

        root = TryIt.TriesPath(positional=dir)
        inv = TryIt.FetchInvocation("file://" * source, nothing, root)
        result = TryIt.fetch_into(inv)
        @test result.ok

        local n
        text = capture_stderr() do
            n = TryIt._report_trust(inv.dest)
        end
        @test n >= 1
        @test occursin("tryit: trust:", text)
        @test occursin("photoabsorption.jl", text)
    end
end
