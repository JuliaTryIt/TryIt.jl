@testitem "selector: Ctrl-P on an undated folder asks which date" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        target = joinpath(dir, "plain")
        mkpath(target)
        # The prompt only appears when the two dates differ, so the
        # mtime has to be something other than today.
        Sys.which("touch") === nothing && return
        run(`touch -t 202001010900 $target`)
        m = TryIt.open_session(root)
        m.cursor = 1

        press_keys!(m, "\x10")          # Ctrl-P
        # Nothing has moved yet — the choice is genuinely open.
        @test m.mode === :datepick
        @test m.date_choice === :mtime  # the row already shows this one
        @test readdir(dir) == ["plain"]
    end
end

@testitem "selector: choosing the folder's own date uses the mtime" begin
    using Dates
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        target = joinpath(dir, "plain")
        mkpath(target)
        Sys.which("touch") === nothing && return
        run(`touch -t 202001010900 $target`)
        m = TryIt.open_session(root)
        m.cursor = 1
        shown = m.visible[1].date

        press_keys!(m, "\x10")
        press_keys!(m, "\r")            # default
        @test m.mode === :normal
        @test only(readdir(dir)) ==
              string(Dates.format(shown, "yyyy-mm-dd"), "-plain")
    end
end

@testitem "selector: choosing today uses today" begin
    using Dates
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        # An mtime deliberately far from today, so the two differ.
        old = joinpath(dir, "vintage")
        mkpath(old)
        # Julia has no utime; shell out so the two dates genuinely
        # differ and the test can tell them apart.
        Sys.which("touch") === nothing && return
        run(`touch -t 200101010000 $old`)
        m = TryIt.open_session(root)
        m.cursor = 1
        @test year(m.visible[1].date) <= 2001   # far from today, whatever the zone

        press_keys!(m, "\x10")
        Tachikoma.update!(m, Tachikoma.KeyEvent(:down, '\0', Tachikoma.key_press))
        @test m.date_choice === :today
        press_keys!(m, "\r")

        @test only(readdir(dir)) ==
              string(Dates.format(Dates.today(), "yyyy-mm-dd"), "-vintage")
    end
end

@testitem "selector: Esc leaves the folder undated" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        target = joinpath(dir, "plain")
        mkpath(target)
        Sys.which("touch") === nothing && return
        run(`touch -t 202001010900 $target`)
        m = TryIt.open_session(root)
        m.cursor = 1

        press_keys!(m, "\x10")
        press_keys!(m, "\e")
        @test m.mode === :normal
        @test readdir(dir) == ["plain"]     # untouched
    end
end

@testitem "selector: removing a prefix does not ask" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # There is nothing to choose when taking a date off.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("already"))
        m = TryIt.open_session(root)
        m.cursor = 1

        press_keys!(m, "\x10")
        @test m.mode === :normal
        @test only(readdir(dir)) == "already"
    end
end

@testitem "selector: no prompt when both dates are the same" begin
    using Dates
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    # A folder touched today offers "its own" and "today" as the same
    # date. Asking to choose between two identical options is friction
    # with no decision behind it.
    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        mkpath(joinpath(dir, "fresh"))
        m = TryIt.open_session(root)
        m.cursor = 1
        @test m.visible[1].date == TryIt.current_date()

        press_keys!(m, "\x10")
        @test m.mode === :normal            # applied straight away
        @test only(readdir(dir)) ==
              string(Dates.format(Dates.today(), "yyyy-mm-dd"), "-fresh")
    end
end

@testitem "selector: the prompt still appears when they differ" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        old = joinpath(dir, "vintage")
        mkpath(old)
        Sys.which("touch") === nothing && return
        run(`touch -t 202001010900 $old`)
        m = TryIt.open_session(root)
        m.cursor = 1
        @test m.visible[1].date != TryIt.current_date()

        press_keys!(m, "\x10")
        @test m.mode === :datepick
    end
end
