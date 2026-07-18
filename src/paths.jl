"""
Resolved tries-path root with a tag indicating how it was resolved.

Resolution order (FR-001 / UB1):

 1. `positional` argument (highest priority).
 2. `ENV["TRY_PATH"]`.
 3. `\$HOME/work/tries` (default), matching `try-rs`.

EARS coverage: UB1.
"""
struct TriesPath
    "Absolute, normalised path to the tries root."
    root::String
    "Where the path came from: `:arg`, `:env`, or `:default`."
    source::Symbol
end

"""
Construct a [`TriesPath`](@ref), auto-creating the root if absent.

If the root cannot be created or is not writable by the current
user, calls [`diag`](@ref) with the error and `exit(Int(ExitCode.PERMISSION))`
(FR-014 / UN1).
"""
function TriesPath(; positional::Union{Nothing, AbstractString}=nothing)
    root, source = _resolve_tries_root(positional)
    abs_root = abspath(normpath(root))
    _ensure_writable(abs_root)
    # Resolve symlinks only after the root is known to exist —
    # `realpath` throws on a missing path. This matters on macOS,
    # where `/var` and `/tmp` are symlinks into `/private`: without
    # it, two spellings of the same root compare unequal and the
    # graduate/rename collision checks can be fooled.
    return TriesPath(realpath(abs_root), source)
end

function _resolve_tries_root(positional::Union{Nothing, AbstractString})
    if positional !== nothing && !isempty(positional)
        return (String(positional), :arg)
    end
    env = get(ENV, "TRY_PATH", "")
    if !isempty(env)
        return (String(env), :env)
    end
    home = get(ENV, "HOME", homedir())
    return (joinpath(home, "work", "tries"), :default)
end

function _ensure_writable(path::AbstractString)
    try
        if !isdir(path)
            mkpath(path)
        end
    catch err
        diag(:tries_path, string(path, ": ", _err_msg(err)))
        exit(Int(ExitCode.PERMISSION))
    end
    # Probe writability by opening a tempfile; cleans up immediately.
    probe = joinpath(path, ".try-write-probe")
    try
        open(probe, "w") do io
            write(io, "")
        end
    catch err
        diag(:tries_path, string(path, ": ", _err_msg(err)))
        exit(Int(ExitCode.PERMISSION))
    finally
        try
            isfile(probe) && rm(probe; force=true)
        catch
            # best-effort cleanup
        end
    end
    return nothing
end

_err_msg(err) = sprint(showerror, err)

"""
A single dated try. `path = dirname(root) joined with YYYY-MM-DD-<slug>`.

EARS coverage: UB1, UB2, ED1, SD7.
"""
struct Try
    "Absolute path to the try's directory."
    path::String
    "Slug portion of the basename, or one derived from it when undated."
    slug::Slug
    "Date prefix parsed from the basename, or the mtime's date when undated."
    date::Date
    "Last-modified timestamp (seconds since epoch)."
    mtime::Float64
    "Directory basename, exactly as it appears on disk. May hold
     characters a `Slug` cannot, such as `LibPARI.jl`."
    name::String
    "Whether the basename carried a `YYYY-MM-DD-` prefix. Undated
     directories are listed too, distinguished in the selector."
    dated::Bool
end

# Back-compat: everything that constructs a dated try keeps working.
function Try(path::AbstractString, s::Slug, date::Date, mtime::Real)
    Try(String(path), s, date, Float64(mtime), s.value, true)
end

"""
Format a try's basename as `YYYY-MM-DD-<slug>`.

EARS coverage: UB2.
"""
function try_basename(date::Date, s::Slug)
    return string(Dates.format(date, dateformat"yyyy-mm-dd"), "-", s.value)
end

"""
Create (or re-use) a dated directory for `s` under `root`.

Idempotent on same-day collision: if the directory already exists,
returns a [`Try`](@ref) pointing at it with no error (this is the
natural consequence of ED3 / ED4 ordering — see the "Edge Cases"
section of the feature spec).

When a `.try-template` file exists in `root.root` and the try
directory is being **freshly** created (not re-used on collision),
its contents are copied into the new directory as `.try-template`.
Template failures are non-fatal (FR-040 / OF3).

EARS coverage: UB1, UB2, ED4, OF3.
"""
function create_try(
        root::TriesPath, s::Slug,
        today::Date=Dates.today()
)
    base = try_basename(today, s)
    path = joinpath(root.root, base)
    fresh = !isdir(path)
    if fresh
        mkpath(path)
        copy_template!(root, path)
    end
    return Try(path, s, today, mtime(path))
end

"""
Copy `\$TRY_PATH/.try-template` into `dest_dir/.try-template` if
the template is a regular file. Silently skips when the template
is absent; emits a stderr diag and skips when it is a directory
or when copying fails. Never throws — the caller treats the
template as best-effort.

EARS coverage: OF3 / FR-040.
"""
function copy_template!(root::TriesPath, dest_dir::AbstractString)
    src = joinpath(root.root, ".try-template")
    isfile(src) || return nothing_if_dir_template(src)
    dst = joinpath(dest_dir, ".try-template")
    try
        cp(src, dst; force=false)
    catch err
        diag(:template, _err_msg(err))
    end
    return nothing
end

