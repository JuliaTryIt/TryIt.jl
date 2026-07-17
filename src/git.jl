"""
Outcome of a single `git` subprocess invocation.

`stderr` is the first non-empty line of captured stderr (empty
string if nothing was written). `exitcode` is `git`'s own exit
code; `0` means success.

EARS coverage: UN3, UN5 downstream routing.
"""
struct GitResult
    exitcode::Int
    stderr::String
end

"""
Is `git` available on the process's resolved `PATH`?

Thin wrapper around `Sys.which` so call sites read cleanly and
tests can control availability via `PATH` scrubbing.

EARS coverage: UN5 / FR-030.
"""
git_available() = Sys.which("git") !== nothing

"""
Resolved inputs to `tryit clone`.

Constructed once the URL (and optional explicit name) have been
slugified and the destination path resolved against `TRY_PATH`.

EARS coverage: ED5 / FR-024.
"""
struct CloneInvocation
    url::String
    slug::Slug
    dest::String
end

"""
Build a [`CloneInvocation`](@ref).

Derives the slug from `name_arg` (if supplied and non-empty) or
from the URL basename. Throws `ArgumentError` on an empty slug or
when `dest` already exists.
"""
function CloneInvocation(
        url::AbstractString,
        name_arg::Union{Nothing, AbstractString},
        root::TriesPath,
        today::Date=Dates.today()
)
    raw = if name_arg === nothing || isempty(String(name_arg))
        _url_basename(url)
    else
        String(name_arg)
    end
    s = slug(raw)
    dest = joinpath(root.root, try_basename(today, s))
    isdir(dest) &&
        throw(ArgumentError(string("destination exists: ", dest)))
    return CloneInvocation(String(url), s, dest)
end

"""
Extract the slug-shaped basename from a clone URL.

Handles HTTPS (`https://host/org/repo.git`), SSH
(`ssh://git@host/org/repo.git`), SCP form
(`git@host:org/repo.git`), local paths (`/path/to/repo/`), and
trailing `.git` / trailing `/`. Throws `ArgumentError` if the
result is empty after stripping.

EARS coverage: ED5 / FR-024. See research §2.
"""
function _url_basename(url::AbstractString)
    s = String(url)
    # Strip trailing '/'.
    while !isempty(s) && last(s) == '/'
        s = SubString(s, 1, prevind(s, lastindex(s))) |> String
    end
    # Take substring after the last '/' or ':'. Both `findlast` calls
    # return `Union{Nothing, Int}`; narrow to `Int` eagerly so JET
    # can see `nextind`'s input type.
    last_slash::Int = something(findlast('/', s), 0)
    last_colon::Int = something(findlast(':', s), 0)
    cut::Int = max(last_slash, last_colon)
    tail = cut == 0 ? s : SubString(s, nextind(s, cut), lastindex(s))
    # Strip trailing '.git'.
    t = String(tail)
    if endswith(t, ".git")
        t = t[1:(end - 4)]
    end
    isempty(t) && throw(ArgumentError("cannot derive basename from URL: $url"))
    return t
end

"""
Run `git clone -- <url> <dest>` and return a [`GitResult`](@ref).

On non-zero exit, removes any partial directory at `dest` so the
tries path is left byte-for-byte unchanged (FR-029 / UN3).

EARS coverage: ED5, UN3, UB4 (stdout discipline).
"""
function clone_into(inv::CloneInvocation)
    err_buf = IOBuffer()
    cmd = pipeline(
        `git clone -- $(inv.url) $(inv.dest)`;
        stdin=stdin,
        stdout=devnull,
        stderr=err_buf
    )
    proc = run(cmd; wait=false)
    wait(proc)
    stderr_text = String(take!(err_buf))
    if proc.exitcode != 0
        # Defensive cleanup: `git clone` normally removes its partial
        # on failure, but a stubbed-git test (or a mid-flight crash)
        # can leave residue. UN3 mandates zero residue.
        try
            isdir(inv.dest) && rm(inv.dest; recursive=true, force=true)
        catch
            # best-effort
        end
    end
    return GitResult(proc.exitcode, _collapse_stderr(stderr_text))
end

"""
Current repo's toplevel directory, or `nothing` if not inside a repo.

Runs `git rev-parse --show-toplevel`. Returns the trimmed path on
exit `0`; `nothing` on any non-zero exit (OF2).

EARS coverage: OF2 / FR-028.
"""
function current_repo_root()
    out_buf = IOBuffer()
    cmd = pipeline(
        `git rev-parse --show-toplevel`;
        stdin=devnull,
        stdout=out_buf,
        stderr=devnull
    )
    proc = try
        run(cmd; wait=false)
    catch
        return nothing
    end
    wait(proc)
    proc.exitcode == 0 || return nothing
    root = strip(String(take!(out_buf)))
    return isempty(root) ? nothing : String(root)
end

"""
Resolved inputs to `tryit worktree <name>`.

Throws `ArgumentError("not inside a git repository")` if the
current working directory is not inside a git repository (OF2).

EARS coverage: ED6, OF2.
"""
struct WorktreeInvocation
    repo_root::String
    slug::Slug
    dest::String
end

function WorktreeInvocation(
        name_arg::AbstractString,
        root::TriesPath,
        today::Date=Dates.today()
)
    repo_root = current_repo_root()
    repo_root === nothing &&
        throw(ArgumentError("not inside a git repository"))
    s = slug(name_arg)
    dest = joinpath(root.root, try_basename(today, s))
    return WorktreeInvocation(repo_root, s, dest)
end

"""
Run `git worktree add -- <dest> HEAD` from `inv.repo_root`.

EARS coverage: ED6 / FR-025.
"""
function worktree_at(inv::WorktreeInvocation)
    err_buf = IOBuffer()
    exitcode = Base.cd(inv.repo_root) do
        cmd = pipeline(
            `git worktree add -- $(inv.dest) HEAD`;
            stdin=devnull,
            stdout=devnull,
            stderr=err_buf
        )
        proc = run(cmd; wait=false)
        wait(proc)
        return proc.exitcode
    end
    stderr_text = String(take!(err_buf))
    return GitResult(exitcode, _collapse_stderr(stderr_text))
end

"""
Collapse multi-line captured stderr to its first non-empty line.

Keeps our `diag(:git, …)` output single-line and stable. Full git
output is available to users by re-running git directly; we do
not re-emit it here.
"""
function _collapse_stderr(s::AbstractString)
    for line in eachsplit(s, '\n')
        stripped = strip(line)
        isempty(stripped) || return String(stripped)
    end
    return ""
end
