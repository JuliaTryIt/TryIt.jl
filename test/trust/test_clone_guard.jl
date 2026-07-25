# The advisory warning `tryit clone` emits when a scan comes back
# dirty (OF7), and its fail-open behaviour (OF8).
#
# `_report_trust` is exercised directly rather than through a cloned
# repository: the git stub creates an empty destination, so an
# end-to-end run has nothing for a scanner to find. The subprocess
# test at the bottom covers the other half — that the default,
# backend-free build stays silent.

@testitem "trust: a HIGH finding is reported on stderr (OF7)" begin
    using TryIt
    include(joinpath(@__DIR__, "trust_helpers.jl"))

    struct DirtyScanner <: TryIt.TrustScanner end
    TryIt.scan_try(::DirtyScanner, path::AbstractString) = TryIt.TrustReport(
        true,
        [
            TryIt.TrustFinding(joinpath(path, "payload.jl"), 12, :high,
                "dynamic symbol resolution"),
            TryIt.TrustFinding(joinpath(path, "noise.jl"), 3, :low,
                "something minor")
        ],
        ""
    )

    previous = TryIt.TRUST_SCANNER[]
    try
        TryIt.register_trust_scanner!(DirtyScanner())
        mktempdir() do dir
            text = capture_stderr() do
                TryIt._report_trust(dir)
            end
            @test occursin("tryit: trust:", text)
            @test occursin("payload.jl", text)
            @test occursin("12", text)
            @test occursin("dynamic symbol resolution", text)
            # Only HIGH is surfaced. Reporting LOW and MED here would
            # bury the one line that matters under noise on every
            # clone of a normal repository.
            @test !occursin("noise.jl", text)
            @test !occursin("something minor", text)
        end
    finally
        TryIt.register_trust_scanner!(previous)
    end
end

@testitem "trust: reporting returns the HIGH count and never throws (OF7)" begin
    using TryIt
    include(joinpath(@__DIR__, "trust_helpers.jl"))

    struct CountScanner <: TryIt.TrustScanner end
    TryIt.scan_try(::CountScanner, path::AbstractString) = TryIt.TrustReport(
        true,
        [
            TryIt.TrustFinding(joinpath(path, "a.jl"), 1, :high, "one"),
            TryIt.TrustFinding(joinpath(path, "b.jl"), 2, :high, "two"),
            TryIt.TrustFinding(joinpath(path, "c.jl"), 3, :med, "three")
        ],
        ""
    )

    previous = TryIt.TRUST_SCANNER[]
    try
        TryIt.register_trust_scanner!(CountScanner())
        mktempdir() do dir
            local n
            capture_stderr() do
                n = TryIt._report_trust(dir)
            end
            # The count is what the caller may log; it is never a
            # failure signal. The clone already succeeded on disk and
            # the `cd` is emitted regardless.
            @test n == 2
        end
    finally
        TryIt.register_trust_scanner!(previous)
    end
end

@testitem "trust: a clean scan emits nothing (OF7)" begin
    using TryIt
    include(joinpath(@__DIR__, "trust_helpers.jl"))

    struct CleanScanner <: TryIt.TrustScanner end
    TryIt.scan_try(::CleanScanner, ::AbstractString) = TryIt.TrustReport(
        true, TryIt.TrustFinding[], "")

    previous = TryIt.TRUST_SCANNER[]
    try
        TryIt.register_trust_scanner!(CleanScanner())
        mktempdir() do dir
            text = capture_stderr() do
                TryIt._report_trust(dir)
            end
            @test isempty(strip(text))
        end
    finally
        TryIt.register_trust_scanner!(previous)
    end
end

@testitem "trust: a broken scanner leaves clone silent and unharmed (OF8)" begin
    using TryIt
    include(joinpath(@__DIR__, "trust_helpers.jl"))

    struct BrokenScanner <: TryIt.TrustScanner end
    TryIt.scan_try(::BrokenScanner, ::AbstractString) = error("boom")

    previous = TryIt.TRUST_SCANNER[]
    try
        TryIt.register_trust_scanner!(BrokenScanner())
        mktempdir() do dir
            local n
            text = capture_stderr() do
                n = TryIt._report_trust(dir)
            end
            @test n == 0
            # Fail-open and *quiet*: a backend the user did not ask
            # for, failing at something advisory, has no business
            # printing a diagnostic about itself on every clone.
            @test isempty(strip(text))
        end
    finally
        TryIt.register_trust_scanner!(previous)
    end
end

@testitem "trust: clone is unchanged when no backend is installed (OF7)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # The default build has no scanner registered, so `clone` must
    # behave exactly as it did before this feature existed: same
    # stdout contract, same exit code, and not one word about trust.
    with_git_stub() do _stub_dir
        with_tmp_tries() do _dir
            (code, out, err) = run_cli_subprocess(
                "clone", "https://github.com/foo/bar.git"
            )
            @test code == 0
            @test occursin(r"^cd '[^']+'\n$", out)
            @test !occursin("trust", err)
        end
    end
end
