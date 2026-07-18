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
using Tachikoma
using Unicode

# Bring the Tachikoma callback names (update!, view, should_quit)
# into scope so we can extend them with our own methods below.
@tachikoma_app

include("docstrings.jl")
include("errors.jl")
include("slug.jl")
include("paths.jl")
include("terminal.jl")
include("git.jl")
include("lifecycle.jl")
include("panels.jl")
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
main(args::AbstractVector{<:AbstractString}) = exit(cli_main(args))

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
