@testitem "errors: ExitCode is a module-scoped enum" begin
    using TryIt: ExitCode

    # Convention: a dedicated module holding a CamelCase type `T`
    # with SCREAMING_SNAKE_CASE values.
    @test ExitCode isa Module
    @test ExitCode.T isa Type
    @test ExitCode.SUCCESS isa ExitCode.T
end

@testitem "errors: ExitCode values match their process exit statuses" begin
    using TryIt: ExitCode

    # These are the wire format — a shell reads them from $?, so the
    # numbers are load-bearing and must not drift.
    @test Int(ExitCode.SUCCESS) == 0
    @test Int(ExitCode.PERMISSION) == 2
    @test Int(ExitCode.USAGE) == 64      # EX_USAGE
    @test Int(ExitCode.NOT_FOUND) == 127
    @test Int(ExitCode.SIGINT) == 130    # 128 + SIGINT
end

@testitem "errors: ExitCode converts to the C exit-status type" begin
    using TryIt: ExitCode

    # `julia_main` must hand a Cint back to PackageCompiler's launcher.
    @test Cint(ExitCode.SUCCESS) isa Cint
    @test Cint(ExitCode.USAGE) == Cint(64)
end

@testitem "errors: ExitCode enumerates exactly the supported statuses" begin
    using TryIt: ExitCode

    # Guards against a value being added without a test, and pins the
    # declaration order.
    @test instances(ExitCode.T) == (
        ExitCode.SUCCESS,
        ExitCode.PERMISSION,
        ExitCode.USAGE,
        ExitCode.NOT_FOUND,
        ExitCode.SIGINT
    )
end

@testitem "errors: exit codes do not leak into the TryIt namespace" begin
    using TryIt

    # The point of the submodule is that these names are *not* here.
    for name in (:SUCCESS, :PERMISSION, :USAGE, :NOT_FOUND, :SIGINT,
        :EXIT_SUCCESS, :EXIT_PERMISSION, :EXIT_USAGE,
        :EXIT_NOT_FOUND, :EXIT_SIGINT)
        @test !isdefined(TryIt, name)
    end
end

@testitem "errors: ExitCode converts to any integer type" begin
    using TryIt: ExitCode

    # `Base` gives enums an `Int(...)` constructor but no `convert`,
    # which a `::Int` return annotation needs. Without the method
    # defined alongside the enum, every CLI dispatcher would raise a
    # MethodError instead of narrowing its return value.
    @test convert(Int, ExitCode.USAGE) === 64
    @test convert(Cint, ExitCode.SIGINT) === Cint(130)
end

@testitem "errors: cli_main narrows to Int, not the enum" begin
    using TryIt: cli_main, ExitCode

    # The status domain is deliberately open: `tryit clone` propagates
    # git's own exit code verbatim (FR-029), which is an arbitrary
    # integer outside the enum. So the boundary is typed `Int` and the
    # enum names only the statuses TryIt itself originates.
    mktempdir() do dir
        code = redirect_stdout(devnull) do
            cli_main(["init", dir])
        end
        @test code isa Int
        @test code == Int(ExitCode.SUCCESS)
    end

    code = redirect_stderr(devnull) do
        cli_main(["definitely", "not", "a", "command"])
    end
    @test code isa Int
    @test code == Int(ExitCode.USAGE)
end
