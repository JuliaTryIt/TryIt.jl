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
    "Sub-mode: `:normal` (default) or `:rename` (Ctrl-R). SD2-masked in `:rename`."
    mode::Symbol = :normal
    "Input line contents while in `:rename`. Empty otherwise."
    rename_buf::String = ""
    "Absolute paths flagged for delete on selector exit (ED9 / ED10)."
    marked_for_delete::Set{String} = Set{String}()
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
    elseif key === :ctrl && evt.char == 't'
        _handle_ctrl_t!(m)
    elseif key === :ctrl && evt.char == 'r'
        _handle_ctrl_r!(m)
    elseif key === :ctrl && evt.char == 'g'
        _handle_ctrl_g!(m)
    elseif key === :ctrl && evt.char == 'd'
        _handle_ctrl_d!(m)
    elseif key === :char && isprint(evt.char) && evt.char != '\0'
        m.filter *= evt.char
        refresh_visible!(m)
        _scroll_after_cursor_move!(m)
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
            diag(:rename, _err_msg(err))
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
            diag(:rename, _err_msg(err))
            return nothing      # stay in :rename
        end
        rethrow()
    end
    try
        rename_try(inv)
    catch err
        diag(:rename, _err_msg(err))
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
            diag(:graduate, _err_msg(err))
            return nothing
        end
        rethrow()
    end
    local dest::String
    try
        dest = graduate_try(inv)
    catch err
        diag(:graduate, _err_msg(err))
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
function _handle_ctrl_t!(m::SelectorSession)
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

function _handle_enter!(m::SelectorSession)
    if !isempty(m.visible) && m.cursor >= 1 && m.cursor <= length(m.visible)
        m.exit_action = :cd
        m.exit_path = m.visible[m.cursor].path
        m.done = true
        return nothing
    end
    # No match → create today's try from the filter string (ED4).
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
Render the selector.

Layout (v0.1):

```text
┌ TryIt — <root> ───────────────────────────────┐
│ > <filter>                                    │
│                                                │
│  2026-04-19 my-idea                            │
│  2026-04-18 another-try                        │
│ ...                                            │
└ Enter=cd/create · Esc=quit · Ctrl-C=abort ─────┘
```

EARS coverage: SD1.
"""
function Tachikoma.view(m::SelectorSession, f::Tachikoma.Frame)
    buf = f.buffer
    area = f.area
    width = area.width
    height = area.height
    base_x = area.x
    base_y = area.y

    # Header.
    header = _pad(string("TryIt — ", m.root.root), width)
    Tachikoma.set_string!(buf, base_x, base_y, header, Tachikoma.tstyle(:primary))

    # Filter / rename input line.
    prefix, buf_content = if m.mode === :rename
        ("✎ ", m.rename_buf)
    else
        ("> ", m.filter)
    end
    filter_line = _pad(string(prefix, buf_content), width)
    Tachikoma.set_string!(buf, base_x, base_y + 1, filter_line, Tachikoma.tstyle(:text))

    # Separator blank.
    Tachikoma.set_string!(
        buf, base_x, base_y + 2, _pad("", width), Tachikoma.tstyle(:text))

    # Rows — render the `[viewport_top, viewport_top + list_rows)` slice.
    list_top = base_y + 3
    list_rows = max(0, height - (list_top - base_y) - 1)
    # Refresh terminal_size for downstream scroll math on redraw.
    m.terminal_size = (height, width)
    vp_top = max(1, m.viewport_top)
    for i in 1:list_rows
        row_y = list_top + (i - 1)
        idx = vp_top + i - 1
        if idx <= length(m.visible)
            t = m.visible[idx]
            marker = if idx == m.cursor
                "▶ "
            elseif t.path in m.marked_for_delete
                "✗ "
            else
                "  "
            end
            line = _pad(string(marker, t.date, " ", t.slug.value), width)
            style = if idx == m.cursor
                Tachikoma.tstyle(:accent)
            elseif t.path in m.marked_for_delete
                Tachikoma.tstyle(:text_dim)
            else
                Tachikoma.tstyle(:text)
            end
            Tachikoma.set_string!(buf, base_x, row_y, line, style)
        else
            Tachikoma.set_string!(
                buf, base_x, row_y, _pad("", width), Tachikoma.tstyle(:text)
            )
        end
    end

    # Footer.
    footer = _pad(
        "Enter=cd/create  Esc=quit  Ctrl-C=abort",
        width
    )
    Tachikoma.set_string!(
        buf, base_x, base_y + height - 1, footer, Tachikoma.tstyle(:text_dim))
    return nothing
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
