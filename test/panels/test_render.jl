# Render tests drive `Tachikoma.view` into an offscreen buffer and
# assert on the resulting text grid. They are the only tests that
# exercise the view at all — the selector's other tests drive
# `update!` and never render.

@testitem "panels: view renders all five panels" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)
        TryIt.refresh_visible!(m)

        text = render_selector(m, 100, 24)
        joined = join(text, "\n")

        @test occursin("Search/New", joined)
        @test occursin("Folders", joined)
        @test occursin("Disk", joined)
        @test occursin("Preview", joined)
        @test occursin("Legends", joined)
        # Footer help bar.
        @test occursin("Nav", joined)
        @test occursin("Quit", joined)
    end
end

@testitem "panels: view renders a complete age column" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)
        TryIt.refresh_visible!(m)

        text = render_selector(m, 100, 24)
        row = findfirst(l -> occursin("alpha", l), text)
        @test row !== nothing

        # Regression: SelectableList advances 2 cells for its marker
        # and 2 for our badge prefix, then clips at the right edge.
        # Under-reserving that width silently truncated the age
        # column's closing paren.
        @test occursin(r"\(\d+d \d\dh \d\dm\)", text[row])
    end
end

@testitem "panels: view marks the cursor row and delete-flagged rows" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        TryIt.create_try(root, TryIt.slug("beta"))
        m = TryIt.open_session(root)
        TryIt.refresh_visible!(m)
        m.cursor = 1

        text = render_selector(m, 100, 24)
        cursor_row = findfirst(l -> occursin("▸", l), text)
        @test cursor_row !== nothing

        # Flagging a row swaps its badge glyph for the delete marker.
        push!(m.marked_for_delete, m.visible[1].path)
        text = render_selector(m, 100, 24)
        @test any(l -> occursin("✗", l), text)
    end
end

@testitem "panels: view drops the side column in a narrow terminal" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)
        TryIt.refresh_visible!(m)

        narrow = join(render_selector(m, 50, 24), "\n")
        # The list must stay usable rather than being squeezed to
        # nothing beside three side panels.
        @test occursin("Folders", narrow)
        @test !occursin("Legends", narrow)
        @test !occursin("Preview", narrow)
    end
end

@testitem "panels: view renders an empty-state hint with no tries" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)
        TryIt.refresh_visible!(m)

        joined = join(render_selector(m, 100, 24), "\n")
        @test occursin("no tries yet", joined)
    end
end

@testitem "panels: view switches the input box to rename mode" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)
        TryIt.refresh_visible!(m)
        m.mode = :rename
        m.rename_buf = "renamed"

        joined = join(render_selector(m, 100, 24), "\n")
        @test occursin("Rename", joined)
        @test occursin("renamed", joined)
        # The normal-mode footer is replaced by the rename bindings.
        @test occursin("Apply", joined)
    end
end

@testitem "panels: view survives a degenerate terminal size" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)
        TryIt.refresh_visible!(m)

        # `split_layout` returns fewer rects than requested when the
        # area is tiny; the view must bail rather than index past the
        # end. A thrown exception here would kill the TUI mid-frame.
        for (w, h) in ((1, 1), (4, 2), (20, 3), (80, 1))
            @test render_selector(m, w, h) isa Vector{String}
        end
    end
end
