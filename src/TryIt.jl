"""
    TryIt

Ephemeral-workspace manager CLI.

Public surface is intentionally minimal: the only exported entry
point is [`main`](@ref). Everything else is internal.

For the compiled standalone build, [`julia_main`](@ref) is the
PackageCompiler entry point.
"""
module TryIt

using Dates
using PrecompileTools
using REPL
using CommonMark
using TOML
using Tachikoma
using Unicode

# Bring the Tachikoma callback names (update!, view, should_quit)
# into scope so we can extend them with our own methods below.
@tachikoma_app

"""
The UI-free layer: slugs, paths, git, lifecycle, panels, settings.

A submodule rather than a package for now, but a real boundary: it
lists no UI dependency, and `test/spec/test_core_boundary.jl` fails if
one appears. That constraint is load-bearing, not stylistic — see the
CHANGELOG entry on `juliac --trim`.

Promotion to a `TryItCore` package is mechanical from here; it is
deferred until a trimmed binary is actually achievable.
"""
module Core

using Dates
using DocStringExtensions
using Downloads
using TOML
using Unicode

# `@template` applies per module, so this is included here *and* in
# the parent. Dropping either one silently strips the generated
# signatures from that module's docstrings.
include("docstrings.jl")
include("color.jl")
include("errors.jl")
include("slug.jl")
include("paths.jl")
include("git.jl")
include("fetch.jl")
include("trust.jl")
include("extensions.jl")
include("lifecycle.jl")
include("panels.jl")
include("config.jl")
include("animations.jl")
include("fps.jl")
include("selector_state.jl")

end # module Core

# Re-export Core's whole surface, underscored internals included.
#
# Core is an internal layer boundary, not a public API: the package's
# public surface is still `main` alone. Every name therefore stays
# reachable as `TryIt.x`, exactly as before the split, so neither the
# outer layers nor the ~3150 tests need to learn where a name lives.
# A hand-maintained export list would drift; this cannot.
#
# `import`, not `using`: the UI layer adds methods to functions the
# core owns — `animation_name` and `blanks_panels` both gain glyph
# background cases in theming.jl — and `using` brings a name in
# without the right to extend it.
for _name in names(Core; all=true, imported=false)
    startswith(string(_name), "#") && continue
    _name in (:Core, :eval, :include) && continue
    isdefined(Core, _name) || continue
    _value = getfield(Core, _name)
    # Skip Core's own dependencies (Dates, TOML, …) but keep modules
    # *defined* in Core — `ExitCode` is one, and dropping it takes the
    # CLI's exit codes with it.
    _value isa Module && parentmodule(_value) !== Core && continue
    @eval import .Core: $_name
end

include("docstrings.jl")
include("terminal.jl")
include("theming.jl")
include("selector.jl")
include("shell_init.jl")
include("cli.jl")
include("app.jl")

export main

"""
Process-level entry point. Parses `args`, dispatches to the
appropriate subcommand, and calls `exit` with the resolved exit
code. Intended to be invoked from the shell function emitted by
`tryit init` (see [`emit_shell_init`](@ref)).

EARS coverage: UB6.
"""
main(args::AbstractVector{<:AbstractString}) = exit(Int(cli_main(args)))
# Last include: `@docs` blocks are expanded against this module, so
# every docstring — `main` included — must already be defined.
include("docs_embed.jl")

# Precompile workload — warms the hottest paths at install time so
# the first `tryit` invocation after precompile does not re-incur
# inference costs. Deliberately scoped to pure / filesystem-only
# operations; `clone_into` / `worktree_at` shell out to `git`, which
# is brittle inside precompile sandboxes.
#
# EARS coverage: NF17 / FR-043.
@compile_workload begin
    slug("warmup idea")
    mktempdir() do _workload_dir
        _workload_root = TriesPath(positional=_workload_dir)
        _workload_entries = list_tries(_workload_root)
        filter_tries(_workload_entries, "")
        placeholder_slug_for_today(_workload_root)
        _workload_session = open_session(_workload_root)
        Tachikoma.update!(
            _workload_session,
            Tachikoma.KeyEvent(:char, 'a')
        )
    end
end

end # module
