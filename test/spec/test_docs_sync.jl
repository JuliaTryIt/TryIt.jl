# Guards against documentation drifting away from the code.
#
# Both checks here encode drift that actually happened: the key
# bindings table kept listing Ctrl-T as "create a new dated try" for a
# commit after the binding moved to Ctrl-N, and a whole section
# documented Tachikoma shortcuts that `default_bindings=false` had
# already switched off. Neither broke a test, because nothing tied the
# prose to the implementation.

@testitem "spec: documented key bindings exist in the code" begin
    using TryIt

    docs = read(
        joinpath(@__DIR__, "..", "..", "docs", "src", "interface.md"), String)

    # Every `Ctrl+X` / `Ctrl-X` in the bindings tables must be a key
    # the selector actually handles.
    section = split(docs, "## Key bindings")[2]
    section = split(section, "## Shell integration")[1]
    documented = Set(lowercase(m.captures[1])
    for m in eachmatch(r"`Ctrl[+-]([A-Za-z])`", section))

    selector = read(
        joinpath(@__DIR__, "..", "..", "src", "selector.jl"), String)
    handled = Set(lowercase(m.captures[1])
    for m in eachmatch(r"evt\.char == '([a-z])'", selector))
    # Ctrl-C is dispatched on its own key symbol rather than by
    # comparing a char, so it never appears in the pattern above.
    occursin(":ctrl_c", selector) && push!(handled, "c")

    undocumented_or_stale = setdiff(documented, handled)
    @test isempty(undocumented_or_stale)
end

@testitem "spec: the help overlay covers the documented bindings" begin
    using TryIt

    docs = read(
        joinpath(@__DIR__, "..", "..", "docs", "src", "interface.md"), String)
    section = split(split(docs, "## Key bindings")[2], "## Shell integration")[1]
    documented = Set(uppercase(m.captures[1])
    for m in eachmatch(r"`Ctrl[+-]([A-Za-z])`", section))

    # `?` is the only place the full keymap is visible at runtime, so
    # it must not fall behind the manual.
    in_overlay = Set(uppercase(m.captures[1])
    for m in eachmatch(r"Ctrl[+-]([A-Za-z])", join(first.(TryIt.HELP_KEYS), " ")))

    @test isempty(setdiff(documented, in_overlay))
end

@testitem "spec: the documented default tries root matches the code" begin
    using TryIt

    # The default appears in README, two docs pages, the shell
    # snippet, and paths.jl. Changing it once meant changing it in six
    # places, and this pins them together.
    default_root = withenv("TRY_PATH" => nothing, "HOME" => "/home/u") do
        last(TryIt._resolve_tries_root(nothing))
        TryIt._resolve_tries_root(nothing)[1]
    end
    @test default_root == "/home/u/work/tries"

    tail = join(splitpath(default_root)[(end - 1):end], "/")   # "work/tries"
    for file in (
        joinpath(@__DIR__, "..", "..", "README.md"),
        joinpath(@__DIR__, "..", "..", "docs", "src", "getting-started.md")
    )
        @test occursin(tail, read(file, String))
    end

    # And the emitted shell function must fall back to the same place.
    io = IOBuffer()
    TryIt.emit_shell_init(io, nothing)
    @test occursin(tail, String(take!(io)))
end