function nothing_if_dir_template(src)
    if isdir(src)
        diag(:template, ".try-template is a directory, skipping")
    end
    return nothing
end

"""
List every directory under `root` whose name parses as
`YYYY-MM-DD-<slug>`, sorted most-recently-modified first.

Entries that do not parse (stray files, differently-shaped
directories) are silently skipped — they belong to someone else.

EARS coverage: ED1.
"""
function list_tries(root::TriesPath)
    isdir(root.root) || return Try[]
    entries = Try[]
    for name in readdir(root.root; sort=false)
        full = joinpath(root.root, name)
        isdir(full) || continue
        stamp = mtime(full)
        parsed = _parse_try_basename(name)
        if parsed === nothing
            # Not one of our dated directories, but still a folder the
            # user put here — list it, dated from the filesystem, and
            # let the selector render it differently.
            push!(
                entries,
                Try(full, _derive_slug(name), _local_date(stamp),
                    stamp, String(name), false)
            )
        else
            date, rest = parsed
            push!(
                entries,
                Try(full, _derive_slug(rest), date, stamp, String(rest), true)
            )
        end
    end
    sort!(entries; by=t -> t.mtime, rev=true)
    return entries
end

"""
Local calendar date of a unix timestamp.

`unix2datetime` yields UTC, but every date TryIt *writes* comes from
`Dates.today()`, which is local. Mixing them puts a folder touched
shortly after midnight on the wrong day, and makes the date shown for
an undated folder disagree with the prefix it would be given.
"""
_local_date(t::Real) = Date(Dates.unix2datetime(t) + (Dates.now() - Dates.now(Dates.UTC)))

const _TRY_BASENAME_RE = r"^(\d{4})-(\d{2})-(\d{2})-(.+)$"

"""
Best-effort slug for a directory whose name was never one.

Used for undated entries so that graduate and rename have something
canonical to work with. Falls back to the raw name when it projects
to nothing at all (a directory called `...`, say).
"""
function _derive_slug(name::AbstractString)
    return try
        slug(name)
    catch err
        err isa ArgumentError ? Slug(String(name)) : rethrow()
    end
end

function _parse_try_basename(name::AbstractString)
    m = match(_TRY_BASENAME_RE, name)
    m === nothing && return nothing
    # Mandatory capture groups — always SubString on a non-nothing match,
    # but JET reads the static type as `Union{Nothing, SubString}`. The
    # explicit widenings below quiet that without a runtime cost.
    y = m.captures[1]::SubString{String}
    mo = m.captures[2]::SubString{String}
    d = m.captures[3]::SubString{String}
    rest = m.captures[4]::SubString{String}
    date = try
        Date(parse(Int, y), parse(Int, mo), parse(Int, d))
    catch
        return nothing
    end
    # The remainder is NOT required to match UB3's output alphabet.
    # It once was, on the reasoning that anything else "is not one of
    # our tries" — but every directory is listed now, so rejecting it
    # here only meant misreading a genuinely dated try as undated and
    # stamping it with today's mtime. `2026-04-15-s-celles-Nghttp2Wrapper.jl`
    # is a real example: uppercase and a dot in the remainder.
    return (date, String(rest))
end

"""
Case-insensitive substring filter over `entries`. Matches against
`"YYYY-MM-DD slug"` joined with a single space, so the user can
filter by either the date or the slug (or both).

EARS coverage: ED2.
"""
function filter_tries(entries::Vector{Try}, query::AbstractString)
    isempty(query) && return entries
    needle = lowercase(query)
    return filter(entries) do t
        haystack = lowercase(string(t.date, " ", t.name))
        return occursin(needle, haystack)
    end
end

"""
Resolve the projects-path root where graduations land.

Resolution order (SPEC glossary):

 1. `ENV["TRY_PROJECTS"]` if non-empty.
 2. `dirname(root.root)` (parent of the tries path).

Auto-creates the target directory if absent. Fails with a diag +
`exit(Int(ExitCode.PERMISSION))` if the target cannot be created or
written to.

EARS coverage: ED8 / FR-035.
"""
function resolve_projects_path(root::TriesPath)
    env = get(ENV, "TRY_PROJECTS", "")
    target = isempty(env) ? dirname(root.root) : String(env)
    abs_target = abspath(normpath(target))
    _ensure_writable(abs_target)
    return abs_target
end

"""
Pick the next free `new-try[-N]` slug for `today`.

Scans the tries root for same-day entries whose slug matches
`new-try` or `new-try-<integer>`, then picks the smallest unused
non-negative integer. Returns `Slug("new-try")` when `0` is free,
`Slug("new-try-N")` otherwise.

EARS coverage: ED11 / FR-026.
"""
function placeholder_slug_for_today(
        root::TriesPath,
        today::Date=Dates.today()
)
    used = Set{Int}()
    for t in list_tries(root)
        t.dated || continue
        t.date == today || continue
        v = t.slug.value
        if v == "new-try"
            push!(used, 0)
        else
            m = match(r"^new-try-(\d+)$", v)
            m === nothing && continue
            push!(used, parse(Int, m.captures[1]::SubString{String}))
        end
    end
    n = 0
    while n in used
        n += 1
    end
    return n == 0 ? Slug("new-try") : Slug(string("new-try-", n))
end
