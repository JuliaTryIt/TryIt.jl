"""
Mutable Tachikoma model backing the try selector.

Holds every piece of state the event loop needs. Output (the `cd`
command) is NOT written from within `update!` — Tachikoma captures
stdout while the app is running, so we record the decision on this
model and let `cli_main` emit the shell command after `app(model)`
returns.

EARS coverage: ED1, ED2, ED3, ED4, ED12, SD1, UN7.
"""
@kwdef mutable struct SelectorSession <: Tachikoma.Model
    "Resolved tries root."
    root::TriesPath
    "Snapshot of every try at selector-open time, mtime-desc."
    all_tries::Vector{Try} = Try[]
    "Current filter string; empty matches everything."
    filter::String = ""
    "1-based cursor into `visible`. `0` when `visible` is empty."
    cursor::Int = 0
    "Filter-applied projection of `all_tries`."
    visible::Vector{Try} = Try[]
    "Decision taken when the event loop exits: `:none`, `:cd`, `:quit`, `:interrupted`."
    exit_action::Symbol = :none
    "Absolute path to emit with `cd` when `exit_action == :cd`."
    exit_path::String = ""
    "Set to `true` to terminate the Tachikoma event loop."
    done::Bool = false
    "Index into `visible` of the top-most rendered row (SD3). `0` when `visible` is empty."
    viewport_top::Int = 0
    "Current terminal dimensions `(rows, cols)`; refreshed on every redraw."
    terminal_size::Tuple{Int, Int} = (24, 80)
    "Sub-mode: `:normal` (default), `:rename` (Ctrl-R), or `:choose`
     (open-or-create prompt). SD2-masked in `:rename`."
    mode::Symbol = :normal
    "Highlighted action while in `:choose`: `:open` or `:create`."
    choice::Symbol = :open
    "Transient message shown in the help bar. Tachikoma redirects
     stderr for the whole TUI session, so `diag` output from inside
     `update!` is invisible — failures have to be surfaced in-frame."
    notice::String = ""
    "Cursor into [`BACKGROUND_NAMES`](@ref) while in `:animation`."
    anim_index::Int = 1
    "Animation active when the picker opened, restored if cancelled."
    anim_before::String = "fog"
    "Cursor into [`DOC_PAGES`](@ref) while in `:docs`."
    doc_index::Int = 1
    "Scroll offset within the current docs page."
    doc_offset::Int = 0
    "Cursor into `Tachikoma.ALL_THEMES` while in `:theme`."
    theme_index::Int = 1
    "Theme active when the picker opened, restored if it is cancelled."
    theme_before::String = ""
    "Input line contents while in `:rename`. Empty otherwise."
    rename_buf::String = ""
    "Absolute paths flagged for delete on selector exit (ED9 / ED10)."
    marked_for_delete::Set{String} = Set{String}()
    "Badge cache keyed by try path. Populated lazily; `detect_badges`
     touches the filesystem and the view runs every frame."
    badge_cache::Dict{String, Vector{Symbol}} = Dict{String, Vector{Symbol}}()
    "Path the `preview` field currently describes. Empty when none."
    preview_path::String = ""
    "Directory listing of the selected try, for the preview panel."
    preview::Vector{PreviewEntry} = PreviewEntry[]
    "Filesystem stats for the tries root. `nothing` when unavailable."
    disk::Union{Nothing, DiskStats} = nothing
    "Terminal handed over by Tachikoma in `init!`. `nothing` in unit
     tests, which drive `update!` without running the event loop.
     Needed because the `.tach` recorder hangs off the terminal, not
     the model."
    terminal::Union{Nothing, Tachikoma.Terminal} = nothing
    "Animated background, or `nothing` when opted out. Resolved once
     at open — see [`background_from_env`](@ref)."
    background::Union{Nothing, SelectorBackground} = nothing
    "Frame counter driving the background animation. Tachikoma has no
     tick event; `view` runs every frame and advances this itself."
    tick::Int = 0
end

# Tachikoma's event loop claims Ctrl+R for `.tach` recording and
# intercepts it before `update!` ever runs. The selector needs Ctrl-R
# for rename — matching try-cli and try-rs — so the framework binding
# is switched off and recording is re-offered on F9 below.
#
# F9 rather than Ctrl+Shift+R: `KeyEvent` carries no modifier fields,
# and a legacy terminal sends the same 0x12 byte for Ctrl+R and
# Ctrl+Shift+R, so the two are not distinguishable. Function keys
# parse in both legacy and Kitty terminals.
Tachikoma.recording_enabled(::SelectorSession) = false

"""
Capture the terminal so [`toggle_recording!`](@ref) can reach its
`.tach` recorder.
"""
function Tachikoma.init!(m::SelectorSession, t::Tachikoma.Terminal)
    m.terminal = t
    return nothing
end

"""
Whether a `.tach` recording is currently in progress.

`false` when no terminal is attached, which is the case in unit tests
that never enter the event loop.
"""
function recording_active(m::SelectorSession)
    m.terminal === nothing && return false
    return m.terminal.recorder.active
end

"""
Start or stop `.tach` recording (F9).

A no-op without an attached terminal. Uses only Tachikoma's exported
recorder API — the framework's own countdown notification and export
modal live in private app-loop state and are deliberately not
reproduced; `start_recording!` still applies its 5-second countdown.

EARS coverage: ED18.
"""
function toggle_recording!(m::SelectorSession)
    t = m.terminal
    t === nothing && return nothing
    rec = t.recorder
    if rec.active
        finish_recording!(rec)
    else
        Tachikoma.start_recording!(
            rec, t.size.width, t.size.height;
            filename=recording_path(m.root.root)
        )
    end
    return nothing
end

"""
Destination for a new `.tach` recording.

Written under the tries root rather than the process's working
directory: `tryit` is invoked from wherever the user happens to be,
and Tachikoma's default would scatter recordings across the
filesystem. The tries root is a known location that is already
guaranteed to exist and be writable.
"""
function recording_path(root::AbstractString)
    ts = Dates.format(Dates.now(), "yyyy-mm-dd_HHMMSS")
    return joinpath(root, "tryit_$(ts).tach")
end

"""
Stop `rec` and write its `.tach` file, if it is running.

Returns the filename written, or `""` when nothing was recording.

Split from [`toggle_recording!`](@ref) because it is also the exit
path: `stop_recording!` is what performs the write, so a recording
left running when the selector closes would otherwise be discarded.
"""
function finish_recording!(rec::Tachikoma.CastRecorder)
    rec.active || return ""
    name = Tachikoma.stop_recording!(rec)
    Tachikoma.clear_recording!(rec)
    return name
end

"""
Flush a still-running recording when the event loop exits.

Covers every way out of the selector — selecting a try, quitting with
Esc, or aborting with Ctrl-C — none of which pass through
[`toggle_recording!`](@ref). Tachikoma calls this after the terminal
has been fully restored.
"""
function Tachikoma.cleanup!(m::SelectorSession)
    t = m.terminal
    t === nothing && return nothing
    finish_recording!(t.recorder)
    return nothing
end

