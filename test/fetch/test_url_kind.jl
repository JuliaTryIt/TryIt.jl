# The clone-vs-fetch routing rule (ED27).
#
# This is the whole feature's load-bearing decision, and it is pure:
# no network, no filesystem. The table below is the specification.

@testitem "fetch: a Julia forge repo is cloned despite its .jl suffix (ED27)" begin
    using TryIt

    # The collision this rule exists for. Julia names repositories
    # `Foo.jl`, so extension alone routes these two identically while
    # they need opposite handling. The second is the shape a forum or
    # gist CDN serves a raw attachment at: deep path, opaque name.
    @test TryIt.url_kind("https://github.com/s-celles/PluginGuard.jl") === :clone
    @test TryIt.url_kind(
        "https://cdn.example.com/forum/original/3X/b/3/abc123.jl"
    ) === :fetch
end

@testitem "fetch: known forges with an owner/repo path are repositories (ED27)" begin
    using TryIt

    for url in (
        "https://github.com/foo/bar",
        "https://github.com/foo/bar/",
        "https://gitlab.com/foo/bar",
        "https://codeberg.org/foo/bar",
        "https://bitbucket.org/foo/bar",
        "https://git.sr.ht/~user/repo"
    )
        @test TryIt.url_kind(url) === :clone
    end
end

@testitem "fetch: a .git suffix is a repository anywhere (ED27)" begin
    using TryIt

    # The escape hatch for self-hosted forges, which the host list
    # cannot enumerate.
    @test TryIt.url_kind("https://git.example.fr/moi/projet.git") === :clone
    @test TryIt.url_kind("https://github.com/foo/bar.git") === :clone
end

@testitem "fetch: ssh and scp forms are repositories (ED27)" begin
    using TryIt

    @test TryIt.url_kind("git@github.com:foo/bar.git") === :clone
    @test TryIt.url_kind("git@github.com:foo/bar") === :clone
    @test TryIt.url_kind("ssh://git@host/org/repo") === :clone
    @test TryIt.url_kind("git://host/org/repo") === :clone
end

@testitem "fetch: anything else over http(s) is a file (ED27)" begin
    using TryIt

    for url in (
        "https://example.com/scripts/setup.jl",
        "https://raw.githubusercontent.com/foo/bar/main/x.jl",
        "https://example.com/archive.tar.gz",
        "http://example.com/notes.md"
    )
        @test TryIt.url_kind(url) === :fetch
    end
end

@testitem "fetch: a deep forge URL is a file, as documented (ED27)" begin
    using TryIt

    # An accepted limitation, pinned so it stays a decision rather
    # than becoming a surprise: this downloads the HTML page, not the
    # file it displays. `tryit clone` / `tryit fetch` override.
    @test TryIt.url_kind("https://github.com/foo/bar/blob/main/x.jl") === :fetch
    # A bare user profile is not a repository either.
    @test TryIt.url_kind("https://github.com/foo") === :fetch
end

@testitem "fetch: scheme and host compare case-insensitively (ED27)" begin
    using TryIt

    @test TryIt.url_kind("HTTPS://GitHub.com/Foo/Bar") === :clone
    @test TryIt.url_kind("https://WWW.github.com/foo/bar") === :clone
end

@testitem "fetch: query strings and fragments do not change the verdict (ED27)" begin
    using TryIt

    @test TryIt.url_kind("https://github.com/foo/bar?tab=readme") === :clone
    @test TryIt.url_kind("https://example.com/x.jl?raw=1") === :fetch
    @test TryIt.url_kind("https://example.com/x.jl#L10") === :fetch
end

@testitem "fetch: plain slugs are not URLs (ED27)" begin
    using TryIt

    for arg in ("my-slug", "", "notes", "2026-07-19-thing", "./local/path")
        @test TryIt.url_kind(arg) === :not_url
    end
end
