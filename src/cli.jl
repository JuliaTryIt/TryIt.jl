using Tachikoma: app

"""
Spawn the command in `ENV["TRY_EDITOR"]` with `path` appended as
its final argument. Returns `nothing` and never affects the
caller's exit code — editor failures are non-fatal (FR-039 /
OF1). Absent or empty `TRY_EDITOR` → silent no-op (matches v0.2).

Call only AFTER `println(stdout, "cd …"); flush(stdout)` so the
shell has already consumed the `cd` line.
"""
function spawn_editor(path::AbstractString)
    editor_raw = get(ENV, "TRY_EDITOR", "")
    isempty(editor_raw) && return nothing
    parts = split(editor_raw)
    isempty(parts) && return nothing
    cmd_parts = vcat(String.(parts), String(path))
    try
        run(
            pipeline(Cmd(cmd_parts); stdin=devnull, stdout=devnull, stderr=devnull);
            wait=false
        )
    catch err
        diag(:editor, _err_msg(err))
    end
    return nothing
end

"""
Dispatch `args` and return a process exit code.

Dispatch table:

| Args shape                       | Behaviour                             |
|:-------------------------------- |:------------------------------------- |
| `[]` (TTY stdin)                 | Open the selector.                    |
| `[]` (non-TTY stdin)             | Exit `64` (UN4: no TTY, no slug).     |
| `[slug]` (non-TTY stdin)         | Direct create-or-reuse + emit `cd`.   |
| `[slug]` (TTY stdin)             | Same as non-TTY direct form (legacy). |
| `["init"]` or `["init", <path>]` | Emit the shell function on stdout.    |
| anything else                    | Exit `64` (usage error).              |

EARS coverage: UB4, UB5, UB6, ED1, ED4, ED12, ED13, ED23, ED24,
ED25, ED26, ED27, UN1, UN4, UN7, UN11, UN12.
"""
function cli_main(args::AbstractVector{<:AbstractString})::Int
    # `--no-colors` is positional-agnostic in the C upstream; strip it
    # first so it is never mistaken for a slug.
    if "--no-colors" in args
        # Recorded before the recursion strips it, which is what was
        # missing: the flag used to be filtered out and discarded, so
        # it suppressed nothing (UB7).
        COLOR_DISABLED[] = true
        return cli_main(filter(!=("--no-colors"), args))
    end
    # Flags are checked before anything else. `slug` strips leading
    # punctuation, so without this `tryit --help` became a try called
    # "help": a directory created, exit 0, and no help in sight.
    if length(args) >= 1 && startswith(args[1], "-")
        if args[1] == "--"
            # Escape hatch, so a slug may begin with a dash. Dispatch
            # the remainder directly rather than recursing, which
            # would put it straight back through this check.
            rest = args[2:end]
            isempty(rest) && return _dispatch_selector_or_usage()
            length(rest) == 1 && return _dispatch_direct(rest[1])
            diag(:usage, string("unknown arguments: ", join(rest, ' ')))
            return ExitCode.USAGE
        elseif args[1] in ("-h", "--help")
            print(stdout, usage_text())
            return ExitCode.SUCCESS
        elseif args[1] in ("-V", "--version")
            println(stdout, "tryit ", ABOUT_VERSION)
            return ExitCode.SUCCESS
        end
        diag(:usage, string("unknown option: ", args[1]))
        return ExitCode.USAGE
    end
    if length(args) >= 1 && args[1] == "init"
        return _dispatch_init(args)
    end
    if length(args) >= 1 && args[1] == "path"
        length(args) == 1 || return _usage("path takes no arguments")
        println(stdout, TriesPath().root)
        return ExitCode.SUCCESS
    end
    if length(args) >= 1 && args[1] == "list"
        length(args) == 1 || return _usage("list takes no arguments")
        for t in list_tries(TriesPath())
            println(stdout, t.path)
        end
        return ExitCode.SUCCESS
    end
    # A bare URL is accepted, as in every upstream — users type it by
    # muscle memory and the keyword adds nothing. Which keyword it
    # stands for is `url_kind`'s decision (ED27); a URL that is
    # neither falls through and is treated as a slug.
    if length(args) == 1
        kind = url_kind(args[1])
        kind === :clone && return _dispatch_clone(["clone", args[1]])
        kind === :fetch && return _dispatch_fetch(["fetch", args[1]])
    end
    if length(args) >= 1 && args[1] == "clone"
        return _dispatch_clone(args)
    end
    if length(args) >= 1 && args[1] == "fetch"
        return _dispatch_fetch(args)
    end
    if length(args) >= 1 && args[1] == "extension"
        return _dispatch_extension(args)
    end
    if length(args) >= 1 && args[1] == "worktree"
        return _dispatch_worktree(args)
    end
    if isempty(args)
        return _dispatch_selector_or_usage()
    end
    if length(args) == 1
        return _dispatch_direct(args[1])
    end
    diag(:usage, string("unknown arguments: ", join(args, ' ')))
    return ExitCode.USAGE