"""
Refresh the side-panel caches to match the current cursor.

Called at the top of every frame, but does real work only when the
selection actually moved: `preview_entries` and `detect_badges` hit
the filesystem, and re-running them at the frame rate would stall the
render on a large try.
"""
function refresh_panels!(m::SelectorSession)
    # Disk stats are resolved once per session — the tries root does
    # not change while the selector is open.
    m.disk === nothing && (m.disk = disk_usage(m.root.root))

    selected = (m.cursor >= 1 && m.cursor <= length(m.visible)) ?
               m.visible[m.cursor].path : ""
    if selected != m.preview_path
        m.preview_path = selected
        m.preview = isempty(selected) ? PreviewEntry[] : preview_entries(selected)
    end
    return nothing
end

"""
Docs-browser reducer.

Unlike the `?` overlay this is not dismissed by any key — the pages
are long, so most keys have to mean "scroll".

EARS coverage: ED20.
"""
function _update_docs!(m::SelectorSession, evt::Tachikoma.KeyEvent)
    key = evt.key
    n = length(DOC_PAGES)
    if key === :escape || key === :f1
        m.mode = :normal
    elseif key === :tab || key === :right
        m.doc_index = mod1(m.doc_index + 1, n)
        m.doc_offset = 0
    elseif key === :backtab || key === :left
        m.doc_index = mod1(m.doc_index - 1, n)
        m.doc_offset = 0
    elseif key === :down
        m.doc_offset += 1
    elseif key === :up
        m.doc_offset = max(0, m.doc_offset - 1)
    elseif key === :pagedown || key === :page_down
        m.doc_offset += 10
    elseif key === :pageup || key === :page_up
        m.doc_offset = max(0, m.doc_offset - 10)
    elseif key === :home
        m.doc_offset = 0
    end
    return nothing
end

"""
Adopt the highlighted undated directory into the dated scheme
(Ctrl-P), keeping the selector open.

The date used is the one already on screen, inferred from the
filesystem mtime, so the row does not jump to today.

EARS coverage: ED19.
"""
function _handle_ctrl_p!(m::SelectorSession)
    (isempty(m.visible) || m.cursor < 1 || m.cursor > length(m.visible)) &&
        return nothing
    src = m.visible[m.cursor]
    local inv::DateInvocation
    try
        inv = DateInvocation(src)
    catch err
        if err isa ArgumentError
            notify!(m, _err_msg(err))
            return nothing
        end
        rethrow()
    end
    local dest::String
    try
        dest = date_try(inv)
    catch err
        notify!(m, _err_msg(err))
        return nothing
    end
    # Re-snapshot so the row shows its new, dated form.
    m.all_tries = list_tries(m.root)
    refresh_visible!(m)
    idx = findfirst(t -> t.path == dest, m.visible)
    idx === nothing || (m.cursor = idx)
    _scroll_after_cursor_move!(m)
    return nothing
end

"""
Open the theme picker (Ctrl-T), remembering the current theme.

EARS coverage: ED15.
"""
function _open_theme_picker!(m::SelectorSession)
    current = Tachikoma.theme().name
    m.theme_before = current
    idx = findfirst(==(current), theme_names())
    m.theme_index = idx === nothing ? 1 : idx
    m.mode = :theme
    return nothing
end

"""
Open the animation picker (Ctrl-B), remembering the current choice.

EARS coverage: ED21.
"""
function _open_animation_picker!(m::SelectorSession)
    current = animation_name(m.background)
    m.anim_before = current
    idx = findfirst(==(current), BACKGROUND_NAMES)
    m.anim_index = idx === nothing ? 1 : idx
    m.mode = :animation
    return nothing
end

"""
Animation-picker reducer.

Mirrors the theme picker: moving applies immediately, since an
animation can only be judged by watching it, so `Esc` has to restore
whatever was playing when the picker opened.
"""
function _update_animation!(m::SelectorSession, evt::Tachikoma.KeyEvent)
    key = evt.key
    if key === :enter
        m.mode = :normal
    elseif key === :escape
        m.background = resolve_background(m.anim_before)
        m.mode = :normal
    elseif key === :up
        m.anim_index = max(1, m.anim_index - 1)
        m.background = resolve_background(BACKGROUND_NAMES[m.anim_index])
    elseif key === :down
        m.anim_index = min(length(BACKGROUND_NAMES), m.anim_index + 1)
        m.background = resolve_background(BACKGROUND_NAMES[m.anim_index])
    end
    return nothing
end

"""
Theme-picker reducer.

Moving the cursor applies the theme immediately: the only way to
judge one is to see it. `Esc` therefore has to restore whatever was
active when the picker opened, or previewing would be a one-way door.
"""
function _update_theme!(m::SelectorSession, evt::Tachikoma.KeyEvent)
    names = theme_names()
    key = evt.key
    if key === :enter
        m.mode = :normal
    elseif key === :escape
        apply_theme!(m.theme_before)
        m.mode = :normal
    elseif key === :up
        m.theme_index = max(1, m.theme_index - 1)
        apply_theme!(names[m.theme_index])
    elseif key === :down
        m.theme_index = min(length(names), m.theme_index + 1)
        apply_theme!(names[m.theme_index])
    end
    return nothing
end

"""
Show `msg` in the help bar until the next keystroke.

Replaces [`diag`](@ref) for failures raised from inside `update!`.
Tachikoma redirects stderr for the whole TUI session (its `app.jl`
does this so stray `println` cannot corrupt the display), so a
`diag` call from a key handler goes nowhere and the key looks dead —
which is exactly how a failing `Ctrl-G` presented.
"""
function notify!(m::SelectorSession, msg::AbstractString)
    m.notice = String(msg)
    return nothing
end

"""
Badges for `t`, memoised in the session's [`badge_cache`](@ref).
"""
function badges_for(m::SelectorSession, t::Try)
    return get!(m.badge_cache, t.path) do
        detect_badges(t.path)
    end
end

"""
Seed the visible list from `all_tries` so first-frame render shows
the full list.
"""
function refresh_visible!(m::SelectorSession)
    m.visible = filter_tries(m.all_tries, m.filter)
    if isempty(m.visible)
        m.cursor = 0
        m.viewport_top = 0
    else
        m.cursor = clamp(m.cursor, 1, length(m.visible))
        m.cursor == 0 && (m.cursor = 1)
        # Anchor the viewport to the top whenever the visible list is
        # freshly computed — the user will scroll again if needed.
        m.viewport_top = 1
    end
    return nothing
end

"""
Construct a `SelectorSession` for `root`, taking an mtime-desc
snapshot of existing tries.

EARS coverage: ED1.
"""
function open_session(root::TriesPath)
    m = SelectorSession(root=root)
    m.all_tries = list_tries(root)
    # Config is read once here rather than per frame: `apply_theme!`
    # mutates a Tachikoma global, and re-reading ENV every frame would
    # fight the in-app theme picker (Ctrl-\), which is allowed to win
    # for the rest of the session.
    apply_theme_from_env!()
    m.background = background_from_env()
    refresh_visible!(m)
    return m
end

# Tachikoma polls should_quit(model) each frame.
Tachikoma.should_quit(m::SelectorSession) = m.done

