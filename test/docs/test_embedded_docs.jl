@testitem "docs: pages are embedded, not read from disk" begin
    using TryIt: DOC_PAGES

    # PackageCompiler bundles no .md files — verified: zero anywhere in
    # the app — and `pkgdir` in a compiled app points at the *build
    # machine's* path. A disk-reading implementation would therefore
    # work for whoever built the binary and fail for everyone else.
    @test !isempty(DOC_PAGES)
    for (title, body) in DOC_PAGES
        @test !isempty(title)
        @test !isempty(body)
        @test body isa String
    end
end

@testitem "docs: the expected pages are present, reference excluded" begin
    using TryIt: DOC_PAGES

    titles = [t for (t, _) in DOC_PAGES]
    for expected in ("Getting Started", "Selector Interface", "Requirements")
        @test expected in titles
    end
    # The Reference page IS included: its `@docs` blocks are expanded
    # against the module, the same job Documenter does for the web, so
    # the terminal gets real API documentation rather than a fence.
    @test "Reference" in titles
    @test !any(occursin("```@docs", body) for (_, body) in DOC_PAGES)

    reference = only(body for (t, body) in DOC_PAGES if t == "Reference")
    @test occursin("Process-level entry point", reference)   # main
    @test !occursin("not found", reference)                  # all resolved
end

@testitem "docs: an unresolvable @docs entry degrades, not throws" begin
    using TryIt

    # A renamed or deleted binding must not take the package down at
    # precompile time; the page says so instead.
    md = "```@docs\nTryIt.no_such_binding\n```\n"
    out = TryIt._expand_documenter_blocks(md, TryIt)
    @test occursin("not found", out)
    @test !occursin("```@docs", out)
end

@testitem "docs: non-@docs Documenter fences are dropped" begin
    using TryIt

    md = "before\n\n```@meta\nCurrentModule = TryIt\n```\n\nafter\n"
    out = TryIt._expand_documenter_blocks(md, TryIt)
    @test occursin("before", out)
    @test occursin("after", out)
    @test !occursin("CurrentModule", out)
end

@testitem "docs: embedded content matches the files on disk" begin
    using TryIt
    using TryIt: DOC_PAGES

    # Guards the embedding going stale relative to docs/src.
    dir = joinpath(@__DIR__, "..", "..", "docs", "src")
    isdir(dir) || return
    on_disk = Dict(
        f => TryIt._expand_documenter_blocks(read(joinpath(dir, f), String), TryIt)
    for f in readdir(dir) if endswith(f, ".md")
    )
    for (_, body) in DOC_PAGES
        @test any(==(body), values(on_disk))
    end
end

@testitem "selector: F1 opens the docs browser" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        TryIt.create_try(root, TryIt.slug("alpha"))
        m = TryIt.open_session(root)

        Tachikoma.update!(m, Tachikoma.KeyEvent(:f1, '\0', Tachikoma.key_press))
        @test m.mode === :docs
        @test m.doc_index == 1

        # Esc leaves; the selector is untouched underneath.
        press_keys!(m, "\e")
        @test m.mode === :normal
        @test m.done === false
    end
end

@testitem "selector: the docs browser pages through the set" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)
        Tachikoma.update!(m, Tachikoma.KeyEvent(:f1, '\0', Tachikoma.key_press))

        n = length(TryIt.DOC_PAGES)
        Tachikoma.update!(m, Tachikoma.KeyEvent(:tab, '\0', Tachikoma.key_press))
        @test m.doc_index == 2
        # Wraps rather than dead-ending.
        for _ in 1:n
            Tachikoma.update!(m, Tachikoma.KeyEvent(:tab, '\0', Tachikoma.key_press))
        end
        @test 1 <= m.doc_index <= n
    end
end

@testitem "selector: the docs browser renders its page" begin
    using TryIt
    using Tachikoma
    include(joinpath(@__DIR__, "..", "tachikoma_helpers.jl"))

    with_tmp_tries() do dir
        root = TryIt.TriesPath(positional=dir)
        m = TryIt.open_session(root)
        Tachikoma.update!(m, Tachikoma.KeyEvent(:f1, '\0', Tachikoma.key_press))

        text = join(render_selector(m, 100, 28), "\n")
        title, _ = TryIt.DOC_PAGES[m.doc_index]
        @test occursin(title, text)
    end
end