end

function _dispatch_init(args::AbstractVector{<:AbstractString})::Int
    positional = length(args) >= 2 ? String(args[2]) : nothing
    emit_shell_init(stdout, positional)
    return ExitCode.SUCCESS
end

function _dispatch_direct(slug_arg::AbstractString)::Int
    local s::Slug
    try
        s = slug(slug_arg)
    catch err
        if err isa ArgumentError
            diag(:slug, _err_msg(err))
            return ExitCode.USAGE
        end
        rethrow()
    end
    root = TriesPath()
    t = create_try(root, s)
    println(stdout, "cd ", _shell_quote(t.path))
    flush(stdout)
    spawn_editor(t.path)
    return ExitCode.SUCCESS
end

function _dispatch_clone(args::AbstractVector{<:AbstractString})::Int
    # Shape: ["clone", url] or ["clone", url, name]
    if length(args) < 2 || length(args) > 3
        diag(:usage, "clone takes <url> [<name>]")
        return ExitCode.USAGE
    end
    if !git_available()
        diag(:git, "git not found")
        return ExitCode.NOT_FOUND
    end
    url = String(args[2])
    name_arg = length(args) == 3 ? String(args[3]) : nothing
    root = TriesPath()
    local inv::CloneInvocation
    try
        inv = CloneInvocation(url, name_arg, root)
    catch err
        if err isa ArgumentError
            diag(:clone, _err_msg(err))
            return ExitCode.USAGE
        end
        rethrow()
    end
    result = clone_into(inv)
    if result.exitcode != 0
        isempty(result.stderr) || diag(:git, result.stderr)
        return result.exitcode
    end
    # Scanned before the `cd` is emitted, so the warning is written
    # before the caller's shell acts on it. Where the two land
    # relative to each other on a terminal is not ours to promise —
    # they are separate streams (OF7).
    _report_trust(inv.dest)
    println(stdout, "cd ", _shell_quote(inv.dest))
    flush(stdout)
    spawn_editor(inv.dest)
    return ExitCode.SUCCESS
end

"""
Print the extension catalogue with a measured state per entry.

Written to stdout, which is why `extension` is one of the
subcommands the emitted shell function runs directly rather than
capturing — see UB4. That also keeps stdout attached to the
terminal, without which UB7 would strip the colour from the one
piece of output that relies on it.

Each state carries a glyph as well as a colour, so the listing still
reads through a pipe or in a log.

EARS coverage: ED28, ED29, UB7.
"""
function _print_extensions(io::IO=stdout)
    lit = color_enabled(io)
    println(io, paint("TryIt extensions", :bold; enabled=lit))
    println(io)
    width = maximum(length(e.name) for e in EXTENSIONS)
    for ext in EXTENSIONS
        state = extension_state(ext)
        color = EXTENSION_STATE_COLORS[state]
        # Padding is applied before painting: escape codes have width
        # zero on screen but not to `rpad`, which would align the
        # coloured rows differently from the plain ones.
        marker = paint(EXTENSION_STATE_MARKERS[state], color; enabled=lit)
        label = paint(rpad(String(state), 9), color; enabled=lit)
        println(io, "  ", marker, " ", rpad(ext.name, width), "  ", label, "  ",
            ext.summary)
        if state === :available
            println(io, " "^(width + 15),
                paint("install: ", :dim; enabled=lit), install_command(ext))
        elseif state === :broken
            println(io, " "^(width + 15),
                paint("installed but failed to load", :dim; enabled=lit))
        end
    end
    return nothing
end

"""
Dispatch `tryit extension [list]`.

EARS coverage: ED28, UN13.
"""
function _dispatch_extension(args::AbstractVector{<:AbstractString})::Int
    if length(args) > 2 || (length(args) == 2 && args[2] != "list")
        diag(:usage, "extension takes no argument, or `list`")
        return ExitCode.USAGE
    end
    _print_extensions(stdout)
    return ExitCode.SUCCESS
end