"""
Event reducer.

Branches on `m.mode` at the top so rename mode's SD2 masking
(FR-038) is a single, obvious if-else with no subtle fall-through.

EARS coverage: ED2, ED3, ED4, ED7, ED8, ED9, ED12, SD2, UN7.
"""
function Tachikoma.update!(m::SelectorSession, evt::Tachikoma.KeyEvent)
    key = evt.key
    # Ctrl-C aborts from ANY mode (selector-keybindings §Edge cases).
    if key === :ctrl_c
        m.exit_action = :interrupted
        m.done = true
        return nothing
    end
    if m.mode === :rename
        _update_rename!(m, evt)
        return nothing
    end
    if m.mode === :choose
        _update_choose!(m, evt)
        return nothing
    end
    if m.mode === :theme
        _update_theme!(m, evt)
        return nothing
    end
    if m.mode === :animation
        _update_animation!(m, evt)
        return nothing
    end
    if m.mode === :docs
        _update_docs!(m, evt)
        return nothing
    end
    if m.mode === :help || m.mode === :about
        # Any key dismisses; these are reference material, not
        # prompts, so trapping the user behind one specific key would
        # only be a hazard.
        m.mode = :normal
        return nothing
    end
    # A notice describes the previous keystroke, so the next one
    # retires it rather than letting a stale error linger.
    isempty(m.notice) || (m.notice = "")
    # :normal mode below.
    if key === :enter
        _handle_enter!(m)
    elseif key === :escape
        m.exit_action = :quit
        m.done = true
    elseif key === :backspace
        if !isempty(m.filter)
            m.filter = SubString(m.filter, 1, prevind(m.filter, lastindex(m.filter)))
            refresh_visible!(m)
        end
    elseif key === :up
        if m.cursor > 1
            m.cursor -= 1
        end
        _scroll_after_cursor_move!(m)
    elseif key === :down
        if m.cursor < length(m.visible)
            m.cursor += 1
        end
        _scroll_after_cursor_move!(m)
    elseif key === :page_up
        vr = _visible_rows(m)
        m.cursor = clamp(m.cursor - vr, 1, max(1, length(m.visible)))
        _scroll_after_cursor_move!(m)
    elseif key === :page_down
        vr = _visible_rows(m)
        m.cursor = clamp(m.cursor + vr, 1, max(1, length(m.visible)))
        _scroll_after_cursor_move!(m)
    elseif key === :ctrl && evt.char == 'n'
        _handle_ctrl_n!(m)
    elseif key === :ctrl && evt.char == 't'
        _open_theme_picker!(m)
    elseif key === :ctrl && evt.char == 'a'
        m.mode = :about
    elseif key === :ctrl && evt.char == 'p'
        _handle_ctrl_p!(m)
    elseif key === :f1
        m.mode = :docs
        m.doc_offset = 0
    elseif key === :ctrl && evt.char == 'b'
        _open_animation_picker!(m)
    elseif key === :ctrl && evt.char == 'w'
        # ED22 — persist theme and animation, reporting where.
        notify!(m, save_settings(animation_name(m.background)))
    elseif key === :ctrl && evt.char == 'r'
        _handle_ctrl_r!(m)
    elseif key === :ctrl && evt.char == 'g'
        _handle_ctrl_g!(m)
    elseif key === :ctrl && evt.char == 'd'
        _handle_ctrl_d!(m)
    elseif key === :f9
        toggle_recording!(m)
    elseif key === :char && evt.char == '?' && isempty(m.filter)
        # Only while the filter is empty. Undated directories are
        # listed under their real names now, so a folder called
        # `what?` is both possible and filterable — taking '?'
        # unconditionally would make it unreachable.
        m.mode = :help
    elseif key === :char && isprint(evt.char) && evt.char != '\0'
        m.filter *= evt.char
        refresh_visible!(m)
        _scroll_after_cursor_move!(m)
    end
    return nothing
end

"""
Open-or-create reducer.

Only the keys that move between the two actions, commit, or back out
are honoured — every other key is swallowed so a stray keystroke
cannot both dismiss the prompt and act on the selector underneath.
"""
function _update_choose!(m::SelectorSession, evt::Tachikoma.KeyEvent)
    key = evt.key
    if key === :enter
        _commit_choice!(m)
    elseif key === :escape
        # Back to editing with the typed text intact — the user may
        # have meant to keep narrowing the filter.
        m.mode = :normal
    elseif key === :up || key === :left
        m.choice = :open
    elseif key === :down || key === :right
        m.choice = :create
    elseif key === :tab
        m.choice = m.choice === :open ? :create : :open
    end
    return nothing
end

"""
Rename-mode reducer. SD2: only Enter / Esc / Backspace /
printable chars are honoured.

EARS coverage: ED7, SD2 / FR-034, FR-038.
"""
function _update_rename!(m::SelectorSession, evt::Tachikoma.KeyEvent)
    key = evt.key
    if key === :enter
        _commit_rename!(m)
    elseif key === :escape
        m.rename_buf = ""
        m.mode = :normal
    elseif key === :backspace
        if !isempty(m.rename_buf)
            m.rename_buf = SubString(
                m.rename_buf, 1, prevind(m.rename_buf, lastindex(m.rename_buf))
            )
        end
    elseif key === :char && isprint(evt.char) && evt.char != '\0'
        m.rename_buf *= evt.char
    end
    # Every other key is a no-op while in :rename (SD2).
    return nothing
end

function _commit_rename!(m::SelectorSession)
    # Must have a valid cursor row to commit against.
    (isempty(m.visible) || m.cursor < 1 || m.cursor > length(m.visible)) &&
        return nothing
    src = m.visible[m.cursor]
    local new_slug::Slug
    try
        new_slug = slug(m.rename_buf)
    catch err
        if err isa ArgumentError
            notify!(m, _err_msg(err))
            return nothing      # stay in :rename so the user can retry
        end
        rethrow()
    end
    # Short-circuit: renaming to the same slug is a no-op.
    if new_slug == src.slug
        m.rename_buf = ""
        m.mode = :normal
        return nothing
    end
    local inv::RenameInvocation
    try
        inv = RenameInvocation(src, new_slug)
    catch err
        if err isa ArgumentError
            notify!(m, _err_msg(err))
            return nothing      # stay in :rename
        end
        rethrow()
    end
    try
        rename_try(inv)
    catch err
        notify!(m, _err_msg(err))
        return nothing
    end
    # Refresh the snapshot so the renamed row is reachable.
    m.all_tries = list_tries(m.root)
    refresh_visible!(m)
    idx = findfirst(t -> t.path == inv.dest_path, m.visible)
    if idx !== nothing
        m.cursor = idx
        _scroll_after_cursor_move!(m)
    end
    m.rename_buf = ""
    m.mode = :normal
    return nothing
end

function _handle_ctrl_r!(m::SelectorSession)
    (isempty(m.visible) || m.cursor < 1 || m.cursor > length(m.visible)) &&
        return nothing
    m.mode = :rename
    m.rename_buf = m.visible[m.cursor].slug.value
    return nothing
end

