# Downloading a single resource into a try, and the routing rule that
# decides whether a URL names a repository or a file.

"""
Hosts whose `<owner>/<repo>` URLs name a git repository.

Deliberately short and deliberately not exhaustive: it exists to
resolve one ambiguity, not to enumerate the web. A self-hosted forge
opts in through the `.git` suffix, or the user says `tryit clone`.
"""
const GIT_FORGES = (
    "github.com", "gitlab.com", "codeberg.org", "bitbucket.org", "git.sr.ht"
)

"""
Largest resource `fetch_into` will keep, in bytes.

The destination is the user's tries path, not a cache, so an
unbounded download has no natural stopping point there.

EARS coverage: UN11.
"""
const FETCH_MAX_BYTES = 100 * 1024 * 1024

"""
Classify `arg` as `:clone`, `:fetch`, or `:not_url`.

Extension alone cannot decide this in Julia. The ecosystem names
repositories `Foo.jl`, so `github.com/s-celles/PluginGuard.jl` and
`cdn.example.com/3X/b/3/<hash>.jl` share a suffix while requiring
opposite handling. The rule is therefore host-and-shape, which has
the further advantage of being decidable offline:

  - `ssh://`, `git://`, or the `git@host:path` scp form → `:clone`
  - any URL whose last path segment ends in `.git` → `:clone`
  - `http(s)` on a host in [`GIT_FORGES`](@ref) whose path is exactly
    `<owner>/<repo>` → `:clone`
  - any other `http(s)` URL → `:fetch`
  - anything else → `:not_url`, and the caller treats it as a slug

Two limitations are accepted rather than papered over: a self-hosted
forge is routed to `:fetch` unless its URL ends in `.git`, and a deep
forge URL such as `github.com/<owner>/<repo>/blob/<ref>/<file>` is
routed to `:fetch`, which downloads the HTML page rather than the
file it renders. `tryit clone` and `tryit fetch` override both.

EARS coverage: ED25, ED27.
"""
function url_kind(arg::AbstractString)::Symbol
    s = String(strip(arg))
    isempty(s) && return :not_url
    # scp form, which has no scheme and so must be checked first.
    startswith(s, "git@") && occursin(':', s) && return :clone
    lower = lowercase(s)
    (startswith(lower, "ssh://") || startswith(lower, "git://")) && return :clone
    if !(startswith(lower, "http://") || startswith(lower, "https://"))
        # Without a scheme this is a slug, unless it carries the one
        # marker that is unambiguous everywhere.
        return endswith(lower, ".git") ? :clone : :not_url
    end
    host, segments = _url_host_and_path(s)
    isempty(host) && return :not_url
    # `.git` wins on any host: it is how a self-hosted forge opts in.
    if !isempty(segments) && endswith(lowercase(last(segments)), ".git")
        return :clone
    end
    host in GIT_FORGES && length(segments) == 2 && return :clone
    return :fetch
end

"""
Split an `http(s)` URL into its lowercased host and its path
segments, discarding query and fragment.

A leading `www.` is stripped so the host comparison does not need
both spellings. Empty segments are dropped, which is what makes a
trailing slash irrelevant to [`url_kind`](@ref).
"""
function _url_host_and_path(s::AbstractString)
    rest = _strip_query_and_fragment(s)
    marker = findfirst("//", rest)
    marker === nothing && return ("", String[])
    rest = String(SubString(rest, nextind(rest, last(marker))))
    segments = String[String(p) for p in eachsplit(rest, '/') if !isempty(p)]
    isempty(segments) && return ("", String[])
    host = lowercase(segments[1])
    startswith(host, "www.") && (host = host[5:end])
    return (host, segments[2:end])
end

"""
Drop everything from the first `?` or `#` onwards.
"""
function _strip_query_and_fragment(s::AbstractString)
    cut = findfirst(c -> c == '?' || c == '#', s)
    cut === nothing && return String(s)
    return String(SubString(s, firstindex(s), prevind(s, cut)))
end

"""
The filename a URL's path ends in.

Taken from the path, never from the host: `https://example.com/` has
no filename and raises, rather than yielding `example.com`. Query and
fragment are discarded first, so `thing.jl?raw=1` is `thing.jl`.

Throws `ArgumentError` when the URL has no path segment to take a
name from.

EARS coverage: ED26, UN12.
"""
function _url_filename(url::AbstractString)
    s = _strip_query_and_fragment(url)
    marker = findfirst("//", s)
    segments = if marker === nothing
        String[String(p) for p in eachsplit(s, '/') if !isempty(p)]
    else
        rest = String(SubString(s, nextind(s, last(marker))))
        segs = String[String(p) for p in eachsplit(rest, '/') if !isempty(p)]
        # `file:///tmp/x.jl` has an empty authority, so every segment
        # is path; `https://host/x.jl` spends the first on the host.
        startswith(rest, "/") ? segs : (isempty(segs) ? segs : segs[2:end])
    end
    isempty(segments) &&
        throw(ArgumentError("URL has no path to take a filename from: $url"))
    return last(segments)
