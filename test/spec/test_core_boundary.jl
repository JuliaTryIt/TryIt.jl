# Architectural invariant, not a behaviour test.
#
# The core must stay free of any UI layer, and the constraint is not
# stylistic: a dependency on Tachikoma runs its `__init__`, which
# performs seven `@load_preference` reads. Under `juliac --trim` those
# resolve to `Base.get_preferences`, which splats into a vararg and
# cannot be resolved statically — so the binary dies at load before
# reaching `main`. Measured 2026-07-18; see CHANGELOG.
#
# A grep is crude, but it fails at the moment someone recouples, which
# is the only moment that matters. It is superseded by a real package
# boundary once the core moves to TryItCore.

@testitem "architecture: the core references no UI layer" begin
    using TryIt

    CORE_FILES = [
        "slug.jl", "paths.jl", "errors.jl", "git.jl", "fetch.jl",
        "trust.jl", "color.jl", "lifecycle.jl", "panels.jl",
        "config.jl", "docstrings.jl", "animations.jl", "fps.jl",
        "selector_state.jl"
    ]
    UI_NAMES = ["Tachikoma", "CommonMark", "DearImGui"]

    src = joinpath(pkgdir(TryIt), "src")
    # Collect every violation rather than asserting per file: a bare
    # `@test !occursin(...)` prints the whole file on failure, which
    # buries the one line that matters.
    violations = String[]
    for file in CORE_FILES
        # Strip comment tails; prose may legitimately name the layer it
        # is contrasting against, and only code couples. Docstrings are
        # deliberately *not* stripped — a core docstring that has to
        # explain Tachikoma's behaviour is describing the wrong layer.
        code = join(
            [first(split(line, '#')) for line in eachline(joinpath(src, file))], '\n')
        for name in UI_NAMES
            occursin(name, code) && push!(violations, string(file, " → ", name))
        end
    end
    @test violations == String[]
end

@testitem "architecture: TryIt.Core loads no UI dependency" begin
    using TryIt

    # The authoritative check, now that Core is a real module: a
    # `using Tachikoma` inside it makes the name resolve there, which
    # no amount of source grepping would need to guess at. The grep
    # above stays as the guard on *which files* form the core; this
    # guards what the module actually pulls in.
    for ui in (:Tachikoma, :CommonMark, :DearImGui, :REPL)
        @test !isdefined(TryIt.Core, ui)
    end

    # The optional trust backend is held to the same rule, for a
    # different reason: a hard reference from the core would stop the
    # weak dependency being weak, and TryIt would fail to load for
    # anyone who has not installed PluginGuard.
    @test !isdefined(TryIt.Core, :PluginGuard)
    @test !isdefined(TryIt, :PluginGuard)

    # Control: the probe must be able to see a dependency that IS
    # there, otherwise it would pass by accident forever.
    @test isdefined(TryIt.Core, :Dates)
    @test isdefined(TryIt.Core, :TOML)

    # And the outer module still has the UI layer — the core being
    # clean must not mean the package lost its frontend.
    @test isdefined(TryIt, :Tachikoma)
end

@testitem "architecture: the UI layer extends core functions, not shadows them" begin
    using TryIt
    using Tachikoma

    # The core owns the animation family as values; the UI layer adds
    # the glyph-background cases. If the re-export ever goes back to
    # `using`, these definitions would silently become a *new*
    # function in TryIt and the core's methods would stop being found
    # — the kind of break that leaves every test passing except the
    # one behaviour nobody covers.
    @test parentmodule(TryIt.animation_name) === TryIt.Core
    @test parentmodule(TryIt.blanks_panels) === TryIt.Core

    # Both families answer through the one function.
    @test TryIt.animation_name(TryIt.FogBackground()) == "fog"
    @test TryIt.animation_name(nothing) == "off"
    @test TryIt.animation_name(Tachikoma.DotWaveBackground()) == "dotwave"

    @test TryIt.blanks_panels(TryIt.FogBackground())
    @test !TryIt.blanks_panels(Tachikoma.DotWaveBackground())
end

@testitem "architecture: selector state is frontend-independent" begin
    using TryIt

    @test parentmodule(TryIt.SelectorState) === TryIt.Core

    # Constructible and drivable with no frontend in sight. This is
    # the whole point of the split: a second frontend has to be able
    # to hold and mutate this without Tachikoma existing.
    mktempdir() do dir
        st = TryIt.SelectorState(root=TryIt.TriesPath(positional=dir))
        st.filter = "abc"
        st.cursor = 1
        st.mode = :rename
        push!(st.marked_for_delete, joinpath(dir, "x"))
        @test st.filter == "abc"
        @test st.mode === :rename
        @test length(st.marked_for_delete) == 1
    end

    # No field of the state may carry a frontend type. `terminal` and
    # `background` are the two that do, and they live on the wrapper.
    state_fields = fieldnames(TryIt.SelectorState)
    @test :terminal ∉ state_fields
    @test :background ∉ state_fields
    @test :terminal ∈ fieldnames(TryIt.SelectorSession)
    @test :background ∈ fieldnames(TryIt.SelectorSession)

    # Forwarding must cover every state field, or a call site that
    # used to reach one would start throwing at runtime only on the
    # branch that touches it.
    for f in state_fields
        @test f ∈ propertynames(TryIt.SelectorSession(root=TryIt.TriesPath(
            positional=mktempdir())))
    end
end
