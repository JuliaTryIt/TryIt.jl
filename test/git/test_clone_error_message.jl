# Which line of git's stderr reaches the user when a clone fails
# (UN3).
#
# git writes its progress banner before anything else, so "the first
# non-empty line" is never the error. These pin the selection rule
# so the banner cannot come back.

@testitem "git: the reported line is the cause, not the banner (UN3)" begin
    using TryIt

    # The exact shape real git produces, banner first.
    raw = """
    Cloning into '/tmp/tries/2026-07-19-thing'...
    fatal: unable to access 'https://example.com/thing.jl/': The requested URL returned error: 403
    """
    line = TryIt._collapse_stderr(raw)
    @test occursin("403", line)
    @test occursin("fatal", line)
    @test !occursin("Cloning into", line)
end

@testitem "git: a localised fatal prefix is still recognised (UN3)" begin
    using TryIt

    # git localises its messages; French keeps the word but inserts a
    # space before the colon. The rule must not be tied to one locale
    # — this is the output that exposed the bug in the first place.
    raw = """
    Clonage dans '/tmp/tries/2026-07-19-thing'...
    fatal : impossible d'accéder à 'https://example.com/thing.jl/' : The requested URL returned error: 403
    """
    line = TryIt._collapse_stderr(raw)
    @test occursin("403", line)
    @test !occursin("Clonage dans", line)
end

@testitem "git: with no recognisable prefix the last line wins (UN3)" begin
    using TryIt

    # Fallback for a locale that translates `fatal:` outright. The
    # last line is still far closer to the cause than the first.
    raw = """
    Klone nach '/tmp/tries/x'...
    Schwerwiegend: Repository nicht gefunden
    """
    @test TryIt._collapse_stderr(raw) == "Schwerwiegend: Repository nicht gefunden"
end

@testitem "git: hint lines after the fatal do not displace it (UN3)" begin
    using TryIt

    raw = """
    Cloning into 'x'...
    fatal: could not read Username for 'https://github.com': terminal prompts disabled
    hint: See 'git help credential' for details.
    """
    line = TryIt._collapse_stderr(raw)
    @test occursin("could not read Username", line)
    @test !startswith(line, "hint:")
end

@testitem "git: empty and blank stderr collapse to an empty string (UN3)" begin
    using TryIt

    @test TryIt._collapse_stderr("") == ""
    @test TryIt._collapse_stderr("\n\n   \n") == ""
end

@testitem "git: a single-line stderr is returned as-is (UN3)" begin
    using TryIt

    @test TryIt._collapse_stderr("fatal: repository not found\n") ==
          "fatal: repository not found"
end

@testitem "git: a failing clone tells the user why (UN3)" begin
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # End to end: the cause must survive all the way to the user's
    # terminal, and the tries path must still be left untouched.
    banner_and_cause = string(
        "Cloning into '/tmp/whatever'...\n",
        "fatal: unable to access 'https://example.com/x.jl/': ",
        "The requested URL returned error: 403\n"
    )
    with_git_stub(; clone_exit=128, clone_stderr=banner_and_cause) do _stub
        with_tmp_tries() do dir
            (code, out, err) = run_cli_subprocess(
                "clone", "https://example.com/x.jl"
            )
            @test code == 128          # UN3: git's own code is propagated
            @test isempty(out)         # no `cd` for a failed clone
            @test occursin("403", err)
            @test !occursin("Cloning into", err)
            # UN3's other half, unchanged: no residue.
            @test isempty(readdir(dir))
        end
    end
end