end

"""
Strip a single trailing extension, leaving any earlier ones in place.

`archive.tar.gz` becomes `archive.tar`: guessing how many suffixes a
compound extension has is not decidable, and dropping one is the
behaviour that surprises least.
"""
function _drop_extension(name::AbstractString)
    idx = findlast('.', name)
    (idx === nothing || idx == firstindex(name)) && return String(name)
    return String(SubString(name, firstindex(name), prevind(name, idx)))
end

"""
Resolved inputs to `tryit fetch`.

`dest` is the try directory; `filename` is the basename the resource
keeps inside it. The slug comes from `name_arg` when supplied,
otherwise from the filename with its final extension dropped.

EARS coverage: ED26, UN12.
"""
struct FetchInvocation
    url::String
    slug::Slug
    dest::String
    filename::String
end

function FetchInvocation(
        url::AbstractString,
        name_arg::Union{Nothing, AbstractString},
        root::TriesPath,
        today::Date=current_date()
)
    filename = _url_filename(url)
    raw = if name_arg === nothing || isempty(String(name_arg))
        _drop_extension(filename)
    else
        String(name_arg)
    end
    s = slug(raw)
    dest = joinpath(root.root, try_basename(today, s))
    return FetchInvocation(String(url), s, dest, filename)
end

"""
Outcome of a fetch.

`path` is the written file on success and empty otherwise; `error`
is a single line naming the cause on failure and empty otherwise.

EARS coverage: ED26, UN11.
"""
struct FetchResult
    ok::Bool
    path::String
    error::String
end

"""
Download `inv.url` into `inv.dest`, returning a [`FetchResult`](@ref).

Never throws for an expected failure — a transport error, a
non-success status, or a response past `max_bytes` all come back as
`ok = false` with a message, because the caller's job is to write one
stderr line and pick an exit code.

The download lands in a temporary file *outside* the tries path and
is moved in only once it has completed and passed the size check.
That ordering is what makes UN11's no-residue guarantee structural
rather than a matter of remembering to clean up: a half-written file
in a try the user is about to `cd` into looks like it worked.

The cap is enforced twice. The progress callback aborts a stream
already past the limit, which is what stops a runaway download from
filling the disk; the check after the fact is the deterministic one,
since libcurl may finish a small transfer before any callback fires.

EARS coverage: ED26, UN11.
"""
function fetch_into(inv::FetchInvocation; max_bytes::Integer=FETCH_MAX_BYTES)
    too_large = string("response too large (over ", max_bytes, " bytes)")
    tmp = tempname()
    try
        Downloads.download(
            inv.url, tmp;
            progress=(_total, now) -> (now > max_bytes && error(too_large); nothing)
        )
        if filesize(tmp) > max_bytes
            rm(tmp; force=true)
            return FetchResult(false, "", too_large)
        end
        mkpath(inv.dest)
        target = joinpath(inv.dest, inv.filename)
        mv(tmp, target; force=true)
        return FetchResult(true, target, "")
    catch err
        rm(tmp; force=true)
        # Remove the try only if this call is what created it and it
        # holds nothing: a same-day re-fetch must not delete a
        # directory the user already has work in.
        try
            isdir(inv.dest) && isempty(readdir(inv.dest)) &&
                rm(inv.dest; recursive=true, force=true)
        catch
            # best-effort
        end
        return FetchResult(false, "", _fetch_error_message(err))
    end
end

"""
Reduce an exception to the single line `diag(:fetch, …)` will print.

Keeps the diagnostic to one line, as UB5 requires of every other
subsystem.
"""
function _fetch_error_message(err)
    for line in eachsplit(sprint(showerror, _unwrap_exception(err)), '\n')
        stripped = strip(line)
        isempty(stripped) || return String(stripped)
    end
    return "unknown error"
end

"""
Peel wrapper exceptions until the one that says what went wrong.

`Downloads` runs the transfer on a task, so an error raised from the
progress callback — which is how the size cap aborts a stream —
arrives as a `TaskFailedException` whose own message is just
`TaskFailedException`. Reporting that would tell the user only that
something failed somewhere.
"""
function _unwrap_exception(err)
    current = err
    while true
        if current isa TaskFailedException
            inner = current.task.result
            inner === nothing && return current
            current = inner
        elseif current isa CapturedException
            current = current.ex
        else
            return current
        end
    end
end
