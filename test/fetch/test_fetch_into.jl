# Downloading into a try (ED26) and its failure modes (UN11, UN12).
#
# `file://` URLs keep these hermetic: libcurl serves them, and a
# missing path raises the same `RequestError` a 404 does, so the
# no-residue guarantee can be exercised without a network.

@testitem "fetch: the file lands in a dated try under its own name (ED26)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        source = joinpath(mktempdir(), "snippet.jl")
        write(source, "f(x) = x + 1\n")

        root = TryIt.TriesPath(positional=dir)
        inv = TryIt.FetchInvocation("file://" * source, nothing, root)
        result = TryIt.fetch_into(inv)

        @test result.ok
        @test isfile(result.path)
        # The file keeps its own basename; the try is named after the
        # basename with its extension dropped.
        @test basename(result.path) == "snippet.jl"
        @test occursin("-snippet", basename(dirname(result.path)))
        @test read(result.path, String) == "f(x) = x + 1\n"
    end
end

@testitem "fetch: an explicit name overrides the derived slug (ED26)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        source = joinpath(mktempdir(), "snippet.jl")
        write(source, "x = 1\n")

        root = TryIt.TriesPath(positional=dir)
        inv = TryIt.FetchInvocation("file://" * source, "my-spike", root)
        result = TryIt.fetch_into(inv)

        @test result.ok
        @test occursin("-my-spike", basename(dirname(result.path)))
        # The file itself is untouched by the renaming.
        @test basename(result.path) == "snippet.jl"
    end
end

@testitem "fetch: only the final extension is dropped from the slug (ED26)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        source = joinpath(mktempdir(), "archive.tar.gz")
        write(source, "not really an archive")

        root = TryIt.TriesPath(positional=dir)
        inv = TryIt.FetchInvocation("file://" * source, nothing, root)
        result = TryIt.fetch_into(inv)

        @test result.ok
        # Stored verbatim: ED26 does not extract archives.
        @test basename(result.path) == "archive.tar.gz"
        @test occursin("-archive-tar", basename(dirname(result.path)))
    end
end

@testitem "fetch: a failed download leaves no residue (UN11)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        inv = TryIt.FetchInvocation(
            "file:///definitely/not/here/missing.jl", nothing, root
        )
        result = TryIt.fetch_into(inv)

        @test !result.ok
        @test !isempty(result.error)
        # The whole point: a half-made try the user is about to `cd`
        # into is worse than no try, because it looks like it worked.
        @test isempty(readdir(dir))
        @test !isdir(inv.dest)
    end
end

@testitem "fetch: a response over the cap is rejected and cleaned up (UN11)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        source = joinpath(mktempdir(), "big.bin")
        write(source, repeat("x", 4096))

        root = TryIt.TriesPath(positional=dir)
        inv = TryIt.FetchInvocation("file://" * source, nothing, root)
        result = TryIt.fetch_into(inv; max_bytes=1024)

        @test !result.ok
        @test occursin("too large", lowercase(result.error))
        @test isempty(readdir(dir))
    end
end

@testitem "fetch: a URL with no usable basename is a usage error (UN12)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        for url in ("https://example.com/", "https://example.com/---")
            @test_throws ArgumentError TryIt.FetchInvocation(url, nothing, root)
        end
        @test isempty(readdir(dir))
    end
end

@testitem "fetch: the basename is taken from the path, not the query (ED26)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        inv = TryIt.FetchInvocation(
            "https://example.com/dir/thing.jl?raw=1&x=y", nothing, root
        )
        @test inv.filename == "thing.jl"
        @test occursin("-thing", basename(inv.dest))
    end
end
