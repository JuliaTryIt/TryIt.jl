using TryIt
using Tachikoma

"""
    with_tmp_tries(f)

Run `f(path)` with `ENV["TRY_PATH"]` pointed at a fresh tempdir.
Restores the previous value (or removes the key) on exit.
"""
function with_tmp_tries(f)
    dir = mktempdir(; cleanup=false)
    prev = get(ENV, "TRY_PATH", nothing)
    ENV["TRY_PATH"] = dir
    try
        f(dir)
    finally
        prev === nothing ? delete!(ENV, "TRY_PATH") : (ENV["TRY_PATH"] = prev)
        try
            rm(dir; recursive=true, force=true)
        catch
            # best-effort cleanup
        end
    end
end

"""
    press_keys!(model, keys)

Feed a sequence of keystrokes to a Tachikoma `Model` by calling
`Tachikoma.update!(model, KeyEvent(...))` directly. This bypasses
the full Tachikoma event loop — fast, deterministic, and suitable
for `@testitem` unit tests.

`keys` is a string; each character is translated into a `KeyEvent`
according to the rules below:

| Input char    | KeyEvent                           |
|:------------- |:---------------------------------- |
| `\\r` / `\\n` | `KeyEvent(:enter, '\\0', ...)`     |
| `\\e`         | `KeyEvent(:escape, '\\0', ...)`    |
| `\\x7f`       | `KeyEvent(:backspace, '\\0', ...)` |
| `\\x03`       | `KeyEvent(:ctrl_c, 'c', ...)`      |
| `\\x1b[A`     | `KeyEvent(:up, '\\0', ...)`        |
| `\\x1b[B`     | `KeyEvent(:down, '\\0', ...)`      |
| anything else | `KeyEvent(:char, c, ...)`          |

(Escape sequences `\\x1b[A` / `\\x1b[B` are recognised as a unit by
the translator.)
"""
function press_keys!(model, keys::AbstractString)
    i = 1
    while i <= lastindex(keys)
        c = keys[i]
        if c == '\r' || c == '\n'
            _press!(model, :enter, '\0')
            i = nextind(keys, i)
        elseif c == '\x03'
            _press!(model, :ctrl_c, 'c')
            i = nextind(keys, i)
        elseif c == '\x04'
            # Ctrl-D — v0.3 mark-for-delete binding.
            _press!(model, :ctrl, 'd')
            i = nextind(keys, i)
        elseif c == '\x07'
            # Ctrl-G — v0.3 graduate binding.
            _press!(model, :ctrl, 'g')
            i = nextind(keys, i)
        elseif c == '\x12'
            # Ctrl-R — v0.3 rename binding.
            _press!(model, :ctrl, 'r')
            i = nextind(keys, i)
        elseif c == '\x14'
            # Ctrl-T — theme picker (was placeholder-create until the
            # keymap moved to match try-rs).
            _press!(model, :ctrl, 't')
            i = nextind(keys, i)
        elseif c == '\x0e'
            # Ctrl-N — placeholder-create binding.
            _press!(model, :ctrl, 'n')
            i = nextind(keys, i)
        elseif c == '\x01'
            # Ctrl-A — About overlay.
            _press!(model, :ctrl, 'a')
            i = nextind(keys, i)
        elseif c == '\x15'
            # Synthetic Page-Up (test-internal shortcut).
            _press!(model, :page_up, '\0')
            i = nextind(keys, i)
        elseif c == '\x16'
            # Synthetic Page-Down (test-internal shortcut).
            _press!(model, :page_down, '\0')
            i = nextind(keys, i)
        elseif c == '\x7f' || c == '\b'
            _press!(model, :backspace, '\0')
            i = nextind(keys, i)
        elseif c == '\e'
            # Peek for "[A" / "[B".
            if i + 2 <= lastindex(keys) && keys[i + 1] == '[' &&
               (keys[i + 2] == 'A' || keys[i + 2] == 'B')
                sym = keys[i + 2] == 'A' ? :up : :down
                _press!(model, sym, '\0')
                i = nextind(keys, i, 3)
            else
                _press!(model, :escape, '\0')
                i = nextind(keys, i)
            end
        else
            _press!(model, :char, c)
            i = nextind(keys, i)
        end
    end
    return model
