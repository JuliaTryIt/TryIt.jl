# A URL pasted into the selector's filter (ED4, ED27).
#
# The routing had been wired into the command-line dispatcher only,
# so the selector slugified the URL and made an empty hundred-
# character directory. These pin the two paths to the same rule.

@testitem "selector: a fetchable URL exits to fetch, creating nothing (ED4, ED27)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    url = "https://cdn.example.com/forum/original/3X/b/3/abc123.jl"
    with_tmp_tries() do dir
        m = TryIt.SelectorSession(root=TryIt.TriesPath(positional=dir))
        m.filter = url
        TryIt._create_from_filter!(m)

        @test m.exit_action === :fetch
        @test m.exit_url == url
        @test m.done
        # The regression in one assertion: no directory is made, and
        # in particular not one named after the slugified URL.
        @test isempty(readdir(dir))
        @test isempty(m.exit_path)
    end
end

@testitem "selector: a repository URL exits to clone (ED4, ED27)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    url = "https://github.com/foo/bar"
    with_tmp_tries() do dir
        m = TryIt.SelectorSession(root=TryIt.TriesPath(positional=dir))
        m.filter = url
        TryIt._create_from_filter!(m)

        @test m.exit_action === :clone
        @test m.exit_url == url
        @test isempty(readdir(dir))
    end
end

@testitem "selector: an ordinary name still creates a try (ED4)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Regression guard on the change: the overwhelmingly common path
    # must be untouched.
    with_tmp_tries() do dir
        m = TryIt.SelectorSession(root=TryIt.TriesPath(positional=dir))
        m.filter = "My New Idea"
        TryIt._create_from_filter!(m)

        @test m.exit_action === :cd
        @test isempty(m.exit_url)
        @test occursin("-my-new-idea", basename(m.exit_path))
        @test isdir(m.exit_path)
    end
end

@testitem "selector: a name that merely looks URL-ish is still a slug (ED4)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # `url_kind` returns `:not_url` for these, so they must keep
    # behaving as names — the routing must not become a trap for
    # anyone whose try is called `api.v2` or `notes/today`.
    with_tmp_tries() do dir
        for name in ("api.v2", "notes-2026", "some.thing")
            m = TryIt.SelectorSession(root=TryIt.TriesPath(positional=dir))
            m.filter = name
            TryIt._create_from_filter!(m)
            @test m.exit_action === :cd
            @test isdir(m.exit_path)
        end
    end
end

@testitem "selector: whitespace around a pasted URL is tolerated (ED4, ED27)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Pasting into a terminal picks up a trailing space or newline
    # more often than not.
    with_tmp_tries() do dir
        m = TryIt.SelectorSession(root=TryIt.TriesPath(positional=dir))
        m.filter = "  https://example.com/snippet.jl  "
        TryIt._create_from_filter!(m)

        @test m.exit_action === :fetch
        @test m.exit_url == "https://example.com/snippet.jl"
        @test isempty(readdir(dir))
    end
end

@testitem "selector: the URL exits carry no local path to cd into (ED4)" begin
    using TryIt
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # `exit_path` and `exit_url` are separate fields precisely so that
    # a URL can never reach `emit_cd_for`. If they were ever merged,
    # this is the test that would fail.
    with_tmp_tries() do dir
        m = TryIt.SelectorSession(root=TryIt.TriesPath(positional=dir))
        m.filter = "https://example.com/snippet.jl"
        TryIt._create_from_filter!(m)
        @test !occursin("://", m.exit_path)
    end
end
