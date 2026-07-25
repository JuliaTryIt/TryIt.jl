@testitem "panels: detect_badges recognises project markers" begin
    using TryIt: detect_badges

    mktempdir() do dir
        # An empty directory carries no badges.
        @test isempty(detect_badges(dir))

        touch(joinpath(dir, "Cargo.toml"))
        @test :rust in detect_badges(dir)

        touch(joinpath(dir, "go.mod"))
        @test :go in detect_badges(dir)

        touch(joinpath(dir, "pyproject.toml"))
        @test :python in detect_badges(dir)

        touch(joinpath(dir, "pom.xml"))
        @test :maven in detect_badges(dir)

        touch(joinpath(dir, "pubspec.yaml"))
        @test :flutter in detect_badges(dir)

        touch(joinpath(dir, ".mise.toml"))
        @test :mise in detect_badges(dir)
    end
end

@testitem "panels: detect_badges recognises each python marker variant" begin
    using TryIt: detect_badges

    for marker in ("pyproject.toml", "requirements.txt", "setup.py")
        mktempdir() do dir
            touch(joinpath(dir, marker))
            @test :python in detect_badges(dir)
        end
    end
end

@testitem "panels: detect_badges distinguishes julia from python pyproject" begin
    using TryIt: detect_badges

    # `Project.toml` is Julia; `pyproject.toml` is Python. On a
    # case-insensitive filesystem these must not be conflated.
    mktempdir() do dir
        touch(joinpath(dir, "Project.toml"))
        badges = detect_badges(dir)
        @test :julia in badges
        @test !(:python in badges)
    end
end

@testitem "panels: detect_badges separates git repo, worktree, and submodule" begin
    using TryIt: detect_badges

    # A normal repository: `.git` is a directory.
    mktempdir() do dir
        mkpath(joinpath(dir, ".git"))
        badges = detect_badges(dir)
        @test :git in badges
        @test !(:worktree in badges)
    end

    # A linked worktree: `.git` is a *file* containing a gitdir pointer.
    mktempdir() do dir
        write(joinpath(dir, ".git"), "gitdir: /elsewhere/.git/worktrees/wt\n")
        badges = detect_badges(dir)
        @test :worktree in badges
        @test !(:git in badges)
    end

    # Submodules are flagged independently of the .git shape.
    mktempdir() do dir
        mkpath(joinpath(dir, ".git"))
        touch(joinpath(dir, ".gitmodules"))
        badges = detect_badges(dir)
        @test :git in badges
        @test :submodule in badges
    end
end

@testitem "panels: detect_badges is order-stable and deduplicated" begin
    using TryIt: detect_badges, BADGE_ORDER

    mktempdir() do dir
        touch(joinpath(dir, "Cargo.toml"))
        touch(joinpath(dir, "go.mod"))
        mkpath(joinpath(dir, ".git"))

        badges = detect_badges(dir)
        @test length(badges) == length(unique(badges))
        # Rendering must not jitter between frames, so the result
        # follows a fixed declaration order rather than readdir order.
        @test badges == filter(b -> b in badges, BADGE_ORDER)
    end
end

@testitem "panels: detect_badges tolerates a missing or unreadable path" begin
    using TryIt: detect_badges

    # The selector renders from a snapshot; a try can be deleted out
    # from under it between refreshes. That must not throw mid-frame.
    @test isempty(detect_badges(joinpath(tempdir(), "does-not-exist-xyz")))
end
