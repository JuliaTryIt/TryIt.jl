@testitem "lifecycle: dating an undated try adds the prefix in place" begin
    using Dates
    using TryIt: TriesPath, list_tries, DateInvocation, date_try

    mktempdir() do dir
        root = TriesPath(positional=dir)
        target = joinpath(dir, "LibPARI.jl")
        mkpath(target)
        src = only(list_tries(root))
        @test src.dated === false

        inv = DateInvocation(src)
        date_try(inv)

        # The name is preserved verbatim — dating adds a prefix, it
        # does not re-slug. `LibPARI.jl` would otherwise become
        # `libpari-jl` and lose its identity.
        expected = string(Dates.format(src.date, "yyyy-mm-dd"), "-LibPARI.jl")
        @test basename(inv.dest_path) == expected
        @test isdir(inv.dest_path)
        @test !ispath(target)
    end
end

@testitem "lifecycle: the adopted date is the one that was displayed" begin
    using Dates
    using TryIt: TriesPath, list_tries, DateInvocation

    # The row shows a date inferred from mtime; dating must commit
    # exactly that, not today, or the entry would appear to jump.
    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "plain"))
        src = only(list_tries(root))

        inv = DateInvocation(src)
        @test startswith(
            basename(inv.dest_path), Dates.format(src.date, "yyyy-mm-dd"))
    end
end

@testitem "lifecycle: a dated try is refused, not re-dated" begin
    using TryIt: TriesPath, list_tries, slug, create_try, DateInvocation

    mktempdir() do dir
        root = TriesPath(positional=dir)
        create_try(root, slug("already"))
        src = only(list_tries(root))
        @test src.dated === true

        @test_throws ArgumentError DateInvocation(src)
    end
end

@testitem "lifecycle: dating refuses to clobber an existing directory" begin
    using Dates
    using TryIt: TriesPath, list_tries, DateInvocation

    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "plain"))
        src = only(list_tries(root))
        # Occupy the destination.
        mkpath(joinpath(dir, string(Dates.format(src.date, "yyyy-mm-dd"), "-plain")))

        @test_throws ArgumentError DateInvocation(src)
    end
end

@testitem "selector: Ctrl-P dates the highlighted undated try" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        mkpath(joinpath(dir, "plain"))
        m = TryIt.open_session(root)
        m.cursor = 1
        @test m.visible[1].dated === false

        press_keys!(m, "\x10")          # Ctrl-P
        # Stays in the selector, list refreshed in place.
        @test m.done === false
        @test length(m.visible) == 1
        @test m.visible[1].dated === true
        @test m.visible[1].name == "plain"
    end
end

@testitem "selector: Ctrl-P on a dated try explains itself" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("already"))
        m = TryIt.open_session(root)
        m.cursor = 1

        press_keys!(m, "\x10")
        @test m.done === false
        # A silent no-op would read as a dead key, which is exactly
        # what the stderr-redirect bug produced for Ctrl-G.
        @test !isempty(m.notice)
    end
end