"""
Load the optional trust backend on first use, if it is installed.

A package extension activates when its trigger package is *loaded*,
not when it is installed — and the shell function `tryit init` emits
runs `julia -e 'using TryIt; TryIt.main(ARGS)'`, which never loads
PluginGuard. Installing it was therefore not enough: the scanner
stayed `NoScanner` and the feature was silently inert for every CLI
user, which is every user.

Loading it here rather than from the emitted shell function is what
lets an already-installed shell function pick the feature up; the
alternative would have obliged everyone to re-run `tryit init`. It
is also the moment the backend is actually needed — `tryit` opening
the selector, or creating a try from a name, never scans and never
pays for this.

This is the one place in the package that names the backend, and it
names it as a string for `identify_package`: no binding is created,
so `TryIt` and `TryIt.Core` stay free of it and
`test_core_boundary.jl` still holds.

`Base.require` is legal here — a plain runtime call, outside
`__init__` and outside precompilation. An installed-but-broken
backend is swallowed: it must not take a completed clone with it
(OF8).

EARS coverage: OF7, OF8.
"""
function _ensure_trust_backend()
    ext = find_extension("pluginguard")
    ext === nothing || activate_extension!(ext)
    return nothing
end

"""
Scan `path` and write one stderr line per `HIGH` finding, returning
how many were reported.

Only `HIGH` is surfaced. Reporting `LOW` and `MED` too would bury
the one line that matters under noise on every clone of an ordinary
repository, and a warning nobody reads is worse than none.

The count is for the caller to log, never a failure signal: the
operation has already succeeded on disk and the `cd` is emitted
regardless (OF7). A scan that found nothing, or that could not run
at all, prints nothing — a backend the user did not ask for, failing
at something advisory, has no business announcing itself on every
clone (OF8).

EARS coverage: OF7, OF8.
"""
function _report_trust(path::AbstractString)
    _ensure_trust_backend()
    report = scan_try(path)
    report.available || return 0
    count = 0
    for finding in report.findings
        finding.severity === :high || continue
        count += 1
        diag(:trust, string(
            finding.file, ":", finding.line, ": ", finding.description
        ))
    end
    count == 0 || diag(:trust,
        string(
            "advisory only — ", count, " high-severity finding",
            count == 1 ? "" : "s", "; nothing has been executed"
        ))
    return count
end

"""
Download a single resource into a new try.

Unlike `clone`, failure here is not a git exit code to propagate, so
it resolves to `ExitCode.FAILURE`. `fetch_into` never throws for an
expected failure, which keeps this dispatcher to one branch.

EARS coverage: ED26, ED27, UN11, UN12.
"""
function _dispatch_fetch(args::AbstractVector{<:AbstractString})::Int
    # Shape: ["fetch", url] or ["fetch", url, name]
    if length(args) < 2 || length(args) > 3
        diag(:usage, "fetch takes <url> [<name>]")
        return ExitCode.USAGE
    end
    url = String(args[2])
    name_arg = length(args) == 3 ? String(args[3]) : nothing
    root = TriesPath()
    local inv::FetchInvocation
    try
        inv = FetchInvocation(url, name_arg, root)
    catch err
        if err isa ArgumentError
            diag(:fetch, _err_msg(err))
            return ExitCode.USAGE
        end
        rethrow()
    end
    result = fetch_into(inv)
    if !result.ok
        diag(:fetch, result.error)
        return ExitCode.FAILURE
    end
    _report_trust(inv.dest)
    println(stdout, "cd ", _shell_quote(inv.dest))
    flush(stdout)
    spawn_editor(inv.dest)
    return ExitCode.SUCCESS
end

function _dispatch_worktree(args::AbstractVector{<:AbstractString})::Int
    # Shape: ["worktree", name]
    if length(args) != 2
        diag(:usage, "worktree takes <name>")
        return ExitCode.USAGE
    end
    if !git_available()
        diag(:git, "git not found")
        return ExitCode.NOT_FOUND
    end
    root = TriesPath()
    local inv::WorktreeInvocation
    try
        inv = WorktreeInvocation(String(args[2]), root)
    catch err
        if err isa ArgumentError
            msg = _err_msg(err)
            subsystem = occursin("not inside", msg) ? :worktree : :worktree
            diag(subsystem, msg)
            return ExitCode.USAGE
        end
        rethrow()
    end
    result = worktree_at(inv)
    if result.exitcode != 0
        isempty(result.stderr) || diag(:git, result.stderr)
        return result.exitcode
    end
    println(stdout, "cd ", _shell_quote(inv.dest))
    flush(stdout)
    spawn_editor(inv.dest)
    return ExitCode.SUCCESS
end

"""
Report a usage error and return the corresponding status.
"""
function _usage(msg::AbstractString)
    diag(:usage, msg)
    return ExitCode.USAGE
end

