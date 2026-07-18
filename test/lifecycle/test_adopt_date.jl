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

@testitem "lifecycle: dating a dated try strips the prefix" begin
    using TryIt: TriesPath, list_tries, slug, create_try, DateInvocation, date_try

    # A toggle, not a one-way door.
    mktempdir() do dir
        root = TriesPath(positional=dir)
        create_try(root, slug("already"))
        src = only(list_tries(root))
        @test src.dated === true

        inv = DateInvocation(src)
        @test basename(inv.dest_path) == "already"     # date gone
        date_try(inv)
        @test isdir(inv.dest_path)

        back = only(list_tries(root))
        @test back.dated === false
        @test back.name == "already"
    end
end

@testitem "lifecycle: the date toggle round-trips" begin
    using TryIt: TriesPath, list_tries, DateInvocation, date_try

    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "LibPARI.jl"))
        before = only(list_tries(root))

        date_try(DateInvocation(before))               # add
        mid = only(list_tries(root))
        @test mid.dated === true
        @test mid.name == "LibPARI.jl"

        date_try(DateInvocation(mid))                  # remove
        after = only(list_tries(root))
        @test after.dated === false
        # The name survives both directions untouched.
        @test after.name == "LibPARI.jl"
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

@testitem "selector: Ctrl-P on a dated try removes the prefix" begin
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
        @test length(m.visible) == 1
        @test m.visible[1].dated === false
        @test m.visible[1].name == "already"
    end
end