end

function _press!(model, key::Symbol, ch::Char)
    evt = _key_event(key, ch)
    Tachikoma.update!(model, evt)
    return nothing
end

# Tachikoma's KeyEvent takes (key::Symbol, char::Char[, action]).
# We use a narrow helper so tests do not depend on Tachikoma's
# internal default-action values.
function _key_event(key::Symbol, ch::Char)
    return Tachikoma.KeyEvent(key, ch)
end

"""
    run_cli_subprocess(args...; stdin = devnull, env_overrides = Dict())

Spawn a fresh `julia --project -e 'using TryIt; TryIt.main(ARGS)'`
subprocess with `args`. Returns `(exit_code, stdout::String, stderr::String)`.

By default `stdin` is `devnull` (non-TTY) — useful for exercising
the FR-015 / UN4 direct form. Pass a `Base.TTY` / PTY master end to
exercise the TTY branch.
"""
function run_cli_subprocess(args::AbstractString...; stdin=devnull,
        env_overrides=Dict{String, String}())
    project = abspath(joinpath(@__DIR__, ".."))
    cmd = `$(Base.julia_cmd()) --startup-file=no --project=$project -e "using TryIt; TryIt.main(ARGS)" -- $(collect(args))`
    out = IOBuffer()
    err = IOBuffer()
    # Compose the environment: start from the current ENV and apply overrides.
    merged = Dict{String, String}()
    for (k, v) in ENV
        merged[k] = v
    end
    for (k, v) in env_overrides
        merged[k] = v
    end
    proc = run(
        pipeline(setenv(cmd, merged); stdin=stdin, stdout=out, stderr=err);
        wait=false
    )
    wait(proc)
    return (proc.exitcode, String(take!(out)), String(take!(err)))
end

"""
    with_git_stub(f; clone_exit = 0, worktree_exit = 0, rev_parse_stdout = "/tmp/stub-repo")

Install a shell-script `git` stub at a tempdir, prepend it to
`PATH` for the duration of `f(stub_dir)`, and restore afterwards.

The stub recognises `clone`, `worktree`, and `rev-parse`
subcommands. `clone` and `worktree` create the destination
directory passed to them and exit with the configured code
(default `0`). `rev-parse --show-toplevel` prints
`rev_parse_stdout` and exits `0`.

Pass a *negative* clone_exit to skip creating the destination
(simulates git-rejected clone where no residue is left).

See [`specs/002-git-integration-bulk-selector/contracts/git-subprocess.md`](../specs/002-git-integration-bulk-selector/contracts/git-subprocess.md).
"""
function with_git_stub(
        f;
        clone_exit::Int=0,
        worktree_exit::Int=0,
        rev_parse_stdout::AbstractString="/tmp/stub-repo"
)
    stub_dir = mktempdir(; cleanup=false)
    is_windows = Sys.iswindows()
    script_name = is_windows ? "git.cmd" : "git"
    script_path = joinpath(stub_dir, script_name)
    _write_git_stub(
        script_path, is_windows;
        clone_exit=clone_exit,
        worktree_exit=worktree_exit,
        rev_parse_stdout=rev_parse_stdout
    )
    prev_path = get(ENV, "PATH", "")
    sep = is_windows ? ";" : ":"
    ENV["PATH"] = string(stub_dir, sep, prev_path)
    try
        f(stub_dir)
    finally
        ENV["PATH"] = prev_path
        try
            rm(stub_dir; recursive=true, force=true)
        catch
            # best-effort
        end
    end
end

