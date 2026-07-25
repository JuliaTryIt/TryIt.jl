# The core trust layer, exercised with no scanner backend present.
#
# Everything here must hold whether or not PluginGuard is installed:
# these are TryIt's own types and its default no-op behaviour (OF7,
# OF8).

@testitem "trust: with no scanner registered the report is unavailable (OF7)" begin
    using TryIt

    # Force the default (no-op) scanner regardless of load order: an
    # extension test that does `using PluginGuard` swaps in a real
    # backend via __init__, so this test must not depend on ordering.
    previous = TryIt.TRUST_SCANNER[]
    TryIt.TRUST_SCANNER[] = TryIt.NoScanner()
    try
        mktempdir() do dir
            r = TryIt.scan_try(dir)
            @test r isa TryIt.TrustReport
            # Unavailable is *not* the same as clean. A caller that
            # conflated the two would report "no findings" for a tree
            # nothing ever looked at.
            @test !r.available
            @test isempty(r.findings)
            @test isempty(r.error)
            @test TryIt.trust_max_severity(r) === nothing
        end
    finally
        TryIt.TRUST_SCANNER[] = previous
    end
end

@testitem "trust: severity ranks are ordered and total (OF7)" begin
    using TryIt

    @test TryIt.trust_rank(:low) < TryIt.trust_rank(:med) < TryIt.trust_rank(:high)
    # An unknown symbol must rank below every real severity rather
    # than throwing: it reaches this function from a backend we do
    # not control, and a typo there must not abort a clone (OF8).
    @test TryIt.trust_rank(:nonsense) < TryIt.trust_rank(:low)
end

@testitem "trust: max severity picks the worst finding, not the last (OF7)" begin
    using TryIt

    findings = [
        TryIt.TrustFinding("a.jl", 1, :low, "low one"),
        TryIt.TrustFinding("b.jl", 2, :high, "high one"),
        TryIt.TrustFinding("c.jl", 3, :med, "med one")
    ]
    r = TryIt.TrustReport(true, findings, "")
    @test TryIt.trust_max_severity(r) === :high

    # And an available-but-clean scan is distinguishable from an
    # unavailable one by `available`, both reporting no severity.
    clean = TryIt.TrustReport(true, TryIt.TrustFinding[], "")
    @test TryIt.trust_max_severity(clean) === nothing
    @test clean.available
end

@testitem "trust: a scanner that throws fails open (OF8)" begin
    using TryIt

    struct ExplodingScanner <: TryIt.TrustScanner end
    TryIt.scan_try(::ExplodingScanner, ::AbstractString) = error("backend exploded")

    previous = TryIt.TRUST_SCANNER[]
    try
        TryIt.register_trust_scanner!(ExplodingScanner())
        mktempdir() do dir
            # The contract is that this returns rather than
            # propagating: `clone` has already succeeded on disk by
            # the time it runs, and a scanner fault must not turn a
            # completed operation into a failed one.
            r = TryIt.scan_try(dir)
            @test !r.available
            @test isempty(r.findings)
            @test occursin("exploded", r.error)
        end
    finally
        TryIt.register_trust_scanner!(previous)
    end
end

@testitem "trust: a registered scanner is consulted (OF7)" begin
    using TryIt

    struct StubScanner <: TryIt.TrustScanner end
    TryIt.scan_try(::StubScanner, path::AbstractString) = TryIt.TrustReport(
        true,
        [TryIt.TrustFinding(joinpath(path, "evil.jl"), 7, :high, "stub finding")],
        ""
    )

    previous = TryIt.TRUST_SCANNER[]
    try
        TryIt.register_trust_scanner!(StubScanner())
        mktempdir() do dir
            r = TryIt.scan_try(dir)
            @test r.available
            @test length(r.findings) == 1
            @test TryIt.trust_max_severity(r) === :high
            @test r.findings[1].line == 7
        end
    finally
        TryIt.register_trust_scanner!(previous)
    end
end

@testitem "trust: the core owns the trust layer, free of any backend" begin
    using TryIt

    # Same invariant as test_core_boundary.jl, stated for this
    # feature: the optional backend must never become a hard
    # reference from the core, or the weak dependency stops being
    # weak and TryIt fails to load without it.
    @test parentmodule(TryIt.TrustReport) === TryIt.Core
    @test parentmodule(TryIt.TrustScanner) === TryIt.Core
    @test parentmodule(TryIt.scan_try) === TryIt.Core
    @test !isdefined(TryIt.Core, :PluginGuard)
end
