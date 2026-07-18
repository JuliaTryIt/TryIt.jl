@testitem "paths: list_tries includes undated directories" begin
    using TryIt: TriesPath, list_tries, slug, create_try

    # Regression: `_parse_try_basename` returned `nothing` for
    # anything without a YYYY-MM-DD- prefix and `list_tries` skipped
    # it, so a hand-made or cloned directory was simply invisible.
    mktempdir() do dir
        root = TriesPath(positional=dir)
        create_try(root, slug("dated-one"))
        mkpath(joinpath(dir, "Tachikoma.jl"))
        mkpath(joinpath(dir, "hello"))

        entries = list_tries(root)
        names = sort([t.name for t in entries])
        @test names == ["Tachikoma.jl", "dated-one", "hello"]
    end
end

@testitem "paths: dated and undated entries are distinguishable" begin
    using TryIt: TriesPath, list_tries, slug, create_try

    mktempdir() do dir
        root = TriesPath(positional=dir)
        create_try(root, slug("dated-one"))
        mkpath(joinpath(dir, "plain"))

        byname = Dict(t.name => t for t in list_tries(root))
        @test byname["dated-one"].dated === true
        @test byname["plain"].dated === false
    end
end

@testitem "paths: an undated entry dates from the filesystem" begin
    using Dates
    using TryIt: TriesPath, list_tries

    mktempdir() do dir
        root = TriesPath(positional=dir)
        target = joinpath(dir, "plain")
        mkpath(target)

        t = only(list_tries(root))
        # No prefix to read, so the OS mtime stands in.
        @test t.date == Date(Dates.unix2datetime(mtime(target)))
        @test t.mtime == mtime(target)
    end
end

@testitem "paths: a name that is not a valid slug is still listed" begin
    using TryIt: TriesPath, list_tries

    # `LibPARI.jl` has uppercase and a dot, so `Slug` cannot hold it
    # verbatim — the display name and the derived slug differ.
    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "LibPARI.jl"))

        t = only(list_tries(root))
        @test t.name == "LibPARI.jl"
        @test t.slug.value == "libpari-jl"
        @test t.dated === false
    end
end

@testitem "paths: undated entries are filterable by name" begin
    using TryIt: TriesPath, list_tries, filter_tries

    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "Tachikoma.jl"))
        mkpath(joinpath(dir, "unrelated"))

        entries = list_tries(root)
        @test length(filter_tries(entries, "tachi")) == 1
        @test only(filter_tries(entries, "tachi")).name == "Tachikoma.jl"
    end
end

@testitem "paths: undated entries do not affect placeholder numbering" begin
    using TryIt: TriesPath, placeholder_slug_for_today

    # `new-try` numbering counts today's *dated* tries. An undated
    # directory touched today must not be mistaken for one.
    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "new-try"))
        @test placeholder_slug_for_today(root).value == "new-try"
    end
end

@testitem "lifecycle: renaming an undated try leaves it undated" begin
    using TryIt: TriesPath, list_tries, slug, RenameInvocation, rename_try

    # Renaming must not silently promote a plain directory into the
    # dated scheme — the user did not ask for a date.
    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "plain"))
        src = only(list_tries(root))

        inv = RenameInvocation(src, slug("renamed"))
        # No date prefix on the destination — `rename_try` returns
        # nothing, so assert against the invocation's target.
        @test basename(inv.dest_path) == "renamed"
        rename_try(inv)
        @test isdir(inv.dest_path)
        @test !ispath(joinpath(dir, "plain"))
    end
end

@testitem "paths: a dated try keeps its date even with an odd name" begin
    using Dates
    using TryIt: TriesPath, list_tries

    # Regression: the parser required the remainder to match
    # ^[a-z0-9-]+$, so `2026-04-15-s-celles-Nghttp2Wrapper.jl` was read
    # as undated and stamped with today's mtime instead of 2026-04-15.
    mktempdir() do dir
        root = TriesPath(positional=dir)
        mkpath(joinpath(dir, "2026-04-15-s-celles-Nghttp2Wrapper.jl"))

        t = only(list_tries(root))
        @test t.dated === true
        @test t.date == Date(2026, 4, 15)
        @test t.name == "s-celles-Nghttp2Wrapper.jl"
    end
end
