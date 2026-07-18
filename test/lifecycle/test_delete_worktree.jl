@testitem "lifecycle: is_worktree distinguishes a linked worktree" begin
    using TryIt: is_worktree

    # `git worktree add` writes a `.git` *file* holding a gitdir
    # pointer; a normal repository has a `.git` directory.
    mktempdir() do dir
        wt = joinpath(dir, "linked")
        mkpath(wt)
        write(joinpath(wt, ".git"), "gitdir: /elsewhere/.git/worktrees/linked\n")
        @test is_worktree(wt) === true

        repo = joinpath(dir, "repo")
        mkpath(joinpath(repo, ".git"))
        @test is_worktree(repo) === false

        plain = joinpath(dir, "plain")
        mkpath(plain)
        @test is_worktree(plain) === false

        @test is_worktree(joinpath(dir, "does-not-exist")) === false
    end
end

@testitem "lifecycle: deleting a worktree unregisters it from its repo" begin
    using TryIt: execute_deletes!
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # Regression: deletion was an unconditional `rm -rf`, which leaves
    # the worktree registered in the parent repository — `git worktree
    # list` keeps showing it and the admin directory lingers under
    # .git/worktrees. try-rs runs `git worktree remove` for this case.
    Sys.which("git") === nothing && return

    mktempdir() do dir
        repo = joinpath(dir, "repo")
        mkpath(repo)
        run_quiet(`git -C $repo init -q -b main`)
        run_quiet(`git -C $repo config user.email t@example.com`)
        run_quiet(`git -C $repo config user.name Tester`)
        write(joinpath(repo, "f.txt"), "hello\n")
        run_quiet(`git -C $repo add f.txt`)
        run_quiet(`git -C $repo commit -q -m init`)

        wt = joinpath(dir, "2026-07-18-a-worktree")
        run_quiet(`git -C $repo worktree add -q $wt -b feature`)
        @test isdir(wt)
        @test occursin("a-worktree", read(`git -C $repo worktree list`, String))

        @test execute_deletes!([wt]) == 1
        @test !ispath(wt)
        # The parent repository must no longer list it.
        @test !occursin("a-worktree", read(`git -C $repo worktree list`, String))
        @test !isdir(joinpath(repo, ".git", "worktrees", "2026-07-18-a-worktree"))
    end
end

@testitem "lifecycle: a plain try is still deleted normally" begin
    using TryIt: execute_deletes!

    mktempdir() do dir
        plain = joinpath(dir, "2026-07-18-plain")
        mkpath(joinpath(plain, "nested"))
        write(joinpath(plain, "nested", "f.txt"), "x")

        @test execute_deletes!([plain]) == 1
        @test !ispath(plain)
    end
end

@testitem "lifecycle: a broken worktree still gets removed" begin
    using TryIt: execute_deletes!

    # The parent repository may be gone, or `git` may be absent. The
    # directory must still disappear — failing to unregister is not a
    # reason to leave it on disk.
    mktempdir() do dir
        wt = joinpath(dir, "2026-07-18-orphan")
        mkpath(wt)
        write(joinpath(wt, ".git"), "gitdir: /nowhere/.git/worktrees/orphan\n")

        @test execute_deletes!([wt]) == 1
        @test !ispath(wt)
    end
end
