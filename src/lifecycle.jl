"""
Resolved inputs to a rename commit (Ctrl-R inside the selector).

`dest_path` is `joinpath(dirname(src_try.path), YYYY-MM-DD-<new_slug>)`
— the date prefix is preserved, only the slug changes.

EARS coverage: ED7 / FR-034.
"""
struct RenameInvocation
    src_try::Try
    new_slug::Slug
    dest_path::String
end

function RenameInvocation(src::Try, new_slug::Slug)
    parent = dirname(src.path)
    # Renaming an undated directory must not silently promote it into
    # the dated scheme — the user did not ask for a date.
    dest = joinpath(
        parent,
        src.dated ? try_basename(src.date, new_slug) : new_slug.value
    )
    isdir(dest) &&
        throw(ArgumentError(string("destination exists: ", dest)))
    return RenameInvocation(src, new_slug, dest)
end

"""
Perform the in-place rename described by `inv`.

Uses `Base.mv(; force = false)`, which is atomic on same-FS moves
and falls back to copy-and-delete across filesystems. Failure
propagates as a `SystemError` that the caller should catch.

EARS coverage: ED7 / FR-034.
"""
function rename_try(inv::RenameInvocation)
    Base.mv(inv.src_try.path, inv.dest_path; force=false)
    return nothing
end

"""
Resolved inputs to a graduate commit (Ctrl-G inside the selector).

`dest_path` is `joinpath(projects_root, src_try.slug.value)` —
the date prefix is dropped when moving from `\$TRY_PATH` to
`\$TRY_PROJECTS`.

EARS coverage: ED8 / FR-035.
"""
struct GraduateInvocation
    src_try::Try
    projects_root::String
    dest_path::String
end

function GraduateInvocation(src::Try, root::TriesPath)
    projects = resolve_projects_path(root)
    dest = joinpath(projects, src.slug.value)
    isdir(dest) &&
        throw(ArgumentError(string("destination exists: ", dest)))
    return GraduateInvocation(src, projects, dest)
end

"""
Perform the graduation described by `inv`.

Moves `inv.src_try.path` to `inv.dest_path` and returns the new
path for the caller to emit as `cd`.

EARS coverage: ED8 / FR-035.
"""
function graduate_try(inv::GraduateInvocation)
    Base.mv(inv.src_try.path, inv.dest_path; force=false)
    return inv.dest_path
end

"""
Interactive prompt: `Delete <N> tries? [y/N] `.

Writes the prompt to `stderr_io` (stderr by default), reads one
line from `stdin_io` (stdin by default), returns `true` iff the
line is `"y"` or `"Y"` after whitespace stripping. Returns
`false` on EOF / non-TTY / any other response — the fail-safe
for scripted contexts (spec Assumptions).

EARS coverage: ED10 / FR-037.
"""
function confirm_delete(
        n::Integer;
        stdin_io::IO=stdin,
        stderr_io::IO=stderr
)
    n <= 0 && return false
    print(stderr_io, "Delete ", n, " tries? [y/N] ")
    flush(stderr_io)
    response = try
        readline(stdin_io)
    catch
        return false
    end
    trimmed = strip(response)
    return trimmed == "y" || trimmed == "Y"
end

"""
Recursively delete each path in `paths`.

Best-effort: failures emit a single stderr diag per path via
[`diag`](@ref) and the loop continues. Missing directories are
silently ignored (stale marks from earlier rename/graduate
operations). Returns the number of paths successfully removed.

EARS coverage: ED10 / FR-037.
"""
# EARS coverage: UN10.
function execute_deletes!(paths)
    deleted = 0
    for path in paths
        try
            isdir(path) || continue
            # A linked worktree has to be unregistered from its parent
            # repository, not just unlinked from the filesystem: `rm`
            # alone leaves it in `git worktree list` and leaves its
            # admin directory under `.git/worktrees`.
            if is_worktree(path)
                remove_worktree(path)
            end
            # Still remove whatever is left. `git worktree remove` may
            # have failed — the parent repository can be gone, or git
            # may be absent — and that is not a reason to leave the
            # directory behind.
            if isdir(path)
                rm(path; recursive=true, force=true)
            end
            deleted += 1
        catch err
            diag(:delete, string(path, ": ", _err_msg(err)))
        end
    end
    return deleted
end

"""
A pending "adopt this directory into the dated scheme" operation.

Constructing one validates; [`date_try`](@ref) performs the move.

EARS coverage: ED19.
"""
struct DateInvocation
    src_try::Try
    dest_path::String
end

function DateInvocation(src::Try)
    src.dated &&
        throw(ArgumentError(string(src.name, " is already dated")))
    # The prefix is prepended to the name *verbatim*. Re-slugging
    # would turn `LibPARI.jl` into `libpari-jl` and lose the identity
    # the user gave the directory; the parser accepts any remainder
    # after a valid date, so there is no need.
    stamp = Dates.format(src.date, dateformat"yyyy-mm-dd")
    dest = joinpath(dirname(src.path), string(stamp, "-", src.name))
    ispath(dest) &&
        throw(ArgumentError(string("destination exists: ", dest)))
    return DateInvocation(src, dest)
end

"""
Perform the dating described by `inv`, returning the new path.

The date committed is the one the selector was already showing —
inferred from the filesystem mtime — so the entry does not appear to
jump to today the moment it is adopted.

EARS coverage: ED19.
"""
function date_try(inv::DateInvocation)
    Base.mv(inv.src_try.path, inv.dest_path; force=false)
    return inv.dest_path
end