"""
Graduate handler: build and execute a [`GraduateInvocation`](@ref)
for the highlighted try, signal `:cd` exit with the new path.

EARS coverage: ED8 / FR-035.
"""
function _handle_ctrl_g!(m::SelectorSession)
    (isempty(m.visible) || m.cursor < 1 || m.cursor > length(m.visible)) &&
        return nothing
    src = m.visible[m.cursor]
    local inv::GraduateInvocation
    try
        inv = GraduateInvocation(src, m.root)
    catch err
        if err isa ArgumentError
            notify!(m, _err_msg(err))
            return nothing
        end
        rethrow()
    end
    local dest::String
    try
        dest = graduate_try(inv)
    catch err
        notify!(m, _err_msg(err))
        return nothing
    end
    m.exit_action = :cd
    m.exit_path = dest
    m.done = true
    return nothing
end

"""
Ctrl-D handler: toggle the highlighted row's path in
`marked_for_delete`. No deletion yet — that happens on selector
exit via [`confirm_delete`](@ref).

EARS coverage: ED9 / FR-036.
"""
function _handle_ctrl_d!(m::SelectorSession)
    (isempty(m.visible) || m.cursor < 1 || m.cursor > length(m.visible)) &&
        return nothing
    path = m.visible[m.cursor].path
    if path in m.marked_for_delete
        delete!(m.marked_for_delete, path)
    else
        push!(m.marked_for_delete, path)
    end
    return nothing
end

"""
Visible-row count derived from the terminal height.

The selector reserves four rows for chrome (header, filter line,
blank separator, footer). A minimum of `1` is enforced so
degenerate terminals do not produce zero-sized slices.

EARS coverage: SD3.
"""
function _visible_rows(m::SelectorSession)
    rows = m.terminal_size[1]
    return max(1, rows - 4)
end

"""
Keep the cursor inside the visible viewport after a cursor move.

Adjusts `m.viewport_top` so that
`viewport_top <= cursor <= viewport_top + VR - 1` holds, clamped
to `[1, max(1, length(visible) - VR + 1)]`.

EARS coverage: SD3 / FR-027.
"""
function _scroll_after_cursor_move!(m::SelectorSession)
    if isempty(m.visible)
        m.viewport_top = 0
        return nothing
    end
    vr = _visible_rows(m)
    m.viewport_top < 1 && (m.viewport_top = 1)
    if m.cursor < m.viewport_top
        m.viewport_top = m.cursor
    elseif m.cursor > m.viewport_top + vr - 1
        m.viewport_top = m.cursor - vr + 1
    end
    max_top = max(1, length(m.visible) - vr + 1)
    m.viewport_top = clamp(m.viewport_top, 1, max_top)
    return nothing
end

"""
Ctrl-T handler: create a dated placeholder try and highlight it.

Does NOT set `m.done` — the selector stays open (FR-026).

EARS coverage: ED11 / FR-026.
"""
function _handle_ctrl_n!(m::SelectorSession)
    s = placeholder_slug_for_today(m.root)
    new_try = create_try(m.root, s)
    # Re-snapshot so the selector's list of tries includes the new one.
    m.all_tries = list_tries(m.root)
    refresh_visible!(m)
    # Position the cursor on the new try if it's visible under the
    # current filter; otherwise leave the cursor where it was.
    idx = findfirst(t -> t.path == new_try.path, m.visible)
    if idx !== nothing
        m.cursor = idx
        _scroll_after_cursor_move!(m)
    end
    return nothing
end

"""
The filter text normalised to a slug, or `nothing` when it is empty
or cannot form one (pure punctuation).
"""
function _filter_slug(m::SelectorSession)
    raw = strip(m.filter)
    isempty(raw) && return nothing
    return try
        slug(raw).value
    catch err
        err isa ArgumentError ? nothing : rethrow()
    end
end

"""
Whether pressing Enter is ambiguous between opening the highlighted
try and creating a new one from the filter text.

`filter_tries` matches substrings of `"<date> <slug>"`, so typing the
beginning of an existing name — or any digits of the date prefix —
selects that try and leaves no way to create the shorter name. The
prompt only appears when the typed text is genuinely ambiguous: if it
is already the highlighted try's exact slug, Enter opens it directly.

EARS coverage: ED3, ED14.
"""
function needs_choice(m::SelectorSession)
    (m.cursor >= 1 && m.cursor <= length(m.visible)) || return false
    typed = _filter_slug(m)
    typed === nothing && return false
    return typed != m.visible[m.cursor].slug.value
end

"""
Commit the highlighted choice from the open-or-create prompt.
"""
function _commit_choice!(m::SelectorSession)
    m.mode = :normal
    if m.choice === :open
        m.exit_action = :cd
        m.exit_path = m.visible[m.cursor].path
        m.done = true
        return nothing
    end
    return _create_from_filter!(m)
end

function _handle_enter!(m::SelectorSession)
    if !isempty(m.visible) && m.cursor >= 1 && m.cursor <= length(m.visible)
        if needs_choice(m)
            m.mode = :choose
            m.choice = :open
            return nothing
        end
        m.exit_action = :cd
        m.exit_path = m.visible[m.cursor].path
        m.done = true
        return nothing
    end
    # No match → create today's try from the filter string (ED4).
    return _create_from_filter!(m)
end

"""
Create today's try from the filter text and select it.

Shared by the no-match path and the `:create` branch of the
open-or-create prompt, so both produce an identical try.

EARS coverage: ED4.
"""
function _create_from_filter!(m::SelectorSession)
    raw = strip(m.filter)
    if isempty(raw)
        # Nothing typed: pressing Enter on an empty filter is a no-op.
        return nothing
    end
    try
        s = slug(raw)
        new_try = create_try(m.root, s)
        m.exit_action = :cd
        m.exit_path = new_try.path
        m.done = true
    catch err
        # Empty slug (pure-punctuation input) → bail out as usage error.
        if err isa ArgumentError
            m.exit_action = :usage_error
            m.done = true
        else
            rethrow()
        end
    end
    return nothing
end

"""
Colour for each project-type badge.

Deliberately built from `Style`/`ColorRGB` rather than `tstyle`: the
badge palette identifies a language and must stay recognisable across
themes, where `:primary` / `:accent` shift with the theme.
"""
const BADGE_STYLES = Dict(
    :rust => Tachikoma.Style(fg=Tachikoma.ColorRGB(0xde, 0x59, 0x3f), bold=true),
    :julia => Tachikoma.Style(fg=Tachikoma.ColorRGB(0x95, 0x58, 0xb2), bold=true),
    :python => Tachikoma.Style(fg=Tachikoma.ColorRGB(0xff, 0xd4, 0x3b), bold=true),
    :go => Tachikoma.Style(fg=Tachikoma.ColorRGB(0x00, 0xad, 0xd8), bold=true),
    :maven => Tachikoma.Style(fg=Tachikoma.ColorRGB(0xc7, 0x1a, 0x36), bold=true),
    :flutter => Tachikoma.Style(fg=Tachikoma.ColorRGB(0x54, 0xc5, 0xf8), bold=true),
    :mise => Tachikoma.Style(fg=Tachikoma.ColorRGB(0x7a, 0xb8, 0x55), bold=true),
    :locked => Tachikoma.Style(fg=Tachikoma.ColorRGB(0x9e, 0x9e, 0x9e), bold=true),
    :worktree => Tachikoma.Style(fg=Tachikoma.ColorRGB(0x4c, 0xaf, 0x50), bold=true),
    :submodule => Tachikoma.Style(fg=Tachikoma.ColorRGB(0xba, 0x68, 0xc8), bold=true),
    :git => Tachikoma.Style(fg=Tachikoma.ColorRGB(0xf0, 0x5c, 0x2e), bold=true)
)

