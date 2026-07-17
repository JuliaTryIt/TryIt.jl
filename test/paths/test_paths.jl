@testitem "paths: TriesPath resolution order" begin
    using TryIt: TriesPath

    # Positional arg beats env.
    withenv("TRY_PATH" => "/tmp/should-not-be-used") do
        dir = mktempdir()
        r = TriesPath(positional=dir)
        @test r.root == realpath(dir)
        @test r.source === :arg
    end

    # Env beats default.
    dir = mktempdir()
    withenv("TRY_PATH" => dir) do
        r = TriesPath()
        @test r.root == realpath(dir)
        @test r.source === :env
    end

    # Default when nothing is set (HOME-relative). We don't write
    # under the real $HOME — instead, override HOME to a tempdir.
    home = mktempdir()
    withenv("TRY_PATH" => nothing, "HOME" => home) do
        r = TriesPath()
        @test r.root == realpath(joinpath(home, "src", "tries"))
        @test r.source === :default
        @test isdir(r.root)
    end
end

@testitem "paths: create_try (UB1, UB2, ED4)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, try_basename

    dir = mktempdir()
    root = TriesPath(positional=dir)
    s = slug("my-new-idea")
    today = Date(2026, 4, 19)

    t = create_try(root, s, today)
    @test isdir(t.path)
    @test basename(t.path) == "2026-04-19-my-new-idea"
    @test basename(t.path) == try_basename(today, s)

    # Idempotence: same-day collision returns the existing path.
    t2 = create_try(root, s, today)
    @test t2.path == t.path
    @test readdir(dir) == ["2026-04-19-my-new-idea"]
end

@testitem "paths: list_tries sorts mtime-desc (ED1)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, list_tries

    dir = mktempdir()
    root = TriesPath(positional=dir)

    a = create_try(root, slug("apple"), Date(2026, 4, 19))
    sleep(0.05)
    b = create_try(root, slug("banana"), Date(2026, 4, 19))
    sleep(0.05)
    c = create_try(root, slug("cherry"), Date(2026, 4, 19))

    # Bump `a`'s mtime by writing a sentinel file inside it —
    # directory mtime reflects child file changes on all supported
    # OSes (and Base.touch cannot touch a directory on Linux).
    sleep(0.05)
    open(joinpath(a.path, ".bump"), "w") do io
    end

    listed = list_tries(root)
    @test length(listed) == 3
    @test listed[1].path == a.path   # most-recently-bumped first
    @test Set(t.path for t in listed) == Set([a.path, b.path, c.path])
end

@testitem "paths: filter_tries (ED2)" begin
    using Dates
    using TryIt: TriesPath, slug, create_try, list_tries, filter_tries

    dir = mktempdir()
    root = TriesPath(positional=dir)
    create_try(root, slug("apple-tart"), Date(2026, 4, 19))
    create_try(root, slug("banana-bread"), Date(2026, 4, 19))
    create_try(root, slug("cherry-pie"), Date(2026, 4, 18))

    entries = list_tries(root)

    # Empty filter returns everything.
    @test length(filter_tries(entries, "")) == 3

    # Case-insensitive substring on slug.
    matches = filter_tries(entries, "BaNaNa")
    @test length(matches) == 1
    @test matches[1].slug.value == "banana-bread"

    # Substring on date prefix.
    april_19 = filter_tries(entries, "2026-04-19")
    @test length(april_19) == 2
end

@testitem "paths: unwritable TRY_PATH fails with exit 2 (UN1)" begin
    # This is exercised in the CLI subprocess (see cli tests); the
    # direct in-process call would `exit(2)` and terminate the
    # testitem runner, so we only smoke-test the constructor here
    # against a writable tempdir.
    using TryIt: TriesPath
    dir = mktempdir()
    r = TriesPath(positional=dir)
    @test isdir(r.root)
end