function _write_git_stub(
        path::AbstractString, is_windows::Bool;
        clone_exit::Int, worktree_exit::Int,
        rev_parse_stdout::AbstractString
)
    if is_windows
        # .cmd stub. Windows argv indexing is 1-based for %1.
        script = """
        @echo off
        if "%1"=="clone" goto clone
        if "%1"=="worktree" goto worktree
        if "%1"=="rev-parse" goto revparse
        exit /b 1
        :clone
        rem argv: clone -- <url> <dest>   → dest = %4
        """ * ((clone_exit >= 0) ? "mkdir \"%~4\" 2>nul\n" : "") * """
        exit /b $(abs(clone_exit))
        :worktree
        rem argv: worktree add -- <dest> HEAD  → dest = %4
        mkdir "%~4" 2>nul
        mkdir "%~4\\.git" 2>nul
        exit /b $worktree_exit
        :revparse
        echo $rev_parse_stdout
        exit /b 0
        """
        write(path, script)
    else
        script = """
        #!/bin/sh
        case "\$1" in
          clone)
            # argv: clone -- <url> <dest>  → dest = \$4
        """ * ((clone_exit >= 0) ? "    mkdir -p \"\$4\"\n" : "") * """
            exit $(abs(clone_exit))
            ;;
          worktree)
            # argv: worktree add -- <dest> HEAD  → dest = \$4
            mkdir -p "\$4"
            mkdir -p "\$4/.git"
            exit $worktree_exit
            ;;
          rev-parse)
            echo "$rev_parse_stdout"
            exit 0
            ;;
        esac
        exit 1
        """
        write(path, script)
        chmod(path, 0o755)
    end
    return nothing
end

"""
    with_real_git_repo(f; files = ["README.md"])

Materialise a real git repository in a tempdir (via `git init`

  - one commit), yield the repository path to `f`, and clean up
    afterwards. Skipped via `@test_skip` when `git` is not on PATH.
"""
function with_real_git_repo(f; files=["README.md"])
    Sys.which("git") === nothing && return nothing
    dir = mktempdir(; cleanup=false)
    try
        _run_or_fail(`git -C $dir init --quiet`)
        # Silence local identity so the commit succeeds regardless of
        # the test runner's global git config.
        _run_or_fail(`git -C $dir config user.email "test@example.com"`)
        _run_or_fail(`git -C $dir config user.name  "Test"`)
        _run_or_fail(`git -C $dir config commit.gpgsign false`)
        for fname in files
            write(joinpath(dir, fname), "fixture\n")
        end
        _run_or_fail(`git -C $dir add .`)
        _run_or_fail(`git -C $dir commit --quiet -m "fixture"`)
        f(dir)
    finally
        try
            rm(dir; recursive=true, force=true)
        catch
            # best-effort
        end
    end
end

function _run_or_fail(cmd)
    proc = run(
        pipeline(cmd; stdin=devnull, stdout=devnull, stderr=devnull);
        wait=true
    )
    proc.exitcode == 0 || error("fixture-helper command failed: $(cmd)")
    return nothing
end

"""
    render_selector(model, width, height) -> Vector{String}

Render `model` into an offscreen `width`×`height` buffer and return
the resulting text grid, one string per row.

Lets the view be asserted on without a TTY. Styles are dropped —
these tests check layout and content, not colour.
"""
function render_selector(model, width::Int, height::Int)
    rect = Tachikoma.Rect(1, 1, width, height)
    buf = Tachikoma.Buffer(rect)
    frame = Tachikoma.Frame(
        buf, rect, Tachikoma.GraphicsRegion[], Tachikoma.PixelSnapshot[]
    )
    Tachikoma.view(model, frame)
    return [String([Tachikoma.in_bounds(buf, x, y) ?
                    buf.content[Tachikoma.buf_index(buf, x, y)].char : ' '
                    for x in 1:width])
            for y in 1:height]
end

"""
    run_quiet(cmd)

Run `cmd` with stdout and stderr discarded, erroring if it fails.

Fixture setup only — git's progress chatter would otherwise smear the
test output.
"""
function run_quiet(cmd::Cmd)
    run(pipeline(cmd; stdout=devnull, stderr=devnull))
    return nothing
end