"""
Glyph used for every badge.

A filled circle rather than a Nerd Font icon: the reference TUI's
icons render as tofu on terminals without a patched font, and the
colour already carries the meaning.
"""
const BADGE_GLYPH = '●'

"""
Width of the right-hand panel column, in cells.
"""
const SIDE_PANEL_WIDTH = 34

"""
Below this content width the right-hand column is dropped entirely.
"""
const SIDE_PANEL_MIN_TOTAL = 64

"""
Badges per row in the legend panel.
"""
const LEGEND_COLUMNS = 2

"""
Render the selector.

Layout:

```text
┌ Search/New ─────────────────┐┌ Disk ──────────┐
│ > <filter>                  ││ Used: … Free: …│
└─────────────────────────────┘└────────────────┘
┌ Folders ────────────────────┐┌ Preview ───────┐
│▸● 2026-04-19 my-idea  (00d…)││ src            │
│ ● 2026-04-18 another  (01d…)││ README.md      │
└─────────────────────────────┘└────────────────┘
                               ┌ Legends ───────┐
                               │ ● Rust ● Julia │
                               └────────────────┘
 ↑↓ Nav │ Enter Select │ Ctrl-R Rename │ Esc Quit
```

The right-hand column is dropped below `SIDE_PANEL_MIN_TOTAL` cells
so the list stays usable in a narrow terminal.

EARS coverage: SD1.
"""
function Tachikoma.view(m::SelectorSession, f::Tachikoma.Frame)
    buf = f.buffer
    # Downstream scroll math reads this on the next key event.
    m.terminal_size = (f.area.height, f.area.width)
    refresh_panels!(m)

    # Background first: there is no z-buffer, so compositing is purely
    # draw-order. Foreground cells written with a `NoColor` background
    # keep whatever the background left underneath, which is what lets
    # the animation show through the panels.
    # Bound to a local first: narrowing a *mutable field* does not
    # carry into the call, so `m.background` stays
    # `Union{Nothing,Background}` at the call site and JET flags it.
    # `animations_enabled()` is re-checked every frame, not just at
    # open: Ctrl-A toggles it live, and a reduced-motion preference
    # has to take effect immediately rather than at the next launch.
    bg = m.background
    if bg !== nothing && Tachikoma.animations_enabled()
        m.tick += 1
        render_selector_background!(bg, buf, f.area, m.tick)
    end

    rows = Tachikoma.split_layout(
        Tachikoma.Layout(
            Tachikoma.Vertical, [Tachikoma.Fill(), Tachikoma.Fixed(1)]),
        f.area
    )
    length(rows) < 2 && return nothing
    content_area, footer_area = rows[1], rows[2]

    show_side = content_area.width >= SIDE_PANEL_MIN_TOTAL
    left_area = content_area
    if show_side
        cols = Tachikoma.split_layout(
            Tachikoma.Layout(
                Tachikoma.Horizontal,
                [Tachikoma.Fill(), Tachikoma.Fixed(SIDE_PANEL_WIDTH)]
            ),
            content_area
        )
        if length(cols) >= 2
            left_area = cols[1]
            _render_side_column(m, buf, cols[2])
        else
            show_side = false
        end
    end

    lrows = Tachikoma.split_layout(
        Tachikoma.Layout(
            Tachikoma.Vertical, [Tachikoma.Fixed(3), Tachikoma.Fill()]),
        left_area
    )
    length(lrows) < 2 && return nothing
    _render_search(m, buf, lrows[1])
    _render_folders(m, buf, lrows[2])

    _render_footer(m, buf, footer_area)
    # Last, and over the full frame: an overlay that panels could
    # paint across would defeat the point of asking.
    m.mode === :choose && _render_choice(m, buf, f.area)
    m.mode === :help && _render_help(m, buf, f.area)
    m.mode === :theme && _render_theme_picker(m, buf, f.area)
    m.mode === :animation && _render_animation_picker(m, buf, f.area)
    m.mode === :about && _render_about(m, buf, f.area)
    m.mode === :docs && _render_docs(m, buf, f.area)
    return nothing
end

"""
Key bindings shown by the `?` overlay.

Includes Tachikoma's own bindings as well as TryIt's: from the user's
side they are simply keys that work here, and the framework's own
help overlay is private to its app loop, so it cannot be reused.
"""
const HELP_KEYS = [
    ("↑ / ↓", "Move the cursor"),
    ("Enter", "Open the highlighted try, or create one"),
    ("Ctrl-N", "Create a new dated try"),
    ("Ctrl-T", "Theme picker"),
    ("Ctrl-B", "Animation picker"),
    ("Ctrl-A", "About"),
    ("Ctrl-W", "Save theme and animation to the config file"),
    ("Ctrl-R", "Rename the highlighted try"),
    ("Ctrl-D", "Flag the highlighted try for deletion"),
    ("Ctrl-G", "Graduate: drop the date, move out of the tries root"),
    ("Ctrl-P", "Add a date prefix to an undated folder"),
    ("F9", "Start / stop .tach screen recording"),
    ("?", "This key map"),
    ("F1", "Documentation browser"),
    ("Esc", "Quit without changing directory"),
    ("Ctrl-C", "Abort")
]

"""
Draw the theme picker (Ctrl-T).
"""
function _render_theme_picker(m::SelectorSession, buf, area)
    names = theme_names()
    height = min(length(names) + 2, max(5, area.height - 2))
    width = min(area.width - 4, 34)
    (width < 14 || height < 5) && return nothing

    box = Tachikoma.Rect(
        area.x + div(area.width - width, 2),
        area.y + max(0, div(area.height - height, 2)),
        width, height
    )
    _blank_area!(m, buf, box)

    rows = max(1, height - 2)
    # Keep the highlighted theme on screen when the list is longer
    # than the box.
    offset = clamp(m.theme_index - div(rows, 2), 1, max(1, length(names) - rows + 1))
    items = Tachikoma.ListItem[
                               Tachikoma.ListItem(names[i], Tachikoma.tstyle(:text))
                               for i in 1:length(names)
                               ]
    Tachikoma.render(
        Tachikoma.SelectableList(
            items;
            selected=m.theme_index,
            offset=offset - 1,
            focused=true,
            block=Tachikoma.Block(
                title="Theme",
                title_right=string(m.theme_index, "/", length(names)),
                title_style=Tachikoma.tstyle(:title, bold=true),
                border_style=Tachikoma.tstyle(:accent, bold=true)
            ),
            highlight_style=Tachikoma.tstyle(:accent, bold=true)
        ),
        box, buf
    )
    return nothing
end