"""
The `--help` text.

Written by hand rather than generated: this is the whole public
surface, and it is short enough that a hand-written version stays
more readable than anything a parser would emit.
"""
function usage_text()
    return """
    tryit — ephemeral workspaces for the terminal

    usage:
      tryit                       open the selector
      tryit <name>                create or reopen a try, and cd into it
      tryit clone <url> [<name>]  git clone into a new try
      tryit fetch <url> [<name>]  download one file into a new try
      tryit worktree <name>       git worktree into a new try
      tryit <url>                 clone it if it names a repository,
                                  otherwise download it
      tryit init [<path>]         print the shell function to eval
      tryit path                  print the tries root, one line
      tryit list                  print every try's path, one per line
      tryit extension             list optional extensions and their state
      tryit -- <name>             treat <name> as a slug even if it
                                  begins with a dash

    options:
      -h, --help                  show this help
      -V, --version               show the version
          --no-colors             disable colour (also honours NO_COLOR)

    environment:
      TRY_PATH                    tries root (default \$HOME/work/tries)
      TRY_PROJECTS                graduation target (default parent of TRY_PATH)
      TRY_EDITOR                  editor spawned on a try
      TRY_TEMPLATE                directory copied into each new try
      TRY_THEME                   startup theme
      TRY_ANIMATION               background animation, or "off"
      TRY_CONFIG                  config file path

    Everything printed on stdout is meant to be eval'd by the shell
    function that `tryit init` emits; diagnostics go to stderr.
    """
end

"""
Whether `path` is still a usable `cd` target.

Guards the one-line shell contract (UB4): everything written to
stdout is `eval`ed by the caller's shell, so emitting a `cd` into a
directory that has been removed surfaces as a shell error rather than
as anything TryIt can explain.

EARS coverage: UN8.
"""
emit_cd_for(path::AbstractString) = isdir(path)

function _dispatch_selector_or_usage()::Int
    # UN6 guard BEFORE the TTY / alt-screen path: if the terminal is
    # below the 40×10 minimum, bail cleanly with a single diag.
    size_err = check_min_terminal_size(stdout)
    if size_err !== nothing
        diag(:terminal, size_err)
        return ExitCode.USAGE
    end
    if !is_terminal(stdin)
        diag(:usage, "no TTY on stdin and no positional slug")
        return ExitCode.USAGE
    end
    root = TriesPath()
    session = open_session(root)
    # SD6 — we own the keymap: Tachikoma's defaults claim Ctrl+A, Ctrl+T's
    # neighbours, and Ctrl+R, intercepting them before `update!` runs,
    # and only the recording binding has an opt-out. Matching try-rs
    # (Ctrl+T theme, Ctrl+A about, Ctrl+R rename) means taking all of
    # them and providing our own theme, about, and help overlays.
    # `fps` is configurable because the animated background costs one
    # repaint of every cell it covers per frame — see `configured_fps`.
    app(session; default_bindings=false, fps=configured_fps())
    # Tachikoma has exited by now; terminal is restored, stdout is live.
    # Run the deferred-delete confirmation BEFORE emitting any `cd` so the
    # prompt on stderr precedes the shell-evaluable output on stdout
    # (Principle I / FR-037 / ED10).
    if !isempty(session.marked_for_delete)
        if confirm_delete(length(session.marked_for_delete))
            execute_deletes!(collect(session.marked_for_delete))
        end
    end
    if session.exit_action === :cd
        # The deletes above ran *after* the selector chose its target,
        # so that target may no longer exist — marking the try under
        # the cursor and confirming is an easy way to get there. A
        # `cd` into a removed directory makes the caller's shell fail
        # on the eval, which looks like a TryIt crash.
        if !emit_cd_for(session.exit_path)
            diag(:cd, string(session.exit_path, ": no longer exists"))
            return ExitCode.SUCCESS
        end
        println(stdout, "cd ", _shell_quote(session.exit_path))
        flush(stdout)
        spawn_editor(session.exit_path)
        return ExitCode.SUCCESS
    elseif session.exit_action === :clone
        # Deferred out of the event loop on purpose: the terminal is
        # restored and stdout is live here, so `clone`/`fetch` behave
        # exactly as they do from the command line — same diagnostics,
        # same trust scan, same exit codes (ED4, ED27).
        return _dispatch_clone(["clone", session.exit_url])
    elseif session.exit_action === :fetch
        return _dispatch_fetch(["fetch", session.exit_url])
    elseif session.exit_action === :quit
        return ExitCode.SUCCESS
    elseif session.exit_action === :interrupted
        return ExitCode.SIGINT
    elseif session.exit_action === :usage_error
        diag(:slug, "empty slug")
        return ExitCode.USAGE
    else
        return ExitCode.SUCCESS
    end
end
