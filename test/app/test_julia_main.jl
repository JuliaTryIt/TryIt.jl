@testitem "app: julia_main is a PackageCompiler-compatible entry point" begin
    using TryIt: julia_main

    # PackageCompiler requires a zero-argument `julia_main` returning
    # `Cint`. Anything else fails at `create_app` time rather than at
    # build time, so pin the contract here.
    @test hasmethod(julia_main, Tuple{})
    @test Base.return_types(julia_main, Tuple{}) == [Cint]
end

@testitem "app: _app_main returns the CLI exit code as Cint" begin
    using TryIt: _app_main, ExitCode

    # `init` is the only subcommand that is pure stdout with no
    # filesystem or TTY dependency, so it is the safe smoke path.
    mktempdir() do dir
        code = redirect_stdout(devnull) do
            _app_main(["init", dir])
        end
        @test code isa Cint
        @test code == Cint(ExitCode.SUCCESS)
    end

    code = redirect_stderr(devnull) do
        _app_main(["definitely", "not", "a", "command"])
    end
    @test code isa Cint
    @test code == Cint(ExitCode.USAGE)
end

@testitem "app: _app_main flips the process into app mode" begin
    using TryIt: _app_main, _APP_MODE

    previous = _APP_MODE[]
    try
        _APP_MODE[] = false
        mktempdir() do dir
            redirect_stdout(devnull) do
                _app_main(["init", dir])
            end
        end
        @test _APP_MODE[] === true
    finally
        _APP_MODE[] = previous
    end
end
