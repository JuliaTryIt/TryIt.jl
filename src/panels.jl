# Data helpers backing the selector's side panels.
#
# Everything here is pure or filesystem-read-only and returns plain
# data — no Tachikoma types. The view layer in `selector.jl` turns
# these into widgets. Keeping the split lets the panels be tested
# without a terminal.
#
# All of these run inside the render loop, so every function degrades
# to an empty/`nothing` result rather than throwing: a try can be
# deleted out from under the selector between refreshes, and a
# mid-frame exception would take down the TUI.

# ---------------------------------------------------------------- age

"""
Format an age in seconds as `DDd HHh MMm`.

Days are not capped at two digits; sub-minute remainders truncate
rather than round, so a try touched 59 seconds ago reads `00m`.
Negative deltas (clock skew, or a file touched by another machine)
clamp to zero.
"""
function format_age(seconds::Real)
    total = max(0, floor(Int, seconds))
    days, rem = divrem(total, 86400)
    hours, rem = divrem(rem, 3600)
    minutes = div(rem, 60)
    return string(
        lpad(days, 2, '0'), "d ",
        lpad(hours, 2, '0'), "h ",
        lpad(minutes, 2, '0'), "m"
    )
end

"""
Seconds elapsed between `t`'s last-modified time and `now`.
"""
try_age_seconds(t::Try, now::Real=time()) = float(now) - t.mtime

# ------------------------------------------------------------- badges

"""
Badge symbols in render order.

Fixed rather than derived from `readdir`, so a directory's badges do
not jitter between frames.
"""
const BADGE_ORDER = [
    :rust, :julia, :python, :go, :maven, :flutter, :mise,
    :locked, :worktree, :submodule, :git
]

"""
Human-readable label for each badge, used by the legend panel.
"""
const BADGE_LABELS = Dict(
    :rust => "Rust",
    :julia => "Julia",
    :python => "Python",
    :go => "Go",
    :maven => "Maven",
    :flutter => "Flutter",
    :mise => "Mise",
    :locked => "Locked",
    :worktree => "Worktree",
    :submodule => "Submodule",
    :git => "Git"
)

# Marker files that identify a project type. `:julia` deliberately
# precedes `:python` in BADGE_ORDER but the markers are matched
# case-sensitively, so `Project.toml` and `pyproject.toml` stay
# distinct even on a case-insensitive filesystem.
const _BADGE_MARKERS = Dict(
    :rust => ["Cargo.toml"],
    :julia => ["Project.toml", "JuliaProject.toml"],
    :python => ["pyproject.toml", "requirements.txt", "setup.py"],
    :go => ["go.mod"],
    :maven => ["pom.xml"],
    :flutter => ["pubspec.yaml"],
    :mise => [".mise.toml", ".mise.local.toml"],
    :submodule => [".gitmodules"]
)

const _LOCK_MARKERS = [
    "Cargo.lock", "Manifest.toml", "package-lock.json", "poetry.lock",
    "uv.lock", "yarn.lock", "pnpm-lock.yaml", "go.sum", "Gemfile.lock"
]

"""
Detect project-type badges for the directory at `path`.

Returns a deduplicated vector ordered by [`BADGE_ORDER`](@ref). A
missing or unreadable directory yields an empty vector.

`.git` distinguishes two cases: a *directory* marks a normal
repository (`:git`), while a *file* marks a linked worktree
(`:worktree`), since `git worktree add` writes a gitdir pointer file
rather than a full repository.
"""
function detect_badges(path::AbstractString)
    names = try
        isdir(path) ? Set(readdir(path)) : return Symbol[]
    catch
        # Permission denied, or the directory vanished mid-frame.
        return Symbol[]
    end

    found = Set{Symbol}()
    for (badge, markers) in _BADGE_MARKERS
        any(m -> m in names, markers) && push!(found, badge)
    end
    any(m -> m in names, _LOCK_MARKERS) && push!(found, :locked)

    if ".git" in names
        # `isdir` on the join, not on the name — the distinction is
        # the whole point.
        push!(found, isdir(joinpath(path, ".git")) ? :git : :worktree)
    end

    return filter(b -> b in found, BADGE_ORDER)
end

# ------------------------------------------------------------ preview

"""
One row of the preview panel.
"""
struct PreviewEntry
    """
    Base name, as it appears in the directory.
    """
    name::String
    """
    Whether the entry is a directory.
    """
    isdir::Bool
end

"""
List the contents of `path` for the preview panel.

Directories sort before files, then lexicographically. At most
`limit` entries are returned — the panel is a few rows tall, and
sorting a huge directory every frame would stall the render.

A missing or unreadable path yields an empty vector.
"""
function preview_entries(path::AbstractString; limit::Integer=200)
    names = try
        isdir(path) ? readdir(path) : return PreviewEntry[]
    catch
        return PreviewEntry[]
    end

    entries = PreviewEntry[]
    for name in names
        is_dir = try
            isdir(joinpath(path, name))
        catch
            false
        end
        push!(entries, PreviewEntry(name, is_dir))
    end

    # Directories first, then by name. `by` keeps it a single pass.
    sort!(entries; by=e -> (e.isdir ? 0 : 1, e.name))
    return length(entries) > limit ? entries[1:limit] : entries
end

# --------------------------------------------------------------- disk

"""
Free and used bytes for the filesystem holding the tries root.
"""
struct DiskStats
    """
    Bytes in use on the filesystem.
    """
    used::Int
    """
    Bytes available to the current user.
    """
    free::Int
end

"""
Format a byte count as a human-readable size (`37.0 MB`).

Uses binary units (1 KB = 1024 B). Byte counts below 1 KB render
without a decimal, since `512.0 B` reads oddly.
"""
function format_bytes(bytes::Real)
    b = float(max(0, bytes))
    b < 1024 && return string(round(Int, b), " B")
    for unit in ("KB", "MB", "GB", "TB")
        b /= 1024
        if b < 1024 || unit == "TB"
            return string(round(b; digits=1), " ", unit)
        end
    end
    # Unreachable — the loop returns on "TB".
    return string(round(b; digits=1), " TB")
end

"""
Parse the output of `df -k` into a [`DiskStats`](@ref).

macOS and Linux differ in the header text (`1024-blocks` vs
`1K-blocks`) but agree on column positions: used is column 3 and
available is column 4, both in 1 KiB blocks. Returns `nothing` when
there is no data row or the columns are not numeric.
"""
function parse_df_output(out::AbstractString)
    lines = [l for l in split(out, '\n') if !isempty(strip(l))]
    length(lines) < 2 && return nothing

    # Last line, not line 2: `df` wraps long device names onto their
    # own line, pushing the numbers down.
    fields = split(strip(lines[end]))
    length(fields) < 4 && return nothing

    used = tryparse(Int, fields[3])
    free = tryparse(Int, fields[4])
    (used === nothing || free === nothing) && return nothing

    return DiskStats(used * 1024, free * 1024)
end

"""
Disk usage for the filesystem holding `path`.

Shells out to `df -k`, which is absent on Windows — there, and on any
failure, this returns `nothing` and the panel renders as unavailable
rather than failing the frame.
"""
function disk_usage(path::AbstractString)
    (Sys.iswindows() || !ispath(path)) && return nothing
    out = try
        read(`df -k $path`, String)
    catch
        return nothing
    end
    return parse_df_output(out)
end
