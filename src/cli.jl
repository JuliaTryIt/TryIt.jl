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

EARS coverage: UB4, UB5, UB6, ED1, ED4, ED12, ED13, UN1, UN4, UN7.
"""
function cli_main(args::AbstractVector{<:AbstractString})
    if length(args) >= 1 && args[1] == "init"
        return _dispatch_init(args)
    end
    if length(args) >= 1 && args[1] == "clone"
        return _dispatch_clone(args)
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
    return EXIT_USAGE
end

function _dispatch_init(args::AbstractVector{<:AbstractString})
    positional = length(args) >= 2 ? String(args[2]) : nothing
    emit_shell_init(stdout, positional)
    return EXIT_SUCCESS
end

function _dispatch_direct(slug_arg::AbstractString)
    local s::Slug
    try
        s = slug(slug_arg)
    catch err
        if err isa ArgumentError
            diag(:slug, _err_msg(err))
            return EXIT_USAGE
        end
        rethrow()
    end
    root = TriesPath()
    t = create_try(root, s)
    println(stdout, "cd ", _shell_quote(t.path))
    flush(stdout)
    spawn_editor(t.path)
    return EXIT_SUCCESS
end

function _dispatch_clone(args::AbstractVector{<:AbstractString})
    # Shape: ["clone", url] or ["clone", url, name]
    if length(args) < 2 || length(args) > 3
        diag(:usage, "clone takes <url> [<name>]")
        return EXIT_USAGE
    end
    if !git_available()
        diag(:git, "git not found")
        return EXIT_NOT_FOUND
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
            return EXIT_USAGE
        end
        rethrow()
    end
    result = clone_into(inv)
    if result.exitcode != 0
        isempty(result.stderr) || diag(:git, result.stderr)
        return result.exitcode
    end
    println(stdout, "cd ", _shell_quote(inv.dest))
    flush(stdout)
    spawn_editor(inv.dest)
    return EXIT_SUCCESS
end

function _dispatch_worktree(args::AbstractVector{<:AbstractString})
    # Shape: ["worktree", name]
    if length(args) != 2
        diag(:usage, "worktree takes <name>")
        return EXIT_USAGE
    end
    if !git_available()
        diag(:git, "git not found")
        return EXIT_NOT_FOUND
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
            return EXIT_USAGE
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
    return EXIT_SUCCESS
end

function _dispatch_selector_or_usage()
    # UN6 guard BEFORE the TTY / alt-screen path: if the terminal is
    # below the 40×10 minimum, bail cleanly with a single diag.
    size_err = check_min_terminal_size(stdout)
    if size_err !== nothing
        diag(:terminal, size_err)
        return EXIT_USAGE
    end
    if !is_terminal(stdin)
        diag(:usage, "no TTY on stdin and no positional slug")
        return EXIT_USAGE
    end
    root = TriesPath()
    session = open_session(root)
    app(session)
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
        println(stdout, "cd ", _shell_quote(session.exit_path))
        flush(stdout)
        spawn_editor(session.exit_path)
        return EXIT_SUCCESS
    elseif session.exit_action === :quit
        return EXIT_SUCCESS
    elseif session.exit_action === :interrupted
        return EXIT_SIGINT
    elseif session.exit_action === :usage_error
        diag(:slug, "empty slug")
        return EXIT_USAGE
    else
        return EXIT_SUCCESS
    end
end