"""
Draw the in-app documentation browser (F1).

Renders the embedded markdown through Tachikoma's `MarkdownPane`,
which needs CommonMark — enabled once, lazily, because
`enable_markdown()` throws if the extension is not loaded.

EARS coverage: ED20.
"""
# `enable_markdown()` registers Tachikoma's CommonMark extension. It
# is idempotent but not free, and the docs browser is opened rarely,
# so it happens on first use rather than at package load.
const _MARKDOWN_READY = Ref(false)

function _render_docs(m::SelectorSession, buf, area)
    isempty(DOC_PAGES) && return nothing
    if !_MARKDOWN_READY[]
        try
            Tachikoma.enable_markdown()
            _MARKDOWN_READY[] = true
        catch err
            # Without CommonMark there is nothing to render; say so in
            # the frame rather than throwing inside the render loop.
            notify!(m, string("markdown unavailable: ", _err_msg(err)))
            m.mode = :normal
            return nothing
        end
    end
    width = min(area.width - 4, 96)
    height = max(6, area.height - 2)
    (width < 24 || height < 6) && return nothing

    box = Tachikoma.Rect(
        area.x + div(area.width - width, 2),
        area.y + max(0, div(area.height - height, 2)),
        width, height
    )
    _blank_area!(m, buf, box)

    idx = clamp(m.doc_index, 1, length(DOC_PAGES))
    title, body = DOC_PAGES[idx]
    block = Tachikoma.Block(
        title=string(title, "  (", idx, "/", length(DOC_PAGES), ")"),
        title_right="Tab page · ↑↓ scroll · Esc close",
        title_style=Tachikoma.tstyle(:title, bold=true),
        border_style=Tachikoma.tstyle(:accent, bold=true)
    )

    # Reflow width has to allow for the block's two border columns
    # *and* the scrollbar column, or long lines are clipped at the
    # right edge instead of wrapping.
    pane = Tachikoma.MarkdownPane(
        body; width=max(20, width - 5), block=block, show_scrollbar=true
    )
    pane.pane.offset = m.doc_offset
    Tachikoma.render(pane, box, buf)
    return nothing
end

"""
Draw the animation picker (Ctrl-B).
"""
function _render_animation_picker(m::SelectorSession, buf, area)
    names = BACKGROUND_NAMES
    height = min(length(names) + 2, max(5, area.height - 2))
    width = min(area.width - 4, 30)
    (width < 14 || height < 5) && return nothing

    box = Tachikoma.Rect(
        area.x + div(area.width - width, 2),
        area.y + max(0, div(area.height - height, 2)),
        width, height
    )
    _blank_area!(m, buf, box)
    Tachikoma.render(
        Tachikoma.SelectableList(
            [Tachikoma.ListItem(n, Tachikoma.tstyle(:text)) for n in names];
            selected=m.anim_index,
            focused=true,
            block=Tachikoma.Block(
                title="Animation",
                title_right=string(m.anim_index, "/", length(names)),
                title_style=Tachikoma.tstyle(:title, bold=true),
                border_style=Tachikoma.tstyle(:accent, bold=true)
            ),
            highlight_style=Tachikoma.tstyle(:accent, bold=true)
        ),
        box, buf
    )
    return nothing
end

"""
Draw the About overlay (Ctrl-A).

EARS coverage: ED16.
"""
function _render_about(m::SelectorSession, buf, area)
    lines = [
        ("TryIt.jl", Tachikoma.tstyle(:title, bold=true)),
        (string("version ", ABOUT_VERSION), Tachikoma.tstyle(:text_dim)),
        ("", Tachikoma.tstyle(:text)),
        ("Ephemeral-workspace manager for Julia.", Tachikoma.tstyle(:text)),
        ("", Tachikoma.tstyle(:text)),
        ("Inspired by:", Tachikoma.tstyle(:text_dim)),
        ("  try-cli  github.com/tobi/try-cli", Tachikoma.tstyle(:text)),
        ("  try-rs   github.com/tassiovirginio/try-rs", Tachikoma.tstyle(:text)),
        ("", Tachikoma.tstyle(:text)),
        ("TUI built on Tachikoma.jl", Tachikoma.tstyle(:text_dim)),
        ("MIT licensed", Tachikoma.tstyle(:text_dim))
    ]
    height = length(lines) + 2
    width = min(area.width - 4, 52)
    (width < 20 || area.height < height) && return nothing

    box = Tachikoma.Rect(
        area.x + div(area.width - width, 2),
        area.y + max(0, div(area.height - height, 2)),
        width, height
    )
    _blank_area!(m, buf, box)
    inner = Tachikoma.render(
        Tachikoma.Block(
            title="About",
            title_right="any key closes",
            title_style=Tachikoma.tstyle(:title, bold=true),
            border_style=Tachikoma.tstyle(:accent, bold=true)
        ),
        box, buf
    )
    (inner.width <= 0 || inner.height <= 0) && return nothing
    for (i, (text, style)) in enumerate(lines)
        i > inner.height && break
        Tachikoma.set_string!(
            buf, inner.x, inner.y + i - 1, _pad(text, inner.width), style)
    end
    return nothing
end

"""
Version string shown in the About overlay.
"""
const ABOUT_VERSION = let v = pkgversion(@__MODULE__)
    v === nothing ? "unknown" : string(v)
end

"""
Draw the `?` key-binding overlay.

EARS coverage: ED17.
"""
function _render_help(m::SelectorSession, buf, area)
    rows = length(HELP_KEYS) + 2
    width = min(area.width - 4, 64)
    (width < 24 || area.height < rows + 2) && return nothing

    x = area.x + div(area.width - width, 2)
    y = area.y + max(0, div(area.height - rows, 2))
    box = Tachikoma.Rect(x, y, width, rows)

    _blank_area!(m, buf, box)
    inner = Tachikoma.render(
        Tachikoma.Block(
            title="Key bindings",
            title_right="any key closes",
            title_style=Tachikoma.tstyle(:title, bold=true),
            border_style=Tachikoma.tstyle(:accent, bold=true)
        ),
        box, buf
    )
    (inner.width <= 0 || inner.height <= 0) && return nothing

    for (i, (k, desc)) in enumerate(HELP_KEYS)
        i > inner.height && break
        yy = inner.y + i - 1
        # Blank rows separate our bindings from the framework's.
        isempty(k) && continue
        cx = Tachikoma.set_string!(
            buf, inner.x, yy, rpad(k, 9), Tachikoma.tstyle(:accent, bold=true))
        Tachikoma.set_string!(
            buf, cx, yy, _pad(desc, max(0, inner.width - 9)),
            Tachikoma.tstyle(:text))
    end
    return nothing
end

