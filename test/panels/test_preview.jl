@testitem "panels: preview_entries lists directory contents" begin
    using TryIt: preview_entries

    mktempdir() do dir
        touch(joinpath(dir, "README.md"))
        mkpath(joinpath(dir, "src"))
        touch(joinpath(dir, "Project.toml"))

        entries = preview_entries(dir)
        names = [e.name for e in entries]
        @test "README.md" in names
        @test "src" in names
        @test "Project.toml" in names
        @test length(entries) == 3
    end
end

@testitem "panels: preview_entries flags directories" begin
    using TryIt: preview_entries

    mktempdir() do dir
        mkpath(joinpath(dir, "adir"))
        touch(joinpath(dir, "afile"))

        entries = preview_entries(dir)
        byname = Dict(e.name => e for e in entries)
        @test byname["adir"].isdir === true
        @test byname["afile"].isdir === false
    end
end

@testitem "panels: preview_entries sorts directories first, then by name" begin
    using TryIt: preview_entries

    mktempdir() do dir
        touch(joinpath(dir, "b_file"))
        touch(joinpath(dir, "a_file"))
        mkpath(joinpath(dir, "z_dir"))
        mkpath(joinpath(dir, "m_dir"))

        names = [e.name for e in preview_entries(dir)]
        @test names == ["m_dir", "z_dir", "a_file", "b_file"]
    end
end

@testitem "panels: preview_entries honours a row limit" begin
    using TryIt: preview_entries

    mktempdir() do dir
        for i in 1:50
            touch(joinpath(dir, string("f", lpad(i, 2, '0'))))
        end
        # The preview panel is short; reading and sorting 10k entries
        # for a 15-row panel would stall the frame.
        @test length(preview_entries(dir; limit=15)) == 15
    end
end

@testitem "panels: preview_entries tolerates a missing or unreadable path" begin
    using TryIt: preview_entries

    @test isempty(preview_entries(joinpath(tempdir(), "does-not-exist-xyz")))
    # An empty try renders an empty panel rather than an error.
    mktempdir() do dir
        @test isempty(preview_entries(dir))
    end
end
