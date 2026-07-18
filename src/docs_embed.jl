# The manual, embedded in the package at precompile time.
#
# Read from `docs/src` when this file is *compiled*, never at run
# time. PackageCompiler puts no `.md` files in an app bundle — there
# are zero anywhere in it — and `pkgdir` inside a compiled app
# resolves to the path recorded during precompilation, i.e. the
# machine that built the binary. Reading from disk would therefore
# work for whoever ran the build and fail for every other user, which
# is exactly the kind of bug that never shows up in testing.
#
# 36 KB of markdown, so the cost of carrying it is negligible next to
# the runtime already in the image.

"""
Markdown for the docstring attached to `name` in `mod`.

This is the in-TUI counterpart of what Documenter does when it
expands a `@docs` block: resolve the binding, take its docstring, and
splice the result in as ordinary markdown.
"""
function _docstring_markdown(mod::Module, name::AbstractString)
    sym = Symbol(last(split(strip(name), '.')))
    isdefined(mod, sym) || return string("`", name, "` — not found.\n\n")
    doc = try
        Base.Docs.doc(Base.Docs.Binding(mod, sym))
    catch
        return string("`", name, "` — docstring unavailable.\n\n")
    end
    return string("### `", name, "`\n\n", string(doc), "\n\n")
end

"""
Expand Documenter `@docs` blocks in `md` against `mod`.

Other Documenter-only fences (`@example`, `@meta`, `@setup`) carry no
content a reader needs and are dropped — left alone they would render
as literal fences, showing a directive instead of what it stands for.
"""
function _expand_documenter_blocks(md::AbstractString, mod::Module)
    out = IOBuffer()
    lines = split(md, '\n')
    i = firstindex(lines)
    while i <= lastindex(lines)
        opener = lstrip(lines[i])
        if startswith(opener, "```@docs")
            i += 1
            while i <= lastindex(lines) && !startswith(lstrip(lines[i]), "```")
                entry = strip(lines[i])
                isempty(entry) || print(out, _docstring_markdown(mod, entry))
                i += 1
            end
            i += 1                      # closing fence
        elseif startswith(opener, "```@")
            i += 1
            while i <= lastindex(lines) && !startswith(lstrip(lines[i]), "```")
                i += 1
            end
            i += 1
        else
            println(out, lines[i])
            i += 1
        end
    end
    return String(take!(out))
end

"""
Pages shown by the in-app docs browser, in reading order.

`@docs` blocks are expanded against this module, so the Reference
page carries the same API documentation in the terminal that
Documenter produces for the web.
"""
const DOC_PAGES = let
    order = [
        ("index.md", "TryIt.jl"),
        ("getting-started.md", "Getting Started"),
        ("interface.md", "Selector Interface"),
        ("standalone-app.md", "Standalone App"),
        ("rationale.md", "Rationale"),
        ("reference.md", "Reference"),
        ("requirements.md", "Requirements")
    ]
    src = joinpath(dirname(@__DIR__), "docs", "src")
    pages = Tuple{String, String}[]
    for (file, title) in order
        path = joinpath(src, file)
        # Absent during an unusual build (a source tarball without
        # docs, say) is not a reason to fail loading the package.
        isfile(path) || continue
        # Julia invalidates a precompiled image when an *included*
        # source file changes; a file merely `read` is invisible to
        # that machinery. Without this, editing docs/src/*.md leaves
        # the embedded copy stale and the app shows the old manual
        # with nothing to indicate it.
        include_dependency(path)
        push!(pages, (title, _expand_documenter_blocks(read(path, String), @__MODULE__)))
    end
    pages
end