"""
Draw the open-or-create prompt.

Both concrete names are spelled out — the whole point is that the
typed text and the matched try are *different*, so naming only one of
them would leave the choice ambiguous.
"""
function _render_choice(m::SelectorSession, buf, area)
    (m.cursor >= 1 && m.cursor <= length(m.visible)) || return nothing
    matched = m.visible[m.cursor]
    typed = something(_filter_slug(m), strip(m.filter))
    n = length(m.visible)

    Tachikoma.render(
        Tachikoma.Modal(
            title="Open or create?",
            message=string(
                '"', typed, "\" matches ", n, n == 1 ? " try" : " tries", ".",
                "\nChoose what Enter should do."
            ),
            # Modal draws `cancel_label` on the left, so "Open" is the
            # cancel slot: it is the default, and the left button is
            # where the arrow keys and the eye both start. Mapping it
            # to `confirm` instead put the default on the right while
            # Left still selected it.
            cancel_label=string("Open  ", basename(matched.path)),
            confirm_label=string("Create  ", typed),
            selected=m.choice === :open ? :cancel : :confirm,
            cancel_style=Tachikoma.tstyle(:accent, bold=true),
            confirm_style=Tachikoma.tstyle(:success, bold=true),
            border_style=Tachikoma.tstyle(:accent, bold=true),
            title_style=Tachikoma.tstyle(:title, bold=true)
        ),
        area, buf
    )
    return nothing
end

"""
Draw the search / rename input box.

The same box doubles as the rename prompt (SD2), signalled by the
`✎` prefix and a distinct border colour.
"""
function _render_search(m::SelectorSession, buf, area)
    _blank_area!(m, buf, area)
    renaming = m.mode === :rename
    title = renaming ? "Rename" : "Search/New"
    prefix, content = renaming ? ("✎ ", m.rename_buf) : ("> ", m.filter)
    border = renaming ? Tachikoma.tstyle(:warning) : Tachikoma.tstyle(:border)

    inner = Tachikoma.render(
        Tachikoma.Block(
            title=title,
            title_style=Tachikoma.tstyle(:title, bold=true),
            border_style=border
        ),
        area, buf
    )
    inner.width <= 0 && return nothing
    # Trailing block acts as a cursor; the selector has no blinking
    # caret of its own.
    line = _pad(string(prefix, content, "▌"), inner.width)
    Tachikoma.set_string!(buf, inner.x, inner.y, line, Tachikoma.tstyle(:text))
    return nothing
end

"""
Draw the folder list: badge, date, slug, and right-aligned age.
"""
function _render_folders(m::SelectorSession, buf, area)
    _blank_area!(m, buf, area)
    total = length(m.visible)
    block = Tachikoma.Block(
        title="Folders",
        title_right=total == 0 ? "" : string(max(m.cursor, 1), "/", total),
        title_style=Tachikoma.tstyle(:title, bold=true),
        border_style=Tachikoma.tstyle(:border)
    )

    if total == 0
        inner = Tachikoma.render(block, area, buf)
        inner.width > 0 && Tachikoma.set_string!(
            buf, inner.x, inner.y,
            _pad("no tries yet — type a name and press Enter", inner.width),
            Tachikoma.tstyle(:text_dim)
        )
        return nothing
    end

    # Reserve a column for the scrollbar the list draws when the
    # content overflows, so the age column never sits under it.
    inner_w = max(0, area.width - 2)
    visible_rows = max(0, area.height - 2)
    inner_w -= (total > visible_rows ? 1 : 0)
    # SelectableList advances 2 cells for its selection marker
    # (whether or not the row is selected) and then draws our 2-cell
    # badge prefix, so 4 cells are gone before `content` starts. The
    # widget clips at the right edge, so under-reserving here silently
    # eats the last character of the age column.
    label_w = max(0, inner_w - 4)

    items = Tachikoma.ListItem[]
    now = time()
    for (i, t) in enumerate(m.visible)
        marked = t.path in m.marked_for_delete
        age = string("(", format_age(try_age_seconds(t, now)), ")")
        left = string(t.date, " ", t.name)
        # Undated directories are shown too, but dimmed: their date is
        # the filesystem mtime rather than something the user chose,
        # so it carries less meaning than a real prefix.
        row_style = if marked
            Tachikoma.tstyle(:text_dim, strikethrough=true)
        elseif t.dated
            Tachikoma.tstyle(:text)
        else
            Tachikoma.tstyle(:text_dim)
        end

        badges = badges_for(m, t)
        glyph = isempty(badges) ? ' ' : BADGE_GLYPH
        glyph_style = if isempty(badges)
            Tachikoma.tstyle(:text_dim)
        elseif t.dated
            get(BADGE_STYLES, badges[1], Tachikoma.tstyle(:text))
        else
            Tachikoma.tstyle(:text_dim)
        end

        push!(
            items,
            Tachikoma.ListItem(
                _fit_row(left, age, label_w), row_style;
                prefix=string(marked ? '✗' : glyph, ' '),
                prefix_style=marked ? Tachikoma.tstyle(:error) : glyph_style
            )
        )
    end

    Tachikoma.render(
        Tachikoma.SelectableList(
            items;
            selected=max(m.cursor, 1),
            offset=max(0, m.viewport_top - 1),
            focused=m.mode !== :rename,
            block=block,
            highlight_style=Tachikoma.tstyle(:accent, bold=true)
        ),
        area, buf
    )
    return nothing
end

"""
Draw the stacked Disk / Preview / Legends column.

EARS coverage: SD4.
"""
function _render_side_column(m::SelectorSession, buf, area)
    legend_rows = cld(length(BADGE_ORDER), LEGEND_COLUMNS)
    rrows = Tachikoma.split_layout(
        Tachikoma.Layout(
            Tachikoma.Vertical,
            [
                Tachikoma.Fixed(3),
                Tachikoma.Fill(),
                Tachikoma.Fixed(legend_rows + 2)
            ]
        ),
        area
    )
    length(rrows) < 3 && return nothing
    _render_disk(m, buf, rrows[1])
    _render_preview(m, buf, rrows[2])
    _render_legend(m, buf, rrows[3])
    return nothing
end

"""
Draw used / free space for the filesystem holding the tries root.
"""
function _render_disk(m::SelectorSession, buf, area)
    _blank_area!(m, buf, area)
    inner = Tachikoma.render(
        Tachikoma.Block(
            title="Disk",
            title_style=Tachikoma.tstyle(:title, bold=true),
            border_style=Tachikoma.tstyle(:border)
        ),
        area, buf
    )
    inner.width <= 0 && return nothing

    if m.disk === nothing
        Tachikoma.set_string!(
            buf, inner.x, inner.y, _pad("unavailable", inner.width),
            Tachikoma.tstyle(:text_dim)
        )
        return nothing
    end

    x = Tachikoma.set_string!(
        buf, inner.x, inner.y, "Used: ", Tachikoma.tstyle(:text_dim))
    x = Tachikoma.set_string!(
        buf, x, inner.y, format_bytes(m.disk.used), Tachikoma.tstyle(:warning))
    x = Tachikoma.set_string!(
        buf, x, inner.y, " │ Free: ", Tachikoma.tstyle(:text_dim))
    Tachikoma.set_string!(
        buf, x, inner.y, format_bytes(m.disk.free), Tachikoma.tstyle(:success))
    return nothing
end

