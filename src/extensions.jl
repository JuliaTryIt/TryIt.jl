# The catalogue of optional extensions TryIt offers.
#
# Naming a backend here is data, not a dependency: these are strings
# for `identify_package`, and no binding is created. The core still
# holds no reference to any of them, which is what
# `test_core_boundary.jl` asserts.

"""
An optional capability TryIt can gain when a package is installed
alongside it.

`probe` answers "did it actually register?" after a load attempt.
It is a function rather than a flag because what counts as
registered differs per extension — the trust backend swaps a scanner,
a future one might do something else entirely.

EARS coverage: ED28.
"""
struct Extension
    """
    Short name the user types and reads.
    """
    name::String
    """
    Package that triggers the extension.
    """
    package::String
    """
    Where to install it from, for the hint in the listing.
    """
    url::String
    """
    One line, shown in the listing.
    """
    summary::String
    """
    Returns `true` once the extension has registered itself.
    """
    probe::Function
end

"""
Everything TryIt offers. One entry today, shaped for more.

EARS coverage: ED28, ED29.
"""
const EXTENSIONS = Extension[
    Extension(
    "pluginguard",
    "PluginGuard",
    "https://github.com/s-celles/PluginGuard.jl",
    "Warn about untrusted code in a cloned or fetched try",
    () -> !(TRUST_SCANNER[] isa NoScanner)
)
]

"""
Look up an extension by its short name, or `nothing`.
"""
function find_extension(name::AbstractString)
    for ext in EXTENSIONS
        ext.name == name && return ext
    end
    return nothing
end

"""
Is `ext`'s trigger package present in the active environment?

Answers only "could it be loaded", never "does it work" — that is
[`extension_state`](@ref)'s job, and the distinction is the whole
point of ED28.
"""
extension_installed(ext::Extension) = Base.identify_package(ext.package) !== nothing

"""
The install command for `ext`, naming the environment it belongs in.

The project is spelled out because the shell function runs against
the `@TryIt` shared environment, which is *not* the one a user gets
by typing `julia` — an instruction that omitted it would send them
to install into the wrong place and wonder why nothing changed.

EARS coverage: ED29.
"""
function install_command(ext::Extension, project::AbstractString=_active_project_dir())
    return string(
        "julia --project=", project,
        " -e 'using Pkg; Pkg.add(url=\"", ext.url, "\")'"
    )
end

"""
Directory of the active project, for display in an install hint.
"""
function _active_project_dir()
    active = Base.active_project()
    active === nothing && return "@TryIt"
    return dirname(active)
end

"""
Extensions whose load has already been attempted this process.

Keyed by name so a second lookup does not mean a second
`Base.require`, and so a backend that failed once is not retried on
every clone.
"""
const _ACTIVATION_TRIED = Dict{String, Bool}()

"""
Load `ext`'s trigger package if it is installed, and report whether
the extension registered itself.

A package extension activates when its trigger is *loaded*, not when
it is installed, and nothing in a `tryit` invocation loads it — so
without this the whole mechanism is inert for CLI users. `Base.require`
is legal here: a plain runtime call, outside `__init__` and outside
precompilation. Failure is swallowed, because an installed-but-broken
extension must not take down the command that merely wanted to know
about it.

EARS coverage: ED28, OF7, OF8.
"""
function activate_extension!(ext::Extension)
    haskey(_ACTIVATION_TRIED, ext.name) && return ext.probe()
    _ACTIVATION_TRIED[ext.name] = true
    # A library caller may have loaded it already.
    ext.probe() && return true
    id = Base.identify_package(ext.package)
    id === nothing && return false
    try
        Base.require(id)
        # `require` does not always leave the extension's `__init__`
        # run by the time it returns: on the first invocation after
        # the package is installed it triggers precompilation, and
        # the registration landed one statement too late — so the
        # very first `tryit fetch` after installing a backend warned
        # about nothing, and every one after it worked.
        if !ext.probe() && isdefined(Base, :retry_load_extensions)
            Base.retry_load_extensions()
        end
    catch
        return false
    end
    return ext.probe()
end

"""
`:enabled`, `:broken`, or `:available` for `ext`.

Measured, never inferred from the manifest: the state is decided by
attempting the load and asking the extension whether it registered.
Reading the manifest instead would report `enabled` for a backend
that cannot actually load, which is exactly how the trust scanner
managed to look installed while doing nothing.

EARS coverage: ED28.
"""
function extension_state(ext::Extension)
    extension_installed(ext) || return :available
    return activate_extension!(ext) ? :enabled : :broken
end

"""
Human-readable state and the colour it is shown in.

EARS coverage: ED28.
"""
const EXTENSION_STATE_COLORS = Dict(
    :enabled => :green,
    :broken => :red,
    :available => :dim
)

"""
Marker glyph per state, so the listing survives losing its colour.

UB7 turns colour off for a pipe, and a listing that carried its only
signal in the escape codes would be unreadable exactly where it is
most likely to be read — in a log, or through `less`.
"""
const EXTENSION_STATE_MARKERS = Dict(
    :enabled => "●",
    :broken => "✗",
    :available => "○"
)