"""
Draw the contents of the selected try.
"""
function _render_preview(m::SelectorSession, buf, area)
    _blank_area!(m, buf, area)
    inner = Tachikoma.render(
        Tachikoma.Block(
            title="Preview",
            title_style=Tachikoma.tstyle(:title, bold=true),
            border_style=Tachikoma.tstyle(:border)
        ),
        area, buf
    )
    (inner.width <= 0 || inner.height <= 0) && return nothing

    if isempty(m.preview)
        Tachikoma.set_string!(
            buf, inner.x, inner.y,
            _pad(isempty(m.preview_path) ? "" : "empty", inner.width),
            Tachikoma.tstyle(:text_dim)
        )
        return nothing
    end

    for i in 1:min(inner.height, length(m.preview))
        e = m.preview[i]
        style = e.isdir ? Tachikoma.tstyle(:primary, bold=true) :
                Tachikoma.tstyle(:text)
        Tachikoma.set_string!(
            buf, inner.x, inner.y + i - 1,
            _pad(string(e.isdir ? "▸ " : "  ", e.name), inner.width), style
        )
    end
    return nothing
end

"""
Draw the badge colour legend.
"""
function _render_legend(m::SelectorSession, buf, area)
    _blank_area!(m, buf, area)
    inner = Tachikoma.render(
        Tachikoma.Block(
            title="Legends",
            title_style=Tachikoma.tstyle(:title, bold=true),
            border_style=Tachikoma.tstyle(:border)
        ),
        area, buf
    )
    (inner.width <= 0 || inner.height <= 0) && return nothing

    col_w = max(1, div(inner.width, LEGEND_COLUMNS))
    for (i, badge) in enumerate(BADGE_ORDER)
        row = cld(i, LEGEND_COLUMNS) - 1
        col = mod(i - 1, LEGEND_COLUMNS)
        row >= inner.height && break
        x = inner.x + col * col_w
        y = inner.y + row
        x = Tachikoma.set_string!(
            buf, x, y, string(BADGE_GLYPH, ' '),
            get(BADGE_STYLES, badge, Tachikoma.tstyle(:text))
        )
        Tachikoma.set_string!(
            buf, x, y, BADGE_LABELS[badge], Tachikoma.tstyle(:text_dim))
    end
    return nothing
end

"""
Draw the key-binding help bar.

EARS coverage: SD5.
"""
function _render_footer(m::SelectorSession, buf, area)
    key = Tachikoma.tstyle(:accent, bold=true)
    lbl = Tachikoma.tstyle(:text_dim)
    left = if m.mode === :docs
        [
            Tachikoma.Span(" Tab ", key), Tachikoma.Span("Page", lbl),
            Tachikoma.Span(" | ", Tachikoma.tstyle(:border)),
            Tachikoma.Span("↑↓ ", key), Tachikoma.Span("Scroll", lbl),
            Tachikoma.Span(" | ", Tachikoma.tstyle(:border)),
            Tachikoma.Span("Esc ", key), Tachikoma.Span("Close", lbl)
        ]
    elseif !isempty(m.notice)
        # A failure the user just caused outranks the binding list —
        # stderr is redirected, so this bar is the only channel left.
        [
            Tachikoma.Span(" ! ", Tachikoma.tstyle(:error, bold=true)),
            Tachikoma.Span(m.notice, Tachikoma.tstyle(:warning))
        ]
    elseif m.mode === :choose
        [
            Tachikoma.Span(" ↑↓ ", key), Tachikoma.Span("Choose ", lbl),
            Tachikoma.Span("Enter ", key), Tachikoma.Span("Confirm ", lbl),
            Tachikoma.Span("Esc ", key), Tachikoma.Span("Back ", lbl)
        ]
    elseif m.mode === :rename
        [
            Tachikoma.Span(" Enter ", key), Tachikoma.Span("Apply ", lbl),
            Tachikoma.Span("Esc ", key), Tachikoma.Span("Cancel ", lbl)
        ]
    else
        # Mirrors try-rs's bar: pipe-separated, key in accent,
        # action dimmed. F9 lives in `?` help only — screen recording
        # is not something you reach for often enough to spend a slot
        # on, and the bar already truncates below ~80 columns.
        sep = Tachikoma.Span(" | ", Tachikoma.tstyle(:border))
        # StatusBar clips rather than wraps, so a fixed list loses its
        # tail — at 100 columns that silently ate "Esc Quit", and at 80
        # it cut mid-word. Bindings are dropped in reverse order of how
        # often they are reached for; `?` survives every tier, because
        # the overlay is where the dropped ones are still documented.
        entries = [
            ("↑↓ ", "Nav"), ("Enter ", "Select"), ("Ctrl+D ", "Del"),
            ("Ctrl+R ", "Rename"), ("Ctrl+G ", "Graduate"),
            ("Ctrl+T ", "Theme"), ("Ctrl+A ", "About")
        ]
        keep = area.width >= 118 ? 7 :
               area.width >= 100 ? 5 :
               area.width >= 78 ? 4 : 2
        spans = Tachikoma.Span[Tachikoma.Span(" ", lbl)]
        for (i, (k, action)) in enumerate(entries[1:min(keep, end)])
            i > 1 && push!(spans, sep)
            push!(spans, Tachikoma.Span(k, key))
            push!(spans, Tachikoma.Span(action, lbl))
        end
        push!(spans, sep)
        push!(spans, Tachikoma.Span("? ", key))
        push!(spans, Tachikoma.Span("Help", lbl))
        spans
    end
    right = Tachikoma.Span[]
    if recording_active(m)
        # There is no framework notification for our F9 binding, so
        # this indicator is the only signal that capture is running.
        push!(right, Tachikoma.Span("● REC ", Tachikoma.tstyle(:error, bold=true)))
    end
    push!(right, Tachikoma.Span("Esc ", key))
    push!(right, Tachikoma.Span("Quit ", lbl))

    Tachikoma.render(
        Tachikoma.StatusBar(left=left, right=right), area, buf
    )
    return nothing
end

"""
Blank every cell of `rect`, keeping whatever colour is underneath.

The animated background paints braille glyphs across the whole frame,
and panels only write the rows they actually fill — so without this
the background shows through panel interiors as noise rather than as
a wash. Writing a space with a `NoColor` background replaces the
glyph but preserves the cell's background colour, so the animation
still tints the panel.
"""
function _blank_area!(m::SelectorSession, buf, rect)
    blanks_panels(m.background) || return nothing
    (rect.width <= 0 || rect.height <= 0) && return nothing
    blank = " "^rect.width
    for y in (rect.y):(rect.y + rect.height - 1)
        Tachikoma.set_string!(buf, rect.x, y, blank, Tachikoma.tstyle(:text))
    end
    return nothing
end

"""
Compose a row as `left` with `right` flushed to `width`.

When the two cannot both fit, `left` is truncated and `right` is kept
— the age column is fixed-width and losing it would ragged the
right edge of the list.
"""
function _fit_row(left::AbstractString, right::AbstractString, width::Integer)
    width <= 0 && return ""
    length(right) >= width && return _pad(right, width)
    gap = width - length(right)
    return string(_pad(left, gap - 1), " ", right)
end

function _pad(s::AbstractString, width::Integer)
    # Truncate if longer, pad with spaces if shorter. Width counted in
    # Char codepoints — good enough for the ASCII-slug + ISO-date
    # content we render.
    if length(s) >= width
        return String(SubString(s, 1, min(lastindex(s), nextind(s, 0, width))))
    else
        return string(s, " "^(width - length(s)))
    end
end
